import AppKit
import Observation

/// Where notes live. Stored in a shared preferences domain so NotchHub and
/// NotchNotes always point at the same folder.
enum NotesLocation {
    static let sharedDefaults = UserDefaults(suiteName: "com.notchhub.shared") ?? .standard
    private static let folderKey = "notesFolderPath"
    /// Note the other app should select when it opens (set by "Open in NotchNotes").
    static let openRequestKey = "notesOpenRequest"

    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchHub Notes", isDirectory: true)
    }

    static var folder: URL {
        get {
            if let path = sharedDefaults.string(forKey: folderKey), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return defaultFolder
        }
        set { sharedDefaults.set(newValue.path, forKey: folderKey) }
    }

    static func resetToDefault() {
        sharedDefaults.removeObject(forKey: folderKey)
    }
}

/// Notes as plain Markdown files (one `.md` per note) in a user-visible folder.
///
/// - Edits autosave (debounced) with atomic writes.
/// - A note's file is renamed to match its title (first line).
/// - The folder is watched with a DispatchSource, so changes made by the other
///   app, Finder, iCloud Drive or another editor show up automatically.
@Observable
@MainActor
final class NotesStore {
    static let fileExtensions: Set<String> = ["md", "markdown", "txt"]

    private(set) var notes: [Note] = []
    private(set) var folder: URL
    private(set) var lastError: String?

