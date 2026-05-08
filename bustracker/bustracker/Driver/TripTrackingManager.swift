import CoreLocation
import Foundation
import Observation

/// Drives the active-trip side effects: location updates, throttled position pushes,
/// gap detection, and start/end RPCs. The view binds to this and reads `state` to render.
@MainActor
@Observable
final class TripTrackingManager: NSObject {
    enum State: Equatable {
        case idle
        case starting
        case active(tripID: UUID, startedAt: Date)
        case ending
    }

    /// Cached locally so the driver UI can render the active-trip layout immediately on
    /// app relaunch (instead of flashing the idle screen for the second it takes the
    /// resume RPC to confirm). The cache is overwritten as soon as the server responds
    /// and cleared when a trip ends or is found to no longer exist remotely.
    private struct CachedTrip: Codable {
        let id: UUID
        let startedAt: Date
    }

    private enum Cache {
        static let key = "bustracker.driver.activeTrip"

        static func load() -> CachedTrip? {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(CachedTrip.self, from: data)
        }

        static func save(_ trip: CachedTrip) {
            guard let data = try? JSONEncoder().encode(trip) else { return }
            UserDefaults.standard.set(data, forKey: key)
        }

        static func clear() {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    enum PermissionStatus {
        case unknown
        case foregroundOnly
        case always
        case denied
        case restricted
    }

    private(set) var state: State = .idle
    private(set) var permissionStatus: PermissionStatus = .unknown
    private(set) var lastPushAt: Date?
    private(set) var lastError: String?
    private(set) var positionsPushed: Int = 0
    private(set) var gapsRecorded: Int = 0

    private let locationManager = CLLocationManager()
    private let pushIntervalSeconds: TimeInterval = 10
    /// If we go this long without a successful position push during an active trip,
    /// we treat the silence as a coverage gap.
    private let gapDetectionThresholdSeconds: TimeInterval = 30

    private var openGapID: Int?
    private var openGapStartedAt: Date?
    private var lastSuccessfulCoordinate: CLLocationCoordinate2D?
    private var lastSuccessfulPushTime: Date?
    private var pushInFlight = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = kCLDistanceFilterNone
        refreshPermission()

        // If we had an active trip last time the app ran, optimistically restore
        // the active state so the camera/log UI shows up immediately. The async
        // resume RPC will replace this with fresh data — or clear it if the trip
        // ended remotely.
        if let cached = Cache.load() {
            state = .active(tripID: cached.id, startedAt: cached.startedAt)
        }
    }

    // MARK: - Public API

    func refreshPermission() {
        permissionStatus = mapAuthorization(locationManager.authorizationStatus)
    }

