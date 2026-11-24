import XCTest
@testable import RetroPhone

final class ScreenshotImporterTests: XCTestCase {
    typealias Label = ScreenshotLayoutImporter.Label

    func testDraftReadsRowsDockAndUnmatched() {
        let labels = [
            Label(text: "오후 5:19", center: CGPoint(x: 0.2, y: 0.03)),           // status bar → ignored
            Label(text: "카메라", center: CGPoint(x: 0.62, y: 0.20)),
            Label(text: "캘린더", center: CGPoint(x: 0.12, y: 0.21)),
            Label(text: "KakaoTalk", center: CGPoint(x: 0.38, y: 0.205)),
            Label(text: "Instagram", center: CGPoint(x: 0.12, y: 0.32)),
            Label(text: "당근", center: CGPoint(x: 0.38, y: 0.32)),
            Label(text: "Safari", center: CGPoint(x: 0.12, y: 0.93)),
            Label(text: "전화", center: CGPoint(x: 0.38, y: 0.93)),
        ]
        let d = ScreenshotLayoutImporter.draft(from: labels)
        XCTAssertEqual(d.pageApps, ["builtin.calendar", "ext.kakaotalk", "builtin.camera", "ext.instagram"])
        XCTAssertEqual(d.dockApps, ["builtin.browser", "builtin.phone"])
        XCTAssertEqual(d.unmatched, ["당근"])
    }

    func testLayoutFromDraftKeepsAllBuiltinsReachable() {
        let d = ScreenshotLayoutImporter.Draft(pageApps: ["ext.kakaotalk", "builtin.notes"], dockApps: ["builtin.phone"], unmatched: [])
        let l = ScreenshotLayoutImporter.layout(from: d)
        XCTAssertEqual(l.dock, ["builtin.phone"])
        XCTAssertEqual(l.pages[0].first?.appID, "ext.kakaotalk")
        XCTAssertTrue(BuiltinApp.allCases.allSatisfy { l.placedApps.contains($0.appID) })
    }
}

final class WeatherParsingTests: XCTestCase {
    func testParsesOpenMeteoFixture() throws {
        let now = Date(timeIntervalSince1970: 1_764_000_000)
        let t0 = 1_764_000_000.0
        let json = """
        {"current":{"time":\(t0),"temperature_2m":12.4,"weather_code":2,"is_day":1},
         "hourly":{"time":[\(t0 - 7200),\(t0),\(t0 + 3600)],"temperature_2m":[10.0,12.4,null],"weather_code":[0,2,61],"is_day":[1,1,0]},
         "daily":{"time":[\(t0)],"weather_code":[61],"temperature_2m_max":[15.2],"temperature_2m_min":[6.1],"sunrise":[\(t0 - 20000)],"sunset":[\(t0 + 20000)]}}
        """
        let s = try WeatherService.parse(Data(json.utf8), placeName: "서울", now: now)
        XCTAssertEqual(s.temperature, 12.4)
        XCTAssertEqual(s.condition, .partlyCloudy)
        XCTAssertEqual(s.high, 15.2); XCTAssertEqual(s.low, 6.1)
        XCTAssertEqual(s.hourly.count, 1, "past hours >1h old and null values are dropped")
        XCTAssertEqual(s.daily.first?.condition, .rain)
        XCTAssertNotNil(s.sunrise); XCTAssertNotNil(s.sunset)
    }

    func testWMOMapping() {
        XCTAssertEqual(WeatherCondition.fromWMO(0), .clear)
        XCTAssertEqual(WeatherCondition.fromWMO(45), .fog)
        XCTAssertEqual(WeatherCondition.fromWMO(73), .snow)
        XCTAssertEqual(WeatherCondition.fromWMO(95), .thunder)
        XCTAssertEqual(WeatherCondition.fromWMO(1234), .unknown)
    }

    func testRequestRoundsCoordinatesForPrivacy() {
        let url = WeatherService.requestURL(for: .init(latitude: 37.566535, longitude: 126.977969))
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(q.first { $0.name == "latitude" }?.value, "37.57")
        XCTAssertEqual(q.first { $0.name == "longitude" }?.value, "126.98")
    }
}

final class MonthGridTests: XCTestCase {
    func testGridHas42DaysStartingOnFirstWeekday() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let nov2026 = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let days = MonthGrid.days(for: nov2026, calendar: cal)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(cal.component(.weekday, from: days[0]), 1)
        // Nov 1 2026 is a Sunday → first cell is Nov 1.
        XCTAssertEqual(cal.component(.day, from: days[0]), 1)
        XCTAssertEqual(cal.component(.month, from: days[0]), 11)
    }
}

