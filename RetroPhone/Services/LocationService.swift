import CoreLocation
import Observation

/// When-in-use location, requested only when a feature first needs it.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?
    private(set) var placeName: String?
    private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func requestPermission() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// Returns a (coarse) current location, or nil if denied / unavailable.
    func currentLocation(accuracy: CLLocationAccuracy = kCLLocationAccuracyKilometer, timeout: TimeInterval = 15) async -> CLLocation? {
        if isDenied { return nil }
        if let loc = location, loc.timestamp.timeIntervalSinceNow > -600, loc.horizontalAccuracy <= max(accuracy, 3000) {
            return loc
        }
        manager.desiredAccuracy = accuracy
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
            else { manager.requestLocation() }
            // Never wait forever: Core Location may not call back at all (e.g. the permission prompt
            // can't be shown, or no fix arrives). Fall back to the system's last known location.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, !self.waiters.isEmpty else { return }
                if self.lastError == nil { self.lastError = L("위치를 확인할 수 없습니다") }
                self.resume(self.manager.location ?? self.location)
            }
        }
    }

    private func resume(_ loc: CLLocation?) {
        let w = waiters
        waiters.removeAll()
        w.forEach { $0.resume(returning: loc) }
    }

    /// Place name for a location; gives up after `timeout` so a stalled lookup never blocks the weather.
    func reverseGeocode(_ loc: CLLocation, timeout: TimeInterval = 6) async -> String? {
        let geocoder = CLGeocoder()
        let locale = Localizer.shared.language.locale
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { @MainActor in
                let p = (try? await geocoder.reverseGeocodeLocation(loc, preferredLocale: locale))?.first
                return p?.locality ?? p?.subAdministrativeArea ?? p?.administrativeArea
            }
            group.addTask { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                geocoder.cancelGeocode()   // makes the lookup above finish with an error
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: CLLocationManagerDelegate (delivered on the main thread because the manager was created there)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if !self.waiters.isEmpty { self.manager.requestLocation() }
            } else if status == .denied || status == .restricted {
                self.resume(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            self.lastError = nil
            self.resume(loc)
            if self.placeName == nil { self.placeName = await self.reverseGeocode(loc) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.resume(self.location)
        }
    }
}
