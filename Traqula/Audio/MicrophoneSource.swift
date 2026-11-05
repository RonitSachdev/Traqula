@preconcurrency import AVFoundation
import MeetingRecords

/// Captures the default microphone through an `AVAudioEngine` input tap.
///
/// Microphone access must already be granted (see `AVCaptureDevice.requestAccess`).
final class MicrophoneSource: AudioSource {
    let channel = AudioChannel.microphone

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.continuation = continuation
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            continuation.yield(buffer)
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
