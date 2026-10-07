import SwiftUI

/// NotchNotes: a full-window companion to NotchHub's Notes module.
/// Both apps read and write the same folder of Markdown files.
@main
struct NotchNotesApp: App {
    @State private var model = NotesAppModel()

    var body: some Scene {
        Window("NotchNotes", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 640, minHeight: 420)
                .sharedAccentTint()
        }
        .defaultSize(width: 920, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { model.newNote() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Button("Show Notes Folder in Finder") { model.store.revealInFinder() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                // No keyboard shortcut on purpose: ⌘⌫ must keep deleting text in the editor.
                Button("Move Note to Trash…") { model.requestDelete(model.selection) }
                    .disabled(model.selectedNote == nil)
            }
            CommandMenu("Format") {
                Button("Bold") { MarkdownFormatting.apply(.bold) }.keyboardShortcut("b")
                Button("Italic") { MarkdownFormatting.apply(.italic) }.keyboardShortcut("i")
                Button("Strikethrough") { MarkdownFormatting.apply(.strikethrough) }.keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Highlight") { MarkdownFormatting.apply(.highlight) }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Inline Code") { MarkdownFormatting.apply(.code) }.keyboardShortcut("e")
                Button("Link") { MarkdownFormatting.apply(.link) }.keyboardShortcut("k")
                Divider()
                Button("Heading 1") { MarkdownFormatting.apply(.heading(1)) }.keyboardShortcut("1", modifiers: [.command, .option])
                Button("Heading 2") { MarkdownFormatting.apply(.heading(2)) }.keyboardShortcut("2", modifiers: [.command, .option])
                Button("Heading 3") { MarkdownFormatting.apply(.heading(3)) }.keyboardShortcut("3", modifiers: [.command, .option])
                Divider()
                Button("Bulleted List") { MarkdownFormatting.apply(.bullet) }.keyboardShortcut("8", modifiers: [.command, .shift])
                Button("Numbered List") { MarkdownFormatting.apply(.numbered) }.keyboardShortcut("7", modifiers: [.command, .shift])
                Button("Checkbox") { model.insertCheckbox() }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Quote") { MarkdownFormatting.apply(.quote) }.keyboardShortcut("'", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Edit") { model.viewMode = .edit }.keyboardShortcut("1")
                Button("Split") { model.viewMode = .split }.keyboardShortcut("2")
                Button("Preview") { model.viewMode = .preview }.keyboardShortcut("3")
                Divider()
            }
            CommandGroup(replacing: .help) {
                Button("Markdown Cheat Sheet") { model.openCheatSheet() }
            }
        }

        Settings {
            NotchNotesSettings(model: model)
                .sharedAccentTint()
        }
    }
}

/// App-wide state shared by the window, menus and settings.
@Observable
@MainActor
final class NotesAppModel {
    let store = NotesStore()
    var selection: NoteID?
    var searchText = ""
    var viewMode: EditorMode = .split
    /// Note waiting for delete confirmation.
    var pendingDeleteID: NoteID?

    init() {
        viewMode = EditorMode(rawValue: UserDefaults.standard.string(forKey: "viewMode") ?? "") ?? .split
        selection = store.notes.first?.id
        consumeOpenRequest()
    }

    var selectedNote: Note? { store.note(id: selection) }

    var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.notes }
        return store.notes.filter {
            $0.body.localizedCaseInsensitiveContains(query) || $0.fileName.localizedCaseInsensitiveContains(query)
        }
    }

    func newNote() {
        searchText = ""
        if viewMode == .preview { viewMode = .split }
        selection = store.createNote().id
    }

    /// Asks for confirmation before moving a note to the Trash.
    func requestDelete(_ id: NoteID?) {
        pendingDeleteID = id
    }

    func confirmPendingDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        selection = id
        deleteSelected()
    }

    func deleteSelected() {
        guard let id = selection else { return }
        let index = store.notes.firstIndex { $0.id == id } ?? 0
        store.delete(id)
        let remaining = store.notes
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    func insertCheckbox() {
        if MarkdownFormatting.activeTextView != nil {
            MarkdownFormatting.apply(.checkbox)
            return
        }
        guard let note = selectedNote else { return }
        let body = note.body.isEmpty || note.body.hasSuffix("\n") ? note.body + "- [ ] " : note.body + "\n- [ ] "
        store.update(note.id, body: body)
        if viewMode == .preview { viewMode = .split }
    }

    func openCheatSheet() {
        searchText = ""
        selection = MarkdownCheatSheet.restore(in: store).id
        if viewMode == .edit { viewMode = .split }
    }

    /// Selects the note NotchHub asked us to open ("Open in NotchNotes").
    func consumeOpenRequest() {
        let defaults = NotesLocation.sharedDefaults
        guard let fileName = defaults.string(forKey: NotesLocation.openRequestKey) else { return }
        defaults.removeObject(forKey: NotesLocation.openRequestKey)
        store.reload()
        if let note = store.note(fileName: fileName) {
            searchText = ""
            selection = note.id
        }
    }

    func appDidBecomeActive() {
        store.syncFolderWithSharedSetting()
        consumeOpenRequest()
        if selectedNote == nil { selection = store.notes.first?.id }
    }
}

enum EditorMode: String, CaseIterable, Identifiable {
    case edit, split, preview
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .edit: "pencil"
        case .split: "rectangle.split.2x1"
        case .preview: "eye"
        }
    }
}
