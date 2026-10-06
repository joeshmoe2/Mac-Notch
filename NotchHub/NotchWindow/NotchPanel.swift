import AppKit

/// Borderless, non-activating panel that floats above the menu bar on every
/// Space (including full-screen apps) and never steals focus from the
/// frontmost app unless the user clicks into a text field.
final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Above the menu bar (and its own "status bar" level items).
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    // Allow key status so text fields (Notes, Timer input) can receive typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Never let AppKit push the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// True while a text view inside the panel is being edited.
    var isEditingText: Bool {
        isKeyWindow && firstResponder is NSTextView
    }
}

/// Container view that hosts the SwiftUI hierarchy and reports mouse
/// movement via a tracking area (works even when the panel is not key).
final class NotchContainerView: NSView {
    var onMouseMoved: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onMouseMoved?() }
    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
