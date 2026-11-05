import Foundation

/// One spoken segment of a meeting, with its translation when the channel was translated.
struct Utterance: Codable, Sendable, Equatable {
    let id: UUID
    let channel: AudioChannel
    let startedAt: Date
    let duration: TimeInterval
    /// BCP 47 language codes.
    let sourceLanguage: String
    let targetLanguage: String?
    let sourceText: String
    let translatedText: String?
}

struct MeetingManifest: Codable, Sendable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
}

/// The on-disk record of one meeting: `meeting.json` plus an append-only `transcript.jsonl` with one utterance per line.
///
/// Plain files on purpose, so meeting summaries and the planned MCP server can read a meeting without this app.
actor MeetingRecord {
    static let defaultRoot = URL.applicationSupportDirectory
        .appending(path: "Traqula", directoryHint: .isDirectory)
        .appending(path: "Meetings", directoryHint: .isDirectory)

    nonisolated let directory: URL
    private var manifest: MeetingManifest
    private let transcript: FileHandle
    private let encoder = MeetingRecord.makeEncoder()

    init(root: URL = MeetingRecord.defaultRoot, startedAt: Date = .now) throws {
        directory = root.appending(path: Self.folderName(for: startedAt), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let transcriptURL = directory.appending(path: Self.transcriptFileName)
        guard FileManager.default.createFile(atPath: transcriptURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: transcriptURL.path])
        }
        transcript = try FileHandle(forWritingTo: transcriptURL)
        manifest = MeetingManifest(id: UUID(), startedAt: startedAt, endedAt: nil)
        try Self.write(manifest, to: directory, encoder: encoder)
    }

    func append(_ utterance: Utterance) throws {
        var line = try encoder.encode(utterance)
        line.append(UInt8(ascii: "\n"))
        try transcript.write(contentsOf: line)
    }

    func end(at date: Date = .now) throws {
        manifest.endedAt = date
        try Self.write(manifest, to: directory, encoder: encoder)
        try transcript.close()
    }

    // MARK: Reading

    static func manifest(in directory: URL) throws -> MeetingManifest {
        try makeDecoder().decode(MeetingManifest.self, from: Data(contentsOf: directory.appending(path: manifestFileName)))
    }

    static func utterances(in directory: URL) throws -> [Utterance] {
        let decoder = makeDecoder()
        let contents = try String(contentsOf: directory.appending(path: transcriptFileName), encoding: .utf8)
        return try contents.split(separator: "\n").map { try decoder.decode(Utterance.self, from: Data($0.utf8)) }
    }

    // MARK: Files

    private static let manifestFileName = "meeting.json"
    private static let transcriptFileName = "transcript.jsonl"

    private static func write(_ manifest: MeetingManifest, to directory: URL, encoder: JSONEncoder) throws {
        try encoder.encode(manifest).write(to: directory.appending(path: manifestFileName), options: .atomic)
    }

    private static func folderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter.string(from: date)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
