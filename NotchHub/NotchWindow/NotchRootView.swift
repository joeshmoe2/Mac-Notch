import SwiftUI
import UniformTypeIdentifiers

extension EnvironmentValues {
    /// Namespace shared by collapsed and expanded content for matchedGeometryEffect.
    @Entry var notchNamespace: Namespace.ID? = nil
    /// Whether the notch is currently expanded.
    @Entry var notchExpanded: Bool = false
    /// Base font size from Appearance settings.
    @Entry var notchFontSize: CGFloat = 13
}

/// Root SwiftUI view hosted in the notch panel. Draws the notch shape and
/// swaps between the collapsed live-activity view and the expanded hub.
struct NotchRootView: View {
    @Bindable var viewModel: NotchViewModel
    let controller: NotchActions

    @AppStorage(Prefs.cornerRadius) private var cornerRadius
    @AppStorage(Prefs.background) private var background
    @AppStorage(Prefs.contentAppearance) private var contentAppearance
    @AppStorage(Prefs.accentColor) private var accentHex
    @AppStorage(Prefs.fontSize) private var fontSize
    @Environment(\.colorScheme) private var systemScheme
    @Namespace private var namespace

    private var expanded: Bool { viewModel.isExpanded }

    private var shape: AnyShape {
        let h = viewModel.geometry.notchSize.height
        if !expanded && !viewModel.geometry.isHardware {
            return AnyShape(VirtualNotchShape(radius: h / 2))
        }
        return AnyShape(NotchShape(
            topRadius: expanded ? 10 : 6,
            bottomRadius: expanded ? cornerRadius : max(8, h / 3)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            notch
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.notchNamespace, namespace)
        .environment(\.notchExpanded, expanded)
        .environment(\.notchFontSize, fontSize)
        .environment(\.notchActions, controller)
    }

    private var notch: some View {
        let size = viewModel.currentSize
        return ZStack(alignment: .top) {
            backgroundView
            if expanded {
                ExpandedView(viewModel: viewModel, actions: controller)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(NotchAnimation.content.delay(0.05)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            } else if let popup = viewModel.popup {
                NotchPopupView(popup: popup, notchHeight: viewModel.geometry.notchSize.height)
                    .id(popup.id)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                CollapsedView(viewModel: viewModel)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay {
            if viewModel.isDropTargeted {
                shape.stroke(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .contentShape(shape)
        .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 14, y: 6)
        .font(.system(size: fontSize))
        .tint(Color(hex: accentHex) ?? .accentColor)
        .accentColor(Color(hex: accentHex) ?? .accentColor)
        .environment(\.colorScheme, resolvedScheme)
        .onDrop(of: [.fileURL], isTargeted: $viewModel.isDropTargeted) { providers in
            DropLoader.loadFileURLs(from: providers) { urls in
                if AppState.shared.receiveDroppedFiles(urls) {
                    withAnimation(NotchAnimation.content) { viewModel.select(tab: ShelfModuleID) }
                }
            }
            return true
        }
        .animation(NotchAnimation.open, value: viewModel.liveActivity?.moduleID)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if expanded && BackgroundStyle(rawValue: background) == .material {
            ZStack {
                VisualEffectBackground(material: .hudWindow)
                Color.black.opacity(0.35)
            }
        } else {
            Color.black
        }
    }

    private var resolvedScheme: ColorScheme {
        switch ContentAppearance(rawValue: contentAppearance) ?? .dark {
        case .light: return .light
        case .dark: return .dark
        case .auto: return systemScheme
        }
    }
}

/// Module id of the file shelf (drops are routed there).
let ShelfModuleID = "shelf"

enum DropLoader {
    /// Extracts file URLs from drag providers and calls back on the main thread.
    static func loadFileURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let collector = URLCollector()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collector.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = collector.urls
            MainActor.assumeIsolated { completion(urls) }
        }
    }
}

private final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.lock(); storage.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}

/// Collapsed notch: invisible against the hardware notch, optionally showing
/// a live activity in "wings" on either side.
struct CollapsedView: View {
    let viewModel: NotchViewModel

    var body: some View {
        if let activity = viewModel.liveActivity {
            let height = viewModel.geometry.notchSize.height
            HStack(spacing: 0) {
                activity.leading
                    .frame(width: viewModel.wingWidth, height: height)
                    .padding(.leading, 6)
                Spacer(minLength: viewModel.geometry.notchSize.width - 12)
                activity.trailing
                    .frame(width: viewModel.wingWidth, height: height)
                    .padding(.trailing, 6)
            }
            .frame(height: height)
            .foregroundStyle(.white)
            .id(activity.moduleID)
            .transition(.opacity)
        }
    }
}
