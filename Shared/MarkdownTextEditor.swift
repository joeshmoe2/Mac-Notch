import AppKit
import SwiftUI

/// A text editor that formats Markdown as you type ("live preview").
///
/// Backed by an NSTextView: the file stays plain Markdown, but headings,
/// emphasis, code, links, quotes and lists are styled in place. Clicking a
/// `[ ]` box toggles it, and Return continues lists.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 14
    var monospaced = false
    /// When false, behaves like a plain text editor (no styling).
    var liveFormatting = true
    /// "#RRGGBB" accent (from NotchHub's Appearance settings); nil = system accent.
    var accentHex: String?
    var inset = CGSize(width: 12, height: 10)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // TextKit 1: restyling the whole note on every edit is a well-trodden path
        // there, while TextKit 2 can crash when attributes change outside the edited range.
        let textView = MarkdownNSTextView(usingTextLayoutManager: false)
        textView.coordinator = context.coordinator
        textView.isRichText = true // needed to show styling; pasting is forced to plain text below
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = inset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.restyle()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let styleChanged = coordinator.parent.fontSize != fontSize
            || coordinator.parent.monospaced != monospaced
            || coordinator.parent.liveFormatting != liveFormatting
            || coordinator.parent.accentHex != accentHex
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        // Match the SwiftUI color scheme (the notch forces dark content).
        textView.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        // Don't interrupt an in-progress composition (accents, Chinese/Japanese input, emoji).
        if textView.string != text, !textView.hasMarkedText() {
            coordinator.replaceAll(with: text)
        } else if styleChanged {
            coordinator.restyle()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownTextEditor
        weak var textView: NSTextView?

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }

        private var highlighter: MarkdownHighlighter {
            MarkdownHighlighter(fontSize: parent.fontSize, monospaced: parent.monospaced, accent: accent)
        }

        private var accent: NSColor {
            parent.accentHex.flatMap(NSColor.init(hex:)) ?? .controlAccentColor
        }

        func restyle() {
            guard let storage = textView?.textStorage else { return }
            storage.beginEditing()
            style(storage)
            storage.endEditing()
        }

        /// Applies a change made outside the editor (preview checkbox, file changed on
        /// disk, the other app). It goes through the normal editing path so it's
        /// registered with undo. Setting `string` directly left stale ranges on the
        /// undo stack, and ⌘Z afterwards could crash with "range out of bounds".
        func replaceAll(with text: String) {
            guard let textView, let storage = textView.textStorage else { return }
            let selection = textView.selectedRanges
            let full = NSRange(location: 0, length: storage.length)
            textView.breakUndoCoalescing()
            if textView.shouldChangeText(in: full, replacementString: text) {
                storage.replaceCharacters(in: full, with: text)
                textView.didChangeText()
            } else {
                textView.undoManager?.removeAllActions(withTarget: storage)
                textView.string = text
            }
            textView.breakUndoCoalescing()
            let length = (text as NSString).length
            let restored = selection.map { value -> NSValue in
                let r = value.rangeValue
                let location = min(r.location, length)
                return NSValue(range: NSRange(location: location, length: min(r.length, length - location)))
            }
            if !restored.isEmpty { textView.selectedRanges = restored }
            restyle()
        }

        /// Delegate callbacks are expected on the main thread; if AppKit ever calls
        /// one from elsewhere, hop to main instead of trapping.
        nonisolated private func onMain(_ work: @escaping @MainActor () -> Void) {
            if Thread.isMainThread {
                MainActor.assumeIsolated { work() }
            } else {
                DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
            }
        }

        private var isStyling = false

        private func style(_ storage: NSTextStorage) {
            textView?.insertionPointColor = accent
            if parent.liveFormatting {
                highlighter.apply(to: storage)
            } else {
                let font: NSFont = parent.monospaced
                    ? .monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
                    : .systemFont(ofSize: parent.fontSize)
                storage.setAttributes([.font: font, .foregroundColor: NSColor.labelColor],
                                      range: NSRange(location: 0, length: storage.length))
            }
            textView?.typingAttributes = [
                .font: parent.monospaced
                    ? NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
                    : NSFont.systemFont(ofSize: parent.fontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        }

        // Re-style after every edit (notes are small, so the whole text is fine).
        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), Thread.isMainThread else { return }
            MainActor.assumeIsolated {
                guard !isStyling else { return }
                isStyling = true
                defer { isStyling = false }
                style(textStorage)
            }
        }

        nonisolated func textDidChange(_ notification: Notification) {
            onMain { [weak self] in
                guard let self, let textView = self.textView, self.parent.text != textView.string else { return }
                self.parent.text = textView.string
            }
        }

        nonisolated func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard Thread.isMainThread, selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            return MainActor.assumeIsolated {
                // Let the input method handle Return while composing.
                guard !textView.hasMarkedText() else { return false }
                return continueList(in: textView)
            }
        }

        // MARK: List continuation

        private static let listPattern = try! NSRegularExpression(
            pattern: #"^(\s*)(?:([-*+])|(\d{1,9})([.)]))[ \t]+(\[[ xX]\][ \t]+)?(.*)$"#
        )

        /// On Return inside a list item, starts the next item; on an empty item, ends the list.
        private func continueList(in textView: NSTextView) -> Bool {
            let text = textView.string as NSString
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
            var content = text.substring(with: lineRange)
            if content.hasSuffix("\n") { content.removeLast() }
            let lineStartToCursor = selection.location - lineRange.location
            guard lineStartToCursor > 0,
                  let m = Self.listPattern.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length))
            else { return false }
            let ns = content as NSString
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            let indent = group(1) ?? ""
            let body = group(6) ?? ""
            if body.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty item: remove the marker and end the list.
                textView.insertText("", replacementRange: NSRange(location: lineRange.location, length: ns.length))
                return true
            }
            var marker: String
            if let bullet = group(2) {
                marker = bullet + " "
            } else {
                let number = (Int(group(3) ?? "1") ?? 1) + 1
                marker = "\(number)\(group(4) ?? ".") "
            }
            if group(5) != nil { marker += "[ ] " }
            textView.insertText("\n" + indent + marker, replacementRange: selection)
            return true
        }
    }
}

/// NSTextView that toggles `[ ]` / `[x]` when the box is clicked and pastes as plain text.
final class MarkdownNSTextView: NSTextView {
    weak var coordinator: MarkdownTextEditor.Coordinator?

    private static let taskBox = try! NSRegularExpression(pattern: #"^\s*[-*+][ \t]+(\[[ xX]\])"#)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if toggleTask(near: index) { return }
        super.mouseDown(with: event)
    }

    private func toggleTask(near index: Int) -> Bool {
        let text = string as NSString
        guard index <= text.length else { return false }
        let lineRange = text.lineRange(for: NSRange(location: min(index, max(text.length - 1, 0)), length: 0))
        let line = text.substring(with: lineRange)
        guard let m = Self.taskBox.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return false
        }
        let box = NSRange(location: lineRange.location + m.range(at: 1).location, length: 3)
        // Accept clicks on the box or right next to it.
        guard index >= box.location, index <= NSMaxRange(box) else { return false }
        let current = text.substring(with: box)
        let replacement = current.lowercased() == "[x]" ? "[ ]" : "[x]"
        insertText(replacement, replacementRange: box)
        return true
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }
}
