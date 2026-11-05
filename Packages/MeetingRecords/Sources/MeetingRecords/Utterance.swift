import Foundation

/// Where a stream of speech comes from: remote participants (what the Mac plays) or the user (the microphone).
public enum AudioChannel: String, Codable, Sendable, CaseIterable {
    case system
    case microphone

    public var displayName: String {
        switch self {
        case .system: "Them"
        case .microphone: "Me"
        }
    }
}

/// One spoken segment of a meeting, with its translation when the channel was translated.
public struct Utterance: Codable, Sendable, Equatable {
    public let id: UUID
    public let channel: AudioChannel
    public let startedAt: Date
    public let duration: TimeInterval
    /// BCP 47 language codes.
    public let sourceLanguage: String
    public let targetLanguage: String?
    public let sourceText: String
    public let translatedText: String?

    public init(
        id: UUID, channel: AudioChannel, startedAt: Date, duration: TimeInterval,
        sourceLanguage: String, targetLanguage: String?, sourceText: String, translatedText: String?
    ) {
        self.id = id
        self.channel = channel
        self.startedAt = startedAt
        self.duration = duration
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.sourceText = sourceText
        self.translatedText = translatedText
    }
}

public struct MeetingManifest: Codable, Sendable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?

    public init(id: UUID, startedAt: Date, endedAt: Date?) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}
