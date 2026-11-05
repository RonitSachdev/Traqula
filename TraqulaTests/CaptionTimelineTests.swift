import Testing
@testable import Traqula
import MeetingRecords

struct CaptionTimelineTests {
    private func update(_ text: String, final isFinal: Bool, start: Double = 0, end: Double = 1) -> TranscriptionUpdate {
        TranscriptionUpdate(text: text, isFinal: isFinal, start: start, end: end)
    }

    @Test func volatileResultOpensInProgressLine() {
        var timeline = CaptionTimeline()
        let id = timeline.apply(update("今日は", final: false), channel: .system)

        #expect(timeline.lines.count == 1)
        #expect(timeline.lines[0].id == id)
        #expect(timeline.lines[0].sourceText == "今日は")
        #expect(timeline.lines[0].isFinal == false)
    }

    @Test func laterVolatileResultReplacesInProgressLine() {
        var timeline = CaptionTimeline()
        let first = timeline.apply(update("今日は", final: false), channel: .system)
        let second = timeline.apply(update("今日は会議", final: false, end: 2), channel: .system)

        #expect(first == second)
        #expect(timeline.lines.count == 1)
        #expect(timeline.lines[0].sourceText == "今日は会議")
        #expect(timeline.lines[0].end == 2)
    }

    @Test func finalResultCommitsLineSoNextVolatileStartsNewLine() {
        var timeline = CaptionTimeline()
        _ = timeline.apply(update("今日は会議", final: false), channel: .system)
        let committed = timeline.apply(update("今日は会議です。", final: true), channel: .system)
        let next = timeline.apply(update("来週", final: false, start: 1, end: 2), channel: .system)

        #expect(committed != next)
        #expect(timeline.lines.count == 2)
        #expect(timeline.lines[0].isFinal == true)
        #expect(timeline.lines[0].sourceText == "今日は会議です。")
        #expect(timeline.lines[1].isFinal == false)
    }

    @Test func channelsKeepSeparateInProgressLines() {
        var timeline = CaptionTimeline()
        let them = timeline.apply(update("こんにちは", final: false), channel: .system)
        let me = timeline.apply(update("はい", final: false), channel: .microphone)
        _ = timeline.apply(update("こんにちは、皆さん", final: false), channel: .system)

        #expect(them != me)
        #expect(timeline.lines.map(\.sourceText) == ["こんにちは、皆さん", "はい"])
    }

    @Test func translationAttachesToItsLineAndSurvivesVolatileUpdates() throws {
        var timeline = CaptionTimeline()
        let applied = timeline.apply(update("今日は", final: false), channel: .system)
        let id = try #require(applied)
        timeline.setTranslation("Today", for: id)
        _ = timeline.apply(update("今日は会議", final: false), channel: .system)

        #expect(timeline.lines[0].translatedText == "Today")
    }

    @Test func speakerNameSticksToTheLineAndCanArriveLate() {
        var timeline = CaptionTimeline()
        _ = timeline.apply(update("こんにちは", final: false), channel: .system, speaker: nil)
        _ = timeline.apply(update("こんにちは、皆さん", final: false), channel: .system, speaker: "Tanaka")
        _ = timeline.apply(update("こんにちは、皆さん。", final: true), channel: .system, speaker: nil)

        #expect(timeline.lines.map(\.speaker) == ["Tanaka"])
    }

    @Test func emptyResultIsIgnored() {
        var timeline = CaptionTimeline()
        let id = timeline.apply(update("", final: false), channel: .system)

        #expect(id == nil)
        #expect(timeline.lines.isEmpty)
    }
}
