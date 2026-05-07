import CoreLocation

/// One-shot fetcher for the user's current location. Requests "when in use" permission on first use,
/// then asks for a single location fix. Returns nil if permission is denied or the device cannot
/// provide a location.
@MainActor
final class CurrentLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetch() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                // The delegate will request the location once authorization resolves.
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                resume(with: nil)
            @unknown default:
                resume(with: nil)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                resume(with: nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            resume(with: locations.last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            resume(with: nil)
        }
    }

    private func resume(with location: CLLocation?) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: location)
    }
}
