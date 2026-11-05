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
    /// Copies Float32 audio out of a buffer list that is only valid for the duration of an audio callback
    /// into a standard (non-interleaved) buffer, de-interleaving if the callback delivered interleaved
    /// channels. Every source then hands the recognizer the same layout, whichever one Core Audio picked.
    convenience init?(deinterleaving bufferList: UnsafePointer<AudioBufferList>, sampleRate: Double) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard channels > 0, let first = buffers.first, first.mNumberChannels > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)) else {
            return nil
        }
        let frames = Int(first.mDataByteSize) / (Int(first.mNumberChannels) * MemoryLayout<Float>.size)
        self.init(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(frames, 1)))
        frameLength = AVAudioFrameCount(frames)
        guard let target = floatChannelData else { return nil }

        var channel = 0
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return nil }
            let stride = Int(buffer.mNumberChannels)
            for offset in 0..<stride {
                let destination = target[channel + offset]
                if stride == 1 {
                    destination.update(from: data, count: frames)
                } else {
                    for frame in 0..<frames {
                        destination[frame] = data[frame * stride + offset]
                    }
                }
            }
            channel += stride
        }
    }
}

/// Buffers flow from an audio callback to one consumer and are never shared, so the stream can be Sendable.
extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}
