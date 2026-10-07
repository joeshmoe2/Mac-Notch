import AppKit

/// Markdown formatting commands applied to the focused text editor.
///
/// SwiftUI's TextEditor is backed by an NSTextView, so we edit through it.
/// `insertText(_:replacementRange:)` keeps undo working and updates the
/// SwiftUI binding like normal typing does.
@MainActor
enum MarkdownFormatting {
    enum Style {
        case bold, italic, strikethrough, code, highlight, link
        case heading(Int), bullet, numbered, checkbox, quote
    }

    static var activeTextView: NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    static func apply(_ style: Style) {
        guard let textView = activeTextView, textView.isEditable else { return }
        switch style {
        case .bold: wrap(textView, "**", "**", placeholder: "bold text")
        case .italic: wrap(textView, "*", "*", placeholder: "italic text")
        case .strikethrough: wrap(textView, "~~", "~~", placeholder: "strikethrough")
        case .code: wrap(textView, "`", "`", placeholder: "code")
        case .highlight: wrap(textView, "==", "==", placeholder: "highlight")
        case .link: link(textView)
        case .heading(let level): prefixLines(textView, String(repeating: "#", count: level) + " ", replacingHeading: true)
        case .bullet: prefixLines(textView, "- ")
        case .numbered: prefixLines(textView, "1. ")
        case .checkbox: prefixLines(textView, "- [ ] ")
        case .quote: prefixLines(textView, "> ")
        }
    }

    private static func wrap(_ tv: NSTextView, _ prefix: String, _ suffix: String, placeholder: String) {
        let range = tv.selectedRange()
        let string = tv.string as NSString
        let selected = range.length > 0 ? string.substring(with: range) : ""
        // Toggle off if the selection is already wrapped.
        if selected.hasPrefix(prefix), selected.hasSuffix(suffix), selected.count >= prefix.count + suffix.count {
            let inner = String(selected.dropFirst(prefix.count).dropLast(suffix.count))
            replace(tv, range, with: inner, select: NSRange(location: range.location, length: (inner as NSString).length))
            return
        }
        let inner = selected.isEmpty ? placeholder : selected
        let replacement = prefix + inner + suffix
        let innerStart = range.location + (prefix as NSString).length
        replace(tv, range, with: replacement, select: NSRange(location: innerStart, length: (inner as NSString).length))
    }

    private static func link(_ tv: NSTextView) {
        let range = tv.selectedRange()
        let selected = range.length > 0 ? (tv.string as NSString).substring(with: range) : "title"
        let replacement = "[\(selected)](https://)"
        // Select the URL part so the user can paste over it.
        let urlStart = range.location + ("[\(selected)](" as NSString).length
        replace(tv, range, with: replacement, select: NSRange(location: urlStart, length: 8))
    }

    /// Adds `prefix` to the start of every line touched by the selection
    /// (or removes it if all of them already have it).
    private static func prefixLines(_ tv: NSTextView, _ prefix: String, replacingHeading: Bool = false) {
        let string = tv.string as NSString
        let lineRange = string.lineRange(for: tv.selectedRange())
        var block = string.substring(with: lineRange)
        let endsWithNewline = block.hasSuffix("\n")
        if endsWithNewline { block.removeLast() }
        var lines = block.components(separatedBy: "\n")
        let allPrefixed = lines.allSatisfy { $0.hasPrefix(prefix) }
        lines = lines.map { line in
            if allPrefixed { return String(line.dropFirst(prefix.count)) }
            var body = line
            if replacingHeading, let match = body.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                body.removeSubrange(match)
            }
            return prefix + body
        }
        let replacement = lines.joined(separator: "\n") + (endsWithNewline ? "\n" : "")
        let caret = lineRange.location + (replacement as NSString).length - (endsWithNewline ? 1 : 0)
        replace(tv, lineRange, with: replacement, select: NSRange(location: caret, length: 0))
    }

    private static func replace(_ tv: NSTextView, _ range: NSRange, with text: String, select: NSRange) {
        tv.insertText(text, replacementRange: range)
        tv.setSelectedRange(select)
    }
}
