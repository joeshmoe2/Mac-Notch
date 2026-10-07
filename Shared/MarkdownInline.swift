import SwiftUI

/// Inline Markdown → AttributedString.
///
/// Foundation's parser handles **bold**, *italic*, `code`, ~~strike~~ and
/// [links](url). On top of that we add ==highlight==, H~2~O subscript,
/// X^2^ superscript, footnote references [^1] and :emoji: shortcodes.
enum MarkdownInline {
    static func render(_ text: String, size: CGFloat) -> AttributedString {
        let source = replaceEmoji(in: text)
        var result = AttributedString()
        // Split into plain runs and our extension tokens.
        let pattern = #"==(.+?)==|(?<!~)~(?!~)([^~\s]+)~(?!~)|\^([^\^\s]+)\^|\[\^([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return foundation(source)
        }
        let ns = source as NSString
        var cursor = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
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
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += foundation(ns.substring(from: cursor))
        }
        return result
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
        guard let regex = try? NSRegularExpression(pattern: #":([a-z0-9_+\-]+):"#) else { return text }
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
