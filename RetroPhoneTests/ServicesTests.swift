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
            Label(text: "모르는앱", center: CGPoint(x: 0.38, y: 0.32)),
            Label(text: "Safari", center: CGPoint(x: 0.12, y: 0.93)),
            Label(text: "전화", center: CGPoint(x: 0.38, y: 0.93)),
        ]
        let d = ScreenshotLayoutImporter.draft(from: labels)
        XCTAssertEqual(d.pageApps, ["builtin.calendar", "ext.kakaotalk", "builtin.camera", "ext.instagram"])
        XCTAssertEqual(d.dockApps, ["builtin.browser", "builtin.phone"])
        XCTAssertEqual(d.unmatched, ["모르는앱"])
    }

    func testLayoutFromDraftKeepsAllBuiltinsReachable() {
        let d = ScreenshotLayoutImporter.Draft(pageApps: ["ext.kakaotalk", "builtin.notes"], dockApps: ["builtin.phone"], unmatched: [])
        let l = ScreenshotLayoutImporter.layout(from: d)
        XCTAssertEqual(l.dock, ["builtin.phone"])
        XCTAssertEqual(l.pages[0].first?.appID, "ext.kakaotalk")
        XCTAssertTrue(BuiltinApp.allCases.allSatisfy { l.placedApps.contains($0.appID) })
    }
}

final class HomeImportTests: XCTestCase {
    typealias Label = ScreenshotLayoutImporter.Label

    private func label(_ t: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.12) -> Label {
        Label(text: t, center: CGPoint(x: x, y: y), box: CGRect(x: x - w / 2, y: y - 0.008, width: w, height: 0.016))
    }

    func testKeepsOnlyGridLabelsInReadingOrder() {
        let labels = [
            label("오후 6:40", x: 0.2, y: 0.03),                 // status bar
            label("서울 12°", x: 0.3, y: 0.2, w: 0.2),            // widget text
            label("카카오톡", x: 0.386, y: 0.45),
            label("배민", x: 0.159, y: 0.45),
            label("검색", x: 0.5, y: 0.82),                       // search pill
            label("내가 만든 앱", x: 0.841, y: 0.58),
            label("화요일 일정이 없습니다", x: 0.5, y: 0.3, w: 0.6), // widget
            label("Safari", x: 0.159, y: 0.93),                  // dock band
        ]
        let kept = ScreenshotLayoutImporter.appLabels(labels).map(\.text)
        XCTAssertEqual(kept, ["배민", "카카오톡", "내가 만든 앱"])
    }

