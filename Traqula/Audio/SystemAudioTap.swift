import AudioToolbox
@preconcurrency import AVFoundation

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

        var streamDescription = try tapID.readTapStreamFormat()
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CoreAudioError(operation: "interpret the tap's audio format", status: kAudioFormatUnsupportedDataFormatError)
        }

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

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.continuation = continuation
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, input, _, _, _ in
            if let buffer = AVAudioPCMBuffer(copying: input, format: format) {
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

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            stop()
            throw CoreAudioError(operation: operation, status: status)
        }
    }
}
