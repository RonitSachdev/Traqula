@preconcurrency import AVFoundation
import MeetingRecords
import OSLog
import os

/// Captures the default microphone through an `AVAudioEngine` input tap.
///
/// Voice processing is turned on so macOS cancels the echo of whatever the speakers play; without it,
/// remote participants heard through the speakers come back as "Me". Measured on a MacBook: with the
/// canceller on, speaker playback produced no transcript at all. Microphone access must already be granted.
final class MicrophoneSource: AudioSource {
    let channel = AudioChannel.microphone

    private static let logger = Logger(subsystem: "dev.ronit.Traqula", category: "MicrophoneSource")

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private let pausedState = OSAllocatedUnfairLock(initialState: false)

    /// While paused the stream carries silence instead of the microphone, so timing stays intact and nothing is transcribed.
    var isPaused: Bool {
        get { pausedState.withLock { $0 } }
        set { pausedState.withLock { $0 = newValue } }
    }

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        let input = engine.inputNode
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            Self.logger.error("Voice processing unavailable, capturing raw microphone: \(error, privacy: .public)")
        }
        let format = input.outputFormat(forBus: 0)
        // Voice processing exposes the whole microphone array; the recognizer wants one channel.
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1) else {
            throw AudioConversionError.unsupportedFormat(from: format, to: format)
        }

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.continuation = continuation
        let pausedState = self.pausedState
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let out = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength),
                  let source = buffer.floatChannelData, let target = out.floatChannelData else {
                continuation.yield(buffer)
                return
            }
            out.frameLength = buffer.frameLength
            if pausedState.withLock({ $0 }) {
                target[0].update(repeating: 0, count: Int(buffer.frameLength))
            } else {
                target[0].update(from: source[0], count: Int(buffer.frameLength))
            }
            continuation.yield(out)
        }
        engine.prepare()
        try engine.start()
        return stream
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }
}
