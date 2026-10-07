import AppKit
import SwiftUI

/// Owns the panel for one screen and implements the hover / click / drag
/// expand-collapse state machine. All AppKit event handling lives here so the
/// SwiftUI views stay declarative.
@MainActor
final class NotchWindowController {
    let screen: NSScreen
    let panel: NotchPanel
    let viewModel: NotchViewModel

    private let container = NotchContainerView()
    private var monitors: [Any] = []
    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    /// When opened by hotkey/click, don't auto-close until the cursor has visited the panel.
    private var mouseVisitedSinceOpen = true
    private var keyObserver: NSObjectProtocol?

    /// Transparent padding around the shape so shadows aren't clipped.
    private let shadowPadding: CGFloat = 24

    init(screen: NSScreen, geometry: NotchGeometry) {
        self.screen = screen
        self.viewModel = NotchViewModel(geometry: geometry)
        self.panel = NotchPanel(contentRect: .zero)

        let root = NotchRootView(viewModel: viewModel, controller: NotchActions(controller: self))
        let hosting = NSHostingView(rootView: root)
        // The panel's frame is driven by layout(), never by SwiftUI's ideal size.
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.onMouseMoved = { [weak self] in self?.handleMouse(at: NSEvent.mouseLocation) }
        container.onMouseExited = { [weak self] in self?.handleMouse(at: NSEvent.mouseLocation) }
        panel.contentView = container
        panel.onEscape = { [weak self] in self?.collapse() }
        panel.ignoresMouseEvents = true

        layout()
        panel.orderFrontRegardless()
        installMonitors()

        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouse(at: NSEvent.mouseLocation) }
        }
    }

    func tearDown() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        openTask?.cancel()
        closeTask?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: Layout

    /// Re-reads size preferences and positions the panel at the top center of the screen.
    func layout() {
        viewModel.expandedSize = CGSize(width: Prefs.expandedWidth.value, height: Prefs.expandedHeight.value)
        let maxWidth = max(viewModel.expandedSize.width, viewModel.geometry.notchSize.width + viewModel.wingWidth * 2)
        let size = CGSize(
            width: maxWidth + shadowPadding * 2,
            height: viewModel.expandedSize.height + shadowPadding
        )
        let frame = NSRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// The visible shape's rect in screen coordinates.
    private func shapeRect(for size: CGSize) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
               width: size.width, height: size.height)
    }

    private var collapsedHoverRect: NSRect {
        // Extend upward by a point so the very top pixel row counts as inside.
        shapeRect(for: viewModel.collapsedSize).insetBy(dx: -4, dy: 0)
            .union(NSRect(x: screen.frame.midX - viewModel.collapsedSize.width / 2, y: screen.frame.maxY - 1,
                          width: viewModel.collapsedSize.width, height: 2))
    }

    private var expandedHoverRect: NSRect {
        shapeRect(for: viewModel.currentSize).insetBy(dx: -12, dy: -12)
    }

    // MARK: Public actions

    func expand(byHover: Bool = true) {
        cancelPending()
        guard viewModel.state == .collapsed else { return }
        popupTask?.cancel()
        viewModel.popup = nil
        mouseVisitedSinceOpen = byHover
        AppState.shared.prepareForExpand()
        panel.ignoresMouseEvents = false
        withAnimation(NotchAnimation.open) { viewModel.state = .expanded }
        if Prefs.haptics.value {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func collapse() {
        cancelPending()
        guard viewModel.state == .expanded else { return }
        if panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            // Hand keyboard focus back to the app the user was working in.
            if !NSApp.isActive { NSWorkspace.shared.frontmostApplication?.activate() }
        }
        viewModel.isDropTargeted = false
        viewModel.isDraggingFile = false
        viewModel.suppressAutoClose = false
        withAnimation(NotchAnimation.close) { viewModel.state = .collapsed }
        panel.ignoresMouseEvents = true
    }

    // MARK: Gestures

    private var swipeAccumulator: CGFloat = 0
    private var swipeHandled = false

    /// Two-finger horizontal swipe on the open notch switches tabs; scrolling
    /// over the closed notch changes the volume. Both come from the existing
    /// event monitors, so they cost nothing when unused.
    private func handleScroll(_ event: NSEvent, isLocal: Bool) {
        let location = NSEvent.mouseLocation
        switch viewModel.state {
        case .expanded:
            guard isLocal, Prefs.gestureSwipeTabs.value, event.hasPreciseScrollingDeltas,
                  expandedHoverRect.contains(location) else { return }
            if event.phase == .began || event.phase == .mayBegin {
                swipeAccumulator = 0
                swipeHandled = false
            }
            if event.phase == .ended || event.phase == .cancelled {
                swipeAccumulator = 0
                swipeHandled = false
                return
            }
            // Ignore momentum and mostly-vertical scrolling (lists inside modules).
            guard event.momentumPhase.isEmpty,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 else { return }
            swipeAccumulator += event.scrollingDeltaX
            // The shelf scrolls horizontally itself, so swiping there scrolls files instead.
            guard !swipeHandled, abs(swipeAccumulator) > 60, viewModel.selectedTab != ShelfModuleID else { return }
            swipeHandled = true
            switchTab(by: swipeAccumulator < 0 ? 1 : -1)

        case .collapsed:
            guard !isLocal, Prefs.gestureScrollVolume.value,
                  collapsedHoverRect.insetBy(dx: -6, dy: -2).contains(location) else { return }
            // Normalise to finger/wheel direction: up = louder.
            var delta = event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
            delta /= event.hasPreciseScrollingDeltas ? 250 : 25
            guard delta != 0 else { return }
            let audio = AudioDeviceService.shared
            audio.start()
            guard audio.canSetVolume else { return }
            audio.setVolume(audio.volume + Float(delta))
            let percent = Int((audio.volume * 100).rounded())
            showPopup(NotchPopup(
                kind: "volume",
                icon: percent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                iconColor: .white, title: "Volume", detail: nil,
                level: Double(audio.volume), trailing: "\(percent)%"
            ), duration: 1.2)
        }
    }

    /// Moves to the next/previous tab (Home first, then enabled modules in order).
    private func switchTab(by offset: Int) {
        let tabs = ["home"] + AppState.shared.registry.enabled.map(\.id)
        let current = tabs.firstIndex(of: viewModel.selectedTab) ?? 0
        let next = min(max(current + offset, 0), tabs.count - 1)
        guard next != current else { return }
        withAnimation(NotchAnimation.content) { viewModel.select(tab: tabs[next]) }
        if Prefs.haptics.value {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    // MARK: Pop-ups

    private var popupTask: Task<Void, Never>?

    /// Briefly grows the collapsed notch to show `popup`, then shrinks back.
    /// Ignored while the notch is open (the user is busy with it).
    func showPopup(_ popup: NotchPopup, duration: TimeInterval) {
        guard viewModel.state == .collapsed else { return }
        popupTask?.cancel()
        var popup = popup
        if let kind = popup.kind, let current = viewModel.popup, current.kind == kind {
            // Same kind already showing (e.g. volume while scrolling): update in place.
            popup.id = current.id
            viewModel.popup = popup
        } else {
            withAnimation(NotchAnimation.open) { viewModel.popup = popup }
        }
        popupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.viewModel.popup?.id == popup.id else { return }
            withAnimation(NotchAnimation.close) { self.viewModel.popup = nil }
        }
    }

    func toggle() {
        viewModel.isExpanded ? collapse() : expand(byHover: false)
    }

    // MARK: Event monitors

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .scrollWheel]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event: event, isLocal: false) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event: event, isLocal: true) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(event: NSEvent, isLocal: Bool) {
        let location = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            if viewModel.state == .collapsed {
                if Prefs.openOnClick.value, collapsedHoverRect.contains(location) { expand(byHover: true) }
            } else if !isLocal, !expandedHoverRect.contains(location), !viewModel.isDropTargeted {
                // Click somewhere else on screen closes the notch.
                collapse()
            }
        case .leftMouseDragged:
            handleDrag(at: location)
        case .scrollWheel:
            handleScroll(event, isLocal: isLocal)
        case .leftMouseUp:
            viewModel.isDraggingFile = false
            handleMouse(at: location)
        default:
            handleMouse(at: location)
        }
    }

    private func handleDrag(at location: NSPoint) {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount,
              pasteboard.types?.contains(.fileURL) == true else {
            handleMouse(at: location)
            return
        }
        // A file drag is in progress somewhere on screen.
        if viewModel.state == .collapsed {
            guard Prefs.expandOnDrag.value,
                  collapsedHoverRect.insetBy(dx: -20, dy: -20).contains(location) else { return }
            viewModel.isDraggingFile = true
            expand(byHover: true)
        } else if expandedHoverRect.contains(location) {
            viewModel.isDraggingFile = true
            cancelClose()
        } else {
            viewModel.isDraggingFile = false
            handleMouse(at: location)
        }
    }

    /// Core hover state machine.
    func handleMouse(at location: NSPoint) {
        switch viewModel.state {
        case .collapsed:
            if !Prefs.openOnClick.value, collapsedHoverRect.contains(location) {
                scheduleOpen()
            } else {
                cancelOpen()
            }
        case .expanded:
            if expandedHoverRect.contains(location) {
                mouseVisitedSinceOpen = true
                cancelClose()
            } else if mouseVisitedSinceOpen {
                scheduleClose()
            }
        }
    }

    private var canAutoCollapse: Bool {
        !viewModel.isDropTargeted
            && !viewModel.isDraggingFile
            && !viewModel.suppressAutoClose
            && !panel.isEditingText
            && NSEvent.pressedMouseButtons & 1 == 0
            && !panel.childWindowsAreVisible
    }

    private func scheduleOpen() {
        guard openTask == nil else { return }
        let delay = Prefs.hoverDelay.value
        openTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.openTask = nil
            if self.collapsedHoverRect.contains(NSEvent.mouseLocation) { self.expand(byHover: true) }
        }
    }

    private func scheduleClose() {
        guard closeTask == nil else { return }
        let delay = Prefs.closeDelay.value
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.closeTask = nil
            guard !self.expandedHoverRect.contains(NSEvent.mouseLocation) else { return }
            if self.canAutoCollapse { self.collapse() }
        }
    }

    private func cancelOpen() { openTask?.cancel(); openTask = nil }
    private func cancelClose() { closeTask?.cancel(); closeTask = nil }
    private func cancelPending() { cancelOpen(); cancelClose() }
}