    /// A drawn "opened folder" screenshot: OCR finds the app names in reading order (not the folder
    /// title or the blurred dock behind) and the icon rects land on the drawn icons.
    func testOpenedFolderScreenshot() async throws {
        let size = CGSize(width: 1179, height: 2556)
        let names = ["카카오톡", "Instagram", "내 은행", "메모", "날씨"]
        let cols: [CGFloat] = [0.27, 0.5, 0.73], rows: [CGFloat] = [0.42, 0.56]
        let side = 0.143 * size.width
        var squares: [CGRect] = []
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.15, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            func text(_ s: String, _ cx: CGFloat, _ cy: CGFloat, _ pt: CGFloat) {
                let attr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: pt, weight: .medium), .foregroundColor: UIColor.white]
                let sz = (s as NSString).size(withAttributes: attr)
                (s as NSString).draw(at: CGPoint(x: cx * size.width - sz.width / 2, y: cy * size.height - sz.height / 2), withAttributes: attr)
            }
            text("업무", 0.5, 0.22, 90)                 // folder title
            text("Safari", 0.3, 0.95, 36)               // dock behind
            for (i, name) in names.enumerated() {
                let cx = cols[i % 3], cy = rows[i / 3]
                let gap = 0.014 * size.width + 0.008 * size.height
                let sq = CGRect(x: cx * size.width - side / 2, y: cy * size.height - gap - side, width: side, height: side)
                squares.append(sq)
                UIColor(hue: CGFloat(i) / 5, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                UIBezierPath(roundedRect: sq, cornerRadius: side * 0.22).fill()
                text(name, cx, cy, 36)
            }
        }
        let labels = try await ScreenshotLayoutImporter.recognizeLabels(in: image)
        let entries = ScreenshotLayoutImporter.analyzeFolder(labels, imageSize: size)
        XCTAssertEqual(entries.map(\.text), names)
        XCTAssertEqual(entries[0].match, "ext.kakaotalk")
        XCTAssertEqual(entries[1].match, "ext.instagram")
        XCTAssertNil(entries[2].match)
        for (e, sq) in zip(entries, squares) {
            let overlap = e.iconRect.intersection(sq)
            XCTAssertGreaterThan(overlap.width * overlap.height / (e.iconRect.width * e.iconRect.height), 0.8, e.text)
        }
    }

    func testMatchingAliasesAndFolders() {
        XCTAssertEqual(ScreenshotLayoutImporter.match("배민"), "ext.baemin")
        XCTAssertEqual(ScreenshotLayoutImporter.match("Safari"), "builtin.browser")
        XCTAssertEqual(ScreenshotLayoutImporter.match("App Store"), "sys.appstore")
        XCTAssertNil(ScreenshotLayoutImporter.match("내가 만든 앱"))
        XCTAssertTrue(ScreenshotLayoutImporter.isLikelyFolder("유틸리티"))
        XCTAssertTrue(ScreenshotLayoutImporter.isLikelyFolder("🎮"))
        XCTAssertFalse(ScreenshotLayoutImporter.isLikelyFolder("카카오톡"))
    }

    func testIconCropSitsAboveLabelAndInsideImage() {
        let size = CGSize(width: 1179, height: 2556)
        let l = label("카카오톡", x: 0.386, y: 0.45)
        let r = ScreenshotLayoutImporter.iconRect(above: l, imageSize: size)
        XCTAssertLessThan(r.maxY, l.box.minY * size.height)
        XCTAssertEqual(r.midX, 0.386 * size.width, accuracy: 2)
        XCTAssertEqual(r.width, r.height, accuracy: 1)
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(ScreenshotLayoutImporter.dockStripRect(imageSize: size)))
    }

    /// End-to-end on a real iOS 27 home screen (simulator SpringBoard, Korean UI).
    func testRealHomeScreenScreenshot() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ios-home-page1", withExtension: "png"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let labels = try await ScreenshotLayoutImporter.recognizeLabels(in: image)
        let apps = ScreenshotLayoutImporter.appLabels(labels)
        let texts = apps.map(\.text)
        for expected in ["Fitness", "Watch", "미리 알림", "파일", "미리보기", "유틸리티", "연락처", "바이블틈"] {
            XCTAssertTrue(texts.contains(expected), "missing \(expected) in \(texts)")
        }
        XCTAssertFalse(texts.contains("검색"), "search pill filtered")
        XCTAssertFalse(texts.contains("9:41"), "status bar filtered")
        XCTAssertEqual(Array(texts.prefix(4)), ["Fitness", "Watch", "미리 알림", "파일"], "reading order")
        XCTAssertEqual(ScreenshotLayoutImporter.match("미리 알림"), "sys.reminders")
        XCTAssertEqual(ScreenshotLayoutImporter.match("연락처"), "builtin.contacts")
        XCTAssertTrue(ScreenshotLayoutImporter.isLikelyFolder("유틸리티"))
        // The icon crop above "파일" should be mostly the white Files tile (bright), not wallpaper.
        let size = CGSize(width: image.cgImage!.width, height: image.cgImage!.height)
        let files = try XCTUnwrap(apps.first { $0.text == "파일" })
        let crop = try XCTUnwrap(ScreenshotLayoutImporter.crop(image, to: ScreenshotLayoutImporter.iconRect(above: files, imageSize: size)))
        XCTAssertGreaterThan(crop.averageBrightness, 0.6)
    }

    func testCatalogHasNoDuplicateNames() {
        let names = AppCatalog.externalApps.map { ScreenshotLayoutImporter.normalize($0.nameKo) }
        XCTAssertEqual(Set(names).count, names.count)
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
        for app in AppCatalog.externalApps where app.isSystem != true {
            guard let scheme = app.scheme, let s = URL(string: scheme)?.scheme else { continue }
            XCTAssertTrue(declared.contains(s), "\(s) missing from LSApplicationQueriesSchemes")
        }
        XCTAssertLessThanOrEqual(declared.count, 50, "iOS limits query schemes to 50")
        XCTAssertEqual(Set(declared), Set(AppCatalog.probedSchemes), "probe list matches Info.plist")
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

private extension UIImage {
    var averageBrightness: CGFloat {
        guard let cg = cgImage else { return 0 }
        let w = 16, h = 16
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for i in stride(from: 0, to: px.count, by: 4) { sum += (Double(px[i]) + Double(px[i + 1]) + Double(px[i + 2])) / 3 }
        return CGFloat(sum / Double(w * h) / 255)
    }
}
