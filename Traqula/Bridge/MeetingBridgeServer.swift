import Foundation
import Network
import OSLog

/// What the Traqula Bridge extension reports about a meeting page: one full snapshot whenever something changes.
struct BridgeSnapshot: Codable, Sendable, Equatable {
    var site: String
    var inCall: Bool
    var title: String?
    var muted: Bool?
    var speaker: String?
    var participants: [String]
    var me: String?
}

/// Accepts the extension's WebSocket on localhost and hands every snapshot to the app.
///
/// Only the loopback interface is listened on, so nothing outside this Mac can reach it.
@MainActor
final class MeetingBridgeServer {
    static let port: UInt16 = 48213

    private nonisolated static let logger = Logger(subsystem: "dev.ronit.Traqula", category: "MeetingBridgeServer")

    private let listener: NWListener
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let onSnapshot: (BridgeSnapshot) -> Void
    private let onConnectionCountChange: (Int) -> Void

    init(onSnapshot: @escaping (BridgeSnapshot) -> Void, onConnectionCountChange: @escaping (Int) -> Void) throws {
        self.onSnapshot = onSnapshot
        self.onConnectionCountChange = onConnectionCountChange

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            Task { @MainActor [weak self] in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                Self.logger.error("Bridge listener failed: \(error, privacy: .public)")
            }
        }
        listener.start(queue: .main)
    }

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        Self.logger.info("Extension connected")
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor [weak self] in self?.drop(connection) }
            default:
                break
            }
        }
        connection.start(queue: .main)
        receive(on: connection)
        onConnectionCountChange(connections.count)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { data, _, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, let snapshot = try? JSONDecoder().decode(BridgeSnapshot.self, from: data) {
                    Self.logger.info("Snapshot from \(snapshot.site, privacy: .public): inCall=\(snapshot.inCall) muted=\(String(describing: snapshot.muted), privacy: .public) speaker=\(snapshot.speaker ?? "-", privacy: .public) participants=\(snapshot.participants.count)")
                    onSnapshot(snapshot)
                }
                if error == nil {
                    receive(on: connection)
                } else {
                    drop(connection)
                }
            }
        }
    }

    private func drop(_ connection: NWConnection) {
        guard connections.removeValue(forKey: ObjectIdentifier(connection)) != nil else { return }
        connection.cancel()
        onConnectionCountChange(connections.count)
    }
}
