import AppKit
import Foundation
import Observation

/// Traqula's MCP server, shipped inside the app bundle, and the ways to point an assistant at it.
enum MCPServer {
    static let name = "traqula"

    static var executableURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "traqula-mcp")
    }

    /// The `mcpServers` JSON shape most desktop assistants accept.
    static func jsonSnippet(for executable: URL) -> String {
        """
        {
          "mcpServers": {
            "\(name)": {
              "command": "\(executable.path)"
            }
          }
        }
        """
    }

    static func claudeCodeCommand(for executable: URL) -> String {
        "claude mcp add --scope user \(name) \"\(executable.path)\""
    }

    static func codexSnippet(for executable: URL) -> String {
        "[mcp_servers.\(name)]\ncommand = \"\(executable.path)\""
    }
}

/// An assistant that reads its MCP servers from a JSON file with an `mcpServers` object.
struct MCPClient: Identifiable, Sendable {
    let name: String
    let configURL: URL

    var id: String { name }

    static let known: [MCPClient] = [
        MCPClient(name: "Claude Desktop", configURL: .applicationSupportDirectory.appending(path: "Claude/claude_desktop_config.json")),
        MCPClient(name: "Cursor", configURL: .homeDirectory.appending(path: ".cursor/mcp.json")),
        MCPClient(name: "Windsurf", configURL: .homeDirectory.appending(path: ".codeium/windsurf/mcp_config.json")),
        MCPClient(name: "Gemini CLI", configURL: .homeDirectory.appending(path: ".gemini/settings.json")),
    ]

    /// The app counts as installed when its settings folder exists.
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: configURL.deletingLastPathComponent().path)
    }

    func isRegistered(executable: URL) -> Bool {
        guard let config = try? readConfig(), let servers = config["mcpServers"] as? [String: Any],
              let entry = servers[MCPServer.name] as? [String: Any] else { return false }
        return entry["command"] as? String == executable.path
    }

    /// Adds or replaces the `traqula` entry, leaving every other server in the file untouched.
    func register(executable: URL) throws {
        var config = try readConfig() ?? [:]
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        servers[MCPServer.name] = ["command": executable.path]
        config["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: configURL, options: .atomic)
    }

    private func readConfig() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
        let data = try Data(contentsOf: configURL)
        guard !data.isEmpty else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// State behind the Settings section that connects assistants to the MCP server.
@MainActor
@Observable
final class AssistantConnections {
    enum Status: Equatable {
        case notInstalled, available, connected
    }

    let executable: URL? = MCPServer.executableURL
    private(set) var statuses: [String: Status] = [:]
    private(set) var message: String?

    func refresh() {
        guard let executable else { return }
        for client in MCPClient.known {
            statuses[client.id] = !client.isInstalled ? .notInstalled : client.isRegistered(executable: executable) ? .connected : .available
        }
    }

    func connect(_ client: MCPClient) {
        guard let executable else { return }
        do {
            try client.register(executable: executable)
            message = "Added to \(client.name). Restart \(client.name) to pick it up."
        } catch {
            message = "Could not update \(client.name)'s settings: \(error.localizedDescription)"
        }
        refresh()
    }

    func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        message = "\(label) copied to the clipboard."
    }
}
