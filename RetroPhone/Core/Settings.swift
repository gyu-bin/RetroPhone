import Foundation
import Observation

enum BuiltinWallpaper: String, Codable, CaseIterable, Identifiable {
    case droplets, aurora, linen, night, sunset, wave
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .droplets: L("물방울")
        case .aurora: L("오로라")
        case .linen: L("리넨")
        case .night: L("밤하늘")
        case .sunset: L("노을")
        case .wave: L("물결")
        }
    }
}

enum WallpaperChoice: Codable, Hashable {
    case builtin(BuiltinWallpaper)
    case custom(file: String)
}

enum TemperatureUnit: String, Codable, CaseIterable { case celsius, fahrenheit }

enum WeatherLocationSetting: Codable, Hashable {
    case current
    case city(name: String, latitude: Double, longitude: Double)
}

/// Front colour of the virtual phone body (bezels and home button).
enum BodyColor: String, Codable, CaseIterable, Identifiable {
    case black, white
    var id: String { rawValue }
    var displayName: String { self == .black ? L("블랙") : L("화이트") }
}

/// Theme era: iOS 4 (iPhone 4, skeuomorphic) or iOS 7 (iPhone 5s, flat).
enum ThemeEra: String, Codable, CaseIterable, Identifiable {
    case ios4, ios7
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ios4: "iOS 4 · iPhone 4"
        case .ios7: "iOS 7 · iPhone 5s"
        }
    }
    /// The built-in wallpaper that belongs to this era.
    var defaultWallpaper: BuiltinWallpaper { self == .ios7 ? .wave : .droplets }
}

struct RetroSettings: Codable, Equatable {
    var setupCompleted = false
    var language: AppLanguage = .ko
    var soundEnabled = true
    var keyboardClicks = true
    var hapticsEnabled = true
    var textScale: Double = 1.0
    /// Minutes of inactivity before the virtual lock screen shows. 0 = never.
    var autoLockMinutes: Int = 0
    var lockOnLaunch = true
    var showHomeButton = true
    var lockWallpaper: WallpaperChoice = .builtin(.droplets)
    var homeWallpaper: WallpaperChoice = .builtin(.droplets)
    var temperatureUnit: TemperatureUnit = .celsius
    var weatherLocation: WeatherLocationSetting = .current
    var use24HourClock = false
    var themeEra: ThemeEra = .ios4
    var showBatteryPercentage = true
    /// iPhone 4-style thick top/bottom bezels (black top bar over the Dynamic Island area,
    /// chin with a large home button). The "screen" sits between them.
    var classicBezel = true
    /// Whether the one-time "make it look like my iPhone" offer has been shown.
    var homeImportOffered = false
    /// Body colour; nil follows the era (iPhone 4 black, iPhone 5s white/silver).
    var bodyColor: BodyColor? = nil

    var effectiveBodyColor: BodyColor { bodyColor ?? (themeEra == .ios7 ? .white : .black) }

    init() {}

    // Tolerant decoding so adding fields never wipes a user's settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RetroSettings.defaults
        setupCompleted = (try? c.decode(Bool.self, forKey: .setupCompleted)) ?? d.setupCompleted
        language = (try? c.decode(AppLanguage.self, forKey: .language)) ?? d.language
        soundEnabled = (try? c.decode(Bool.self, forKey: .soundEnabled)) ?? d.soundEnabled
        keyboardClicks = (try? c.decode(Bool.self, forKey: .keyboardClicks)) ?? d.keyboardClicks
        hapticsEnabled = (try? c.decode(Bool.self, forKey: .hapticsEnabled)) ?? d.hapticsEnabled
        textScale = (try? c.decode(Double.self, forKey: .textScale)) ?? d.textScale
        autoLockMinutes = (try? c.decode(Int.self, forKey: .autoLockMinutes)) ?? d.autoLockMinutes
        lockOnLaunch = (try? c.decode(Bool.self, forKey: .lockOnLaunch)) ?? d.lockOnLaunch
        showHomeButton = (try? c.decode(Bool.self, forKey: .showHomeButton)) ?? d.showHomeButton
        lockWallpaper = (try? c.decode(WallpaperChoice.self, forKey: .lockWallpaper)) ?? d.lockWallpaper
        homeWallpaper = (try? c.decode(WallpaperChoice.self, forKey: .homeWallpaper)) ?? d.homeWallpaper
        temperatureUnit = (try? c.decode(TemperatureUnit.self, forKey: .temperatureUnit)) ?? d.temperatureUnit
        weatherLocation = (try? c.decode(WeatherLocationSetting.self, forKey: .weatherLocation)) ?? d.weatherLocation
        use24HourClock = (try? c.decode(Bool.self, forKey: .use24HourClock)) ?? d.use24HourClock
        themeEra = (try? c.decode(ThemeEra.self, forKey: .themeEra)) ?? d.themeEra
        showBatteryPercentage = (try? c.decode(Bool.self, forKey: .showBatteryPercentage)) ?? d.showBatteryPercentage
        classicBezel = (try? c.decode(Bool.self, forKey: .classicBezel)) ?? d.classicBezel
        homeImportOffered = (try? c.decode(Bool.self, forKey: .homeImportOffered)) ?? d.homeImportOffered
        bodyColor = try? c.decodeIfPresent(BodyColor.self, forKey: .bodyColor)
    }

    static let defaults = RetroSettings()
}

@Observable
final class SettingsStore {
    static let shared = SettingsStore()
    private static let fileName = "settings.json"
    private let persist: Bool

    var value: RetroSettings {
        didSet {
            guard value != oldValue else { return }
            Localizer.shared.language = value.language
            if persist { FileStore.save(value, to: Self.fileName) }
        }
    }

    init(persist: Bool = true) {
        self.persist = persist
        let loaded = persist ? FileStore.load(RetroSettings.self, from: Self.fileName) : nil
        value = loaded ?? RetroSettings()
        Localizer.shared.language = value.language
    }

    func reset() { value = RetroSettings() }
}
