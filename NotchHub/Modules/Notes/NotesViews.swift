import SwiftUI

struct NotesExpandedView: View {
    @Bindable var module: NotesModule
    /// Show the note rendered as Markdown instead of the raw text.
    @State private var previewMode = false
    /// Delete needs two clicks: the first "arms" the trash button for a few seconds.
    @State private var armedDeleteID: NoteID?
    @State private var search = ""

    /// Notes whose title or text contains the search (case- and accent-insensitive).
    private var filteredNotes: [Note] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return module.notes }
        return module.notes.filter {
            $0.title.localizedStandardContains(query) || $0.body.localizedStandardContains(query)
        }
    }
    @AppStorage(Prefs.notesMonospaced) private var monospaced
    @AppStorage(Prefs.notesLiveFormatting) private var liveFormatting
    @AppStorage(Prefs.accentColor) private var accentHex
    @Environment(\.notchFontSize) private var fontSize

    var body: some View {
        HStack(spacing: 10) {
            sidebar.frame(width: 150)
            Divider().overlay(Color.white.opacity(0.1))
            editor
        }
    }

    private func armDelete(_ id: NoteID) {
        armedDeleteID = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if armedDeleteID == id { armedDeleteID = nil }
        }
    }

    private func confirmDelete(_ note: Note) {
        let alert = NSAlert()
        alert.messageText = "Move \"\(note.title)\" to the Trash?"
        alert.informativeText = "You can restore it from the Trash in Finder."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { module.delete(note.id) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                IconButton(icon: "plus", size: 10, help: "New note") {
                    search = ""
                    module.newNote()
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("Search notes", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .accessibilityLabel("Search notes")
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if filteredNotes.isEmpty && !search.isEmpty {
                        Text("No matches").font(.caption).foregroundStyle(.secondary).padding(6)
                    }
                    ForEach(filteredNotes) { note in
                        NoteListRow(note: note,
                                    selected: note.id == module.selectedID,
                                    pinned: note.id == module.pinnedID)
                            .onTapGesture { module.selectedID = note.id }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(note.id == module.selectedID ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { module.selectedID = note.id }
                            .contextMenu {
                                Button(note.id == module.pinnedID ? "Unpin from Home" : "Pin to Home") {
                                    module.setPinned(note.id == module.pinnedID ? nil : note.id)
                                }
                                Button("Open in NotchNotes") { module.openInCompanion(note) }
                                Button("Show in Finder") { module.store.revealInFinder(note) }
                                Button("Move to Trash…", role: .destructive) { confirmDelete(note) }
                            }
                    }
                }
            }
            Button { module.openInCompanion(module.selected) } label: {
                Label("Open in NotchNotes", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
            .tooltip("Open your notes in the full NotchNotes app", edge: .top)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let note = module.selected {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(note.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    + Text(" ago").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    IconButton(icon: "checklist", size: 10, help: "Insert checkbox") {
                        let body = note.body.isEmpty || note.body.hasSuffix("\n") ? note.body + "- [ ] " : note.body + "\n- [ ] "
                        module.update(note.id, body: body)
                        previewMode = false
                    }
                    IconButton(icon: previewMode ? "pencil" : "eye", size: 10,
                               help: previewMode ? "Edit text" : "Preview formatting") {
                        previewMode.toggle()
                    }
                    IconButton(icon: note.id == module.pinnedID ? "pin.fill" : "pin", size: 10, help: "Pin to Home") {
                        module.setPinned(note.id == module.pinnedID ? nil : note.id)
                    }
                    IconButton(icon: "macwindow", size: 10, help: "Open in NotchNotes") { module.openInCompanion(note) }
                    IconButton(icon: armedDeleteID == note.id ? "trash.fill" : "trash", size: 10,
                               help: armedDeleteID == note.id ? "Click again to move to Trash" : "Move to Trash") {
                        if armedDeleteID == note.id {
                            armedDeleteID = nil
                            module.delete(note.id)
                        } else {
                            armDelete(note.id)
                        }
                    }
                    .foregroundStyle(armedDeleteID == note.id ? Color.red : Color.primary)
                }
                if previewMode {
                    MarkdownView(text: note.body, baseSize: fontSize, baseURL: module.store.folder) { line in
                        module.toggleCheckbox(noteID: note.id, line: line)
                    }
                } else {
                    MarkdownTextEditor(
                        text: Binding(
                            get: { module.selected?.body ?? "" },
                            set: { module.update(note.id, body: $0) }
                        ),
                        fontSize: fontSize,
                        monospaced: monospaced,
                        liveFormatting: liveFormatting,
                        accentHex: accentHex,
                        inset: CGSize(width: 6, height: 6)
                    )
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                }
            }
            .id(note.id)
        } else {
            VStack(spacing: 8) {
                Text("No note selected").foregroundStyle(.secondary)
                Button("New Note") { module.newNote() }.buttonStyle(PillButtonStyle(prominent: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NoteListRow: View {
    let note: Note
    let selected: Bool
    let pinned: Bool

    var body: some View {
        HStack(spacing: 4) {
            if pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.secondary) }
            Text(note.title).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? AnyShapeStyle(.tint.opacity(0.5)) : AnyShapeStyle(Color.clear)))
        .contentShape(Rectangle())
    }
}

struct NotesCompactView: View {
    let module: NotesModule

    /// First lines of a note (line numbers stay the same, so checkboxes still toggle the right line).
    static func excerpt(_ body: String, maxLines: Int = 14) -> String {
        body.components(separatedBy: "\n").prefix(maxLines).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let note = module.pinned ?? module.notes.first
            ModuleTileHeader(icon: module.pinned != nil ? "pin.fill" : "note.text",
                             title: note?.title ?? "Notes")
            if let note {
                // Only the start of the note fits in a tile; don't lay out the rest.
                MarkdownView(text: Self.excerpt(note.body), baseSize: 11, baseURL: module.store.folder, compact: true) { line in
                    module.toggleCheckbox(noteID: note.id, line: line)
                }
            } else {
                Text("No notes yet").foregroundStyle(.secondary)
            }
        }
    }
}

struct NotesSettingsView: View {
    let module: NotesModule
    @AppStorage(Prefs.notesMonospaced) private var monospaced
    @AppStorage(Prefs.notesLiveFormatting) private var liveFormatting

    var body: some View {
        Toggle("Monospaced font", isOn: $monospaced)
        Toggle("Format Markdown while typing", isOn: $liveFormatting)
        Picker("Pinned note on Home", selection: Binding(
            get: { module.pinnedID },
            set: { module.setPinned($0) }
        )) {
            Text("Most recent").tag(NoteID?.none)
            ForEach(module.notes) { note in Text(note.title).tag(NoteID?.some(note.id)) }
        }
        NotesFolderSettings(store: module.store)
        NotchNotesCompanionRow(module: module)
        Text("Tip: start a line with \"- [ ] \" to make a checkbox.").font(.caption).foregroundStyle(.secondary)
    }
}

/// Settings row for the built-in NotchNotes companion app.
private struct NotchNotesCompanionRow: View {
    let module: NotesModule
    @State private var message: String?

    var body: some View {
        LabeledContent("NotchNotes app") {
            HStack {
                Button("Open NotchNotes") { module.openInCompanion(nil) }
                Button("Add to Applications") { message = module.installCompanionInApplications() }
            }
        }
        Text(message ?? "NotchNotes is built into NotchHub. Open it from here, the menu bar icon, or the window button on a note. Add it to Applications to launch it from Launchpad, Spotlight or the Dock.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
