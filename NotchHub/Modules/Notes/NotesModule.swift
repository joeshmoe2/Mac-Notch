import SwiftUI

extension Prefs {
    static let notesPinnedID = PrefKey("notes.pinnedID", "")
    static let notesMonospaced = PrefKey("notes.monospaced", false)
}

/// Multi-note scratchpad persisted as JSON with debounced autosave.
@Observable
@MainActor
final class NotesModule: NotchModule {
    let id = "notes"
    let name = "Notes"
    let icon = "note.text"

    private static let fileName = "notes.json"

    private(set) var notes: [Note] = []
    var selectedID: UUID?
    private(set) var pinnedID: UUID?

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        notes = JSONStore.load([Note].self, from: Self.fileName) ?? []
        if notes.isEmpty {
            notes = [Note(body: "Welcome to NotchHub Notes\n\n- [ ] Hover the notch\n- [x] Take a note")]
        }
        notes.sort { $0.updatedAt > $1.updatedAt }
        selectedID = notes.first?.id
        pinnedID = UUID(uuidString: Prefs.notesPinnedID.value)
    }

    var selected: Note? { notes.first { $0.id == selectedID } }
    var pinned: Note? { notes.first { $0.id == pinnedID } }

    // MARK: Editing

    func newNote() {
        let note = Note()
        notes.insert(note, at: 0)
        selectedID = note.id
        scheduleSave()
    }

    func update(_ id: UUID, body: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].body != body else { return }
        notes[i].body = body
        notes[i].updatedAt = .now
        scheduleSave()
    }

    func toggleCheckbox(noteID: UUID, line: Int) {
        guard let note = notes.first(where: { $0.id == noteID }) else { return }
        update(noteID, body: NoteLine.toggle(lineIndex: line, in: note.body))
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if pinnedID == id { setPinned(nil) }
        if selectedID == id { selectedID = notes.first?.id }
        scheduleSave()
    }

    func setPinned(_ id: UUID?) {
        pinnedID = id
        Prefs.notesPinnedID.set(id?.uuidString ?? "")
    }

    // MARK: Persistence

    /// Autosave shortly after the user stops typing.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        JSONStore.save(notes, to: Self.fileName)
    }

    // MARK: NotchModule

    func compactView() -> AnyView { AnyView(NotesCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(NotesExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(NotesSettingsView(module: self)) }
}
