import SwiftUI

/// Expanded hub: a header row (tabs split around the notch, actions on the right)
/// and the selected module's content below.
struct ExpandedView: View {
    let viewModel: NotchViewModel
    let actions: NotchActions
    @Namespace private var tabNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var registry: ModuleRegistry { AppState.shared.registry }

    private var horizontalPadding: CGFloat { 22 }

    /// Width available on each side of the hardware notch for the header.
    private var sideWidth: CGFloat {
        let total = viewModel.currentSize.width - horizontalPadding * 2
        guard viewModel.geometry.isHardware else { return total / 2 }
        return max(80, (total - viewModel.geometry.notchSize.width) / 2 - 6)
    }

    /// Falls back to Home if the selected module was disabled.
    private var activeTab: String {
        let tab = viewModel.selectedTab
        if tab == "home" || registry.enabled.contains(where: { $0.id == tab }) { return tab }
        return "home"
    }

    var body: some View {
        VStack(spacing: 8) {
            header
                .frame(height: max(26, viewModel.geometry.notchSize.height))
            content
                .fillingAvailableSpace(alignment: .top)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 14)
        .foregroundStyle(.primary)
    }

    /// Home plus every enabled module, in tab order.
    private struct TabItem: Identifiable {
        let id: String
        let icon: String
        let title: String
    }

    private var tabs: [TabItem] {
        [TabItem(id: "home", icon: "square.grid.2x2.fill", title: "Home")]
            + registry.enabled.map { TabItem(id: $0.id, icon: $0.icon, title: $0.name) }
    }

    @Environment(\.notchFontSize) private var fontSize

    /// Tabs are split across both sides of the notch so they all stay visible:
    /// the first half on the left, the rest on the right before the Notes/Settings
    /// buttons. If they still don't fit, every tab shrinks a little.
    private var tabLayout: (left: Int, width: CGFloat) {
        let count = tabs.count
        let preferred = 28 * min(max(fontSize / 13, 0.9), 1.4) + 2
        let actionsWidth: CGFloat = 2 * 26 + 8
        let rightSpace = max(0, sideWidth - actionsWidth)
        let width = min(preferred, max(18, (sideWidth + rightSpace) / CGFloat(max(count, 1))))
        let leftCapacity = max(1, Int(sideWidth / width))
        let rightCapacity = Int(rightSpace / width)
        let balanced = Int((Double(count) / 2).rounded(.up))
        let left = min(max(balanced, count - rightCapacity), leftCapacity, count)
        return (left, width - 2)
    }

    private func tabButtons(_ slice: ArraySlice<TabItem>, width: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(slice) { tab in
                TabButton(id: tab.id, icon: tab.icon, title: tab.title, width: width,
                          selected: activeTab == tab.id, namespace: tabNamespace) {
                    select(tab.id)
                }
            }
        }
    }

    private var header: some View {
        let layout = tabLayout
        let all = tabs
        return HStack(spacing: 0) {
            // Left of the notch.
            tabButtons(all.prefix(layout.left), width: layout.width)
                .frame(width: sideWidth, alignment: .leading)

            Spacer(minLength: 0)

            // Right of the notch: remaining tabs, then actions.
            HStack(spacing: 4) {
                tabButtons(all.dropFirst(layout.left), width: layout.width)
                Spacer(minLength: 0)
                HeaderIconButton(icon: "note.text", help: "Open NotchNotes app") {
                    AppState.shared.openNotchNotes()
                }
                HeaderIconButton(icon: "gearshape.fill", help: "Settings") {
                    SettingsOpener.open()
                }
            }
            .frame(width: sideWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if activeTab == "home" {
                HomeView(viewModel: viewModel)
            } else if let module = registry.module(id: activeTab) {
                module.expandedView()
            }
        }
        .id(activeTab)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
    }

    private func select(_ id: String) {
        withAnimation(NotchAnimation.content) { viewModel.select(tab: id) }
    }
}

private struct TabButton: View {
    let id: String
    let icon: String
    let title: String
    /// Slot width chosen by the header so every tab fits.
    var width: CGFloat = 28
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.notchFontSize) private var fontSize
    private var fontScale: CGFloat { min(max(fontSize / 13, 0.9), 1.4) }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: min(12 * fontScale, width * 0.45), weight: .semibold))
                .frame(width: width, height: 24 * fontScale)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background {
                    if selected {
                        Capsule()
                            .fill(.tint.opacity(0.85))
                            .matchedGeometryEffect(id: "tabSelection", in: namespace)
                    } else if hovering {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .tooltip(title) { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct HeaderIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundStyle(.secondary)
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.08 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .tooltip(help) { hovering = $0 }
        .accessibilityLabel(help)
    }
}

/// Dashboard showing the compact view of several modules side by side.
struct HomeView: View {
    let viewModel: NotchViewModel
    private var registry: ModuleRegistry { AppState.shared.registry }

    var body: some View {
        let modules = registry.homeModules
        if modules.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2").font(.title2)
                Text("Choose modules for Home in Settings → Modules.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 8) {
                ForEach(modules, id: \.id) { module in
                    module.compactView()
                        .fillingAvailableSpace(alignment: .topLeading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture(count: 2) {
                            withAnimation(NotchAnimation.content) { viewModel.select(tab: module.id) }
                        }
                }
            }
        }
    }
}

/// Small rounded card used inside module views.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

/// Header line used by compact views: icon + title.
struct ModuleTileHeader: View {
    let icon: String
    let title: String
    @Environment(\.notchFontSize) private var fontSize
    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: fontSize * 0.8, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

extension View {
    /// Takes exactly the space offered and clips anything taller, instead of
    /// growing. Without this, a long note in a tile or tab could make the
    /// content taller than the notch and push the tab bar out of view.
    func fillingAvailableSpace(alignment: Alignment) -> some View {
        Color.clear
            .overlay(alignment: alignment) { self }
            .clipped()
    }
}
