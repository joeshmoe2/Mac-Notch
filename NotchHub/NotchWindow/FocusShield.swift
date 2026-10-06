import AppKit
import SwiftUI

/// Full-screen "this app is blocked" screen shown when a blocked app is opened
/// during a focus session (similar to Screen Time / Opal shields).
@MainActor
final class FocusShield {
    static let shared = FocusShield()

    private var windows: [NSWindow] = []
    private var autoDismiss: Task<Void, Never>?

    private init() {}

    var isVisible: Bool { !windows.isEmpty }

    func show(appName: String, icon: NSImage?) {
        dismiss()
        // Cover every screen so the blocked app can't just be dragged elsewhere.
        for screen in NSScreen.screens {
            let window = ShieldWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .modalPanel
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: FocusShieldView(
                appName: appName,
                icon: icon,
                end: FocusGuard.shared.sessionEnd,
                isPrimary: screen == NSScreen.main,
                onDismiss: { FocusShield.shared.dismiss() }
            ))
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first { $0.screen == NSScreen.main }?.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            windows.forEach { $0.animator().alphaValue = 1 }
        }
        // Don't leave the screen covered forever if the user walks away.
        autoDismiss = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        autoDismiss?.cancel()
        autoDismiss = nil
        let closing = windows
        windows.removeAll()
        guard !closing.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            closing.forEach { $0.orderOut(nil) }
        })
    }
}

private final class ShieldWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { FocusShield.shared.dismiss() }
}

private struct FocusShieldView: View {
    let appName: String
    let icon: NSImage?
    let end: Date?
    let isPrimary: Bool
    let onDismiss: () -> Void

    @AppStorage(Prefs.accentColor) private var accentHex

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .fullScreenUI)
            Color.black.opacity(0.55)
            if isPrimary {
                content
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .saturation(0)
                        .opacity(0.8)
                }
                Image(systemName: "hourglass.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white, PomodoroPhase.work.color)
                    .offset(x: 8, y: 8)
            }
            Text("\(appName) is blocked")
                .font(.system(size: 30, weight: .bold))
            if let end {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("You're in a focus session · \(TimeFormat.clock(max(0, end.timeIntervalSince(context.date)))) left")
                        .font(.system(size: 17).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("You're in a focus session.")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            Text("It'll be available again on your next break.")
                .foregroundStyle(.secondary)
            Button(action: onDismiss) {
                Text("Back to work")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(hex: accentHex) ?? .accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 8)
        }
        .foregroundStyle(.white)
    }
}
