import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var body: String
    var updatedAt: Date

    init(body: String = "") {
        self.id = UUID()
        self.body = body
        self.updatedAt = .now
    }

    /// First non-empty line, stripped of markdown markers.
    var title: String {
        let line = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let stripped = line
            .replacingOccurrences(of: "- [ ] ", with: "")
            .replacingOccurrences(of: "- [x] ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        return stripped.isEmpty ? "New Note" : stripped
    }

    var hasChecklist: Bool {
        body.contains("- [ ]") || body.contains("- [x]")
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
