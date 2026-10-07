import AppKit
import SwiftUI

/// "Notes folder" rows used in both apps' settings.
struct NotesFolderSettings: View {
    let store: NotesStore

    var body: some View {
        LabeledContent("Notes folder") {
            VStack(alignment: .trailing, spacing: 4) {
                Text(store.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Button("Show in Finder") { store.revealInFinder() }
                    Button("Change…") { chooseFolder() }
                }
            }
        }
        LabeledContent("Markdown help") {
            Button("Restore Cheat Sheet Note") { _ = MarkdownCheatSheet.restore(in: store) }
        }
        if let error = store.lastError {
            Text(error).font(.caption).foregroundStyle(.orange)
        }
        Text("Each note is a Markdown (.md) file. Put the folder in iCloud Drive to sync it, or open the files in any editor. NotchHub and NotchNotes always use the same folder.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.folder
        panel.prompt = "Use Folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.changeFolder(to: url)
    }
}
