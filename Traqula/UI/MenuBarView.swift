import AppKit
import SwiftUI

struct MenuBarView: View {
    let model: AppModel

    var body: some View {
        Button(model.isRunning ? "Stop Captions" : "Start Captions") {
            model.toggleCaptions()
        }
        .disabled(model.state == .starting || model.state == .stopping)

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
        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit Traqula") {
            NSApplication.shared.terminate(nil)
        }
    }
}
