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
    func currentLocation(accuracy: CLLocationAccuracy = kCLLocationAccuracyKilometer) async -> CLLocation? {
        if isDenied { return nil }
        if let loc = location, loc.timestamp.timeIntervalSinceNow > -600, loc.horizontalAccuracy <= max(accuracy, 3000) {
            return loc
        }
        manager.desiredAccuracy = accuracy
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
            else { manager.requestLocation() }
        }
    }

    private func resume(_ loc: CLLocation?) {
        let w = waiters
        waiters.removeAll()
        w.forEach { $0.resume(returning: loc) }
    }

    func reverseGeocode(_ loc: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Localizer.shared.language.locale)
        let p = placemarks?.first
        return p?.locality ?? p?.subAdministrativeArea ?? p?.administrativeArea
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
