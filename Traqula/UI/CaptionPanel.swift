import AppKit
import SwiftUI

/// Borderless, always-on-top window that shows captions over any app, including full-screen meetings,
/// without taking keyboard focus away from them. Resizable from its edges and the corner grip, movable by
/// dragging anywhere else.
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

        let container = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        let grip = ResizeGripView()
        grip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)
        container.addSubview(grip)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: container.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            grip.widthAnchor.constraint(equalToConstant: ResizeGripView.size),
            grip.heightAnchor.constraint(equalToConstant: ResizeGripView.size),
            grip.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            grip.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        self.contentView = container
    }
}

/// Three soft diagonal lines in the card's corner; dragging them resizes the panel from that corner,
/// which a borderless window otherwise gives no hint of.
private final class ResizeGripView: NSView {
    static let size: CGFloat = 14

    private var dragStart: (mouse: NSPoint, frame: NSRect)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        for inset: CGFloat in [2, 6, 10] {
            path.move(to: NSPoint(x: bounds.maxX - 1, y: bounds.minY + inset))
            path.line(to: NSPoint(x: bounds.minX + inset, y: bounds.maxY - 1))
        }
        NSColor.black.withAlphaComponent(0.25).setStroke()
        path.transform(using: AffineTransform(translationByX: 0, byY: -0.5))
        path.stroke()
        path.transform(using: AffineTransform(translationByX: 0, byY: 0.5))
        NSColor.white.withAlphaComponent(0.7).setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStart = (NSEvent.mouseLocation, window.frame)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        let width = max(window.minSize.width, start.frame.width + (mouse.x - start.mouse.x))
        let height = max(window.minSize.height, start.frame.height - (mouse.y - start.mouse.y))
        window.setFrame(NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height), display: true)
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        if let window, let name = window.frameAutosaveName.isEmpty ? nil : window.frameAutosaveName {
            window.saveFrame(usingName: name)
        }
    }
}

/// Owns the caption panel for one session. The panel's size and position persist between sessions.
@MainActor
final class CaptionPanelController {
    private static let frameAutosaveName = "CaptionPanel"
    private let panel: CaptionPanel

    init(session: CaptionSession, settings: CaptionSettings) {
        let content = NSHostingView(rootView: CaptionView(session: session))
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
