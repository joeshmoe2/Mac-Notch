import SwiftUI
import UserNotifications

/// Rounded pill button used throughout module UIs.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                Capsule().fill(prominent ? Color.accentColor : Color.white.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Small circular icon button.
struct IconButton: View {
    let icon: String
    var size: CGFloat = 12
    var help: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size * 2.2, height: size * 2.2)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.15 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? "")
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
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
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
