import Foundation

/// In-memory identifier for a note. Stable for the lifetime of the app even
/// when the note's file is renamed (its title changed).
typealias NoteID = String

/// A note backed by a Markdown file in the notes folder.
/// Shared by NotchHub and the NotchNotes companion app.
struct Note: Identifiable, Equatable {
    let id: NoteID
    /// File name inside the notes folder, e.g. "Shopping list.md".
    var fileName: String
    var body: String
    var updatedAt: Date

    init(id: NoteID = UUID().uuidString, fileName: String, body: String, updatedAt: Date = .now) {
        self.id = id
        self.fileName = fileName
        self.body = body
        self.updatedAt = updatedAt
    }

    /// First non-empty line, stripped of markdown markers.
    var title: String {
        Note.title(for: body) ?? (fileName as NSString).deletingPathExtension
    }

    /// Title derived from the body, or nil if the body has no text yet.
    static func title(for body: String) -> String? {
        for raw in body.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = String(raw).trimmingCharacters(in: .whitespaces)
            for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* "] where line.hasPrefix(prefix) {
                line.removeFirst(prefix.count)
            }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
            if !line.isEmpty { return line }
        }
        return nil
    }

    /// Short preview of the text after the title line.
    var preview: String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
        return lines.prefix(3).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    var hasChecklist: Bool {
        body.contains("- [ ]") || body.contains("- [x]")
    }

    var wordCount: Int {
        body.split { $0.isWhitespace || $0.isNewline }.count
    }
}

/// A parsed line of a note for the checklist view.
struct NoteLine: Identifiable {
    enum Kind { case text, unchecked, checked }
    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ body: String) -> [NoteLine] {
        body.components(separatedBy: "\n").enumerated().map { index, raw in
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") || trimmed == "- [ ]" {
                return NoteLine(id: index, kind: .unchecked, text: String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
            if trimmed.lowercased().hasPrefix("- [x] ") || trimmed.lowercased() == "- [x]" {
                return NoteLine(id: index, kind: .checked, text: String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
            return NoteLine(id: index, kind: .text, text: raw)
        }
    }

    /// Toggles the checkbox on `lineIndex` in `body`.
    static func toggle(lineIndex: Int, in body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return body }
        let line = lines[lineIndex]
        if let range = line.range(of: "- [ ]") {
            lines[lineIndex] = line.replacingCharacters(in: range, with: "- [x]")
        } else if let range = line.range(of: "- [x]", options: .caseInsensitive) {
            lines[lineIndex] = line.replacingCharacters(in: range, with: "- [ ]")
        }
        return lines.joined(separator: "\n")
    }
}