    /// Walks the user up the iOS permission ladder: nothing → when-in-use → always.
    /// Call this before `startTrip`.
    func requestPermissions() async {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways, .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func resumeIfTripExists() async {
        do {
            if let trip = try await SupabaseTripService.fetchActiveTrip() {
                state = .active(tripID: trip.id, startedAt: trip.startedAt)
                Cache.save(CachedTrip(id: trip.id, startedAt: trip.startedAt))

                // Hydrate the counters from the DB so closing/reopening the app
                // doesn't reset them to 0. We also seed lastSuccessfulPushTime
                // so the 10s throttle respects the real last push, not relaunch
                // wall-clock zero.
                if let stats = try? await SupabaseTripService.fetchTripStats(tripID: trip.id) {
                    positionsPushed = stats.positionsCount
                    gapsRecorded = stats.gapsCount
                    lastPushAt = stats.lastPositionAt
                    lastSuccessfulPushTime = stats.lastPositionAt
                }

                beginLocationUpdates()
            } else {
                // No active trip on the server — cache must be wrong (trip ended
                // elsewhere or got cleaned up). Drop back to idle.
                state = .idle
                Cache.clear()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startTrip() async {
        guard case .idle = state else { return }
        guard permissionStatus == .always || permissionStatus == .foregroundOnly else {
            lastError = "Location permission is required to start a trip."
            return
        }

        lastError = nil
        state = .starting
        do {
            let tripID = try await SupabaseTripService.startTrip()
            let startedAt = Date()
            state = .active(tripID: tripID, startedAt: startedAt)
            Cache.save(CachedTrip(id: tripID, startedAt: startedAt))
            positionsPushed = 0
            gapsRecorded = 0
            beginLocationUpdates()
        } catch {
            lastError = error.localizedDescription
            state = .idle
        }
    }

    func endTrip() async {
        guard case .active(let tripID, _) = state else { return }
        lastError = nil
        state = .ending
        endLocationUpdates()

        // Close any gap that was open when the driver hit End.
        if let gapID = openGapID {
            try? await SupabaseTripService.closeGap(gapID: gapID, gapEnd: Date())
            openGapID = nil
            openGapStartedAt = nil
        }

        do {
            try await SupabaseTripService.endTrip(tripID)
            state = .idle
            lastPushAt = nil
            Cache.clear()
        } catch {
            lastError = error.localizedDescription
            // Restore active state so the user can retry End.
            state = .active(tripID: tripID, startedAt: Date())
            beginLocationUpdates()
        }
    }

    // MARK: - Internal

    private func beginLocationUpdates() {
        guard permissionStatus == .always || permissionStatus == .foregroundOnly else { return }
        // Foreground-only tracking for v1. The driver keeps the app open while
        // driving. Setting `allowsBackgroundLocationUpdates = true` on iOS 26
        // with the legacy API has been throwing NSException for us; switching
        // to CLBackgroundActivitySession (iOS 17+) is a follow-up.
        locationManager.startUpdatingLocation()
    }

    private func endLocationUpdates() {
        locationManager.stopUpdatingLocation()
        // We deliberately don't cancel an in-flight push: cancelling it would
        // surface a "cancelled" error, and the worst case if a stray push lands
        // after end_trip() is a single position row attached to a now-ended trip,
        // which is harmless.
    }

    private func handle(_ location: CLLocation) {
        guard case .active(let tripID, _) = state else { return }
        let now = Date()

        // Skip if a push is already in flight — iOS may deliver several location
        // updates per second and we don't want to stomp the previous request.
        if pushInFlight { return }

        // Throttle to ≥ pushIntervalSeconds between pushes.
        if let last = lastSuccessfulPushTime, now.timeIntervalSince(last) < pushIntervalSeconds {
            return
        }

        let coordinate = location.coordinate
        lastSuccessfulCoordinate = coordinate
        pushInFlight = true

        Task { [weak self] in
            guard let self else { return }
            do {
                try await SupabaseTripService.pushPosition(tripID: tripID, coordinate: coordinate, at: now)
                await MainActor.run {
                    self.pushInFlight = false
                    self.lastSuccessfulPushTime = now
                    self.lastPushAt = now
                    self.positionsPushed += 1
                    self.lastError = nil
                }
                await self.closeOpenGapIfNeeded(at: now)
            } catch is CancellationError {
                await MainActor.run { self.pushInFlight = false }
            } catch {
                await MainActor.run {
                    self.pushInFlight = false
                    self.lastError = "Failed to push position: \(error.localizedDescription)"
                }
                await self.openGapIfNeeded(at: now)
            }
        }
    }

    private func openGapIfNeeded(at moment: Date) async {
        guard case .active(let tripID, _) = state else { return }
        guard openGapID == nil else { return }
        let gapStart = lastSuccessfulPushTime ?? moment
        // Only open if the silence has actually exceeded the threshold; brief network blips
        // shouldn't manufacture noise.
        if moment.timeIntervalSince(gapStart) < gapDetectionThresholdSeconds { return }
        do {
            let id = try await SupabaseTripService.openGap(tripID: tripID, gapStart: gapStart)
            openGapID = id
            openGapStartedAt = gapStart
            gapsRecorded += 1
        } catch {
            // We failed to even record the gap; keep going, surface the error.
            lastError = "Failed to record GPS gap: \(error.localizedDescription)"
        }
    }

    private func closeOpenGapIfNeeded(at moment: Date) async {
        guard let id = openGapID else { return }
        do {
            try await SupabaseTripService.closeGap(gapID: id, gapEnd: moment)
            openGapID = nil
            openGapStartedAt = nil
        } catch {
            lastError = "Failed to close GPS gap: \(error.localizedDescription)"
        }
    }

    private func mapAuthorization(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .unknown
        case .authorizedWhenInUse: return .foregroundOnly
        case .authorizedAlways: return .always
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unknown
        }
    }
}

extension TripTrackingManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.permissionStatus = self.mapAuthorization(manager.authorizationStatus)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handle(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = "Location error: \(error.localizedDescription)"
            await self.openGapIfNeeded(at: Date())
        }
    }
}
