import SwiftUI

extension EnvironmentValues {
    /// Lets module views ask the notch window to do AppKit things (share sheet, collapse).
    @Entry var notchActions: NotchActions? = nil
}

struct ShelfExpandedView: View {
    let module: ShelfModule
    @Environment(\.notchActions) private var actions

    var body: some View {
        if module.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("Drop files on the notch to keep them here")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(module.items.count) item\(module.items.count == 1 ? "" : "s") · drag out to use")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All") { module.clear() }.buttonStyle(PillButtonStyle())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(module.items) { item in
                            ShelfTile(module: module, item: item, actions: actions)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct ShelfTile: View {
    let module: ShelfModule
    let item: ShelfItem
    let actions: NotchActions?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = module.thumbnails[item.id] {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "doc").font(.system(size: 30)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)

                if hovering {
                    Button { module.remove(item.id) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .tooltip("Remove from shelf")
                    .offset(x: 6, y: -6)
                }
            }
            Text(item.fileName)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 84)
            if hovering {
                HStack(spacing: 2) {
                    IconButton(icon: "arrow.up.forward.app", size: 8, help: "Open") { module.open(item) }
                    IconButton(icon: "folder", size: 8, help: "Reveal in Finder") { module.reveal(item) }
                    IconButton(icon: "square.and.arrow.up", size: 8, help: "Share") { share() }
                }
            }
        }
        .padding(6)
        .frame(width: 96, height: 132, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(hovering ? 0.1 : 0.04)))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { module.open(item) }
        .onDrag { module.dragProvider(for: item) }
        .contextMenu {
            Button("Open") { module.open(item) }
            Button("Reveal in Finder") { module.reveal(item) }
            Button("AirDrop") { module.airDrop(item) }
            Button("Share…") { share() }
            Divider()
            Button("Remove", role: .destructive) { module.remove(item.id) }
        }
        .help(item.fileName)
    }

    private func share() {
        guard let url = module.resolve(item) else { return }
        actions?.share([url])
    }
}

struct ShelfCompactView: View {
    let module: ShelfModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTileHeader(icon: "tray.full.fill", title: "Shelf")
            if module.items.isEmpty {
                Text("Drop files here").foregroundStyle(.secondary).font(.caption)
            } else {
                HStack(spacing: -10) {
                    ForEach(module.items.prefix(4)) { item in
                        Group {
                            if let image = module.thumbnails[item.id] {
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "doc")
                            }
                        }
                        .frame(width: 32, height: 32)
                        .onDrag { module.dragProvider(for: item) }
                    }
                }
                Text("\(module.items.count) item\(module.items.count == 1 ? "" : "s")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct ShelfSettingsView: View {
    let module: ShelfModule
    @AppStorage(Prefs.shelfCopyFiles) private var copyFiles
    @AppStorage(Prefs.shelfAutoClearHours) private var autoClearHours
    @AppStorage(Prefs.shelfMaxItems) private var maxItems

    var body: some View {
        Toggle("Copy files to the shelf instead of referencing them", isOn: $copyFiles)
        Picker("Auto-clear items after", selection: $autoClearHours) {
            Text("Never").tag(0)
            Text("1 hour").tag(1)
            Text("6 hours").tag(6)
            Text("12 hours").tag(12)
            Text("24 hours").tag(24)
            Text("3 days").tag(72)
            Text("1 week").tag(168)
        }
        Stepper("Maximum items: \(maxItems)", value: $maxItems, in: 1...100)
        Button("Clear Shelf", role: .destructive) { module.clear() }
    }
}
