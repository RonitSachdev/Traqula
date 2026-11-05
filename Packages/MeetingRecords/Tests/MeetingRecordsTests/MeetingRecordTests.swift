import Foundation
import Testing
@testable import MeetingRecords

struct MeetingRecordTests {
    @Test func writesManifestAndTranscriptThatReadBack() async throws {
        let root = URL.temporaryDirectory.appending(path: "MeetingRecordsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let startedAt = Date(timeIntervalSince1970: 1_762_300_000)

        let record = try MeetingRecord(root: root, startedAt: startedAt)
        let first = Utterance(
            id: UUID(), channel: .system, startedAt: startedAt, duration: 1.5,
            sourceLanguage: "ja", targetLanguage: "en",
            sourceText: "おはようございます。", translatedText: "Good morning."
        )
        let second = Utterance(
            id: UUID(), channel: .microphone, startedAt: startedAt.addingTimeInterval(2), duration: 0.8,
            sourceLanguage: "en", targetLanguage: nil,
            sourceText: "Morning.", translatedText: nil
        )
        try await record.append(first)
        try await record.append(second)
        try await record.end(at: startedAt.addingTimeInterval(60))

        let manifest = try MeetingRecord.manifest(in: record.directory)
        #expect(manifest.startedAt == startedAt)
        #expect(manifest.endedAt == startedAt.addingTimeInterval(60))
        #expect(try MeetingRecord.utterances(in: record.directory) == [first, second])
        #expect(record.directory.path.hasPrefix(root.path))
    }

    @Test func partialTrailingLineFromLiveWritingIsIgnored() async throws {
        let root = URL.temporaryDirectory.appending(path: "MeetingRecordsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let record = try MeetingRecord(root: root)
        // Whole seconds: the record stores ISO 8601 dates, which carry no fractional seconds.
        let utterance = Utterance(
            id: UUID(), channel: .system, startedAt: Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)), duration: 1,
            sourceLanguage: "ja", targetLanguage: "en", sourceText: "はい", translatedText: "Yes"
        )
        try await record.append(utterance)
        let handle = try FileHandle(forWritingTo: MeetingRecord.transcriptURL(in: record.directory))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"half-writ".utf8))
        try handle.close()

        #expect(try MeetingRecord.utterances(in: record.directory) == [utterance])
    }
}