    @ObservationIgnored private var saveTasks: [NoteID: Task<Void, Never>] = [:]
    /// Modification dates we last read or wrote, to ignore our own changes.
    @ObservationIgnored private var knownDates: [String: Date] = [:]
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init() {
        folder = NotesLocation.folder
        ensureFolder()
        reload()
        startWatching()
        // Catch anything the watcher missed (e.g. a network or iCloud folder).
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { NotesStore.instances.forEach { $0.reload() } }
        }
        NotesStore.instances.append(self)
    }

    /// Lets the activation observer reach every store without capturing self.
    private static var instances: [NotesStore] = []

    // MARK: Folder

    func changeFolder(to url: URL) {
        flushSaves()
        NotesLocation.folder = url
        folder = url
        ensureFolder()
        knownDates.removeAll()
        notes.removeAll()
        reload()
        startWatching()
    }

    /// Picks up a folder change made in the other app.
    func syncFolderWithSharedSetting() {
        let shared = NotesLocation.folder
        if shared.standardizedFileURL != folder.standardizedFileURL { changeFolder(to: shared) }
    }

    func revealInFinder(_ note: Note? = nil) {
        if let note {
            NSWorkspace.shared.activateFileViewerSelecting([url(for: note.fileName)])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }

    private func ensureFolder() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            lastError = nil
        } catch {
            lastError = "Can't use the notes folder: \(error.localizedDescription)"
        }
    }

    func url(for fileName: String) -> URL {
        folder.appendingPathComponent(fileName)
    }

    // MARK: Loading

    func reload() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return }

        let existingByFile = Dictionary(notes.map { ($0.fileName, $0) }, uniquingKeysWith: { a, _ in a })
        var loaded: [Note] = []
        for url in urls where Self.fileExtensions.contains(url.pathExtension.lowercased()) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let fileName = url.lastPathComponent
            let modified = values?.contentModificationDate ?? .now

            if let existing = existingByFile[fileName] {
                // Keep in-memory text if we have unsaved edits or the file hasn't changed.
                if saveTasks[existing.id] != nil || knownDates[fileName] == modified {
                    loaded.append(existing)
                    continue
                }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    var updated = existing
                    updated.body = text
                    updated.updatedAt = modified
                    loaded.append(updated)
                    knownDates[fileName] = modified
                }
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                loaded.append(Note(fileName: fileName, body: text, updatedAt: modified))
                knownDates[fileName] = modified
            }
        }
        // Notes that are new in memory but not yet written stay visible.
        for note in notes where saveTasks[note.id] != nil && !loaded.contains(where: { $0.id == note.id }) {
            loaded.append(note)
        }
        loaded.sort { $0.updatedAt > $1.updatedAt }
        if loaded != notes { notes = loaded }
    }

    // MARK: Editing

    @discardableResult
    func createNote(body: String = "") -> Note {
        let fileName = uniqueFileName(base: Note.title(for: body).map(Self.sanitize) ?? "Untitled", excluding: nil)
        let note = Note(fileName: fileName, body: body)
        notes.insert(note, at: 0)
        write(note.id)
        return note
    }

    func note(id: NoteID?) -> Note? {
        guard let id else { return nil }
        return notes.first { $0.id == id }
    }

    func note(fileName: String) -> Note? {
        notes.first { $0.fileName == fileName }
    }

    func update(_ id: NoteID, body: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].body != body else { return }
        notes[i].body = body
        notes[i].updatedAt = .now
        scheduleSave(id)
    }

    func toggleCheckbox(_ id: NoteID, line: Int) {
        guard let note = note(id: id) else { return }
        update(id, body: NoteLine.toggle(lineIndex: line, in: note.body))
    }

    /// Moves the note's file to the Trash (recoverable).
    func delete(_ id: NoteID) {
        guard let note = note(id: id) else { return }
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        let url = url(for: note.fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                lastError = "Couldn't delete \(note.fileName): \(error.localizedDescription)"
                return
            }
        }
        knownDates[note.fileName] = nil
        notes.removeAll { $0.id == id }
    }

    // MARK: Saving

    private func scheduleSave(_ id: NoteID) {
        saveTasks[id]?.cancel()
        saveTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.saveTasks[id] = nil
            self.write(id)
        }
    }

    /// Writes all pending edits immediately (e.g. on quit).
    func flushSaves() {
        let pending = Array(saveTasks.keys)
        for id in pending {
            saveTasks[id]?.cancel()
            saveTasks[id] = nil
            write(id)
        }
    }

    private func write(_ id: NoteID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[i]

        // Rename the file to follow the title.
        if let title = Note.title(for: note.body) {
            let newName = uniqueFileName(base: Self.sanitize(title), excluding: note.fileName)
            // Skip no-ops and case-only changes (the default macOS file system is case-insensitive).
            if newName.lowercased() != note.fileName.lowercased() {
                let oldURL = url(for: note.fileName)
                if FileManager.default.fileExists(atPath: oldURL.path) {
                    do {
                        try FileManager.default.moveItem(at: oldURL, to: url(for: newName))
                        knownDates[note.fileName] = nil
                        note.fileName = newName
                    } catch {
                        // Keep the old name if the rename fails.
                    }
                } else {
                    note.fileName = newName
                }
            }
        }

        let fileURL = url(for: note.fileName)
        do {
            try note.body.write(to: fileURL, atomically: true, encoding: .utf8)
            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            knownDates[note.fileName] = modified
            if let modified { note.updatedAt = modified }
            lastError = nil
        } catch {
            lastError = "Couldn't save \(note.fileName): \(error.localizedDescription)"
        }
        if let j = notes.firstIndex(where: { $0.id == id }) { notes[j] = note }
    }

    // MARK: File names

    /// Makes a title safe to use as a file name.
    static func sanitize(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        var s = title.components(separatedBy: forbidden).joined(separator: " ")
        s = s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        if s.count > 80 { s = String(s.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? "Untitled" : s
    }

    private func uniqueFileName(base: String, excluding current: String?) -> String {
        let currentLower = current?.lowercased()
        let taken = Set(notes.map { $0.fileName.lowercased() }).subtracting([currentLower].compactMap { $0 })
        var candidate = base + ".md"
        var n = 2
        while taken.contains(candidate.lowercased())
            || (candidate.lowercased() != currentLower && FileManager.default.fileExists(atPath: url(for: candidate).path)) {
            candidate = "\(base) \(n).md"
            n += 1
        }
        return candidate
    }

    // MARK: Watching

    private func startWatching() {
        watcher?.cancel()
        watcher = nil
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
