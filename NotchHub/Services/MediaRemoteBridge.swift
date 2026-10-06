import AppKit

/// OPTIONAL fallback using Apple's private MediaRemote framework.
///
/// Tradeoffs (why this is off by default):
/// - It's private API: no compatibility guarantees, and apps using it can't ship on the Mac App Store.
/// - Starting with macOS 15.4, MediaRemote only returns now-playing data to
///   Apple-entitled processes, so on current systems it typically returns nothing.
/// - When it does work, it supports *any* player (Safari, Chrome, Podcasts, …),
///   which the AppleScript path (Music + Spotify only) can't.
///
/// Everything is resolved dynamically with dlopen/dlsym, so if the framework or
/// symbols are missing the bridge simply reports `isAvailable == false`.
@MainActor
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    struct Info {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var elapsed: Double
        var timestamp: Date
        var isPlaying: Bool
        var artworkData: Data?
    }

    enum Command: UInt32 {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private var getInfo: GetInfoFn?
    private var sendCommandFn: SendCommandFn?
    private var register: RegisterFn?
    private var setElapsed: SetElapsedFn?
    private var observer: NSObjectProtocol?

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else { return }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") { getInfo = unsafeBitCast(sym, to: GetInfoFn.self) }
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") { sendCommandFn = unsafeBitCast(sym, to: SendCommandFn.self) }
        if let sym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") { register = unsafeBitCast(sym, to: RegisterFn.self) }
        if let sym = dlsym(handle, "MRMediaRemoteSetElapsedTime") { setElapsed = unsafeBitCast(sym, to: SetElapsedFn.self) }
    }

    var isAvailable: Bool { getInfo != nil && sendCommandFn != nil }

    /// Starts listening for now-playing changes.
    func startObserving(_ onChange: @escaping @MainActor () -> Void) {
        guard isAvailable, observer == nil else { return }
        register?(DispatchQueue.main)
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    func stopObserving() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func fetch(_ completion: @escaping @MainActor (Info?) -> Void) {
        guard let getInfo else { completion(nil); return }
        getInfo(DispatchQueue.main) { dict in
            let info = (dict as? [String: Any]).flatMap(Self.parse)
            MainActor.assumeIsolated { completion(info) }
        }
    }

    func send(_ command: Command) {
        _ = sendCommandFn?(command.rawValue, nil)
    }

    func seek(to seconds: Double) {
        setElapsed?(seconds)
    }

    private nonisolated static func parse(_ d: [String: Any]) -> Info? {
        let title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        return Info(
            title: title,
            artist: d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
            album: d["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            duration: d["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0,
            elapsed: d["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0,
            timestamp: d["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? .now,
            isPlaying: (d["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0) > 0,
            artworkData: d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        )
    }
}
