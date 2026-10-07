import Foundation

/// A single countdown. Time is derived from `endDate` while running so no
/// per-second state mutation is needed (views use TimelineView to redraw).
struct CountdownTimer: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var duration: TimeInterval
    /// Set while running.
    var endDate: Date?
    /// Remaining time while paused (or not yet started).
    var pausedRemaining: TimeInterval
    var isFinished = false
    /// True if the timer ran out while NotchHub wasn't running (set on relaunch).
    var finishedWhileClosed: Bool? = nil

    init(label: String, duration: TimeInterval) {
        self.id = UUID()
        self.label = label
        self.duration = duration
        self.pausedRemaining = duration
    }

    var isRunning: Bool { endDate != nil }

    func remaining(at now: Date = .now) -> TimeInterval {
        if isFinished { return 0 }
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining
    }

    func progress(at now: Date = .now) -> Double {
        guard duration > 0 else { return 0 }
        return 1 - remaining(at: now) / duration
    }
}

enum TimeFormat {
    /// "m:ss" or "h:mm:ss".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Parses "25" (minutes), "1:30" (m:ss) or "1:00:00" (h:mm:ss).
    static func parse(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.compactMap { $0 }
        let seconds: Double
        switch values.count {
        case 1: seconds = values[0] * 60
        case 2: seconds = values[0] * 60 + values[1]
        case 3: seconds = values[0] * 3600 + values[1] * 60 + values[2]
        default: return nil
        }
        return seconds > 0 ? seconds : nil
    }
}
