import AudioToolbox
@preconcurrency import AVFoundation
import MeetingRecords
import OSLog

/// Captures everything the Mac plays through its default output device with a Core Audio process tap.
///
/// A tap needs no virtual audio device and no screen-recording permission. macOS asks for
/// "System Audio Recording" permission the first time a tap is created; a tap that was denied
/// still starts but delivers silence.
final class SystemAudioTap: AudioSource {
    let channel = AudioChannel.system

    private nonisolated static let logger = Logger(subsystem: "dev.ronit.Traqula", category: "SystemAudioTap")

    private let queue = DispatchQueue(label: "Traqula.SystemAudioTap", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tap.uuid = UUID()
        tap.isPrivate = true
        tap.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(tap, &tapID), "create the process tap")

        // The tap only produces audio as part of an aggregate device clocked by the real output device.
        let outputUID = try AudioObjectID.system.readDefaultSystemOutputDevice().readDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Traqula Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tap.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create the aggregate device")

        // The callback delivers the aggregate's input stream, interleaved or not depending on the output
        // path (it changes under the microphone's voice processing, for example), so the buffers are
        // de-interleaved into the standard layout the recognizer and the microphone source already use.
        let streamDescription = try aggregateID.readInputStreamFormat()
        let sampleRate = streamDescription.mSampleRate
        let tapChannels = try tapID.readTapStreamFormat().mChannelsPerFrame
        Self.logger.notice("Tap stream: \(sampleRate, privacy: .public) Hz, \(streamDescription.mChannelsPerFrame) ch, tap \(tapChannels) ch, output \(outputUID, privacy: .public)")
        guard sampleRate > 0, streamDescription.mFormatID == kAudioFormatLinearPCM,
              streamDescription.mFormatFlags & kAudioFormatFlagIsFloat != 0, streamDescription.mBitsPerChannel == 32 else {
            throw CoreAudioError(operation: "interpret the tap's audio format", status: kAudioFormatUnsupportedDataFormatError)
        }

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.continuation = continuation
        let meter = TapMeter()
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, input, _, _, _ in
            if let buffer = AVAudioPCMBuffer(deinterleaving: input, sampleRate: sampleRate, preferring: tapChannels) {
                meter.record(buffer, from: input)
                continuation.yield(buffer)
            } else {
                meter.recordRejected(input)
            }
        }
        try check(status, "attach the I/O callback")
        try check(AudioDeviceStart(aggregateID, ioProcID), "start the aggregate device")
        return stream
    }

    func stop() {
        continuation?.finish()
        continuation = nil
        if aggregateID != kAudioObjectUnknown {
            _ = AudioDeviceStop(aggregateID, ioProcID)
            if let ioProcID {
                _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
                self.ioProcID = nil
            }
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    deinit { stop() }

    /// Logs how much audio the tap delivers, so a silent "Them" channel can be told apart from a dead tap.
    /// Only touched on the tap's I/O queue.
    private final class TapMeter: @unchecked Sendable {
        private var buffers = 0
        private var rejected = 0
        private var peak: Float = 0
        private var channels: AVAudioChannelCount = 0

        private var layout = ""

        func record(_ buffer: AVAudioPCMBuffer, from bufferList: UnsafePointer<AudioBufferList>) {
            buffers += 1
            channels = buffer.format.channelCount
            layout = Self.describe(bufferList)
            if let data = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) {
                        peak = max(peak, abs(data[channel][frame]))
                    }
                }
            }
            report()
        }

        func recordRejected(_ bufferList: UnsafePointer<AudioBufferList>) {
            rejected += 1
            layout = Self.describe(bufferList)
            report()
        }

        private static func describe(_ bufferList: UnsafePointer<AudioBufferList>) -> String {
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            return buffers.map { "\($0.mNumberChannels)ch/\($0.mDataByteSize)B/\($0.mData == nil ? "nil" : "data")" }.joined(separator: ",")
        }

        private func report() {
            guard (buffers + rejected) % 6000 == 0 else { return }
            SystemAudioTap.logger.notice("Tap delivered \(self.buffers) buffers (\(self.channels) ch), rejected \(self.rejected), peak \(self.peak, privacy: .public), layout [\(self.layout, privacy: .public)]")
            peak = 0
        }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            stop()
            throw CoreAudioError(operation: operation, status: status)
        }
    }
}
