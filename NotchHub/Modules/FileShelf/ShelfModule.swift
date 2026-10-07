import AppKit
import QuickLookThumbnailing
import SwiftUI

extension Prefs {
    static let shelfCopyFiles = PrefKey("shelf.copyFiles", false)
    /// 0 = never.
    static let shelfAutoClearHours = PrefKey("shelf.autoClearHours", 24)
    static let shelfMaxItems = PrefKey("shelf.maxItems", 20)
    /// Put new screenshots on the shelf automatically.
    static let shelfAutoAddScreenshots = PrefKey("shelf.autoAddScreenshots", true)
}

/// Temporary holding area for files dragged onto the notch.
@Observable
@MainActor
final class ShelfModule: NotchModule {
    let id = ShelfModuleID
    let name = "Shelf"
    let icon = "tray.full.fill"

    private static let fileName = "shelf.json"

    private(set) var items: [ShelfItem] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]
    /// URLs we've started security-scoped access for (sandboxed builds only).
    @ObservationIgnored private var accessing: [UUID: URL] = [:]

    private var copiesDirectory: URL {
        let dir = JSONStore.directory.appendingPathComponent("Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        items = JSONStore.load([ShelfItem].self, from: Self.fileName) ?? []
        autoClear()
        items.forEach(generateThumbnail)
    }

    // MARK: Adding / removing

    func add(_ urls: [URL]) {
        let copy = Prefs.shelfCopyFiles.value
        for source in urls {
            // Skip duplicates of files already on the shelf.
            if items.contains(where: { $0.path == source.path && !$0.isCopy }) { continue }
            var url = source
            if copy, let copied = copyToShelf(source) { url = copied }
            guard let bookmark = try? url.bookmarkData(options: Sandbox.bookmarkCreationOptions,
                                                      includingResourceValuesForKeys: nil, relativeTo: nil) else { continue }
            let item = ShelfItem(url: url, bookmark: bookmark, isCopy: copy && url != source)
            items.insert(item, at: 0)
            generateThumbnail(for: item)
        }
        trimToMax()
        save()
    }

    func remove(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.isCopy, let url = resolve(item) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        accessing[id]?.stopAccessingSecurityScopedResource()
        accessing[id] = nil
        thumbnails[id] = nil
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        for item in items { remove(item.id) }
    }

    private func copyToShelf(_ url: URL) -> URL? {
        let folder = copiesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func trimToMax() {
        let maxItems = max(1, Prefs.shelfMaxItems.value)
        while items.count > maxItems, let last = items.last { remove(last.id) }
    }

    /// Removes items older than the configured number of hours.
    func autoClear() {
        let hours = Prefs.shelfAutoClearHours.value
        guard hours > 0 else { return }
        let cutoff = Date.now.addingTimeInterval(-Double(hours) * 3600)
        for item in items where item.addedAt < cutoff { remove(item.id) }
    }

    private func save() {
        JSONStore.save(items, to: Self.fileName)
    }

    // MARK: Resolving

    /// Resolves the bookmark (refreshing it if stale) and starts security-scoped access if needed.
    func resolve(_ item: ShelfItem) -> URL? {
        if let url = accessing[item.id] { return url }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: item.bookmark, options: Sandbox.bookmarkResolutionOptions,
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            if Sandbox.isActive, url.startAccessingSecurityScopedResource() { accessing[item.id] = url }
            if stale, let fresh = try? url.bookmarkData(options: Sandbox.bookmarkCreationOptions,
                                                       includingResourceValuesForKeys: nil, relativeTo: nil),
               let i = items.firstIndex(where: { $0.id == item.id }) {
                items[i].bookmark = fresh
                items[i].path = url.path
                save()
            }
            return url
        }
        let fallback = URL(fileURLWithPath: item.path)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    // MARK: Actions

    func open(_ item: ShelfItem) {
        guard let url = resolve(item) else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ item: ShelfItem) {
        guard let url = resolve(item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func airDrop(_ item: ShelfItem) {
        guard let url = resolve(item) else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url])
    }

    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        guard let url = resolve(item) else { return NSItemProvider() }
        return NSItemProvider(object: url as NSURL)
    }

    // MARK: Thumbnails

    private func generateThumbnail(for item: ShelfItem) {
        guard let url = resolve(item) else { return }
        thumbnails[item.id] = NSWorkspace.shared.icon(forFile: url.path)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 96, height: 96),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
        )
        let id = item.id
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    AppState.shared.module(ShelfModule.self)?.setThumbnail(image, for: id)
                }
            }
        }
    }

    fileprivate func setThumbnail(_ image: NSImage, for id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        thumbnails[id] = image
    }

    // MARK: NotchModule

    func willExpand() {
        autoClear()
        // Picks up a changed screenshot location (Screenshot app › Options › Save to).
        updateScreenshotWatching()
    }

    // MARK: Screenshots

    @ObservationIgnored private var active = false
    @ObservationIgnored private lazy var screenshotWatcher = ScreenshotWatcher { urls in
        AppState.shared.module(ShelfModule.self)?.add(urls)
    }

    func setActive(_ active: Bool) {
        self.active = active
        updateScreenshotWatching()
    }

    /// Starts/stops watching the screenshot folder to match the setting.
    func updateScreenshotWatching() {
        if active && Prefs.shelfAutoAddScreenshots.value {
            screenshotWatcher.start()
        } else {
            screenshotWatcher.stop()
        }
    }

    var screenshotFolderPath: String {
        ScreenshotWatcher.screenshotFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    func compactView() -> AnyView { AnyView(ShelfCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(ShelfExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(ShelfSettingsView(module: self)) }
}
