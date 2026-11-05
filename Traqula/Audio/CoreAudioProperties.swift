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

    func readDeviceUID() throws -> String {
        try read(kAudioDevicePropertyDeviceUID, initial: "" as CFString) as String
    }

    func readTapStreamFormat() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
    }

    private func read<Value>(_ selector: AudioObjectPropertySelector, initial: Value) throws -> Value {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
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
