import Foundation
import MeetingRecords
import Testing
@testable import Traqula

@MainActor
struct MeetingBridgeTests {
    private func snapshot(speaker: String?, me: String? = "Ronit", muted: Bool? = false) -> BridgeSnapshot {
        BridgeSnapshot(site: "meet", inCall: true, title: "Standup", muted: muted, speaker: speaker, participants: ["Tanaka", "Ronit"], me: me)
    }

    @Test func attributesLinesToWhoeverWasSpeakingAtThatMoment() {
        let bridge = MeetingBridge()
        let t0 = Date(timeIntervalSince1970: 1_762_300_000)
        bridge.apply(snapshot(speaker: "Tanaka"), at: t0)
        bridge.apply(snapshot(speaker: nil), at: t0.addingTimeInterval(5))
        bridge.apply(snapshot(speaker: "Suzuki"), at: t0.addingTimeInterval(8))

        #expect(bridge.speakerName(for: .system, at: t0.addingTimeInterval(-1)) == nil)
        #expect(bridge.speakerName(for: .system, at: t0.addingTimeInterval(2)) == "Tanaka")
        #expect(bridge.speakerName(for: .system, at: t0.addingTimeInterval(6)) == nil)
        #expect(bridge.speakerName(for: .system, at: t0.addingTimeInterval(20)) == "Suzuki")
        #expect(bridge.speakerName(for: .microphone, at: t0.addingTimeInterval(20)) == "Ronit")
    }

    @Test func unchangedSpeakerDoesNotAddHistory() {
        let bridge = MeetingBridge()
        bridge.apply(snapshot(speaker: "Tanaka", muted: false))
        bridge.apply(snapshot(speaker: "Tanaka", muted: true))

        #expect(bridge.speakerChanges.count == 1)
        #expect(bridge.isMuted == true)
    }
}
