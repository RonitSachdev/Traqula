import Foundation
import MCP
import MeetingRecords
import MeetingSummaries

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The MCP tools Traqula exposes, and how each one renders meeting records as text an assistant can read.
struct MeetingTools: Sendable {
    let library: MeetingLibrary
    let summaries: MeetingSummaryService

    init(library: MeetingLibrary) {
        self.library = library
        summaries = MeetingSummaryService(library: library)
    }

    static let definitions: [Tool] = [
        Tool(
            name: "list_meetings",
            description: "List recorded meetings, newest first, with id, start and end time, duration, and line count. Use the id with get_transcript.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "limit": .object(["type": "integer", "description": "Maximum meetings to return. Default 20."]),
                ]),
            ])
        ),
        Tool(
            name: "get_transcript",
            description: "The transcript of one meeting as timestamped lines. 'Them' is remote participants, 'Me' is the user. Narrow long meetings with start_seconds/end_seconds.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "meeting": .object(["type": "string", "description": "Meeting id from list_meetings, or 'latest'. Default 'latest'."]),
                    "start_seconds": .object(["type": "number", "description": "Only lines at or after this many seconds into the meeting."]),
                    "end_seconds": .object(["type": "number", "description": "Only lines before this many seconds into the meeting."]),
                    "speaker": .object(["type": "string", "enum": .array(["them", "me"]), "description": "Only one side of the conversation."]),
                    "text": .object(["type": "string", "enum": .array(["translated", "original", "both"]), "description": "Which text to show. Default 'translated' (falls back to the original when a line was not translated)."]),
                ]),
            ])
        ),
        Tool(
            name: "search_transcripts",
            description: "Find lines across all meetings containing a word or phrase, in either the original or translated text. Case-insensitive.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object(["type": "string", "description": "Word or phrase to look for."]),
                    "limit": .object(["type": "integer", "description": "Maximum matches to return. Default 20."]),
                ]),
                "required": .array(["query"]),
            ])
        ),
        Tool(
            name: "meeting_summary",
            description: "A summary of one meeting (summary, decisions, action items, open questions), written on-device by Apple Intelligence and cached next to the transcript. Generating one can take a minute for a long meeting.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "meeting": .object(["type": "string", "description": "Meeting id from list_meetings, or 'latest'. Default 'latest'."]),
                    "refresh": .object(["type": "boolean", "description": "Regenerate even if a summary is cached. Default false."]),
                ]),
            ])
        ),
        Tool(
            name: "live_meeting",
            description: "The last few minutes of the meeting being captioned right now, if one is in progress.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "minutes": .object(["type": "number", "description": "How many minutes back to include. Default 5."]),
                ]),
            ])
        ),
    ]

    func call(_ name: String, arguments: [String: Value]) async throws -> String {
        switch name {
        case "list_meetings": try listMeetings(limit: arguments["limit"]?.intValue ?? 20)
        case "get_transcript": try transcript(arguments)
        case "search_transcripts": try search(arguments)
        case "meeting_summary": try await summary(arguments)
        case "live_meeting": try liveMeeting(minutes: arguments["minutes"]?.doubleValue ?? 5)
        default: throw ToolError(message: "Unknown tool: \(name)")
        }
    }

    // MARK: Tools

    private func listMeetings(limit: Int) throws -> String {
        let meetings = try library.meetings().prefix(max(limit, 1))
        guard !meetings.isEmpty else { return "No meetings recorded yet. Meetings appear here once Traqula captions one." }
        return try meetings.map { meeting in
            let lines = try library.utterances(of: meeting)
            return "\(meeting.id) — \(describe(meeting, lineCount: lines.count))"
        }.joined(separator: "\n")
    }

    private func transcript(_ arguments: [String: Value]) throws -> String {
        let id = arguments["meeting"]?.stringValue ?? "latest"
        guard let meeting = try library.meeting(id: id) else {
            throw ToolError(message: id == "latest" ? "No meetings recorded yet." : "No meeting with id '\(id)'. Use list_meetings to see ids.")
        }
        var lines = try library.utterances(of: meeting)
        let total = lines.count
        if let start = arguments["start_seconds"]?.doubleValue {
            lines = lines.filter { $0.startedAt.timeIntervalSince(meeting.startedAt) >= start }
        }
        if let end = arguments["end_seconds"]?.doubleValue {
            lines = lines.filter { $0.startedAt.timeIntervalSince(meeting.startedAt) < end }
        }
        if let speaker = arguments["speaker"]?.stringValue {
            let channel: AudioChannel = speaker.lowercased() == "me" ? .microphone : .system
            lines = lines.filter { $0.channel == channel }
        }
        let text = TextChoice(rawValue: arguments["text"]?.stringValue ?? "translated") ?? .translated
        let header = "Meeting \(meeting.id) — \(describe(meeting, lineCount: total))"
        guard !lines.isEmpty else { return header + "\nNo lines match." }
        return header + "\n" + format(lines, relativeTo: meeting.startedAt, text: text)
    }

    private func search(_ arguments: [String: Value]) throws -> String {
        guard let query = arguments["query"]?.stringValue, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ToolError(message: "search_transcripts needs a non-empty 'query'.")
        }
        let hits = try library.search(query, limit: arguments["limit"]?.intValue ?? 20)
        guard !hits.isEmpty else { return "No lines contain \"\(query)\"." }
        return hits.map { hit in
            "\(hit.meeting.id) " + format([hit.utterance], relativeTo: hit.meeting.startedAt, text: .both)
        }.joined(separator: "\n")
    }

    private func summary(_ arguments: [String: Value]) async throws -> String {
        let id = arguments["meeting"]?.stringValue ?? "latest"
        guard let meeting = try library.meeting(id: id) else {
            throw ToolError(message: id == "latest" ? "No meetings recorded yet." : "No meeting with id '\(id)'. Use list_meetings to see ids.")
        }
        let summary = try await summaries.summary(for: meeting, refresh: arguments["refresh"]?.boolValue ?? false)
        return "Summary of meeting \(meeting.id) — \(describe(meeting, lineCount: try library.utterances(of: meeting).count))\n\n" + summary
    }

    private func liveMeeting(minutes: Double) throws -> String {
        guard let meeting = try library.liveMeeting() else {
            return "No meeting is being captioned right now."
        }
        let lines = try library.utterances(of: meeting)
        let cutoff = Date.now.addingTimeInterval(-max(minutes, 0.5) * 60)
        let recent = lines.filter { $0.startedAt >= cutoff }
        let header = "Live meeting \(meeting.id), started \(Self.dateFormatter.string(from: meeting.startedAt)), \(lines.count) lines so far"
        guard !recent.isEmpty else { return header + "\nNothing said in the last \(Self.minutes(minutes))." }
        return header + "\n" + format(recent, relativeTo: meeting.startedAt, text: .translated)
    }

    // MARK: Rendering

    private enum TextChoice: String {
        case translated, original, both
    }

    private func describe(_ meeting: Meeting, lineCount: Int) -> String {
        let started = Self.dateFormatter.string(from: meeting.startedAt)
        let length: String
        if let ended = meeting.endedAt {
            length = Self.minutes(ended.timeIntervalSince(meeting.startedAt) / 60)
        } else {
            length = "in progress"
        }
        return "started \(started), \(length), \(lineCount) lines"
    }

    private func format(_ lines: [Utterance], relativeTo start: Date, text: TextChoice) -> String {
        lines.map { line in
            let offset = max(0, Int(line.startedAt.timeIntervalSince(start)))
            let stamp = String(format: "[%02d:%02d]", offset / 60, offset % 60)
            let body: String = switch text {
            case .translated: line.translatedText ?? line.sourceText
            case .original: line.sourceText
            case .both: line.translatedText.map { "\($0)  (\(line.sourceText))" } ?? line.sourceText
            }
            return "\(stamp) \(line.channel.displayName): \(body)"
        }.joined(separator: "\n")
    }

    private static func minutes(_ value: Double) -> String {
        value < 1.5 ? "1 minute" : "\(Int(value.rounded())) minutes"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
