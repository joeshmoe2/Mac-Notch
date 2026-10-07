import SwiftUI
import UserNotifications

/// Rounded pill button used throughout module UIs.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.notchFontSize) private var fontSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize * 0.92, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Small circular icon button. `help` is required so every icon explains itself on hover.
struct IconButton: View {
    let icon: String
    var size: CGFloat = 12
    let help: String
    var tooltipEdge: VerticalEdge = .bottom
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.notchFontSize) private var fontSize

    /// Icons grow with the Appearance font size (for larger text).
    private var scaled: CGFloat { size * min(max(fontSize / 13, 0.9), 1.4) }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: scaled, weight: .semibold))
                .frame(width: scaled * 2.2, height: scaled * 2.2)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.15 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .tooltip(help, edge: tooltipEdge) { hovering = $0 }
        .accessibilityLabel(help)
    }
}

// MARK: - Hover tooltips

/// Shows a small label after hovering for a moment.
///
/// The notch lives in a non-activating panel of a background app, where
/// standard macOS tooltips (`.help`) often don't appear, so this draws its own.
/// `.help` is still applied for VoiceOver and for when the app is active.
private struct HoverTooltip: ViewModifier {
    let text: String
    let edge: VerticalEdge
    let onHover: ((Bool) -> Void)?
    @State private var visible = false
    @State private var delay: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                onHover?(inside)
                delay?.cancel()
                if inside {
                    delay = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.12)) { visible = true }
                    }
                } else {
                    visible = false
                }
            }
            .overlay(alignment: edge == .bottom ? .bottom : .top) {
                if visible && !text.isEmpty {
                    Text(text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(white: 0.16)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        .alignmentGuide(edge == .bottom ? .bottom : .top) { d in
                            edge == .bottom ? d[.top] - 4 : d[.bottom] + 4
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .zIndex(visible ? 100 : 0)
            .help(text)
    }
}

extension View {
    /// Adds a hover label. Pass `onHover` instead of a separate `.onHover` to track hover state.
    func tooltip(_ text: String, edge: VerticalEdge = .bottom, onHover: ((Bool) -> Void)? = nil) -> some View {
        modifier(HoverTooltip(text: text, edge: edge, onHover: onHover))
    }
}

/// Circular progress ring.
struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
                .accessibilityHidden(true)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
    }
}

/// Settings row that explains notification permission state and links to System Settings.
struct NotificationPermissionRow: View {
    private var service: NotificationService { .shared }

    var body: some View {
        HStack {
            switch service.authorization {
            case .denied:
                Label("Notifications are turned off for NotchHub.", systemImage: "bell.slash")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open System Settings") { service.openSystemSettings() }
            case .notDetermined:
                Label("NotchHub will ask permission to send notifications.", systemImage: "bell")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Allow Notifications") { service.requestAuthorizationIfNeeded() }
            default:
                Label("Notifications allowed", systemImage: "bell.badge")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { service.refreshStatus() }
    }
}
