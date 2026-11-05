import Foundation

/// One recorded meeting as found on disk.
public struct Meeting: Identifiable, Sendable, Equatable {
    /// The meeting's folder name, e.g. `2026-11-05 10-40-12`. Stable and human-readable, so it doubles as the public id.
    public let id: String
    public let directory: URL
    public let manifest: MeetingManifest

    public var startedAt: Date { manifest.startedAt }
    public var endedAt: Date? { manifest.endedAt }
}

public struct SearchHit: Sendable, Equatable {
    public let meeting: Meeting
    public let utterance: Utterance
}

/// Read-only access to every meeting under a root folder, newest first.
public struct MeetingLibrary: Sendable {
    public let root: URL

    /// A meeting with no end time counts as live only while its transcript is still being written.
    public static let liveThreshold: TimeInterval = 15 * 60

    public init(root: URL = MeetingRecord.defaultRoot) {
        self.root = root
    }

    public func meetings() throws -> [Meeting] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return folders
            .compactMap { folder -> Meeting? in
                guard let manifest = try? MeetingRecord.manifest(in: folder) else { return nil }
                return Meeting(id: folder.lastPathComponent, directory: folder, manifest: manifest)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// Looks a meeting up by folder name, by manifest UUID, or by the word `latest`.
    public func meeting(id: String) throws -> Meeting? {
        let all = try meetings()
        if id.lowercased() == "latest" { return all.first }
        return all.first { $0.id == id || $0.manifest.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }
    }

    /// The meeting currently being captioned, if any.
    public func liveMeeting(now: Date = .now) throws -> Meeting? {
        try meetings().first { meeting in
            guard meeting.endedAt == nil else { return false }
            let transcript = MeetingRecord.transcriptURL(in: meeting.directory)
            let modified = (try? transcript.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return now.timeIntervalSince(modified) < Self.liveThreshold
        }
    }

    public func utterances(of meeting: Meeting) throws -> [Utterance] {
        try MeetingRecord.utterances(in: meeting.directory)
    }

    /// Case-insensitive substring search over original and translated text, newest meetings first.
    public func search(_ query: String, limit: Int = 20) throws -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for meeting in try meetings() {
            for utterance in try utterances(of: meeting) where hits.count < limit {
                let haystacks = [utterance.sourceText, utterance.translatedText ?? ""]
                if haystacks.contains(where: { $0.localizedCaseInsensitiveContains(needle) }) {
                    hits.append(SearchHit(meeting: meeting, utterance: utterance))
                }
            }
            if hits.count >= limit { break }
        }
        return hits
    }
}
