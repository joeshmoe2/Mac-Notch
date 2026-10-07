import AppKit

/// Runs and lists Apple Shortcuts through the `shortcuts` command-line tool.
enum ShortcutsService {
    private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    struct RunError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Names of the user's shortcuts.
    static func list() async -> [String] {
        let result = await execute(["list"])
        guard result.status == 0 else { return [] }
        return result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Runs a shortcut and waits for it to finish.
    static func run(_ name: String) async -> Result<Void, RunError> {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .failure(RunError(message: "No shortcut chosen.")) }
        let result = await execute(["run", trimmed])
        if result.status == 0 { return .success(()) }
        let detail = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(RunError(message: detail.isEmpty ? "“\(trimmed)” failed (code \(result.status))." : detail))
    }

    static func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    private static func execute(_ arguments: [String]) async -> (status: Int32, output: String, error: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = tool
            process.arguments = arguments
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.terminationHandler = { proc in
                let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: (proc.terminationStatus, output, error))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, "", error.localizedDescription))
            }
        }
    }
}
