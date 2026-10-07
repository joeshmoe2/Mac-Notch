import AppKit
import Darwin

/// Watches the screenshot folder and reports new screenshots.
///
/// The folder comes from the `com.apple.screencapture` preferences (set in the
/// Screenshot app's Options › Save to), falling back to the Desktop. It's
/// watched with a DispatchSource on the folder, so nothing runs until a file
/// actually appears.
@MainActor
final class ScreenshotWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var scanTask: Task<Void, Never>?
    private(set) var folder: URL?
    private var known: Set<String> = []
    private var startedAt = Date.now
    private let onNew: ([URL]) -> Void

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "pdf"]

    init(onNew: @escaping ([URL]) -> Void) {
        self.onNew = onNew
    }

    /// Where macOS saves screenshots.
    static var screenshotFolder: URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        guard let raw = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
              !raw.isEmpty else { return desktop }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return desktop
        }
        return url
    }

    /// Prefix macOS uses for screenshot file names ("Screenshot" by default).
    private static var namePrefix: String {
        UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "name") ?? "Screenshot"
    }

    var isRunning: Bool { source != nil }

    func start() {
        let target = Self.screenshotFolder
        if isRunning, folder == target { return }
        stop()
        folder = target
        startedAt = .now
        known = Set((try? FileManager.default.contentsOfDirectory(atPath: target.path)) ?? [])
        let fd = open(target.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        scanTask?.cancel()
    }

    /// Screenshots are written to a hidden temp file and renamed; wait a moment so
    /// the final file (and its metadata) is in place.
    private func scheduleScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    private func scan() {
        guard let folder else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var found: [URL] = []
        for name in names where !known.contains(name) && !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            guard Self.imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
            // Only files created since we started watching.
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            guard created >= startedAt.addingTimeInterval(-2) else { continue }
            guard isScreenshot(url) else { continue }
            known.insert(name)
            found.append(url)
        }
        // Forget deleted files so the set doesn't grow forever.
        known.formIntersection(names)
        if !found.isEmpty { onNew(found) }
    }

    /// macOS tags screenshots with kMDItemIsScreenCapture; fall back to the file-name prefix.
    private func isScreenshot(_ url: URL) -> Bool {
        let size = url.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path else { return -1 }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0)
        }
        if size > 0 { return true }
        return url.lastPathComponent.hasPrefix(Self.namePrefix)
    }
}
