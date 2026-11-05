import Foundation
import MeetingRecords

/// Returns a meeting's summary, generating it on first use and whenever the transcript has grown since.
public struct MeetingSummaryService: Sendable {
    private let library: MeetingLibrary
    private let summarizer: MeetingSummarizer

    public init(library: MeetingLibrary, summarizer: MeetingSummarizer = MeetingSummarizer()) {
        self.library = library
        self.summarizer = summarizer
    }

    public func summary(for meeting: Meeting, refresh: Bool = false) async throws -> String {
        let summaryURL = MeetingRecord.summaryURL(in: meeting.directory)
        if !refresh, let cached = try? String(contentsOf: summaryURL, encoding: .utf8), Self.isCurrent(summaryURL, for: meeting) {
            return cached
        }
        let summary = try await summarizer.summarize(meeting, utterances: try library.utterances(of: meeting))
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
        return summary
    }

    /// A cached summary is current when nothing has been added to the transcript since it was written.
    private static func isCurrent(_ summaryURL: URL, for meeting: Meeting) -> Bool {
        let transcriptURL = MeetingRecord.transcriptURL(in: meeting.directory)
        guard let summaryDate = modificationDate(of: summaryURL), let transcriptDate = modificationDate(of: transcriptURL) else {
            return false
        }
        return summaryDate >= transcriptDate
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
