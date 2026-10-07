import AppKit

extension Prefs {
    static let focusBlockWebsites = PrefKey("pomodoro.blockWebsites", false)
    /// Comma separated domains, e.g. "youtube.com,reddit.com".
    static let focusBlockedSites = PrefKey("pomodoro.blockedSites", "")
}

/// Blocks websites during focus sessions by adding entries to /etc/hosts.
///
/// Editing /etc/hosts needs root. Instead of asking for a password at the start
/// and end of every session, a one-time install (password required once) puts
/// a small root-owned script at `/usr/local/libexec/notchhub-hosts` plus a
/// sudoers rule that lets the current user run *only that script* without a
/// password. The script can only add/remove its own marked block of
/// `0.0.0.0 <domain>` lines and validates every domain, so it can't be used to
/// redirect sites anywhere else.
@Observable
@MainActor
final class WebsiteBlocker {
    static let shared = WebsiteBlocker()

    static let helperPath = "/usr/local/libexec/notchhub-hosts"
    static let sudoersPath = "/etc/sudoers.d/notchhub"

    private(set) var isInstalled = false
    /// True while our block is (believed to be) present in /etc/hosts.
    private(set) var isBlocking = false
    private(set) var lastError: String?

    private init() {
        refreshInstalled()
    }

    func refreshInstalled() {
        isInstalled = FileManager.default.isExecutableFile(atPath: Self.helperPath)
            && FileManager.default.fileExists(atPath: Self.sudoersPath)
    }

    // MARK: Domains

    var domains: [String] { Prefs.focusBlockedSites.value.idList }

    /// Turns "https://www.YouTube.com/watch?v=1" into "youtube.com".
    static func normalize(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = s.range(of: "://") { s = String(s[range.upperBound...]) }
        s = String(s.split(separator: "/").first ?? "")
        s = String(s.split(separator: ":").first ?? "")
        if s.hasPrefix("www.") { s.removeFirst(4) }
        let valid = s.range(of: #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$"#,
                            options: .regularExpression) != nil
        return valid ? s : nil
    }

    func addSite(_ input: String) -> Bool {
        guard let domain = Self.normalize(input) else { return false }
        var list = domains
        if !list.contains(domain) { list.append(domain) }
        Prefs.focusBlockedSites.set(list.joinedIDs)
        if isBlocking { apply(blocking: true) }
        return true
    }

    func removeSite(_ domain: String) {
        Prefs.focusBlockedSites.set(domains.filter { $0 != domain }.joinedIDs)
        if isBlocking { apply(blocking: true) }
    }

    /// Each domain plus common subdomains people actually hit.
    private var expandedDomains: [String] {
        domains.flatMap { ["\($0)", "www.\($0)", "m.\($0)"] }
    }

    // MARK: Applying

    func apply(blocking: Bool, wait: Bool = false) {
        guard isInstalled else {
            if blocking { lastError = "Install the website blocker in Settings → Pomodoro first." }
            return
        }
        let arguments: [String]
        if blocking && !domains.isEmpty {
            arguments = ["-n", Self.helperPath, "on"] + expandedDomains
        } else {
            arguments = ["-n", Self.helperPath, "off"]
        }
        let turningOn = arguments[2] == "on"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { proc in
            let ok = proc.terminationStatus == 0
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let blocker = WebsiteBlocker.shared
                    blocker.lastError = ok ? nil : "Website blocker failed (code \(proc.terminationStatus)). Try reinstalling it."
                    if ok { blocker.isBlocking = turningOn }
                }
            }
        }
        do {
            try process.run()
            if wait { process.waitUntilExit() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Removes any leftover block (e.g. after a crash) at launch.
    func cleanUpOnLaunch() {
        // A focus session restored at launch re-applies its own block.
        if isInstalled && !FocusGuard.shared.isActive { apply(blocking: false) }
    }

    // MARK: Install / uninstall (asks for an administrator password once)

    func install() {
        let user = NSUserName()
        guard user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            lastError = "Unsupported user name."
            return
        }
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-hosts-\(UUID().uuidString)")
        let sudoersURL = FileManager.default.temporaryDirectory.appendingPathComponent("notchhub-sudoers-\(UUID().uuidString)")
        do {
            try Self.helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try "\(user) ALL=(root) NOPASSWD: \(Self.helperPath)\n".write(to: sudoersURL, atomically: true, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
            return
        }
        defer {
            try? FileManager.default.removeItem(at: scriptURL)
            try? FileManager.default.removeItem(at: sudoersURL)
        }
        let shell = [
            "/usr/sbin/visudo -cf '\(sudoersURL.path)'",
            "/bin/mkdir -p /usr/local/libexec",
            "/usr/bin/install -m 755 -o root -g wheel '\(scriptURL.path)' '\(Self.helperPath)'",
            "/usr/bin/install -m 440 -o root -g wheel '\(sudoersURL.path)' '\(Self.sudoersPath)'",
        ].joined(separator: " && ")
        runPrivileged(shell)
        refreshInstalled()
    }

    func uninstall() {
        if isInstalled { apply(blocking: false, wait: true) }
        runPrivileged("/bin/rm -f '\(Self.helperPath)' '\(Self.sudoersPath)'")
        refreshInstalled()
        isBlocking = false
    }

    private func runPrivileged(_ shell: String) {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        NSApp.activate(ignoringOtherApps: true)
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -128 = user cancelled the password prompt.
            lastError = number == -128 ? nil : (error[NSAppleScript.errorMessage] as? String ?? "Installation failed.")
        } else {
            lastError = nil
        }
    }

    // MARK: Helper script (installed as root)

    static let helperScript = #"""
    #!/bin/bash
    # NotchHub website blocker helper.
    # Only adds/removes NotchHub's own marked block in /etc/hosts.
    # Usage: notchhub-hosts on <domain>...  |  notchhub-hosts off
    set -euo pipefail
    HOSTS=/etc/hosts
    BEGIN="# BEGIN NotchHub focus block"
    END="# END NotchHub focus block"
    TMP=$(mktemp)
    trap 'rm -f "$TMP"' EXIT
    # Copy hosts without any previous NotchHub block.
    awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$HOSTS" > "$TMP"
    case "${1:-}" in
      on)
        shift
        echo "$BEGIN" >> "$TMP"
        COUNT=0
        for d in "$@"; do
          [ "$COUNT" -ge 1500 ] && break
          if [[ "$d" =~ ^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$ ]]; then
            echo "0.0.0.0 $d" >> "$TMP"
            echo ":: $d" >> "$TMP"
            COUNT=$((COUNT + 1))
          fi
        done
        echo "$END" >> "$TMP"
        ;;
      off) ;;
      *) echo "usage: notchhub-hosts on <domain>... | off" >&2; exit 64 ;;
    esac
    # Write in place to keep the file's owner and permissions.
    cat "$TMP" > "$HOSTS"
    /usr/bin/dscacheutil -flushcache || true
    /usr/bin/killall -HUP mDNSResponder 2>/dev/null || true
    """#
}
