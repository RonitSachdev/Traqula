import AppKit
import Foundation

/// The Traqula Bridge Chrome extension: shipped inside the app bundle and installed to a folder the
/// user can find and point Chrome's "Load unpacked" at.
enum BrowserExtension {
    /// Where Chrome loads the extension from. Outside the app bundle so the path reads naturally in a
    /// file picker and stays the same across app updates and rebuilds.
    static let installedURL = URL.applicationSupportDirectory.appending(path: "Traqula/Extension")

    private static var bundledURL: URL? {
        Bundle.main.resourceURL?.appending(path: "extension")
    }

    /// Replaces the installed copy with the bundled one in a single step, so a loaded extension never
    /// sees a half-written folder. Chrome reads the folder live; reloading the extension picks up changes.
    static func install() throws {
        guard let bundled = bundledURL else { return }
        let fileManager = FileManager.default
        let parent = installedURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appending(path: ".Extension-\(UUID().uuidString)")
        try fileManager.copyItem(at: bundled, to: staging)
        if fileManager.fileExists(atPath: installedURL.path) {
            _ = try fileManager.replaceItemAt(installedURL, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: installedURL)
        }
    }

    /// Opens the folder itself in Finder.
    static func reveal() {
        NSWorkspace.shared.open(installedURL)
    }

    /// Puts the folder path on the clipboard for Chrome's file picker (⌘⇧G, paste).
    static func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(installedURL.path, forType: .string)
    }
}
