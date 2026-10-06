import AppKit
import CoreLocation

/// One-shot CoreLocation wrapper with async/await and graceful denial handling.
@Observable
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    enum LocationError: LocalizedError {
        case denied, unavailable
        var errorDescription: String? {
            switch self {
            case .denied: "Location access is off. Allow it in System Settings or set a city in Settings → Weather."
            case .unavailable: "Couldn't determine your location. Set a city in Settings → Weather."
            }
        }
    }

    private(set) var authorization: CLAuthorizationStatus
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var continuations: [CheckedContinuation<CLLocation, Error>] = []

    override private init() {
        authorization = .notDetermined
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Returns the current location, asking for permission the first time.
    func currentLocation() async throws -> CLLocation {
        if isDenied { throw LocationError.denied }
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -900 { return recent }
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            if authorization == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    /// Reverse-geocodes a location to a short place name.
    func placeName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.locality ?? placemarks?.first?.name
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume(with: result) }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let service = LocationService.shared
                service.authorization = status
                guard !service.continuations.isEmpty else { return }
                switch status {
                case .denied, .restricted: service.finish(.failure(LocationError.denied))
                case .notDetermined: break
                default: service.manager.requestLocation()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { LocationService.shared.finish(.success(location)) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                LocationService.shared.finish(.failure(denied ? LocationError.denied : LocationError.unavailable))
            }
        }
    }
}
