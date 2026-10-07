import AppKit

/// Notices when the general pasteboard changes.
///
/// macOS has no notification or KVO for pasteboard changes, so the only way to
/// see new copies is to compare `NSPasteboard.changeCount`. Reading that
/// integer is extremely cheap (no pasteboard data is touched), so a 0.5 s
/// timer with generous tolerance costs effectively nothing. The timer only
/// runs while the Clipboard History module is enabled.
@MainActor
final class PasteboardWatcher {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let onChange: (NSPasteboard) -> Void

    init(onChange: @escaping (NSPasteboard) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { self.check() }
        }
        timer.tolerance = 0.25 // let macOS coalesce wake-ups
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call after writing to the pasteboard ourselves so our own copy isn't recorded.
    func ignoreCurrentContents() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        onChange(pasteboard)
    }
}
