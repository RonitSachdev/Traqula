@preconcurrency import AVFoundation
import Testing
@testable import Traqula

/// The system audio tap may receive its channels interleaved or not; both must become the standard layout
/// the recognizer and the format converter already handle.
struct AudioBufferTests {
    private let frames = 4
    private let sampleRate = 48_000.0

    @Test func deinterleavesAnInterleavedStereoCallback() throws {
        // L0 R0 L1 R1 ... as one buffer with two channels.
        var samples: [Float] = (0..<frames).flatMap { [Float($0), Float($0) + 100] }
        let buffer = try #require(samples.withUnsafeMutableBytes { bytes -> AVAudioPCMBuffer? in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            return AVAudioPCMBuffer(deinterleaving: &list, sampleRate: sampleRate, preferring: 2)
        })

        #expect(buffer.format.channelCount == 2)
        #expect(buffer.format.isInterleaved == false)
        #expect(buffer.format.sampleRate == sampleRate)
        #expect(buffer.frameLength == AVAudioFrameCount(frames))
        let channels = try #require(buffer.floatChannelData)
        #expect(Array(UnsafeBufferPointer(start: channels[0], count: frames)) == [0, 1, 2, 3])
        #expect(Array(UnsafeBufferPointer(start: channels[1], count: frames)) == [100, 101, 102, 103])
    }

    @Test func copiesANonInterleavedStereoCallback() throws {
        var left: [Float] = [1, 2, 3, 4]
        var right: [Float] = [5, 6, 7, 8]
        let buffer = try #require(left.withUnsafeMutableBytes { leftBytes -> AVAudioPCMBuffer? in
            right.withUnsafeMutableBytes { rightBytes -> AVAudioPCMBuffer? in
                // An AudioBufferList with two buffers is a variable-length struct; build it in raw memory.
                let size = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.stride
                let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
                defer { raw.deallocate() }
                let list = raw.assumingMemoryBound(to: AudioBufferList.self)
                list.pointee.mNumberBuffers = 2
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(leftBytes.count), mData: leftBytes.baseAddress)
                buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(rightBytes.count), mData: rightBytes.baseAddress)
                return AVAudioPCMBuffer(deinterleaving: list, sampleRate: sampleRate, preferring: 2)
            }
        })

        #expect(buffer.format.channelCount == 2)
        #expect(buffer.format.isInterleaved == false)
        let channels = try #require(buffer.floatChannelData)
        #expect(Array(UnsafeBufferPointer(start: channels[0], count: frames)) == [1, 2, 3, 4])
        #expect(Array(UnsafeBufferPointer(start: channels[1], count: frames)) == [5, 6, 7, 8])
    }

    @Test func picksTheTapStreamBesideAHeadsetMicrophoneStream() throws {
        var mic: [Float] = [9, 9, 9, 9]
        var tap: [Float] = (0..<frames).flatMap { [Float($0), Float($0) + 100] }
        let buffer = try #require(mic.withUnsafeMutableBytes { micBytes -> AVAudioPCMBuffer? in
            tap.withUnsafeMutableBytes { tapBytes -> AVAudioPCMBuffer? in
                let size = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.stride
                let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
                defer { raw.deallocate() }
                let list = raw.assumingMemoryBound(to: AudioBufferList.self)
                list.pointee.mNumberBuffers = 2
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(micBytes.count), mData: micBytes.baseAddress)
                buffers[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(tapBytes.count), mData: tapBytes.baseAddress)
                return AVAudioPCMBuffer(deinterleaving: list, sampleRate: sampleRate, preferring: 2)
            }
        })

        #expect(buffer.format.channelCount == 2)
        let channels = try #require(buffer.floatChannelData)
        #expect(Array(UnsafeBufferPointer(start: channels[0], count: frames)) == [0, 1, 2, 3])
        #expect(Array(UnsafeBufferPointer(start: channels[1], count: frames)) == [100, 101, 102, 103])
    }

    @Test func takesTheLastStereoStreamWhenTwoArrive() throws {
        // Seen with wired earphones: a stereo input stream of the headphone device rides before the tap.
        var first: [Float] = [9, 9, 9, 9, 9, 9, 9, 9]
        var tap: [Float] = (0..<frames).flatMap { [Float($0), Float($0) + 100] }
        let buffer = try #require(first.withUnsafeMutableBytes { firstBytes -> AVAudioPCMBuffer? in
            tap.withUnsafeMutableBytes { tapBytes -> AVAudioPCMBuffer? in
                let size = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.stride
                let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
                defer { raw.deallocate() }
                let list = raw.assumingMemoryBound(to: AudioBufferList.self)
                list.pointee.mNumberBuffers = 2
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                buffers[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(firstBytes.count), mData: firstBytes.baseAddress)
                buffers[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(tapBytes.count), mData: tapBytes.baseAddress)
                return AVAudioPCMBuffer(deinterleaving: list, sampleRate: sampleRate, preferring: 2)
            }
        })

        #expect(buffer.format.channelCount == 2)
        #expect(buffer.frameLength == AVAudioFrameCount(frames))
        let channels = try #require(buffer.floatChannelData)
        #expect(Array(UnsafeBufferPointer(start: channels[0], count: frames)) == [0, 1, 2, 3])
        #expect(Array(UnsafeBufferPointer(start: channels[1], count: frames)) == [100, 101, 102, 103])
    }

    @Test func skipsStreamsWithoutData() throws {
        var tap: [Float] = [1, 2, 3, 4]
        let buffer = try #require(tap.withUnsafeMutableBytes { tapBytes -> AVAudioPCMBuffer? in
            let size = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.stride
            let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { raw.deallocate() }
            let list = raw.assumingMemoryBound(to: AudioBufferList.self)
            list.pointee.mNumberBuffers = 2
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 4096, mData: nil)
            buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(tapBytes.count), mData: tapBytes.baseAddress)
            return AVAudioPCMBuffer(deinterleaving: list, sampleRate: sampleRate, preferring: 2)
        })

        #expect(buffer.format.channelCount == 1)
        let channels = try #require(buffer.floatChannelData)
        #expect(Array(UnsafeBufferPointer(start: channels[0], count: frames)) == [1, 2, 3, 4])
    }

    @Test func standardStereoConvertsToTheRecognizerFormat() throws {
        // The shape the recognizer asks for: mono 16 kHz Float32.
        let target = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 480))
        input.frameLength = 480
        let converted = try AudioFormatConverter(outputFormat: target).convert(input)
        #expect(converted.format == target)
        #expect(converted.frameLength == 160)
    }
}
