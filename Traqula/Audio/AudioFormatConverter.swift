@preconcurrency import AVFoundation

enum AudioConversionError: LocalizedError {
    case unsupportedFormat(from: AVAudioFormat, to: AVAudioFormat)
    case failed(Error?)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(from, to): "Cannot convert audio from \(from) to \(to)."
        case let .failed(error): "Audio conversion failed: \(error?.localizedDescription ?? "unknown error")."
        }
    }
}

/// Resamples captured audio into the format the speech analyzer asks for. Use one per audio source.
final class AudioFormatConverter {
    let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if buffer.format == outputFormat { return buffer }

        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            // Avoid priming so output timing lines up with the input instead of drifting.
            converter?.primeMethod = .none
        }
        guard let converter else {
            throw AudioConversionError.unsupportedFormat(from: buffer.format, to: outputFormat)
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(capacity, 1)) else {
            throw AudioConversionError.unsupportedFormat(from: buffer.format, to: outputFormat)
        }

        // The input block runs synchronously inside `convert`, so this flag never crosses threads.
        nonisolated(unsafe) var delivered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { throw AudioConversionError.failed(error) }
        return output
    }
}
