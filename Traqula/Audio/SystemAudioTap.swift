import AudioToolbox
@preconcurrency import AVFoundation
import MeetingRecords

/// Captures everything the Mac plays through its default output device with a Core Audio process tap.
///
/// A tap needs no virtual audio device and no screen-recording permission. macOS asks for
/// "System Audio Recording" permission the first time a tap is created; a tap that was denied
/// still starts but delivers silence.
final class SystemAudioTap: AudioSource {
    let channel = AudioChannel.system

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

        // The I/O callback delivers the aggregate's input stream, not the tap's advertised format: the two
        // differ when the output path changes under it (for example while the microphone runs with voice
        // processing on), so the format is read from the aggregate and re-checked against each buffer list.
        var streamDescription = try aggregateID.readInputStreamFormat()
        guard let nominal = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CoreAudioError(operation: "interpret the tap's audio format", status: kAudioFormatUnsupportedDataFormatError)
        }
        let formats = DeliveredFormat(nominal: nominal)

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.continuation = continuation
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, input, _, _, _ in
            if let buffer = AVAudioPCMBuffer(copying: input, format: formats.format(for: input)) {
                continuation.yield(buffer)
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

    /// The format of the buffers actually delivered, rebuilt from the buffer list when its channel layout
    /// stops matching the nominal format. Only touched on the tap's I/O queue.
    private final class DeliveredFormat: @unchecked Sendable {
        private var format: AVAudioFormat

        init(nominal: AVAudioFormat) {
            format = nominal
        }

        func format(for bufferList: UnsafePointer<AudioBufferList>) -> AVAudioFormat {
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            let channels = buffers.reduce(0) { $0 + $1.mNumberChannels }
            let interleaved = buffers.count == 1 && channels > 1
            if channels == format.channelCount, interleaved == format.isInterleaved {
                return format
            }
            if let rebuilt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                channels: AVAudioChannelCount(channels), interleaved: interleaved
            ) {
                format = rebuilt
            }
            return format
        }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            stop()
            throw CoreAudioError(operation: operation, status: status)
        }
    }
}
