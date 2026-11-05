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
    /// Display name of who spoke, when a meeting page reported it; nil means only the channel is known.
    public let speaker: String?

    public init(
        id: UUID, channel: AudioChannel, startedAt: Date, duration: TimeInterval,
        sourceLanguage: String, targetLanguage: String?, sourceText: String, translatedText: String?,
        speaker: String? = nil
    ) {
        self.id = id
        self.channel = channel
        self.startedAt = startedAt
        self.duration = duration
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.speaker = speaker
    }

    /// "Tanaka (Them)" when the speaker is known, otherwise just the channel.
    public var speakerLabel: String {
        speaker.map { "\($0) (\(channel.displayName))" } ?? channel.displayName
    }
}

public struct MeetingManifest: Codable, Sendable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public var endedAt: Date?
    /// Meeting name and attendee names, when a browser meeting page reported them.
    public var title: String?
    public var participants: [String]?

    public init(id: UUID, startedAt: Date, endedAt: Date?, title: String? = nil, participants: [String]? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.participants = participants
    }
}
