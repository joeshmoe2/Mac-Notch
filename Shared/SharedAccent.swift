import AppKit
import SwiftUI

/// The accent color chosen in NotchHub (Settings → Appearance), shared with
/// NotchNotes through the `com.notchhub.shared` preferences domain.
///
/// NotchHub publishes the color and posts a distributed notification, so an
/// open NotchNotes window updates immediately.
@Observable
@MainActor
final class SharedAccent {
    static let shared = SharedAccent()

    private static let key = "accentColorHex"
    private static let changed = Notification.Name("com.notchhub.accentColorChanged")

    /// "#RRGGBB", or nil if NotchHub hasn't published one yet.
    private(set) var hex: String?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        reload()
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Self.changed, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SharedAccent.shared.reload() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SharedAccent.shared.reload() }
        })
    }

    func reload() {
        let value = NotesLocation.sharedDefaults.string(forKey: Self.key)
        if value != hex { hex = value }
    }

    /// Called by NotchHub whenever its accent color changes.
    static func publish(_ hex: String) {
        guard NotesLocation.sharedDefaults.string(forKey: key) != hex else { return }
        NotesLocation.sharedDefaults.set(hex, forKey: key)
        shared.reload()
        DistributedNotificationCenter.default().postNotificationName(changed, object: nil, deliverImmediately: true)
    }

    var color: Color? { hex.flatMap(Color.init(hex:)) }
    var nsColor: NSColor? { hex.flatMap(NSColor.init(hex:)) }
}

extension Color {
    /// Parses "#RRGGBB" or "RRGGBB".
    init?(hex: String) {
        guard let ns = NSColor(hex: hex) else { return nil }
        self.init(nsColor: ns)
    }

    /// "#RRGGBB" representation (sRGB).
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension NSColor {
    /// Parses "#RRGGBB" or "RRGGBB".
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private struct SharedAccentTint: ViewModifier {
    private var accent: SharedAccent { .shared }

    func body(content: Content) -> some View {
        if let color = accent.color {
            content.tint(color)
        } else {
            content
        }
    }
}

extension View {
    /// Tints controls and accents with NotchHub's accent color when one is set.
    func sharedAccentTint() -> some View { modifier(SharedAccentTint()) }
}
