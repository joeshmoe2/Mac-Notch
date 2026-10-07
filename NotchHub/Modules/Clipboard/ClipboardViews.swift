import SwiftUI

struct ClipboardExpandedView: View {
    let module: ClipboardModule
    @State private var search = ""

    private var filtered: [ClipItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let list = module.items.sorted { ($0.pinned ? 0 : 1, $1.date) < ($1.pinned ? 0 : 1, $0.date) }
        guard !query.isEmpty else { return list }
        return list.filter { ($0.text ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $search)
                    .textFieldStyle(.plain)
                Spacer()
                Text("Click to copy").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))

            if module.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Things you copy will appear here.").foregroundStyle(.secondary)
                    Text("Passwords and copies from excluded apps are never saved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { item in
                            ClipRow(module: module, item: item)
                        }
                    }
                }
            }
        }
    }
}

private struct ClipRow: View {
    let module: ClipboardModule
    let item: ClipItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            if module.lastCopiedID == item.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
            if hovering || item.pinned {
                IconButton(icon: item.pinned ? "pin.fill" : "pin", size: 9,
                           help: item.pinned ? "Unpin" : "Pin (kept when history is cleared)") {
                    module.togglePin(item)
                }
            }
            if hovering {
                IconButton(icon: "trash", size: 9, help: "Remove from history") { module.remove(item) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(hovering ? 0.1 : 0.04)))
        .contentShape(Rectangle())
        .onTapGesture { module.copy(item) }
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(item.pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                if item.kind == .image, let image = module.image(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 48, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text(item.text ?? "")
                        .lineLimit(2)
                        .foregroundStyle(item.kind == .link ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                }
                HStack(spacing: 4) {
                    Text(item.date, format: .relative(presentation: .named))
                    if let app = item.sourceApp { Text("· \(app)") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        }
    }
}

struct ClipboardCompactView: View {
    let module: ClipboardModule

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ModuleTileHeader(icon: "doc.on.clipboard", title: "Clipboard")
            if module.items.isEmpty {
                Text("Nothing copied yet").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(module.items.prefix(3)) { item in
                Button { module.copy(item) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.kind == .image ? "photo" : (item.kind == .link ? "link" : "text.alignleft"))
                            .foregroundStyle(.secondary)
                        Text(item.kind == .image ? "Image" : (item.text ?? "")).lineLimit(1)
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .tooltip("Copy again")
            }
        }
    }
}

struct ClipboardSettingsView: View {
    let module: ClipboardModule
    @AppStorage(Prefs.clipboardLimit) private var limit
    @AppStorage(Prefs.clipboardCaptureImages) private var captureImages
    @AppStorage(Prefs.clipboardExcludedApps) private var excluded
    @State private var confirmClear = false

    var body: some View {
        Picker("Keep the last", selection: $limit) {
            ForEach([25, 50, 100, 200], id: \.self) { Text("\($0) items").tag($0) }
        }
        Toggle("Save copied images", isOn: $captureImages)
        LabeledContent("Never save copies from") {
            Button("Add App…") { module.runAddExcludedAppPanel() }
        }
        ForEach(excluded.idList, id: \.self) { bundleID in
            HStack {
                let app = BlockableApp(bundleID: bundleID)
                Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
                Text(app.url == nil ? bundleID : app.name)
                    .foregroundStyle(app.url == nil ? .secondary : .primary)
                Spacer()
                Button {
                    excluded = excluded.idList.filter { $0 != bundleID }.joinedIDs
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        Button("Clear History…", role: .destructive) { confirmClear = true }
            .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
                Button("Clear", role: .destructive) { module.clearHistory() }
            } message: {
                Text("Pinned items are kept.")
            }
        Text("History is stored only on this Mac (Application Support › NotchHub). Items marked as passwords or temporary by other apps are skipped automatically.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
