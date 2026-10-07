import Foundation

/// A block-level Markdown element.
enum MarkdownBlock {
    struct ListItem {
        enum Marker { case bullet, number(Int), task(checked: Bool) }
        var marker: Marker
        var text: String
        /// Nesting depth (0 = top level).
        var depth: Int
        /// Source line index in the note (used to toggle task boxes).
        var line: Int
    }

    enum Alignment { case leading, center, trailing }

    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case list([ListItem])
    case code(language: String, text: String)
    case rule
    case table(header: [String], alignments: [Alignment], rows: [[String]])
    case image(alt: String, source: String)
    case definition(term: String, definitions: [String])
    case footnotes([(label: String, text: String)])
}

/// Small, dependency-free Markdown block parser covering CommonMark basics
/// plus common extensions (tables, task lists, footnotes, definition lists,
/// fenced code). Inline syntax is handled by `MarkdownInline`.
enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var footnotes: [(label: String, text: String)] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line ends a paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Fenced code block.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // closing fence
                blocks.append(.code(language: language, text: code.joined(separator: "\n")))
                continue
            }

            // Heading.
            if let match = firstMatch(#"^(#{1,6})\s+(.*?)\s*#*\s*$"#, in: trimmed) {
                flushParagraph()
                var text = match[2]
                // Strip a custom heading ID: "My Heading {#custom-id}".
                if let idRange = text.range(of: #"\s*\{#[^}]*\}$"#, options: .regularExpression) {
                    text.removeSubrange(idRange)
                }
                blocks.append(.heading(level: match[1].count, text: text))
                i += 1
                continue
            }

            // Horizontal rule.
            if trimmed.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil {
                // "Text\n---" is a setext heading in CommonMark.
                if !paragraph.isEmpty, trimmed.hasPrefix("-") || trimmed.hasPrefix("=") {
                    let text = paragraph.joined(separator: " ")
                    paragraph.removeAll()
                    blocks.append(.heading(level: 2, text: text))
                } else {
                    flushParagraph()
                    blocks.append(.rule)
                }
                i += 1
                continue
            }
            if !paragraph.isEmpty, trimmed.range(of: #"^=+$"#, options: .regularExpression) != nil {
                let text = paragraph.joined(separator: " ")
                paragraph.removeAll()
                blocks.append(.heading(level: 1, text: text))
                i += 1
                continue
            }

            // Footnote definition: [^1]: text
            if let match = firstMatch(#"^\[\^([^\]]+)\]:\s*(.*)$"#, in: trimmed) {
                flushParagraph()
                footnotes.append((label: match[1], text: match[2]))
                i += 1
                continue
            }

            // Block quote.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var content = String(t.dropFirst())
                    if content.hasPrefix(" ") { content.removeFirst() }
                    quoted.append(content)
                    i += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            // List (bullets, numbers, tasks), including nested items.
            if listItem(line, index: i) != nil {
                flushParagraph()
                var items: [MarkdownBlock.ListItem] = []
                while i < lines.count {
                    if let item = listItem(lines[i], index: i) {
                        items.append(item)
                        i += 1
                    } else if !lines[i].trimmingCharacters(in: .whitespaces).isEmpty,
                              lines[i].hasPrefix("  ") || lines[i].hasPrefix("\t"),
                              !items.isEmpty {
                        // Continuation line of the previous item.
                        items[items.count - 1].text += "\n" + lines[i].trimmingCharacters(in: .whitespaces)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(items))
                continue
            }

            // Table: header row followed by a delimiter row.
            if trimmed.contains("|"), i + 1 < lines.count, isTableDelimiter(lines[i + 1]) {
                flushParagraph()
                let header = tableCells(trimmed)
                let alignments = tableCells(lines[i + 1]).map { cell -> MarkdownBlock.Alignment in
                    let c = cell.trimmingCharacters(in: .whitespaces)
                    if c.hasPrefix(":") && c.hasSuffix(":") { return .center }
                    if c.hasSuffix(":") { return .trailing }
                    return .leading
                }
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.contains("|") else { break }
                    rows.append(tableCells(t))
                    i += 1
                }
                blocks.append(.table(header: header, alignments: alignments, rows: rows))
                continue
            }

            // Definition list: term followed by ": definition" lines.
            if paragraph.isEmpty, i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix(": ") {
                var definitions: [String] = []
                var j = i + 1
                while j < lines.count {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(": ") else { break }
                    definitions.append(String(t.dropFirst(2)))
                    j += 1
                }
                blocks.append(.definition(term: trimmed, definitions: definitions))
                i = j
                continue
            }

            // Image on its own line.
            if let match = firstMatch(#"^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)$"#, in: trimmed) {
                flushParagraph()
                blocks.append(.image(alt: match[1], source: match[2]))
                i += 1
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        if !footnotes.isEmpty { blocks.append(.footnotes(footnotes)) }
        return blocks
    }

    // MARK: Helpers

    private static func listItem(_ line: String, index: Int) -> MarkdownBlock.ListItem? {
        guard let match = firstMatch(#"^(\s*)([-*+]|\d{1,9}[.)])\s+(.*)$"#, in: line) else { return nil }
        let indent = match[1].replacingOccurrences(of: "\t", with: "    ").count
        let depth = indent / 2
        var text = match[3]
        let markerText = match[2]
        var marker: MarkdownBlock.ListItem.Marker
        if let number = Int(markerText.dropLast()), markerText.last == "." || markerText.last == ")" {
            marker = .number(number)
        } else {
            marker = .bullet
        }
        if let task = firstMatch(#"^\[( |x|X)\]\s*(.*)$"#, in: text) {
            marker = .task(checked: task[1] != " ")
            text = task[2]
        }
        return .init(marker: marker, text: text, depth: depth, line: index)
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        return t.range(of: #"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$"#, options: .regularExpression) != nil
    }

    private static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Returns capture groups (index 0 = whole match) for the first match.
    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { idx in
            guard let r = Range(m.range(at: idx), in: text) else { return "" }
            return String(text[r])
        }
    }
}
