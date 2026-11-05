import Foundation
import Testing
@testable import Traqula

struct MeetingRecordTests {
    @Test func writesManifestAndTranscriptThatReadBack() async throws {
        let root = URL.temporaryDirectory.appending(path: "TraqulaTests-\(UUID().uuidString)")
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
}
