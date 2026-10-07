import AVFoundation
import SwiftUI

extension Prefs {
    static let cameraMirrored = PrefKey("camera.mirrored", true)
}

/// A quick look in the mirror. The camera only runs while this tab is showing.
@Observable
@MainActor
final class CameraModule: NotchModule {
    let id = "camera"
    let name = "Mirror"
    let icon = "camera.fill"
    /// Off until the user turns it on (it uses the camera).
    var enabledByDefault: Bool { false }

    var camera: CameraService { .shared }

    func setActive(_ active: Bool) {
        if !active { camera.stop() }
    }

    func compactView() -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 6) {
            ModuleTileHeader(icon: "camera.fill", title: "Mirror")
            Text("Open the Mirror tab to check your camera.").font(.caption).foregroundStyle(.secondary)
        })
    }

    func expandedView() -> AnyView { AnyView(CameraMirrorView(camera: camera)) }
    func settingsView() -> AnyView { AnyView(CameraSettingsView(camera: camera)) }
}

/// Live preview. Starts the camera on appear and stops it on disappear
/// (switching tabs or collapsing the notch removes this view).
struct CameraMirrorView: View {
    let camera: CameraService
    @AppStorage(Prefs.cameraMirrored) private var mirrored

    var body: some View {
        ZStack {
            if camera.isDenied {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("NotchHub doesn't have access to the camera.").foregroundStyle(.secondary)
                    Button("Open Camera Privacy Settings") { camera.openPrivacySettings() }
                        .buttonStyle(PillButtonStyle())
                }
            } else if let error = camera.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                CameraPreview(session: camera.session)
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        IconButton(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", size: 10,
                                   help: mirrored ? "Show as others see you" : "Mirror the image") {
                            mirrored.toggle()
                        }
                        .padding(8)
                    }
                    .overlay {
                        if !camera.isRunning {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .aspectRatio(4 / 3, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}

/// AVCaptureVideoPreviewLayer in an NSView.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Mirroring is done in SwiftUI (scaleEffect) so it's predictable for every camera.
        if let connection = (nsView.layer as? AVCaptureVideoPreviewLayer)?.connection,
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }
}

struct CameraSettingsView: View {
    let camera: CameraService
    @AppStorage(Prefs.cameraMirrored) private var mirrored

    var body: some View {
        Toggle("Mirror the image (like a real mirror)", isOn: $mirrored)
        if camera.isDenied {
            LabeledContent("Camera access") {
                Button("Open Privacy Settings") { camera.openPrivacySettings() }
            }
        }
        Text("The camera turns on only while the Mirror tab is open and turns off as soon as you switch tabs or the notch closes.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
