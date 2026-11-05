import Foundation
import MeetingRecords

/// One line in the caption window: what was said on a channel and, once available, its translation.
struct CaptionLine: Identifiable, Sendable, Equatable {
    let id: UUID
    let channel: AudioChannel
    var sourceText: String
    var translatedText: String?
    /// Who said it, when a meeting page reported a name.
    var speaker: String?
    var isFinal: Bool
    /// Seconds since the session started.
    var start: TimeInterval
    var end: TimeInterval
}
