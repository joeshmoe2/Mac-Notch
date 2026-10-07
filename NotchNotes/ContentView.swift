import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: NotesAppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
        } detail: {
            if let note = model.selectedNote {
                NoteEditor(model: model, note: note)
                    .id(note.id)
            } else {
                ContentUnavailableView {
                    Label("No Note Selected", systemImage: "note.text")
                } description: {
                    Text("Pick a note on the left or press ⌘N to start a new one.")
                } actions: {
                    Button("New Note") { model.newNote() }
                        .help("Create a new note (⌘N)")
                }
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search notes")
        .confirmationDialog(
            "Move \"\(model.store.note(id: model.pendingDeleteID)?.title ?? "this note")\" to the Trash?",
            isPresented: Binding(
                get: { model.pendingDeleteID != nil },
                set: { if !$0 { model.pendingDeleteID = nil } }
            )
        ) {
            Button("Move to Trash", role: .destructive) { model.confirmPendingDelete() }
            Button("Cancel", role: .cancel) { model.pendingDeleteID = nil }
        } message: {
            Text("You can restore it from the Trash in Finder.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.appDidBecomeActive()
        }
        .onChange(of: model.viewMode) { _, mode in
            UserDefaults.standard.set(mode.rawValue, forKey: "viewMode")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.store.flushSaves()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            // Save right away when switching apps so NotchHub sees the latest text.
            model.store.flushSaves()
        }
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            ForEach(model.filteredNotes) { note in
                NoteRow(note: note)
                    .tag(note.id)
                    .contextMenu {
                        Button("Show in Finder") { model.store.revealInFinder(note) }
                        Divider()
                        Button("Move to Trash…", role: .destructive) { model.requestDelete(note.id) }
                    }
            }
        }
        .overlay {
            if model.filteredNotes.isEmpty {
                Text(model.searchText.isEmpty ? "No notes yet" : "No matches")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem {
                Button { model.newNote() } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .help("New Note (⌘N)")
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(note.updatedAt, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
                Text(note.preview.isEmpty ? "No additional text" : note.preview)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
        .padding(.vertical, 3)
    }
}

private struct NoteEditor: View {
    @Bindable var model: NotesAppModel
    let note: Note
    @AppStorage("editorFontSize") private var fontSize = 15.0
    @AppStorage("editorMonospaced") private var monospaced = false

    private var store: NotesStore { model.store }

    var body: some View {
        VStack(spacing: 0) {
            switch model.viewMode {
            case .edit:
                editor
            case .preview:
                preview
            case .split:
                HSplitView {
                    editor.frame(minWidth: 220)
                    preview
                        .frame(minWidth: 220)
                        .background(Color.primary.opacity(0.03))
                }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(note.title)
        .navigationSubtitle(note.fileName)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Bold  ⌘B") { MarkdownFormatting.apply(.bold) }
                    Button("Italic  ⌘I") { MarkdownFormatting.apply(.italic) }
                    Button("Strikethrough  ⇧⌘X") { MarkdownFormatting.apply(.strikethrough) }
                    Button("Highlight  ⇧⌘H") { MarkdownFormatting.apply(.highlight) }
                    Button("Inline Code  ⌘E") { MarkdownFormatting.apply(.code) }
                    Button("Link  ⌘K") { MarkdownFormatting.apply(.link) }
                    Divider()
                    Button("Heading 1") { MarkdownFormatting.apply(.heading(1)) }
                    Button("Heading 2") { MarkdownFormatting.apply(.heading(2)) }
                    Button("Heading 3") { MarkdownFormatting.apply(.heading(3)) }
                    Divider()
                    Button("Bulleted List") { MarkdownFormatting.apply(.bullet) }
                    Button("Numbered List") { MarkdownFormatting.apply(.numbered) }
                    Button("Checkbox") { model.insertCheckbox() }
                    Button("Quote") { MarkdownFormatting.apply(.quote) }
                    Divider()
                    Button("Open Markdown Cheat Sheet") { model.openCheatSheet() }
                } label: {
                    Label("Format", systemImage: "textformat")
                }
                .help("Markdown formatting (place the cursor in the editor first)")
                .disabled(model.viewMode == .preview)
            }
            ToolbarItem {
                Picker("View", selection: $model.viewMode) {
                    ForEach(EditorMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Edit, Split or Preview (⌘1 / ⌘2 / ⌘3)")
            }
            ToolbarItemGroup {
                ShareLink(item: store.url(for: note.fileName)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share this note")
                Button { store.revealInFinder(note) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show this note's file in Finder")
                Button(role: .destructive) { model.requestDelete(note.id) } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .help("Move this note to the Trash")
            }
        }
    }

    private var editor: some View {
        TextEditor(text: Binding(
            get: { store.note(id: note.id)?.body ?? "" },
            set: { store.update(note.id, body: $0) }
        ))
        .font(monospaced ? .system(size: fontSize, design: .monospaced) : .system(size: fontSize))
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var preview: some View {
        MarkdownView(
            text: store.note(id: note.id)?.body ?? note.body,
            baseSize: fontSize,
            baseURL: store.folder,
            onToggleTask: { line in store.toggleCheckbox(note.id, line: line) }
        )
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack {
            Text("\(note.wordCount) word\(note.wordCount == 1 ? "" : "s")")
            Spacer()
            Text("Edited \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

struct NotchNotesSettings: View {
    let model: NotesAppModel
    @AppStorage("editorFontSize") private var fontSize = 15.0
    @AppStorage("editorMonospaced") private var monospaced = false

    var body: some View {
        Form {
            Section("Storage") {
                NotesFolderSettings(store: model.store)
            }
            Section("Editor") {
                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $fontSize, in: 11...24, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Monospaced font", isOn: $monospaced)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}
