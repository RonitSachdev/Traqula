import Foundation
import MCP
import MeetingRecords

// traqula-mcp: a stdio MCP server that lets any MCP client list, read, search, and summarize Traqula's meeting records.
//
//   traqula-mcp [--meetings <folder>]      (default: ~/Library/Application Support/Traqula/Meetings)

let arguments = CommandLine.arguments
let meetingsRoot: URL = {
    if let index = arguments.firstIndex(of: "--meetings"), index + 1 < arguments.count {
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }
    return MeetingRecord.defaultRoot
}()
let tools = MeetingTools(library: MeetingLibrary(root: meetingsRoot))

let server = Server(
    name: "traqula",
    version: "0.2.0",
    instructions: "Reads meeting transcripts captioned by Traqula on this Mac. Meetings have two speakers: 'Them' (remote participants) and 'Me' (the user). Start with list_meetings or live_meeting, then get_transcript or meeting_summary.",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: MeetingTools.definitions)
}

await server.withMethodHandler(CallTool.self) { params in
    do {
        return .init(content: [.text(text: try await tools.call(params.name, arguments: params.arguments ?? [:]), annotations: nil, _meta: nil)], isError: false)
    } catch {
        return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
    }
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
