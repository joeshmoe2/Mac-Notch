import AppKit

/// Styles Markdown source text in place ("live preview" editing).
///
/// The text stays plain Markdown; we only change how it looks: headings get
/// bigger, **bold** turns bold, markers like `**` and `#` are dimmed, and so on.
@MainActor
struct MarkdownHighlighter {
    var fontSize: CGFloat
    var monospaced: Bool

    private var baseFont: NSFont {
        monospaced
            ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : .systemFont(ofSize: fontSize)
    }

    private var codeFont: NSFont { .monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular) }
    private let markerColor = NSColor.tertiaryLabelColor
    private let accent = NSColor.controlAccentColor

    // MARK: Regexes (compiled once)

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are constants; a failure is a programming error.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let heading = regex(#"^(#{1,6})[ \t]+.*$"#)
    private static let quote = regex(#"^\s*(>+)\s?"#)
    private static let listMarker = regex(#"^(\s*)([-*+]|\d{1,9}[.)])[ \t]+"#)
    private static let task = regex(#"^(\s*[-*+][ \t]+)(\[[ xX]\])"#)
    private static let rule = regex(#"^\s*([-*_])(\s*\1){2,}\s*$"#)
    private static let fence = regex(#"^\s*(```|~~~)"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = regex(#"(?<![*_\w])([*_])(?=\S)(.+?)(?<=\S)\1(?![*_\w])"#)
    private static let strike = regex(#"(~~)(?=\S)(.+?)(?<=\S)~~"#)
    private static let code = regex(#"(`+)([^`\n]+?)\1"#)
    private static let highlight = regex(#"(==)(?=\S)(.+?)(?<=\S)=="#)
    private static let link = regex(#"(!?)\[([^\]\n]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)
    private static let footnoteRef = regex(#"\[\^[^\]\s]+\]"#)
    private static let tablePipe = regex(#"\|"#)
    private static let headingID = regex(#"\s\{#[^}]*\}\s*$"#)

    // MARK: Apply

    func apply(to storage: NSTextStorage) {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.25
        paragraph.paragraphSpacing = fontSize * 0.2

        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ], range: full)

        var inFence = false
        var codeRanges: [NSRange] = []
        var location = 0
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            var contentRange = lineRange
            // Exclude the trailing newline from styling.
            if contentRange.length > 0, text.character(at: NSMaxRange(contentRange) - 1) == 10 {
                contentRange.length -= 1
            }
            let line = text.substring(with: contentRange)
            styleLine(line, range: contentRange, storage: storage, inFence: &inFence, codeRanges: &codeRanges)
            location = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }

        // Inline styles everywhere except code blocks.
        applyInline(storage: storage, text: text, excluding: codeRanges)
    }

    private func styleLine(_ line: String, range: NSRange, storage: NSTextStorage,
                           inFence: inout Bool, codeRanges: inout [NSRange]) {
        let local = NSRange(location: 0, length: (line as NSString).length)

        // Fenced code blocks.
        if Self.fence.firstMatch(in: line, range: local) != nil {
            storage.addAttributes([.font: codeFont, .foregroundColor: markerColor], range: range)
            codeRanges.append(range)
            inFence.toggle()
            return
        }
        if inFence {
            storage.addAttributes([
                .font: codeFont,
                .backgroundColor: NSColor.labelColor.withAlphaComponent(0.06),
            ], range: range)
            codeRanges.append(range)
            return
        }

        // Headings.
        if let m = Self.heading.firstMatch(in: line, range: local) {
            let level = m.range(at: 1).length
            let scales: [CGFloat] = [1.75, 1.45, 1.25, 1.12, 1.05, 1.0]
            let font = NSFont.systemFont(ofSize: fontSize * scales[level - 1], weight: level <= 2 ? .bold : .semibold)
            storage.addAttribute(.font, value: font, range: range)
            dim(NSRange(location: range.location, length: m.range(at: 1).length + 1), storage)
            if let id = Self.headingID.firstMatch(in: line, range: local) {
                dim(offset(id.range, by: range.location), storage)
            }
            return
        }

        // Horizontal rule.
        if Self.rule.firstMatch(in: line, range: local) != nil {
            dim(range, storage)
            return
        }

        // Block quote.
        if let m = Self.quote.firstMatch(in: line, range: local) {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            storage.addAttribute(.foregroundColor, value: accent, range: offset(m.range(at: 1), by: range.location))
            italicize(range, storage)
        }

        // Lists and tasks.
        if let m = Self.listMarker.firstMatch(in: line, range: local) {
            storage.addAttribute(.foregroundColor, value: accent, range: offset(m.range(at: 2), by: range.location))
            if let t = Self.task.firstMatch(in: line, range: local) {
                let box = offset(t.range(at: 2), by: range.location)
                storage.addAttributes([
                    .foregroundColor: accent,
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                    .cursor: NSCursor.pointingHand,
                ], range: box)
                let checked = (line as NSString).substring(with: t.range(at: 2)).lowercased() == "[x]"
                if checked {
                    let restStart = NSMaxRange(box)
                    let rest = NSRange(location: restStart, length: NSMaxRange(range) - restStart)
                    storage.addAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ], range: rest)
                }
            }
        }

        // Tables: dim the pipes.
        if line.contains("|") {
            for m in Self.tablePipe.matches(in: line, range: local) {
                dim(offset(m.range, by: range.location), storage)
            }
        }
    }

    private func applyInline(storage: NSTextStorage, text: NSString, excluding code: [NSRange]) {
        let full = NSRange(location: 0, length: text.length)
        let string = text as String
        func outsideCode(_ r: NSRange) -> Bool {
            !code.contains { NSIntersectionRange($0, r).length > 0 }
        }

        // Inline code first so emphasis inside it is ignored.
        var inlineCode: [NSRange] = []
        for m in Self.code.matches(in: string, range: full) where outsideCode(m.range) {
            storage.addAttributes([
                .font: codeFont,
                .backgroundColor: NSColor.labelColor.withAlphaComponent(0.08),
            ], range: m.range)
            dimMarkers(m, storage)
            inlineCode.append(m.range)
        }
        func free(_ r: NSRange) -> Bool {
            outsideCode(r) && !inlineCode.contains { NSIntersectionRange($0, r).length > 0 }
        }

        for m in Self.bold.matches(in: string, range: full) where free(m.range) {
            addTrait(.boldFontMask, range: m.range(at: 2), storage)
            dimMarkers(m, storage)
        }
        for m in Self.italic.matches(in: string, range: full) where free(m.range) {
            addTrait(.italicFontMask, range: m.range(at: 2), storage)
            dimMarkers(m, storage)
        }
        for m in Self.strike.matches(in: string, range: full) where free(m.range) {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 2))
            dimMarkers(m, storage)
        }
        for m in Self.highlight.matches(in: string, range: full) where free(m.range) {
            storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: m.range(at: 2))
            dimMarkers(m, storage)
        }
        for m in Self.link.matches(in: string, range: full) where free(m.range) {
            let title = m.range(at: 2)
            let urlRange = m.range(at: 3)
            dim(m.range, storage)
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            if let url = URL(string: text.substring(with: urlRange)), url.scheme != nil {
                attributes[.link] = url
            }
            storage.addAttributes(attributes, range: title)
        }
        for m in Self.footnoteRef.matches(in: string, range: full) where free(m.range) {
            storage.addAttribute(.foregroundColor, value: accent, range: m.range)
        }
    }

    // MARK: Helpers

    private func offset(_ r: NSRange, by delta: Int) -> NSRange {
        NSRange(location: r.location + delta, length: r.length)
    }

    private func dim(_ r: NSRange, _ storage: NSTextStorage) {
        guard r.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: markerColor, range: r)
    }

    /// Dims the delimiter characters around group 2 of a match.
    private func dimMarkers(_ m: NSTextCheckingResult, _ storage: NSTextStorage) {
        let whole = m.range
        let inner = m.range(at: 2)
        dim(NSRange(location: whole.location, length: inner.location - whole.location), storage)
        dim(NSRange(location: NSMaxRange(inner), length: NSMaxRange(whole) - NSMaxRange(inner)), storage)
    }

    private func addTrait(_ trait: NSFontTraitMask, range: NSRange, _ storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? NSFont) ?? baseFont
            let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: sub)
        }
    }

    private func italicize(_ range: NSRange, _ storage: NSTextStorage) {
        addTrait(.italicFontMask, range: range, storage)
    }
}