final class SoundSynthesisTests: XCTestCase {
    func testAllEffectsProduceBoundedAudio() {
        for effect in SoundService.Effect.allCases {
            let s = SoundService.synthesize(effect)
            XCTAssertFalse(s.isEmpty, "\(effect)")
            XCTAssertLessThan(s.count, 44_100 * 3, "\(effect) shorter than 3s")
            XCTAssertTrue(s.allSatisfy { $0 >= -1 && $0 <= 1 }, "\(effect) clipped")
        }
    }

    func testDTMFKeys() {
        for key in "0123456789*#" { XCTAssertEqual(SoundService.dtmf(key).count, Int(44_100 * 0.16)) }
        XCTAssertTrue(SoundService.dtmf("x").isEmpty)
    }
}

final class LocalizationTests: XCTestCase {
    override func tearDown() { Localizer.shared.language = SettingsStore.shared.value.language }

    func testEnglishLookupAndFallback() {
        Localizer.shared.language = .en
        XCTAssertEqual(L("설정"), "Settings")
        XCTAssertEqual(L("밀어서 잠금 해제"), "slide to unlock")
        XCTAssertEqual(L("번역 없는 문장"), "번역 없는 문장")
        XCTAssertEqual(LF("페이지 %d/%d", 2, 3), "Page 2 of 3")
        Localizer.shared.language = .ko
        XCTAssertEqual(L("설정"), "설정")
    }
}

final class ExternalAppTests: XCTestCase {
    func testURLValidation() {
        XCTAssertEqual(ExternalAppLauncher.normalizedURL("myapp"), "myapp://")
        XCTAssertEqual(ExternalAppLauncher.normalizedURL(" https://example.com "), "https://example.com")
        XCTAssertNil(ExternalAppLauncher.normalizedURL(""))
        XCTAssertNil(ExternalAppLauncher.normalizedURL("javascript:alert(1)"))
        XCTAssertNil(ExternalAppLauncher.normalizedURL("1abc://"))
    }

    func testCatalogSchemesAreDeclaredForCanOpenURL() throws {
        let declared = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? []
        for app in AppCatalog.externalApps {
            guard let scheme = app.scheme, let s = URL(string: scheme)?.scheme else { continue }
            XCTAssertTrue(declared.contains(s), "\(s) missing from LSApplicationQueriesSchemes")
        }
        XCTAssertLessThanOrEqual(declared.count, 50, "iOS limits query schemes to 50")
    }

    func testCatalogIDsUnique() {
        let ids = AppCatalog.externalApps.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}

final class PersistenceTests: XCTestCase {
    func testSettingsDecodingToleratesMissingAndUnknownKeys() throws {
        let json = #"{"language":"en","soundEnabled":false,"futureKey":123}"#
        let s = try JSONDecoder().decode(RetroSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.language, .en)
        XCTAssertFalse(s.soundEnabled)
        XCTAssertTrue(s.hapticsEnabled, "missing keys fall back to defaults")
        XCTAssertEqual(s.homeWallpaper, .builtin(.droplets))
    }

    func testBackupRoundTrip() throws {
        let store = LayoutStore(persist: false, layout: .default)
        var settings = RetroSettings()
        settings.language = .en
        let url = try store.exportBackup(settings: settings)
        defer { try? FileManager.default.removeItem(at: url) }
        let backup = try LayoutStore.decodeBackup(Data(contentsOf: url))
        XCTAssertEqual(backup.layout, store.layout)
        XCTAssertEqual(backup.settings.language, .en)
        XCTAssertThrowsError(try LayoutStore.decodeBackup(Data(#"{"format":"x"}"#.utf8)))
    }

    func testNotesStoreCRUD() {
        let notes = NotesStore(persist: false)
        let n = notes.create("첫 줄\n둘째 줄")
        XCTAssertEqual(notes.notes.first?.title, "첫 줄")
        notes.update(n.id, text: "수정됨")
        XCTAssertEqual(notes.notes.first?.text, "수정됨")
        notes.create("   ")
        notes.pruneEmpty()
        XCTAssertEqual(notes.notes.count, 1)
        notes.delete(n.id)
        XCTAssertTrue(notes.notes.isEmpty)
    }

    func testWallpaperRenderingIsDeterministic() {
        let a = WallpaperRenderer.render(.droplets, size: CGSize(width: 40, height: 80)).pngData()
        let b = WallpaperRenderer.render(.droplets, size: CGSize(width: 40, height: 80)).pngData()
        XCTAssertEqual(a, b)
    }
}
