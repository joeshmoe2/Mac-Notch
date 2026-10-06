import AppKit

extension Prefs {
    /// "auto", "music" or "spotify".
    static let audioPreferredPlayer = PrefKey("audio.preferredPlayer", "auto")
    static let audioUseMediaRemote = PrefKey("audio.useMediaRemote", false)
}

enum MediaPlayer: String, CaseIterable {
    case music, spotify, system

    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        case .system: ""
        }
    }

    var displayName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        case .system: "Now Playing"
        }
    }

    var isRunning: Bool {
        guard !bundleID.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Distributed notification the player posts on every state change.
    var changeNotification: String? {
        switch self {
        case .music: "com.apple.Music.playerInfo"
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        case .system: nil
        }
    }
}

struct NowPlaying: Equatable {
    var player: MediaPlayer
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    /// When `position` was sampled; the UI interpolates from here while playing.
    var positionDate: Date
    var isPlaying: Bool
    var artworkURL: String?

    func elapsed(at now: Date = .now) -> Double {
        guard isPlaying else { return position }
        return min(duration, position + now.timeIntervalSince(positionDate))
    }
}

/// Now-playing info + transport controls for Music and Spotify.
///
/// Event-driven: listens to the players' distributed notifications and app
/// launch/quit, so nothing is polled while idle.
@Observable
@MainActor
final class MediaService {
    static let shared = MediaService()

    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: NSImage?
    /// Players whose Automation permission was denied.
    private(set) var deniedPlayers: Set<MediaPlayer> = []

