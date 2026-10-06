import SwiftUI

/// Expanded hub: a header row (tabs left of the notch, actions right of it)
/// and the selected module's content below.
struct ExpandedView: View {
    let viewModel: NotchViewModel
    let actions: NotchActions
    @Namespace private var tabNamespace

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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 14)
        .foregroundStyle(.primary)
    }

    private var header: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    TabButton(id: "home", icon: "square.grid.2x2.fill", title: "Home",
                              selected: activeTab == "home", namespace: tabNamespace) {
                        select("home")
                    }
                    ForEach(registry.enabled, id: \.id) { module in
                        TabButton(id: module.id, icon: module.icon, title: module.name,
                                  selected: activeTab == module.id, namespace: tabNamespace) {
                            select(module.id)
                        }
                    }
                }
            }
            .frame(width: sideWidth, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Spacer(minLength: 0)
                HeaderIconButton(icon: "note.text", help: "Open NotchNotes app") {
                    AppState.shared.openNotchNotes()
                }
                HeaderIconButton(icon: "gearshape.fill", help: "Settings") {
                    actions.collapse()
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
        .transition(.opacity.combined(with: .offset(y: 6)))
    }

    private func select(_ id: String) {
        withAnimation(NotchAnimation.content) { viewModel.select(tab: id) }
    }
}

private struct TabButton: View {
    let id: String
    let icon: String
    let title: String
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.85))
                            .matchedGeometryEffect(id: "tabSelection", in: namespace)
                    } else if hovering {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .tooltip(title) { hovering = $0 }
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
