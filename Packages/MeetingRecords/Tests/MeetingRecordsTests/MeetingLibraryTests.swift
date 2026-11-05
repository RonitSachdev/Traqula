import Foundation
import Testing
@testable import MeetingRecords

struct MeetingLibraryTests {
    private func makeMeeting(in root: URL, startedAt: Date, lines: [(AudioChannel, String, String?)], ended: Bool) async throws -> MeetingRecord {
        let record = try MeetingRecord(root: root, startedAt: startedAt)
        for (offset, line) in lines.enumerated() {
            try await record.append(Utterance(
                id: UUID(), channel: line.0, startedAt: startedAt.addingTimeInterval(Double(offset) * 5), duration: 3,
                sourceLanguage: "ja", targetLanguage: "en", sourceText: line.1, translatedText: line.2
            ))
        }
        if ended { try await record.end(at: startedAt.addingTimeInterval(600)) }
        return record
    }

    @Test func listsMeetingsNewestFirstAndResolvesLatest() async throws {
        let root = URL.temporaryDirectory.appending(path: "MeetingLibraryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let older = Date(timeIntervalSince1970: 1_762_000_000)
        let newer = older.addingTimeInterval(86_400)
        _ = try await makeMeeting(in: root, startedAt: older, lines: [(.system, "古い", "old")], ended: true)
        _ = try await makeMeeting(in: root, startedAt: newer, lines: [(.system, "新しい", "new")], ended: true)

        let library = MeetingLibrary(root: root)
        let meetings = try library.meetings()
        #expect(meetings.map(\.startedAt) == [newer, older])
        #expect(try library.meeting(id: "latest")?.startedAt == newer)
        #expect(try library.meeting(id: meetings[1].id)?.startedAt == older)
        #expect(try library.meeting(id: meetings[1].manifest.id.uuidString)?.startedAt == older)
    }

    @Test func liveMeetingIsTheUnfinishedOneStillBeingWritten() async throws {
        let root = URL.temporaryDirectory.appending(path: "MeetingLibraryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await makeMeeting(in: root, startedAt: .now.addingTimeInterval(-3600), lines: [(.system, "a", "a")], ended: true)
        let live = try await makeMeeting(in: root, startedAt: .now, lines: [(.microphone, "b", "b")], ended: false)

        let library = MeetingLibrary(root: root)
        #expect(try library.liveMeeting()?.id == live.directory.lastPathComponent)
        #expect(try library.liveMeeting(now: .now.addingTimeInterval(MeetingLibrary.liveThreshold + 1)) == nil)
    }

    @Test func searchMatchesOriginalAndTranslatedTextCaseInsensitively() async throws {
        let root = URL.temporaryDirectory.appending(path: "MeetingLibraryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await makeMeeting(in: root, startedAt: .now, lines: [
            (.system, "リリース計画について", "About the release plan"),
            (.microphone, "はい", "Yes"),
            (.system, "バグ修正", "Bug fix"),
        ], ended: true)

        let library = MeetingLibrary(root: root)
        #expect(try library.search("RELEASE").map(\.utterance.translatedText) == ["About the release plan"])
        #expect(try library.search("バグ").map(\.utterance.sourceText) == ["バグ修正"])
        #expect(try library.search("  ").isEmpty)
        #expect(try library.search("i", limit: 1).count == 1)
    }
}
