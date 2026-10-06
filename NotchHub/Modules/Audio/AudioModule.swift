import SwiftUI

/// Now playing (Music / Spotify), transport controls, volume and output device.
@Observable
@MainActor
final class AudioModule: NotchModule {
    let id = "audio"
    let name = "Now Playing"
    let icon = "music.note"

    var media: MediaService { .shared }
    var devices: AudioDeviceService { .shared }

    func setActive(_ active: Bool) {
        if active {
            MediaService.shared.start()
            AudioDeviceService.shared.start()
        } else {
            MediaService.shared.stop()
            AudioDeviceService.shared.stop()
        }
    }

    func willExpand() {
        media.refresh()
    }

    // MARK: NotchModule

    var supportsLiveActivity: Bool { true }

    var liveActivity: LiveActivity? {
        guard let playing = media.nowPlaying, playing.isPlaying else { return nil }
        let artwork = media.artwork
        return LiveActivity(moduleID: id) {
            AlbumArtView(image: artwork, size: 22, cornerRadius: 5)
                .matchedAlbumArt()
        } trailing: {
            AudioBarsView(isPlaying: true)
                .frame(width: 18, height: 14)
        }
    }

    func compactView() -> AnyView { AnyView(AudioCompactView(module: self)) }
    func expandedView() -> AnyView { AnyView(AudioExpandedView(module: self)) }
    func settingsView() -> AnyView { AnyView(AudioSettingsView(module: self)) }
}
