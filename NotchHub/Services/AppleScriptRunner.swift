import AppKit
import CoreServices

/// Runs AppleScript against Music / Spotify.
///
/// Automation permission (TCC) is checked first with
/// `AEDeterminePermissionToAutomateTarget` on a background queue, because the
/// first check shows a blocking consent dialog. Scripts themselves are short
/// and run on the main thread (NSAppleScript is not documented as thread-safe).
@MainActor
enum AppleScriptRunner {
    enum Permission { case unknown, granted, denied, notRunning }

    private static var compiled: [String: NSAppleScript] = [:]

    /// Checks (and, if `ask`, prompts for) permission to send Apple Events to `bundleID`.
    static func permission(for bundleID: String, ask: Bool) async -> Permission {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
                let result: Permission
                switch status {
                case noErr: result = .granted
                case OSStatus(errAEEventNotPermitted): result = .denied
                case OSStatus(procNotFound): result = .notRunning
                default: result = .unknown // e.g. -1744 "would require user consent"
                }
                continuation.resume(returning: result)
            }
        }
    }

    struct ScriptError: Error {
        let number: Int
        var isPermissionDenied: Bool { number == -1743 }
    }

    /// Executes `source` and returns the result descriptor.
    @discardableResult
    static func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else { return .failure(ScriptError(number: -1)) }
            compiled[source] = created
            script = created
        }
        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? -1
            return .failure(ScriptError(number: number))
        }
        return .success(descriptor)
    }
}

extension NSAppleEventDescriptor {
    /// 1-based list access returning a string.
    func string(at index: Int) -> String {
        guard numberOfItems >= index else { return "" }
        return atIndex(index)?.stringValue ?? ""
    }

    func double(at index: Int) -> Double {
        guard numberOfItems >= index, let item = atIndex(index) else { return 0 }
        if let s = item.stringValue, let d = Double(s.replacingOccurrences(of: ",", with: ".")) { return d }
        return item.doubleValue
    }
}
