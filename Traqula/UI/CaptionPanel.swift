import AppKit
import SwiftUI

/// Borderless, always-on-top window that shows captions over any app, including full-screen meetings,
/// without taking keyboard focus away from them. Resizable from its edges and movable by dragging anywhere.
final class CaptionPanel: NSPanel {
    init(contentView: NSView, hiddenFromScreenSharing: Bool) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // `.none` keeps the window out of screenshots and screen sharing, so viewers never see the captions.
        sharingType = hiddenFromScreenSharing ? .none : .readOnly
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        minSize = CGSize(width: 360, height: 120)
        self.contentView = contentView
    }
}

/// Owns the caption panel for one session. The panel's size and position persist between sessions.
@MainActor
final class CaptionPanelController {
    private static let frameAutosaveName = "CaptionPanel"
    private let panel: CaptionPanel

    init(session: CaptionSession, settings: CaptionSettings) {
        let content = NSHostingView(rootView: CaptionView(session: session, settings: settings))
        panel = CaptionPanel(contentView: content, hiddenFromScreenSharing: settings.hideFromScreenSharing)
    }

    func show() {
        if !panel.setFrameUsingName(Self.frameAutosaveName), let screen = NSScreen.main {
            let area = screen.visibleFrame
            let size = CGSize(width: min(900, area.width - 80), height: 220)
            let origin = CGPoint(x: area.midX - size.width / 2, y: area.minY + 40)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        panel.orderFrontRegardless()
    }

    func close() {
        panel.close()
    }
}
