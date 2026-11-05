import Foundation
import Testing
import MeetingRecords
@testable import MeetingSummaries

struct MeetingSummarizerTests {
    @Test func transcriptLinesUseTranslationWhenPresentAndStampOffsets() {
        let start = Date(timeIntervalSince1970: 1_762_300_000)
        let lines = MeetingSummarizer.transcriptLines([
            Utterance(id: UUID(), channel: .system, startedAt: start.addingTimeInterval(65), duration: 1,
                      sourceLanguage: "ja", targetLanguage: "en", sourceText: "はい", translatedText: "Yes"),
            Utterance(id: UUID(), channel: .microphone, startedAt: start.addingTimeInterval(3), duration: 1,
                      sourceLanguage: "en", targetLanguage: nil, sourceText: "Hello", translatedText: nil),
        ], relativeTo: start)

        #expect(lines == ["[01:05] Them: Yes", "[00:03] Me: Hello"])
    }

    @Test func chunkKeepsPartsWithinBudgetAndNeverSplitsALine() {
        let lines = ["aaaa", "bbbb", "cccc", "dddddddddddd", "ee"]
        let parts = MeetingSummarizer.chunk(lines, budget: 9)

        #expect(parts == ["aaaa\nbbbb", "cccc", "dddddddddddd", "ee"])
        #expect(MeetingSummarizer.chunk([], budget: 9).isEmpty)
        #expect(MeetingSummarizer.chunk(lines, budget: 1_000) == [lines.joined(separator: "\n")])
    }
}