private extension NSWindow {
    var childWindowsAreVisible: Bool {
        (childWindows ?? []).contains { $0.isVisible }
    }
}

/// Animations shared by the window controller and views.
enum NotchAnimation {
    static var speed: Double { max(0.25, Prefs.animationSpeed.value) }
    /// System Settings › Accessibility › Display › Reduce motion: springs become short fades.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var open: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42 / speed, dampingFraction: 0.78)
    }
    static var close: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.36 / speed, dampingFraction: 0.92)
    }
    static var content: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3 / speed, dampingFraction: 0.85)
    }
}

/// Thin, view-safe wrapper so SwiftUI views can ask the controller to do things
/// without holding a reference to AppKit types.
@MainActor
struct NotchActions {
    weak var controller: NotchWindowController?

    func collapse() { controller?.collapse() }
    func expand() { controller?.expand(byHover: false) }

    /// Shows the macOS share picker anchored near the cursor.
    func share(_ items: [Any]) {
        guard let controller, let view = controller.panel.contentView else { return }
        controller.viewModel.suppressAutoClose = true
        let picker = NSSharingServicePicker(items: items)
        let delegate = SharingPickerDelegate { [weak controller] in
            controller?.viewModel.suppressAutoClose = false
        }
        SharingPickerDelegate.current = delegate
        picker.delegate = delegate
        let mouse = controller.panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = view.convert(mouse, from: nil)
        picker.show(relativeTo: NSRect(x: point.x, y: point.y, width: 1, height: 1), of: view, preferredEdge: .minY)
    }
}

final class SharingPickerDelegate: NSObject, NSSharingServicePickerDelegate {
    static var current: SharingPickerDelegate?
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onFinish()
        SharingPickerDelegate.current = nil
    }
}
