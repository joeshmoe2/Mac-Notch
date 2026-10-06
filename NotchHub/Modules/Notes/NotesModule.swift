import AppKit
import SwiftUI

extension Prefs {
    /// File name of the note pinned to Home.
    static let notesPinnedFile = PrefKey("notes.pinnedFile", "")
    static let notesMonospaced = PrefKey("notes.monospaced", false)
}

/// Multi-note scratchpad. Notes are Markdown files in a user-visible folder
/// (see `NotesStore`), shared with the NotchNotes companion app.
@Observable
@MainActor
final class NotesModule: NotchModule {
    let id = "notes"
    let name = "Notes"
    let icon = "note.text"

    static let companionBundleID = "com.notchhub.NotchNotes"

    let store: NotesStore
    var selectedID: NoteID?
    /// Mirrors `Prefs.notesPinnedFile` so the UI updates when pinning.
    private var pinnedFile = Prefs.notesPinnedFile.value

    init() {
        store = NotesStore()
        migrateLegacyJSONIfNeeded()
        if store.notes.isEmpty {
            store.createNote(body: "Welcome to NotchHub Notes\n\n- [ ] Hover the notch\n- [x] Take a note\n\nNotes are saved as Markdown files in Documents › NotchHub Notes.")
        }
        selectedID = store.notes.first?.id
    }

    var notes: [Note] { store.notes }
    var selected: Note? { store.note(id: selectedID) }

    var pinnedID: NoteID? {
        pinnedFile.isEmpty ? nil : store.note(fileName: pinnedFile)?.id
    }

    var pinned: Note? { store.note(id: pinnedID) }

    // MARK: Editing

    func newNote() {
        selectedID = store.createNote().id
    }

    func update(_ id: NoteID, body: String) {
        let wasPinned = pinnedID == id
        store.update(id, body: body)
        // Saving may rename the file; keep the pin pointing at it afterwards.
        if wasPinned { trackPinnedRename(id) }
    }

    func toggleCheckbox(noteID: NoteID, line: Int) {
        store.toggleCheckbox(noteID, line: line)
    }

    func delete(_ id: NoteID) {
        if pinnedID == id { setPinned(nil) }
        store.delete(id)
        if selectedID == id { selectedID = store.notes.first?.id }
    }

    func setPinned(_ id: NoteID?) {
        pinnedFile = store.note(id: id)?.fileName ?? ""
        Prefs.notesPinnedFile.set(pinnedFile)
    }

    private func trackPinnedRename(_ id: NoteID) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, let note = self.store.note(id: id) else { return }
            if self.pinnedFile != note.fileName { self.setPinned(id) }
        }
    }

    func saveNow() {
        store.flushSaves()
    }

    // MARK: Companion app

    var companionURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.companionBundleID)
    }

    /// Opens NotchNotes, selecting `note` if given.
    func openInCompanion(_ note: Note?) {
        store.flushSaves()
        if let note {
            NotesLocation.sharedDefaults.set(store.note(id: note.id)?.fileName ?? note.fileName,
                                             forKey: NotesLocation.openRequestKey)
        }
        guard let url = companionURL else {
            let alert = NSAlert()
            alert.messageText = "NotchNotes isn't installed"
            alert.informativeText = "Build the NotchNotes scheme in Xcode (or copy NotchNotes.app to Applications), then try again. Your notes are also plain Markdown files you can open in any editor."
            alert.addButton(withTitle: "Show Notes Folder")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { store.revealInFinder() }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: Migration from the old notes.json

    private struct LegacyNote: Decodable {
        var body: String
        var updatedAt: Date
    }

    private func migrateLegacyJSONIfNeeded() {
        let legacyURL = JSONStore.url(for: "notes.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              let legacy = JSONStore.load([LegacyNote].self, from: "notes.json") else { return }
        for note in legacy.sorted(by: { $0.updatedAt < $1.updatedAt }) where !note.body.isEmpty {
            store.createNote(body: note.body)
        }
        store.flushSaves()
        try? FileManager.default.moveItem(at: legacyURL, to: legacyURL.appendingPathExtension("migrated"))
    }

    // MARK: NotchModule

    func willExpand() {
        store.syncFolderWithSharedSetting()
        store.reload()
        if selected == nil { selectedID = store.notes.first?.id }
    }

    func compactView() -> AnyView { AnyView(NotesCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(NotesExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(NotesSettingsView(module: self)) }
}
