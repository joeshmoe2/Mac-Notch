import SwiftUI

/// Inline Markdown → AttributedString.
///
/// Foundation's parser handles **bold**, *italic*, `code`, ~~strike~~ and
/// [links](url). On top of that we add ==highlight==, H~2~O subscript,
/// X^2^ superscript, footnote references [^1], :emoji: shortcodes and a few
/// simple inline HTML tags (<u>, <mark>, <sub>, <sup>, <b>, <i>, <s>, <kbd>,
/// <br>, and <span style="color:…">). Other HTML is shown as typed.
enum MarkdownInline {
    static func render(_ text: String, size: CGFloat) -> AttributedString {
        let source = replaceEmoji(in: text)
        var result = AttributedString()
        // Split into plain runs and our extension tokens.
        let pattern = #"==(.+?)==|(?<!~)~(?!~)([^~\s]+)~(?!~)|\^([^\^\s]+)\^|\[\^([^\]]+)\]"#
            + #"|<(?i:(u|ins|mark|sub|sup|b|strong|i|em|s|del|strike|kbd|small|span|font))(\s[^>]*)?>(.*?)</(?i:\5)\s*>"#
            + #"|(<(?i:br)\s*/?>)"#
            + #"|\[\[([^\[\]\n]+)\]\]"#
            + #"|(?<!!)\[([^\[\]\n]+)\]\((<[^>\n]*>|[^)\n]*)\)"#
        guard let regex = MarkdownParser.cachedRegex(pattern) else {
            return foundation(source)
        }
        let ns = source as NSString
        // Leave `code spans` alone, so `<u>x</u>` in backticks is shown as typed.
        let codeSpans = MarkdownParser.cachedRegex(#"(`+)[^`]*?\1"#)?
            .matches(in: source, range: NSRange(location: 0, length: ns.length)).map(\.range) ?? []
        var cursor = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        where match.range.location >= cursor
            && !codeSpans.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
            if match.range.location > cursor {
                result += foundation(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            if let r = Range(match.range(at: 1), in: source) {
                var part = foundation(String(source[r]))
                part.backgroundColor = Color.yellow.opacity(0.45)
                result += part
            } else if let r = Range(match.range(at: 2), in: source) {
                var part = AttributedString(String(source[r]))
                part.font = .system(size: size * 0.72)
                part.baselineOffset = -size * 0.2
                result += part
            } else if let r = Range(match.range(at: 3), in: source) {
                var part = AttributedString(String(source[r]))
                part.font = .system(size: size * 0.72)
                part.baselineOffset = size * 0.4
                result += part
            } else if let r = Range(match.range(at: 4), in: source) {
                var part = AttributedString(String(source[r]))
                part.font = .system(size: size * 0.72)
                part.baselineOffset = size * 0.4
                result += part
            } else if let tagRange = Range(match.range(at: 5), in: source),
                      let innerRange = Range(match.range(at: 7), in: source) {
                let attributes = Range(match.range(at: 6), in: source).map { String(source[$0]) } ?? ""
                result += html(tag: source[tagRange].lowercased(), attributes: attributes,
                               inner: render(String(source[innerRange]), size: size), size: size)
            } else if match.range(at: 8).location != NSNotFound {
                result += AttributedString("\n")
            } else if let r = Range(match.range(at: 9), in: source) {
                // [[Other Note]], [[Other Note#Heading]], [[Other Note|label]]
                if let wiki = NoteLink.resolveWiki(String(source[r])) {
                    var part = AttributedString(wiki.label)
                    if let url = wiki.link.url { part.link = url }
                    result += part
                } else {
                    result += AttributedString(ns.substring(with: match.range))
                }
            } else if let textRange = Range(match.range(at: 10), in: source),
                      let destinationRange = Range(match.range(at: 11), in: source) {
                // [text](destination): handled here so destinations may contain spaces
                // and can point at headings or other notes.
                let destination = String(source[destinationRange])
                    .replacingOccurrences(of: #"\s+"[^"]*"\s*$"#, with: "", options: .regularExpression)
                var part = render(String(source[textRange]), size: size)
                if let url = NoteLink.resolve(destination)?.url { part.link = url }
                result += part
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += foundation(ns.substring(from: cursor))
        }
        return result
    }

    // MARK: Inline HTML

    private static func html(tag: String, attributes: String, inner: AttributedString, size: CGFloat) -> AttributedString {
        var part = inner
        switch tag {
        case "u", "ins":
            part.underlineStyle = Text.LineStyle.single
        case "s", "del", "strike":
            part.strikethroughStyle = Text.LineStyle.single
        case "mark":
            part.backgroundColor = Color.yellow.opacity(0.45)
        case "sub":
            part.font = .system(size: size * 0.72)
            part.baselineOffset = -size * 0.2
        case "sup":
            part.font = .system(size: size * 0.72)
            part.baselineOffset = size * 0.4
        case "small":
            part.font = .system(size: size * 0.82)
        case "b", "strong":
            addIntent(.stronglyEmphasized, to: &part)
        case "i", "em":
            addIntent(.emphasized, to: &part)
        case "kbd":
            part.font = .system(size: size * 0.88, design: .monospaced)
            part.backgroundColor = Color.primary.opacity(0.12)
        case "span", "font":
            if let color = color(fromAttributes: attributes) { part.foregroundColor = color }
        default:
            break
        }
        return part
    }

    /// Adds bold/italic on top of whatever the inner text already has (code, links…).
    private static func addIntent(_ intent: InlinePresentationIntent, to part: inout AttributedString) {
        for run in part.runs {
            var combined = run.inlinePresentationIntent ?? []
            combined.insert(intent)
            part[run.range].inlinePresentationIntent = combined
        }
    }

    /// Reads `style="color: red"` or `color="#ff0000"`.
    private static func color(fromAttributes attributes: String) -> Color? {
        let patterns = [#"(?i)color\s*:\s*([#\w]+)"#, #"(?i)color\s*=\s*["']?([#\w]+)"#]
        for pattern in patterns {
            if let match = MarkdownParser.firstMatch(pattern, in: attributes), match.count > 1 {
                return namedColor(match[1])
            }
        }
        return nil
    }

    private static func namedColor(_ value: String) -> Color? {
        let name = value.lowercased()
        if name.hasPrefix("#") {
            var hex = String(name.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            return Color(hex: "#" + hex)
        }
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow", "gold": return .yellow
        case "green", "lime": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan", "aqua": return .cyan
        case "blue", "navy": return .blue
        case "indigo": return .indigo
        case "purple", "violet", "magenta", "fuchsia": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey", "silver": return .gray
        case "black": return .black
        case "white": return .white
        default: return nil
        }
    }

    private static func foundation(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    // MARK: Emoji shortcodes

    static func replaceEmoji(in text: String) -> String {
        guard text.contains(":") else { return text }
        guard let regex = MarkdownParser.cachedRegex(#":([a-z0-9_+\-]+):"#) else { return text }
        let ns = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            guard let emoji = emojiMap[name] else { continue }
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += emoji
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }

    static let emojiMap: [String: String] = [
        "joy": "😂", "smile": "😄", "smiley": "😃", "grin": "😁", "laughing": "😆", "wink": "😉", "blush": "😊",
        "heart_eyes": "😍", "kissing_heart": "😘", "thinking": "🤔", "neutral_face": "😐", "sunglasses": "😎",
        "sob": "😭", "cry": "😢", "angry": "😠", "rage": "😡", "scream": "😱", "sweat_smile": "😅", "upside_down_face": "🙃",
        "rofl": "🤣", "sleeping": "😴", "nerd_face": "🤓", "partying_face": "🥳", "exploding_head": "🤯",
        "heart": "❤️", "broken_heart": "💔", "sparkling_heart": "💖", "+1": "👍", "thumbsup": "👍", "-1": "👎",
        "thumbsdown": "👎", "clap": "👏", "pray": "🙏", "wave": "👋", "ok_hand": "👌", "muscle": "💪", "raised_hands": "🙌",
        "point_right": "👉", "point_left": "👈", "eyes": "👀", "brain": "🧠", "fire": "🔥", "sparkles": "✨", "star": "⭐",
        "tada": "🎉", "rocket": "🚀", "zap": "⚡", "100": "💯", "boom": "💥", "bulb": "💡", "memo": "📝", "pencil": "✏️",
        "book": "📖", "books": "📚", "calendar": "📅", "date": "📅", "pushpin": "📌", "paperclip": "📎", "link": "🔗",
        "lock": "🔒", "key": "🔑", "bell": "🔔", "gift": "🎁", "trophy": "🏆", "dart": "🎯", "computer": "💻",
        "iphone": "📱", "email": "📧", "envelope": "✉️", "phone": "☎️", "hourglass": "⌛", "alarm_clock": "⏰",
        "white_check_mark": "✅", "heavy_check_mark": "✔️", "x": "❌", "warning": "⚠️", "question": "❓",
        "exclamation": "❗", "no_entry": "⛔", "sunny": "☀️", "cloud": "☁️", "umbrella": "☔", "snowflake": "❄️",
        "rainbow": "🌈", "coffee": "☕", "tea": "🍵", "pizza": "🍕", "apple": "🍎", "cake": "🍰", "beer": "🍺",
        "dog": "🐶", "cat": "🐱", "tree": "🌳", "seedling": "🌱", "earth_americas": "🌎", "moneybag": "💰",
        "chart_with_upwards_trend": "📈", "musical_note": "🎵", "headphones": "🎧", "camera": "📷", "art": "🎨",
        "house": "🏠", "car": "🚗", "airplane": "✈️", "skull": "💀", "ghost": "👻", "robot": "🤖", "poop": "💩",
    ]
}
