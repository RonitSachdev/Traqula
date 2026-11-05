import Foundation
import MeetingRecords

/// Every caption line of a session in order: all finalized lines plus at most one in-progress line per channel.
///
/// This is the pure bookkeeping behind the caption window, kept free of audio and UI so it can be tested.
struct CaptionTimeline: Sendable, Equatable {
    private(set) var lines: [CaptionLine] = []

    /// Records a recognition result and returns the line it landed in, or nil if the result was empty.
    ///
    /// A volatile result replaces the channel's in-progress line (creating one if needed); a final result
    /// commits that line, so the next volatile result starts a new one.
    mutating func apply(_ update: TranscriptionUpdate, channel: AudioChannel) -> CaptionLine.ID? {
        guard !update.text.isEmpty else { return nil }

        if let index = lines.lastIndex(where: { $0.channel == channel && !$0.isFinal }) {
            lines[index].sourceText = update.text
            lines[index].isFinal = update.isFinal
            lines[index].start = update.start
            lines[index].end = update.end
            return lines[index].id
        }

        let line = CaptionLine(
            id: UUID(),
            channel: channel,
            sourceText: update.text,
            translatedText: nil,
            isFinal: update.isFinal,
            start: update.start,
            end: update.end
        )
        lines.append(line)
        return line.id
    }

    mutating func setTranslation(_ text: String, for id: CaptionLine.ID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].translatedText = text
    }
}
