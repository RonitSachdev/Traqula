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
    /// into a standard (non-interleaved) buffer, de-interleaving if a buffer carries interleaved channels.
    ///
    /// A callback may carry several streams: an aggregate device hands over every input stream of its
    /// sub-devices (a headset microphone, for example) before its taps. `preferring` is the channel count
    /// of the stream wanted; the last buffer with data that has it is copied alone, since taps come last.
    /// Without a match every buffer with data is copied. Every source then hands the recognizer the same layout.
    convenience init?(deinterleaving bufferList: UnsafePointer<AudioBufferList>, sampleRate: Double, preferring channels: UInt32) {
        let all = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        let withData = all.filter { $0.mData != nil && $0.mNumberChannels > 0 && $0.mDataByteSize > 0 }
        let buffers = withData.last(where: { $0.mNumberChannels == channels }).map { [$0] } ?? withData
        let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard channelCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channelCount)) else {
            return nil
        }
        let frames = buffers.map { Int($0.mDataByteSize) / (Int($0.mNumberChannels) * MemoryLayout<Float>.size) }.min() ?? 0
        self.init(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(frames, 1)))
        frameLength = AVAudioFrameCount(frames)
        guard let target = floatChannelData else { return nil }

        var channel = 0
        for buffer in buffers {
            let data = buffer.mData!.assumingMemoryBound(to: Float.self)
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
