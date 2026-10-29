import Foundation

/// Where a link inside a note points.
///
/// Supported forms:
/// - `[Text](#Heading Name)` / `[Text](#heading-name)`: a heading in this note
/// - `[[Other Note]]`, `[[Other Note#Heading]]`, `[[Other Note|shown text]]`: another note
/// - `[Text](Other Note.md)`, `[Text](<Other Note.md#Heading>)`: another note, Markdown style
/// - anything with a scheme (`https://…`, `mailto:…`): opened normally
///
/// Spaces are fine everywhere; headings are matched by their anchor, so
/// "#French Homework" and "#french-homework" both work.
enum NoteLink: Equatable {
    case anchor(String)
    case note(name: String, anchor: String?)
    case external(URL)

    private static let scheme = "notchnote"

    /// Interprets a link destination as written in the note.
    static func resolve(_ destination: String) -> NoteLink? {
        var text = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<"), text.hasSuffix(">") { text = String(text.dropFirst().dropLast()) }
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("#") {
            let anchor = decode(String(text.dropFirst()))
            return anchor.isEmpty ? nil : .anchor(anchor)
        }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), !scheme.isEmpty {
            if scheme == Self.scheme { return decode(url) }
            // "C:" style or a lone word with a colon isn't a real scheme; anything else is external.
            if text.contains("://") || ["mailto", "tel", "sms", "facetime", "maps"].contains(scheme) {
                return .external(url)
            }
        }
        // Another note: "Name", "Name.md", "folder/Name.md#Heading".
        var name = text
        var anchor: String?
        if let hash = name.firstIndex(of: "#") {
            anchor = decode(String(name[name.index(after: hash)...]))
            name = String(name[..<hash])
        }
        name = decode(name)
        name = (name as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        if ["md", "markdown", "txt"].contains(ext) { name = (name as NSString).deletingPathExtension }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return anchor.map { .anchor($0) } }
        return .note(name: name, anchor: anchor.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Parses the inside of `[[…]]`. Returns the target and the text to show.
    static func resolveWiki(_ inner: String) -> (link: NoteLink, label: String)? {
        var target = inner
        var label: String?
        if let bar = inner.firstIndex(of: "|") {
            target = String(inner[..<bar])
            label = String(inner[inner.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
        }
        target = target.trimmingCharacters(in: .whitespaces)
        var name = target
        var anchor: String?
        if let hash = target.firstIndex(of: "#") {
            name = String(target[..<hash]).trimmingCharacters(in: .whitespaces)
            anchor = String(target[target.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
        }
        let link: NoteLink
        if name.isEmpty {
            guard let anchor, !anchor.isEmpty else { return nil }
            link = .anchor(anchor)
        } else {
            link = .note(name: name, anchor: anchor.flatMap { $0.isEmpty ? nil : $0 })
        }
        let shown = label.flatMap { $0.isEmpty ? nil : $0 }
            ?? (anchor.map { name.isEmpty ? $0 : "\(name) › \($0)" } ?? name)
        return (link, shown)
    }

    /// A URL to store in text attributes. Internal links use the `notchnote:` scheme.
    var url: URL? {
        switch self {
        case .external(let url):
            return url
        case .anchor(let anchor):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "anchor"
            components.queryItems = [URLQueryItem(name: "id", value: anchor)]
            return components.url
        case .note(let name, let anchor):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "note"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
                + (anchor.map { [URLQueryItem(name: "anchor", value: $0)] } ?? [])
            return components.url
        }
    }

    /// Reads a link back from a clicked URL (or a raw destination string).
    static func decode(_ url: URL) -> NoteLink? {
        guard url.scheme?.lowercased() == scheme else { return resolve(url.absoluteString) }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host?.lowercased() {
        case "anchor": return value("id").map { .anchor($0) }
        case "note": return value("name").map { .note(name: $0, anchor: value("anchor")) }
        default: return nil
        }
    }

    private static func decode(_ text: String) -> String {
        (text.removingPercentEncoding ?? text).trimmingCharacters(in: .whitespaces)
    }
}

/// Asks an editor or preview to scroll to a heading. A new value (new `id`)
/// triggers the jump even when the anchor text is the same as last time.
struct AnchorRequest: Equatable {
    let anchor: String
    let id = UUID()
}
