import AppKit
import AVFoundation

/// Front camera session for the Camera Mirror module.
///
/// The camera is only running while the Camera tab is on screen: the view
/// calls `start()` when it appears and `stop()` when it disappears (tab
/// change or notch collapse), so the green camera light never stays on.
@Observable
@MainActor
final class CameraService {
    static let shared = CameraService()

    private(set) var authorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let queue = DispatchQueue(label: "NotchHub.camera")
    @ObservationIgnored private var configured = false
    /// Incremented on every start/stop so a late async start can't win over a stop.
    @ObservationIgnored private var generation = 0

    private init() {}

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func start() {
        generation += 1
        let current = generation
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                authorization = AVCaptureDevice.authorizationStatus(for: .video)
                if granted, current == generation { startSession(generation: current) }
            }
        case .authorized:
            startSession(generation: current)
        default:
            break
        }
    }

    func stop() {
        generation += 1
        isRunning = false
        let session = self.session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func startSession(generation current: Int) {
        if !configured {
            guard configure() else { return }
        }
        let session = self.session
        queue.async {
            if !session.isRunning { session.startRunning() }
            let running = session.isRunning
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let service = CameraService.shared
                    if service.generation == current {
                        service.isRunning = running
                    } else if running {
                        // Stopped while we were starting.
                        service.queue.async { session.stopRunning() }
                    }
                }
            }
        }
    }

    private func configure() -> Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        )
        guard let device = discovery.devices.first(where: { $0.deviceType == .builtInWideAngleCamera })
                ?? discovery.devices.first
                ?? AVCaptureDevice.default(for: .video) else {
            errorMessage = "No camera found."
            return false
        }
        session.beginConfiguration()
        session.sessionPreset = .medium
        defer { session.commitConfiguration() }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                errorMessage = "The camera is in use by another app."
                return false
            }
            session.addInput(input)
            configured = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
