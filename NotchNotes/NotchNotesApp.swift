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
                Button("Move Note to Trash") { model.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .disabled(model.selectedNote == nil)
            }
            CommandMenu("Format") {
                Button("Insert Checkbox") { model.insertCheckbox() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(model.selectedNote == nil)
                Button(model.checklistMode ? "Edit as Text" : "Show as Checklist") { model.checklistMode.toggle() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        Settings {
            NotchNotesSettings(model: model)
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
    var checklistMode = false

    init() {
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
        checklistMode = false
        selection = store.createNote().id
    }

    func deleteSelected() {
        guard let id = selection else { return }
        let index = store.notes.firstIndex { $0.id == id } ?? 0
        store.delete(id)
        let remaining = store.notes
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    func insertCheckbox() {
        guard let note = selectedNote else { return }
        let body = note.body.isEmpty || note.body.hasSuffix("\n") ? note.body + "- [ ] " : note.body + "\n- [ ] "
        store.update(note.id, body: body)
        checklistMode = false
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
