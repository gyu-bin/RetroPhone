import Foundation
import CoreLocation
import Observation

/// Condition groups we have classic icons for.
enum WeatherCondition: String, Codable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, thunder, unknown

    var labelKo: String {
        switch self {
        case .clear: "맑음"; case .partlyCloudy: "구름 조금"; case .cloudy: "흐림"
        case .fog: "안개"; case .drizzle: "이슬비"; case .rain: "비"
        case .snow: "눈"; case .thunder: "뇌우"; case .unknown: "알 수 없음"
        }
    }

    /// WMO weather interpretation codes (used by Open-Meteo).
    static func fromWMO(_ code: Int) -> WeatherCondition {
        switch code {
        case 0: .clear
        case 1, 2: .partlyCloudy
        case 3: .cloudy
        case 45, 48: .fog
        case 51...57: .drizzle
        case 61...67, 80...82: .rain
        case 71...77, 85, 86: .snow
        case 95...99: .thunder
        default: .unknown
        }
    }
}

struct WeatherSnapshot: Codable, Equatable {
    struct Hour: Codable, Equatable, Identifiable {
        var time: Date
        var temperature: Double
        var condition: WeatherCondition
        var isDay: Bool
        var id: Date { time }
    }
    struct Day: Codable, Equatable, Identifiable {
        var date: Date
        var high: Double
        var low: Double
        var condition: WeatherCondition
        var id: Date { date }
    }
    var placeName: String
    var fetchedAt: Date
    var temperature: Double        // °C
    var high: Double
    var low: Double
    var condition: WeatherCondition
    var isDay: Bool
    var sunrise: Date?
    var sunset: Date?
    var hourly: [Hour]
    var daily: [Day]
    var source: String
}

/// Weather from Open-Meteo (free, keyless, non-commercial use; data CC BY 4.0).
/// Coordinates are rounded to ~1 km before leaving the device; no identifiers are sent.
/// WeatherKit requires a paid developer account capability, so it is not the default — see docs.
@Observable
final class WeatherService {
    static let shared = WeatherService()
    private static let cacheFile = "weather-cache.json"

    enum Status: Equatable { case idle, loading, loaded, failed(String), locationDenied, needsPermission }

    private(set) var snapshot: WeatherSnapshot?
    private(set) var status: Status = .idle
    private var inFlight: Task<Void, Never>?

    private init() {
        snapshot = FileStore.load(WeatherSnapshot.self, from: Self.cacheFile)
    }

    var isStale: Bool { (snapshot?.fetchedAt.timeIntervalSinceNow ?? -.infinity) < -30 * 60 }

    /// Background refresh (widgets, app activation). Never shows a permission prompt —
    /// permissions are requested only when the user opens the Weather app.
    func refreshIfNeeded() {
        if isStale && inFlight == nil { refresh(allowPrompt: false) }
    }

    func refresh(allowPrompt: Bool = true) {
        inFlight?.cancel()
        inFlight = Task {
            defer { inFlight = nil }
            status = .loading
            let setting = SettingsStore.shared.value.weatherLocation
            var name: String
            let coordinate: CLLocationCoordinate2D
            switch setting {
            case .city(let n, let lat, let lon):
                name = n
                coordinate = .init(latitude: lat, longitude: lon)
            case .current:
                if !allowPrompt && LocationService.shared.authorization == .notDetermined {
                    status = .needsPermission
                    return
                }
                guard let loc = await LocationService.shared.currentLocation() else {
                    status = LocationService.shared.isDenied ? .locationDenied : .failed(L("위치를 확인할 수 없습니다"))
                    return
                }
                coordinate = loc.coordinate
                name = await LocationService.shared.reverseGeocode(loc) ?? L("현재 위치")
            }
            if name.isEmpty { name = L("현재 위치") }
            do {
                let snap = try await Self.fetchOpenMeteo(coordinate: coordinate, placeName: name)
                guard !Task.isCancelled else { return }
                snapshot = snap
                status = .loaded
                FileStore.save(snap, to: Self.cacheFile)
            } catch is CancellationError {
            } catch {
                status = .failed(NetworkMonitor.shared.isOnline ? L("날씨 정보를 가져오지 못했습니다") : L("네트워크에 연결되어 있지 않습니다"))
            }
        }
    }

