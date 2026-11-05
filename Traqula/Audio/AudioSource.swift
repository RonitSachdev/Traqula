@preconcurrency import AVFoundation
import MeetingRecords

/// A live source of PCM audio.
///
/// `start()` delivers buffers as they are captured; the stream ends when `stop()` is called.
/// Buffers are owned by the receiver, so they may be held and converted off the audio thread.
protocol AudioSource: AnyObject {
    var channel: AudioChannel { get }
    func start() throws -> AsyncStream<AVAudioPCMBuffer>
    func stop()
}

extension AVAudioPCMBuffer {
    /// Copies the audio out of a buffer list that is only valid for the duration of an audio callback.
    convenience init?(copying bufferList: UnsafePointer<AudioBufferList>, format: AVAudioFormat) {
        guard let view = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: bufferList, deallocator: nil) else {
            return nil
        }
        self.init(pcmFormat: format, frameCapacity: max(view.frameLength, 1))
        frameLength = view.frameLength
        let source = UnsafeMutableAudioBufferListPointer(view.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            memcpy(to.mData, from.mData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
    }
}

/// Buffers flow from an audio callback to one consumer and are never shared, so the stream can be Sendable.
extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}
