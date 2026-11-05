import Foundation
import MeetingRecords
import Observation

/// The live state of the browser meeting, as reported by the Traqula Bridge extension.
@MainActor
@Observable
final class MeetingBridge {
    struct SpeakerChange: Equatable {
        let at: Date
        let name: String?
    }

    var isExtensionConnected = false
    private(set) var snapshot: BridgeSnapshot?
    /// Recent active-speaker changes, so a line can be attributed to whoever was speaking when it was said,
    /// not whoever is speaking when recognition finishes a second or two later.
    private(set) var speakerChanges: [SpeakerChange] = []

    var inCall: Bool { snapshot?.inCall ?? false }
    var isMuted: Bool? { snapshot?.muted }
    var title: String? { snapshot?.title }
    var participants: [String] { snapshot?.participants ?? [] }
    var selfName: String? { snapshot?.me }

    func apply(_ snapshot: BridgeSnapshot, at date: Date = .now) {
        if snapshot.speaker != self.snapshot?.speaker {
            speakerChanges.append(SpeakerChange(at: date, name: snapshot.speaker))
            if speakerChanges.count > 500 { speakerChanges.removeFirst(speakerChanges.count - 500) }
        }
        self.snapshot = snapshot
    }

    /// The name to put on a line spoken at `date` on `channel`, or nil when nothing is known.
    func speakerName(for channel: AudioChannel, at date: Date) -> String? {
        switch channel {
        case .microphone: selfName
        case .system: speakerChanges.last { $0.at <= date }?.name
        }
    }
}
