import Foundation
import Observation

/// One captioning run.
///
/// Each channel's audio is transcribed; every result lands in `timeline` for the caption window, and
/// translated lines are translated on the fly. Finalized lines are written to the meeting record.
@MainActor
@Observable
final class CaptionSession {
    struct Channel {
        let source: any AudioSource
        let transcriber: LiveTranscriber
        /// Nil when the channel is already spoken in the target language.
        let translator: (any Translator)?
    }

    private(set) var timeline = CaptionTimeline()
    private(set) var lastError: String?

    let record: MeetingRecord
    private let channels: [Channel]
    private let targetLanguage: Locale.Language
    private let startedAt = Date()
    private var channelTasks: [Task<Void, Never>] = []
    /// Translation of in-progress text is debounced per channel; a newer volatile result cancels the older one.
    private var volatileTranslations: [AudioChannel: Task<Void, Never>] = [:]

    init(channels: [Channel], targetLanguage: Locale.Language, record: MeetingRecord) {
        self.channels = channels
        self.targetLanguage = targetLanguage
        self.record = record
    }

    func start() {
        channelTasks = channels.map { channel in Task { await self.run(channel) } }
    }

    func stop() async {
        for channel in channels { channel.source.stop() }
        for task in channelTasks { task.cancel() }
        channelTasks = []
        for task in volatileTranslations.values { task.cancel() }
        volatileTranslations = [:]
        do {
            try await record.end()
        } catch {
            lastError = "Could not close the meeting record: \(error.localizedDescription)"
        }
    }

    private func run(_ channel: Channel) async {
        do {
            let audio = try channel.source.start()
            for try await update in channel.transcriber.transcribe(audio) {
                guard let lineID = timeline.apply(update, channel: channel.source.channel) else { continue }
                handle(update, lineID: lineID, in: channel)
            }
        } catch is CancellationError {
            return
        } catch {
            lastError = "\(channel.source.channel.displayName): \(error.localizedDescription)"
        }
    }

    private func handle(_ update: TranscriptionUpdate, lineID: CaptionLine.ID, in channel: Channel) {
        guard let translator = channel.translator else {
            if update.isFinal { persist(update, translation: nil, in: channel) }
            return
        }

        volatileTranslations[channel.source.channel]?.cancel()
        let task = Task {
            if !update.isFinal {
                // Let the recognizer settle before spending a translation on text that will change again.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
            }
            do {
                let translated = try await translator.translate(update.text)
                timeline.setTranslation(translated, for: lineID)
                if update.isFinal { persist(update, translation: translated, in: channel) }
            } catch {
                lastError = "Translation: \(error.localizedDescription)"
                if update.isFinal { persist(update, translation: nil, in: channel) }
            }
        }
        if !update.isFinal { volatileTranslations[channel.source.channel] = task }
    }

    private func persist(_ update: TranscriptionUpdate, translation: String?, in channel: Channel) {
        let utterance = Utterance(
            id: UUID(),
            channel: channel.source.channel,
            startedAt: startedAt.addingTimeInterval(update.start),
            duration: update.end - update.start,
            sourceLanguage: channel.transcriber.locale.language.minimalIdentifier,
            targetLanguage: channel.translator == nil ? nil : targetLanguage.minimalIdentifier,
            sourceText: update.text,
            translatedText: translation
        )
        Task {
            do {
                try await record.append(utterance)
            } catch {
                lastError = "Could not save transcript: \(error.localizedDescription)"
            }
        }
    }
}
