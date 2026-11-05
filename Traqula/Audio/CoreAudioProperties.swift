import AudioToolbox

struct CoreAudioError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? { "Core Audio could not \(operation) (OSStatus \(status))." }
}

/// The slice of the Core Audio HAL property API that the system audio tap needs.
extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try read(kAudioHardwarePropertyDefaultSystemOutputDevice, initial: AudioDeviceID(kAudioObjectUnknown))
    }

    func readDefaultOutputDevice() throws -> AudioDeviceID {
        try read(kAudioHardwarePropertyDefaultOutputDevice, initial: AudioDeviceID(kAudioObjectUnknown))
    }

    /// The built-in audio device's data source for its internal speaker ('ispk' in IOKit's audio types).
    private static let internalSpeakerSource: UInt32 = 0x6973_706B

    /// True for the Mac's own speakers, as opposed to headphones or any external output.
    func isBuiltInSpeaker() -> Bool {
        guard let transport = try? read(kAudioDevicePropertyTransportType, initial: UInt32(0)),
              transport == kAudioDeviceTransportTypeBuiltIn,
              let source = try? read(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput, initial: UInt32(0)) else {
            return false
        }
        return source == Self.internalSpeakerSource
    }

    func readDeviceUID() throws -> String {
        try read(kAudioDevicePropertyDeviceUID, initial: "" as CFString) as String
    }

    func readTapStreamFormat() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
    }

    /// The format a device's input I/O callback delivers.
    func readInputStreamFormat() throws -> AudioStreamBasicDescription {
        try read(kAudioDevicePropertyStreamFormat, scope: kAudioObjectPropertyScopeInput, initial: AudioStreamBasicDescription())
    }

    private func read<Value>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        initial: Value
    ) throws -> Value {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Value>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(self, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else {
            throw CoreAudioError(operation: "read property \(selector)", status: status)
        }
        return value
    }
}
