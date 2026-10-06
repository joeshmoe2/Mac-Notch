import SwiftUI

/// Renders a note with clickable markdown-style checkboxes.
struct ChecklistView: View {
    let note: Note
    var compact = false
    let onToggle: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                ForEach(NoteLine.parse(note.body)) { line in
                    switch line.kind {
                    case .text:
                        if !line.text.isEmpty || !compact {
                            Text(line.text.isEmpty ? " " : line.text)
                        }
                    case .unchecked, .checked:
                        Button {
                            onToggle(line.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: line.kind == .checked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(line.kind == .checked ? Color.accentColor : .secondary)
                                Text(line.text)
                                    .strikethrough(line.kind == .checked)
                                    .foregroundStyle(line.kind == .checked ? .secondary : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
