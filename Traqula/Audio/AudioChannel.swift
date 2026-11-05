/// Where a stream of speech comes from.
///
/// Captions and stored utterances are tagged with their channel so the meeting record can tell
/// remote participants (what the Mac plays) apart from the user (the microphone).
enum AudioChannel: String, Codable, Sendable, CaseIterable {
    case system
    case microphone

    var displayName: String {
        switch self {
        case .system: "Them"
        case .microphone: "Me"
        }
    }
}
