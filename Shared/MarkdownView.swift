import AppKit
import SwiftUI

/// Renders a note's Markdown. Task-list boxes are clickable.
struct MarkdownView: View {
    let text: String
    var baseSize: CGFloat = 14
    /// Folder used to resolve relative image paths.
    var baseURL: URL?
    /// Compact mode (Home tile): tighter spacing, no scrolling.
    var compact = false
    var onToggleTask: ((Int) -> Void)?

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        let content = VStack(alignment: .leading, spacing: compact ? 4 : baseSize * 0.7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: baseSize))
        .textSelection(.enabled)

        if compact {
            content
        } else {
            ScrollView { content.padding(.bottom, 12) }
        }
    }

    private func inline(_ text: String) -> Text {
        Text(MarkdownInline.render(text, size: baseSize))
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            VStack(alignment: .leading, spacing: 3) {
                Text(MarkdownInline.render(text, size: headingSize(level)))
                    .font(.system(size: headingSize(level), weight: level <= 2 ? .bold : .semibold))
                    .padding(.top, compact ? 0 : baseSize * 0.3)
                if level <= 2 && !compact { Divider() }
            }

        case .paragraph(let text):
            inline(text)
                .fixedSize(horizontal: false, vertical: true)

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint.opacity(0.7))
                    .frame(width: 3)
                inline(text)
                    .foregroundStyle(.secondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

        case .list(let items):
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(item)
                }
            }

        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if !language.isEmpty && !compact {
                    Text(language.uppercased())
                        .font(.system(size: baseSize * 0.65, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: baseSize * 0.9, design: .monospaced))
                        .fixedSize()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))

        case .rule:
            Divider().padding(.vertical, compact ? 0 : 4)

        case .table(let header, let alignments, let rows):
            tableView(header: header, alignments: alignments, rows: rows)

        case .image(let alt, let source):
            MarkdownImage(alt: alt, source: source, baseURL: baseURL, maxHeight: compact ? 60 : 320)

        case .definition(let term, let definitions):
            VStack(alignment: .leading, spacing: 2) {
                inline(term).bold()
                ForEach(Array(definitions.enumerated()), id: \.offset) { _, definition in
                    inline(definition)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                }
            }

        case .footnotes(let notes):
            VStack(alignment: .leading, spacing: 3) {
                Divider()
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(note.label).foregroundStyle(.tint)
                        inline(note.text)
                    }
                    .font(.system(size: baseSize * 0.82))
                }
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        let scales: [CGFloat] = compact ? [1.25, 1.15, 1.1, 1.05, 1, 1] : [1.9, 1.5, 1.25, 1.1, 1.0, 0.95]
        return baseSize * scales[min(max(level, 1), 6) - 1]
    }

    @ViewBuilder
    private func listRow(_ item: MarkdownBlock.ListItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch item.marker {
            case .bullet:
                Text(item.depth % 2 == 0 ? "•" : "◦").foregroundStyle(.secondary)
            case .number(let n):
                Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
            case .task(let checked):
                Button {
                    onToggleTask?(item.line)
                } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .disabled(onToggleTask == nil)
            }
            inline(item.text)
                .strikethrough(isChecked(item))
                .foregroundStyle(isChecked(item) ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(item.depth) * baseSize * 1.3)
    }

    private func isChecked(_ item: MarkdownBlock.ListItem) -> Bool {
        if case .task(true) = item.marker { return true }
        return false
    }

    private func tableView(header: [String], alignments: [MarkdownBlock.Alignment], rows: [[String]]) -> some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        func alignment(_ column: Int) -> HorizontalAlignment {
            switch column < alignments.count ? alignments[column] : .leading {
            case .leading: .leading
            case .center: .center
            case .trailing: .trailing
            }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        inline(c < header.count ? header[c] : "")
                            .bold()
                            .gridColumnAlignment(alignment(c))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                }
                .background(Color.primary.opacity(0.08))
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { c in
                            inline(c < row.count ? row[c] : "")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                    }
                    .background(index % 2 == 1 ? Color.primary.opacity(0.04) : Color.clear)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// Image from a URL or a path relative to the notes folder.
private struct MarkdownImage: View {
    let alt: String
    let source: String
    let baseURL: URL?
    let maxHeight: CGFloat

    private var url: URL? {
        if let url = URL(string: source), url.scheme != nil { return url }
        let path = (source as NSString).expandingTildeInPath
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return baseURL?.appendingPathComponent(source)
    }

    var body: some View {
        Group {
            if let url, url.isFileURL {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    placeholder
                }
            } else if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fit)
                    case .failure: placeholder
                    default: ProgressView().frame(height: 40)
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxHeight: maxHeight, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(alt)
    }

    private var placeholder: some View {
        Label(alt.isEmpty ? source : alt, systemImage: "photo")
            .foregroundStyle(.secondary)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.4)))
    }
}
