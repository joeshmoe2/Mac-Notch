import SwiftUI

extension Prefs {
    static let popupCharger = PrefKey("popups.charger", true)
    static let popupHeadphones = PrefKey("popups.headphones", true)
    /// Seconds a pop-up stays open.
    static let popupDuration = PrefKey("popups.duration", 3.0)
    // Gestures
    static let gestureSwipeTabs = PrefKey("behavior.swipeTabs", true)
    static let gestureScrollVolume = PrefKey("behavior.scrollVolume", true)
}

/// Content of a brief notch pop-up.
struct NotchPopup: Equatable {
    var id = UUID()
    /// Pop-ups of the same kind (e.g. "volume") update in place instead of re-animating.
    var kind: String?
    var icon: String
    var iconColor: Color
    var title: String
    var detail: String?
    /// Optional level 0...1 drawn as a bar (battery).
    var level: Double?
    var trailing: String?
}

/// Pop-up layout: the hardware notch stays black on top, content sits below it.
struct NotchPopupView: View {
    let popup: NotchPopup
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 10) {
                Image(systemName: popup.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(popup.iconColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(popup.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let detail = popup.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let level = popup.level {
                    BatteryBar(level: level, color: popup.iconColor)
                }
                if let trailing = popup.trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(popup.iconColor)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }
}

private struct BatteryBar: View {
    let level: Double
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.5), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .padding(2)
                    .frame(width: max(4, 30 * min(max(level, 0), 1)))
            }
            .frame(width: 30, height: 14)
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.5)).frame(width: 2, height: 5)
        }
    }
}