    // MARK: Open-Meteo

    static func requestURL(for c: CLLocationCoordinate2D) -> URL {
        let lat = (c.latitude * 100).rounded() / 100
        let lon = (c.longitude * 100).rounded() / 100
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "7"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        return comps.url!
    }

    struct OMResponse: Decodable {
        struct Current: Decodable { var time: TimeInterval; var temperature_2m: Double; var weather_code: Int; var is_day: Int }
        struct Hourly: Decodable { var time: [TimeInterval]; var temperature_2m: [Double?]; var weather_code: [Int?]; var is_day: [Int?] }
        struct Daily: Decodable {
            var time: [TimeInterval]; var weather_code: [Int?]
            var temperature_2m_max: [Double?]; var temperature_2m_min: [Double?]
            var sunrise: [TimeInterval?]; var sunset: [TimeInterval?]
        }
        var current: Current
        var hourly: Hourly
        var daily: Daily
    }

    static func fetchOpenMeteo(coordinate: CLLocationCoordinate2D, placeName: String) async throws -> WeatherSnapshot {
        var request = URLRequest(url: requestURL(for: coordinate), timeoutInterval: 15)
        request.setValue("RetroPhone/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data, placeName: placeName, now: Date())
    }

    /// Pure parsing step (unit-tested with a fixture).
    static func parse(_ data: Data, placeName: String, now: Date) throws -> WeatherSnapshot {
        let r = try JSONDecoder().decode(OMResponse.self, from: data)
        var hours: [WeatherSnapshot.Hour] = []
        for (i, t) in r.hourly.time.enumerated() where t >= now.timeIntervalSince1970 - 3600 {
            guard let temp = r.hourly.temperature_2m[i], let code = r.hourly.weather_code[i] else { continue }
            hours.append(.init(time: Date(timeIntervalSince1970: t), temperature: temp,
                               condition: .fromWMO(code), isDay: (r.hourly.is_day[i] ?? 1) == 1))
            if hours.count >= 24 { break }
        }
        var days: [WeatherSnapshot.Day] = []
        for (i, t) in r.daily.time.enumerated() {
            guard let hi = r.daily.temperature_2m_max[i], let lo = r.daily.temperature_2m_min[i] else { continue }
            days.append(.init(date: Date(timeIntervalSince1970: t), high: hi, low: lo,
                              condition: .fromWMO(r.daily.weather_code[i] ?? -1)))
        }
        let sunrise = r.daily.sunrise.first.flatMap { $0 }.map { Date(timeIntervalSince1970: $0) }
        let sunset = r.daily.sunset.first.flatMap { $0 }.map { Date(timeIntervalSince1970: $0) }
        return WeatherSnapshot(
            placeName: placeName, fetchedAt: now,
            temperature: r.current.temperature_2m,
            high: days.first?.high ?? r.current.temperature_2m,
            low: days.first?.low ?? r.current.temperature_2m,
            condition: .fromWMO(r.current.weather_code), isDay: r.current.is_day == 1,
            sunrise: sunrise, sunset: sunset, hourly: hours, daily: days, source: "Open-Meteo")
    }

    /// City search via Apple's on-device/Apple-hosted geocoder (no third party).
    static func searchCity(_ query: String) async -> [(name: String, coordinate: CLLocationCoordinate2D)] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let marks = (try? await CLGeocoder().geocodeAddressString(query, in: nil,
                                                                  preferredLocale: Localizer.shared.language.locale)) ?? []
        return marks.compactMap { m in
            guard let c = m.location?.coordinate else { return nil }
            let name = [m.locality, m.administrativeArea, m.country].compactMap { $0 }.first ?? query
            return (name, c)
        }
    }
}

extension Double {
    /// Formats a Celsius value in the user's unit, e.g. "23°".
    var temperatureString: String {
        let unit = SettingsStore.shared.value.temperatureUnit
        let v = unit == .celsius ? self : self * 9 / 5 + 32
        return "\(Int(v.rounded()))°"
    }
}
