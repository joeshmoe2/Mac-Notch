import SwiftUI

private struct MatchedAlbumArt: ViewModifier {
    @Environment(\.notchNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "albumArt", in: namespace)
        } else {
            content
        }
    }
}

extension View {
    /// Morphs album art between the collapsed live activity and the expanded player.
    func matchedAlbumArt() -> some View { modifier(MatchedAlbumArt()) }
}

struct AlbumArtView: View {
    let image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Animated equalizer bars. Updates 4× per second (cheap) rather than every frame.
struct AudioBarsView: View {
    var isPlaying: Bool
    var color: Color = .accentColor

    var body: some View {
        TimelineView(.periodic(from: .now, by: isPlaying ? 0.3 : 3600)) { context in
            let seed = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: geo.size.width * 0.12) {
                    ForEach(0..<4, id: \.self) { i in
                        let h = isPlaying ? 0.3 + 0.7 * abs(sin(seed * 2.3 + Double(i) * 1.7)) : 0.2
                        Capsule()
                            .fill(color)
                            .frame(height: geo.size.height * h)
                            .animation(.easeInOut(duration: 0.3), value: h)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct AudioExpandedView: View {
    let module: AudioModule
    @State private var scrubbing: Double?

    private var media: MediaService { module.media }

    var body: some View {
        HStack(spacing: 16) {
            if let playing = media.nowPlaying {
                AlbumArtView(image: media.artwork, size: 120, cornerRadius: 14)
                    .matchedAlbumArt()
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    .onTapGesture { media.openPlayer() }
                VStack(alignment: .leading, spacing: 6) {
                    Text(playing.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(playing.artist).foregroundStyle(.secondary).lineLimit(1)
                    progress(playing)
                    controls(playing)
                    VolumeRow(devices: module.devices)
                }
            } else {
                emptyState
            }
        }
    }

    private func progress(_ playing: NowPlaying) -> some View {
        TimelineView(.periodic(from: .now, by: playing.isPlaying ? 1 : 3600)) { context in
            let elapsed = scrubbing ?? playing.elapsed(at: context.date)
            VStack(spacing: 2) {
                Slider(value: Binding(
                    get: { elapsed },
                    set: { scrubbing = $0 }
                ), in: 0...max(playing.duration, 1), onEditingChanged: { editing in
                    if !editing, let value = scrubbing {
                        media.seek(to: value)
                        scrubbing = nil
                    }
                })
                .controlSize(.mini)
                HStack {
                    Text(TimeFormat.clock(elapsed))
                    Spacer()
                    Text("-" + TimeFormat.clock(max(0, playing.duration - elapsed)))
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private func controls(_ playing: NowPlaying) -> some View {
        HStack(spacing: 18) {
            Spacer()
            ControlButton(icon: "backward.fill", size: 16) { media.previous() }
            ControlButton(icon: playing.isPlaying ? "pause.fill" : "play.fill", size: 22) { media.playPause() }
            ControlButton(icon: "forward.fill", size: 16) { media.next() }
            Spacer()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.secondary)
            if !media.deniedPlayers.isEmpty {
                Text("NotchHub isn't allowed to control \(media.deniedPlayers.map(\.displayName).sorted().joined(separator: " / ")).")
                    .foregroundStyle(.orange)
                HStack {
                    Button("Open Automation Settings") { media.openAutomationSettings() }.buttonStyle(PillButtonStyle())
                    Button("Check Again") { media.recheckPermissions() }.buttonStyle(PillButtonStyle())
                }
            } else {
                Text("Nothing playing in Music or Spotify").foregroundStyle(.secondary)
            }
            VolumeRow(devices: module.devices).frame(width: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ControlButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .frame(width: size * 1.9, height: size * 1.9)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Volume slider + output device menu.
struct VolumeRow: View {
    let devices: AudioDeviceService

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: devices.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.1.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(devices.volume) }, set: { devices.setVolume(Float($0)) }), in: 0...1)
                .controlSize(.mini)
                .disabled(!devices.canSetVolume)
            Menu {
                ForEach(devices.devices) { device in
                    Button {
                        devices.setDefaultOutput(device.id)
                    } label: {
                        if device.id == devices.defaultOutputID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "hifispeaker.2.fill").font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(devices.devices.first { $0.id == devices.defaultOutputID }?.name ?? "Output device")
        }
    }
}

struct AudioCompactView: View {
    let module: AudioModule
    private var media: MediaService { module.media }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModuleTileHeader(icon: "music.note", title: media.nowPlaying?.player.displayName ?? "Now Playing")
            if let playing = media.nowPlaying {
                HStack(spacing: 8) {
                    AlbumArtView(image: media.artwork, size: 36, cornerRadius: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(playing.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(playing.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(spacing: 4) {
                    IconButton(icon: "backward.fill", size: 9) { media.previous() }
                    IconButton(icon: playing.isPlaying ? "pause.fill" : "play.fill", size: 9) { media.playPause() }
                    IconButton(icon: "forward.fill", size: 9) { media.next() }
                }
            } else {
                Text("Nothing playing").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct AudioSettingsView: View {
    let module: AudioModule
    @AppStorage(Prefs.audioPreferredPlayer) private var preferred
    @AppStorage(Prefs.audioUseMediaRemote) private var useMediaRemote

    var body: some View {
        Picker("Player", selection: $preferred) {
            Text("Automatic (whichever is playing)").tag("auto")
            Text("Apple Music").tag("music")
            Text("Spotify").tag("spotify")
        }
        .onChange(of: preferred) { module.media.refresh() }
        Toggle("Use MediaRemote fallback for other players (experimental)", isOn: $useMediaRemote)
            .onChange(of: useMediaRemote) {
                module.setActive(false)
                module.setActive(true)
            }
        Text("MediaRemote is a private framework. On macOS 15.4 and later it is restricted to Apple apps and usually returns nothing; NotchHub falls back to AppleScript for Music and Spotify.")
            .font(.caption)
            .foregroundStyle(.secondary)
        HStack {
            if module.media.deniedPlayers.isEmpty {
                Label("Automation permission is requested the first time a player is detected.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("Automation denied for \(module.media.deniedPlayers.map(\.displayName).sorted().joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open System Settings") { module.media.openAutomationSettings() }
                Button("Check Again") { module.media.recheckPermissions() }
            }
        }
    }
}