    @ObservationIgnored private var permissions: [MediaPlayer: AppleScriptRunner.Permission] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var isStarted = false

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let distributed = DistributedNotificationCenter.default()
        for player in MediaPlayer.allCases {
            guard let name = player.changeNotification else { continue }
            observers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { MediaService.shared.refresh() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let id = app?.bundleIdentifier
                MainActor.assumeIsolated {
                    if MediaPlayer.allCases.contains(where: { $0.bundleID == id }) {
                        // Give a quitting app a moment to disappear from the running list.
                        Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            MediaService.shared.refresh()
                        }
                    }
                }
            })
        }
        if Prefs.audioUseMediaRemote.value {
            MediaRemoteBridge.shared.startObserving { MediaService.shared.refresh() }
        }
        refresh()
    }

    func stop() {
        observers.forEach {
            DistributedNotificationCenter.default().removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        MediaRemoteBridge.shared.stopObserving()
        isStarted = false
        nowPlaying = nil
        artwork = nil
    }

    // MARK: Player selection

    /// Which player to talk to, honoring the user's preference.
    private var candidatePlayers: [MediaPlayer] {
        switch Prefs.audioPreferredPlayer.value {
        case "music": [.music]
        case "spotify": [.spotify]
        default: [.spotify, .music]
        }
    }

    // MARK: Refresh

    func refresh() {
        Task { await refreshAsync() }
    }

    private func refreshAsync() async {
        var best: NowPlaying?
        for player in candidatePlayers where player.isRunning {
            guard await ensurePermission(player) else { continue }
            if let state = query(player) {
                // Prefer whichever player is actually playing.
                if best == nil || (state.isPlaying && best?.isPlaying == false) { best = state }
            }
        }
        if best == nil, Prefs.audioUseMediaRemote.value, MediaRemoteBridge.shared.isAvailable {
            best = await fetchMediaRemote()
        }
        apply(best)
    }

    private func ensurePermission(_ player: MediaPlayer) async -> Bool {
        if permissions[player] == .granted { return true }
        let result = await AppleScriptRunner.permission(for: player.bundleID, ask: true)
        permissions[player] = result
        if result == .denied { deniedPlayers.insert(player) } else { deniedPlayers.remove(player) }
        return result == .granted
    }

    /// Re-checks permission after the user changed it in System Settings.
    func recheckPermissions() {
        permissions.removeAll()
        refresh()
    }

    private func query(_ player: MediaPlayer) -> NowPlaying? {
        let source: String
        switch player {
        case .music:
            source = """
            tell application id "com.apple.Music"
                if player state is stopped then return "STOPPED"
                set t to current track
                return {name of t, artist of t, album of t, (duration of t) as text, (player position) as text, (player state as text), (persistent ID of t) as text, ""}
            end tell
            """
        case .spotify:
            source = """
            tell application id "com.spotify.client"
                if player state is stopped then return "STOPPED"
                set t to current track
                return {name of t, artist of t, album of t, ((duration of t) / 1000) as text, (player position) as text, (player state as text), (id of t) as text, (artwork url of t) as text}
            end tell
            """
        case .system:
            return nil
        }
        switch AppleScriptRunner.run(source) {
        case .success(let d):
            guard d.numberOfItems >= 7 else { return nil }
            return NowPlaying(
                player: player,
                trackID: d.string(at: 7),
                title: d.string(at: 1),
                artist: d.string(at: 2),
                album: d.string(at: 3),
                duration: d.double(at: 4),
                position: d.double(at: 5),
                positionDate: .now,
                isPlaying: d.string(at: 6).lowercased().contains("playing"),
                artworkURL: d.string(at: 8).isEmpty ? nil : d.string(at: 8)
            )
        case .failure(let error):
            if error.isPermissionDenied {
                permissions[player] = .denied
                deniedPlayers.insert(player)
            }
            return nil
        }
    }

    private func fetchMediaRemote() async -> NowPlaying? {
        await withCheckedContinuation { continuation in
            MediaRemoteBridge.shared.fetch { info in
                guard let info else { continuation.resume(returning: nil); return }
                if let data = info.artworkData { MediaService.shared.mediaRemoteArtwork = NSImage(data: data) }
                continuation.resume(returning: NowPlaying(
                    player: .system, trackID: info.title + info.artist, title: info.title, artist: info.artist,
                    album: info.album, duration: info.duration, position: info.elapsed,
                    positionDate: info.timestamp, isPlaying: info.isPlaying, artworkURL: nil
                ))
            }
        }
    }

    @ObservationIgnored private var mediaRemoteArtwork: NSImage?

    private func apply(_ state: NowPlaying?) {
        if nowPlaying != state { nowPlaying = state }
        guard let state else {
            artwork = nil
            artworkKey = nil
            return
        }
        let key = "\(state.player.rawValue)|\(state.trackID)"
        guard key != artworkKey else { return }
        artworkKey = key
        loadArtwork(for: state, key: key)
    }

    // MARK: Artwork

    private func loadArtwork(for state: NowPlaying, key: String) {
        switch state.player {
        case .music:
            let script = "tell application id \"com.apple.Music\" to get data of artwork 1 of current track"
            if case .success(let d) = AppleScriptRunner.run(script), let image = NSImage(data: d.data) {
                artwork = image
            } else {
                artwork = nil
            }
        case .spotify:
            guard let string = state.artworkURL, let url = URL(string: string) else { artwork = nil; return }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      self.artworkKey == key else { return }
                self.artwork = NSImage(data: data)
            }
        case .system:
            artwork = mediaRemoteArtwork
        }
    }

    // MARK: Controls

    private func send(_ command: String, mediaRemote: MediaRemoteBridge.Command) {
        guard let player = nowPlaying?.player else { return }
        if player == .system {
            MediaRemoteBridge.shared.send(mediaRemote)
        } else {
            AppleScriptRunner.run("tell application id \"\(player.bundleID)\" to \(command)")
        }
        // Distributed notifications will follow, but update promptly for snappy UI.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            refresh()
        }
    }

    func playPause() {
        if var state = nowPlaying {
            // Optimistic UI update.
            state.position = state.elapsed()
            state.positionDate = .now
            state.isPlaying.toggle()
            nowPlaying = state
        }
        send("playpause", mediaRemote: .togglePlayPause)
    }

    func next() { send("next track", mediaRemote: .nextTrack) }
    func previous() { send("previous track", mediaRemote: .previousTrack) }

    func seek(to seconds: Double) {
        guard var state = nowPlaying else { return }
        state.position = seconds
        state.positionDate = .now
        nowPlaying = state
        if state.player == .system {
            MediaRemoteBridge.shared.seek(to: seconds)
        } else {
            AppleScriptRunner.run("tell application id \"\(state.player.bundleID)\" to set player position to \(String(format: "%.2f", seconds))")
        }
    }

    func openPlayer() {
        guard let player = nowPlaying?.player, !player.bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
