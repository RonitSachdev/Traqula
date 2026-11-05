import SwiftUI

/// Menu bar app: captions live in a floating panel, settings in a standard window, and nothing in the Dock.
@main
struct TraqulaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Traqula", image: "MenuBarIcon") {
            MenuBarView(model: model)
        }
        Settings {
            SettingsView()
        }
    }
}
