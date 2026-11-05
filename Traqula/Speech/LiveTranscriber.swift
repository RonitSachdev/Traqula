@preconcurrency import AVFoundation
import CoreMedia
import OSLog
import Speech

/// One recognition result for a stretch of audio.
///
/// Volatile updates are the recognizer's current best guess for audio it has not finalized yet; a final
/// update replaces the volatile text that preceded it. Times are seconds since transcription started.
struct TranscriptionUpdate: Sendable, Equatable {
    let text: String
    let isFinal: Bool
    let start: TimeInterval
    let end: TimeInterval
}

enum TranscriptionError: LocalizedError {
    case noCompatibleAudioFormat

    var errorDescription: String? {
        switch self {
        case .noCompatibleAudioFormat: "The speech recognizer offered no usable audio format."
        }
    }
}

/// On-device speech recognition for one audio source, built on Apple's `SpeechAnalyzer`.
///
/// Uses the `DictationTranscriber` module because it streams a result every few hundred milliseconds.
/// `SpeechTranscriber` reads better on paper, but measured on macOS 26.5 it holds each sentence back for
/// 8–10 seconds after the speaker pauses, which is useless for live captions.
///
/// The dictation module never finalizes on its own, so a segment is finalized here as soon as the running
/// text ends in sentence punctuation, or once it has stopped changing for `idleFinalizationDelay`.
final class LiveTranscriber: Sendable {
    let locale: Locale

    /// How long the running text may stay unchanged before it is treated as a finished segment.
    static let idleFinalizationDelay: Duration = .milliseconds(2500)

    init(locale: Locale) {
        self.locale = locale
    }

    /// Downloads the recognition model for `locale` if it is missing and keeps it from being purged.
    static func installAssets(for locale: Locale) async throws {
        let transcriber = makeTranscriber(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let reserved = await AssetInventory.reservedLocales
        if !reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            try await AssetInventory.reserve(locale: locale)
        }
    }

    /// Recognizes speech in `audio` until the audio stream ends or the returned stream is cancelled.
    func transcribe(_ audio: AsyncStream<AVAudioPCMBuffer>) -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(audio: audio, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        audio: AsyncStream<AVAudioPCMBuffer>,
        into continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation
    ) async throws {
        let transcriber = Self.makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.noCompatibleAudioFormat
        }

        let (inputs, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let feeder = Task {
            let converter = AudioFormatConverter(outputFormat: format)
            for await buffer in audio {
                guard !Task.isCancelled else { break }
                let converted = try converter.convert(buffer)
                inputContinuation.yield(AnalyzerInput(buffer: converted))
            }
            inputContinuation.finish()
            // Flush whatever the recognizer is still holding so the last words become final.
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        defer { feeder.cancel() }

        try await analyzer.start(inputSequence: inputs)
        let segmenter = SegmentFinalizer(analyzer: analyzer, idleDelay: Self.idleFinalizationDelay)
        for try await result in transcriber.results {
            let text = String(result.text.characters)
            continuation.yield(TranscriptionUpdate(
                text: text,
                isFinal: result.isFinal,
                start: result.range.start.seconds,
                end: result.range.end.seconds
            ))
            await segmenter.observe(text: text, isFinal: result.isFinal, end: result.range.end)
        }
        try await feeder.value
    }

    private static func makeTranscriber(locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
    }
}

/// Watches the running text of one transcription and asks the analyzer to finalize it at segment boundaries.
private actor SegmentFinalizer {
    private static let sentenceEndings: Set<Character> = ["。", "？", "！", ".", "?", "!"]
    private static let logger = Logger(subsystem: "dev.ronit.Traqula", category: "SegmentFinalizer")

    private let analyzer: SpeechAnalyzer
    private let idleDelay: Duration
    private var runningText = ""
    private var finalizedThrough = CMTime.zero
    private var idleTimer: Task<Void, Never>?

    init(analyzer: SpeechAnalyzer, idleDelay: Duration) {
        self.analyzer = analyzer
        self.idleDelay = idleDelay
    }

    func observe(text: String, isFinal: Bool, end: CMTime) {
        if isFinal {
            runningText = ""
            idleTimer?.cancel()
            return
        }
        // Volatile results for audio that is already being finalized are superseded; ignore them.
        guard end > finalizedThrough, !text.isEmpty, text != runningText else { return }
        runningText = text
        idleTimer?.cancel()

        if let last = text.last, Self.sentenceEndings.contains(last) {
            finalize(through: end)
        } else {
            idleTimer = Task {
                try? await Task.sleep(for: idleDelay)
                guard !Task.isCancelled else { return }
                self.finalize(through: end)
            }
        }
    }

    private func finalize(through end: CMTime) {
        finalizedThrough = end
        // Runs separately so a slow finalize never stalls result delivery.
        Task {
            do {
                try await analyzer.finalize(through: end)
            } catch {
                Self.logger.error("finalize(through:) failed: \(error, privacy: .public)")
            }
        }
    }
}
