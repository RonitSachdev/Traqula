import AppKit
import SwiftUI
import MeetingRecords

struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(model.isRunning ? "Stop Captions" : "Start Captions") {
            model.toggleCaptions()
        }
        .disabled(model.state == .starting || model.state == .stopping)

        if model.isCapturingMicrophone {
            Button(model.isMicrophonePaused ? "Resume My Mic Captions" : "Pause My Mic Captions") {
                model.toggleMicrophonePause()
            }
        }
        if model.state == .starting {
            Text("Preparing speech and translation models…")
        }
        if let message = model.statusMessage ?? model.session?.lastError {
            Text(message)
        }

        Divider()

        Button("Show Meetings Folder") {
            NSWorkspace.shared.open(MeetingRecord.defaultRoot)
        }
        Button("Settings…") {
            // A menu bar app is not the active app when its menu is used, so the window would open behind others.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }

        Divider()

        Button("Quit Traqula") {
            NSApplication.shared.terminate(nil)
        }
    }
}
