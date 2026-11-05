import Foundation
import FoundationModels
import MeetingRecords

public enum SummaryError: LocalizedError {
    case modelUnavailable(String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case let .modelUnavailable(reason): "The on-device model is unavailable: \(reason)"
        case .emptyTranscript: "The meeting has no transcript lines to summarize."
        }
    }
}

/// Summarizes a meeting transcript with the on-device Apple Intelligence model, so nothing leaves the Mac.
///
/// The model's context window is small, so long transcripts are summarized part by part and the notes
/// are merged into one summary.
public struct MeetingSummarizer: Sendable {
    /// Transcript characters per model call. Leaves room in the context window for the instructions and the answer.
    public static let chunkCharacterBudget = 5_000

    public init() {}

    /// Nil when the model can be used; otherwise a sentence the user can act on.
    public static func availabilityProblem() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: "this Mac does not support Apple Intelligence."
            case .appleIntelligenceNotEnabled: "turn on Apple Intelligence in System Settings."
            case .modelNotReady: "Apple Intelligence is still downloading its model; try again in a few minutes."
            @unknown default: "Apple Intelligence is not available right now."
            }
        }
    }

    public func summarize(_ meeting: Meeting, utterances: [Utterance]) async throws -> String {
        if let problem = Self.availabilityProblem() { throw SummaryError.modelUnavailable(problem) }
        let lines = Self.transcriptLines(utterances, relativeTo: meeting.startedAt)
        guard !lines.isEmpty else { throw SummaryError.emptyTranscript }

        let parts = Self.chunk(lines, budget: Self.chunkCharacterBudget)
        if parts.count == 1 {
            return try await respond(Self.summaryInstructions, to: parts[0])
        }

        var notes: [String] = []
        for (index, part) in parts.enumerated() {
            notes.append(try await respond(Self.notesInstructions, to: "Part \(index + 1) of \(parts.count):\n\(part)"))
        }
        // Fold the notes until they fit in one call, then write the final summary from them.
        while notes.joined(separator: "\n\n").count > Self.chunkCharacterBudget, notes.count > 1 {
            var folded: [String] = []
            for group in Self.chunk(notes, budget: Self.chunkCharacterBudget) {
                folded.append(try await respond(Self.notesInstructions, to: group))
            }
            notes = folded
        }
        return try await respond(Self.summaryInstructions, to: notes.joined(separator: "\n\n"))
    }

    private func respond(_ instructions: String, to prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3)).content
    }

    // MARK: Prompts

    static let summaryInstructions = """
        You write summaries of meeting transcripts. In the transcript, "Them" is what other participants said \
        and "Me" is what the user said; names mentioned in a line are people being talked to or about, not the speaker. \
        "Me" lines were captured by the user's own microphone, so they may include side conversations with people \
        in the room while the user was muted; if a "Me" line clearly does not belong to the meeting, leave it out. \
        Write in the same language as the transcript. Be factual and specific; never invent details or names. \
        Output markdown with exactly these sections: "## Summary" (3-6 sentences), "## Decisions" (bullets, or "None"), \
        "## Action items" (bullets with who and what, or "None"), "## Open questions" (bullets, or "None").
        """

    static let notesInstructions = """
        You take notes on one part of a longer meeting transcript (or on notes from earlier parts). \
        In the transcript, "Them" is what other participants said and "Me" is what the user said; "Me" lines came from \
        the user's own microphone and may include side talk with people in the room while muted, which you should leave out. \
        Write in the same language as the input. List, as concise bullets, the topics discussed, any decisions, \
        any action items with who and what, and open questions. Keep every concrete detail (names, dates, numbers); \
        never invent any.
        """

    // MARK: Transcript preparation

    /// `[mm:ss] Speaker: text` lines, using the translation when there is one.
    public static func transcriptLines(_ utterances: [Utterance], relativeTo start: Date) -> [String] {
        utterances.map { utterance in
            let offset = max(0, Int(utterance.startedAt.timeIntervalSince(start)))
            let stamp = String(format: "[%02d:%02d]", offset / 60, offset % 60)
            return "\(stamp) \(utterance.channel.displayName): \(utterance.translatedText ?? utterance.sourceText)"
        }
    }

    /// Joins consecutive lines into parts no longer than `budget` characters. A single line longer than the budget
    /// becomes a part of its own rather than being cut.
    public static func chunk(_ lines: [String], budget: Int) -> [String] {
        var parts: [String] = []
        var current = ""
        for line in lines {
            if current.isEmpty {
                current = line
            } else if current.count + 1 + line.count <= budget {
                current += "\n" + line
            } else {
                parts.append(current)
                current = line
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
