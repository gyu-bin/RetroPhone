import Foundation
import Vision
import UIKit

/// Builds a draft home layout from a screenshot of the user's real iOS home screen, using
/// on-device text recognition (Vision). Only app *labels* can be read — icons, folders' contents
/// and widgets are not recognized — so the result is always a draft the user confirms and edits.
enum ScreenshotLayoutImporter {
    struct Label: Equatable {
        var text: String
        /// Normalized center (0...1, origin top-left).
        var center: CGPoint
        /// Normalized bounding box (origin top-left). Zero when unknown.
        var box: CGRect = .zero
    }

    struct Draft: Equatable {
        var pageApps: [AppID]
        var dockApps: [AppID]
        var unmatched: [String]
    }

    /// Runs OCR on-device. No image data leaves the device.
    static func recognizeLabels(in image: UIImage) async throws -> [Label] {
        guard let cg = image.cgImage else { return [] }
        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, error in
                if let error { cont.resume(throwing: error); return }
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let labels = obs.compactMap { o -> Label? in
                    guard let text = o.topCandidates(1).first?.string else { return nil }
                    let b = o.boundingBox
                    return Label(text: text, center: CGPoint(x: b.midX, y: 1 - b.midY),
                                 box: CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
                }
                cont.resume(returning: labels)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .init(image.imageOrientation))
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) } catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Known label spellings → app. Includes common iOS system app names mapped to RetroPhone equivalents.
    static let aliases: [String: AppID] = {
        var map: [String: AppID] = [:]
        for b in BuiltinApp.allCases {
            map[normalize(b.nameKo)] = b.appID
            if let en = EnglishTable.core[b.nameKo] { map[normalize(en)] = b.appID }
        }
        let extra: [String: String] = [
            "safari": "builtin.browser", "사파리": "builtin.browser",
            "설정": "builtin.settings", "settings": "builtin.settings",
            "음성메모": "builtin.voiceMemos", "voicememos": "builtin.voiceMemos",
            "facetime": "builtin.phone",
        ]
        for (k, v) in extra { map[normalize(k)] = AppID(v) }
        for ext in AppCatalog.externalApps {
            map[normalize(ext.nameKo)] = ext.id
            map[normalize(ext.nameEn)] = ext.id
            for a in ext.aliases ?? [] { map[normalize(a)] = ext.id }
        }
        // Apple apps that RetroPhone re-implements map to the classic versions.
        let classic: [String: String] = [
            "메시지": "builtin.messages", "messages": "builtin.messages", "전화": "builtin.phone", "phone": "builtin.phone",
            "사진": "builtin.photos", "photos": "builtin.photos", "카메라": "builtin.camera", "camera": "builtin.camera",
            "캘린더": "builtin.calendar", "calendar": "builtin.calendar", "시계": "builtin.clock", "clock": "builtin.clock",
            "날씨": "builtin.weather", "weather": "builtin.weather", "지도": "builtin.maps", "maps": "builtin.maps",
            "메모": "builtin.notes", "notes": "builtin.notes", "계산기": "builtin.calculator", "calculator": "builtin.calculator",
            "음악": "builtin.music", "music": "builtin.music", "연락처": "builtin.contacts", "contacts": "builtin.contacts",
            "음성메모": "builtin.voiceMemos", "voicememos": "builtin.voiceMemos", "safari": "builtin.browser",
            "설정": "builtin.settings", "settings": "builtin.settings",
        ]
        for (k, v) in classic { map[normalize(k)] = AppID(v) }
        map[normalize("Instagram")] = "ext.instagram"
        map[normalize("네이버지도")] = "ext.navermap"
        map[normalize("naver")] = "ext.naver"
        return map
    }()

    // MARK: - Home screen import v2 (multi-page, icon crops)

    /// Approximate horizontal centers of the 4 icon columns on a modern iPhone home screen (normalized).
    static let columnCenters: [CGFloat] = [0.159, 0.386, 0.614, 0.841]
    /// Icon side relative to screenshot width (≈62 pt on a 402 pt-wide screen).
    static let iconWidthRatio: CGFloat = 0.155

    /// Keeps only labels that sit where app/folder labels sit: under one of the 4 columns, short, and
    /// outside the status bar / dock band. Drops widget text, the "Search" pill, times and temperatures.
    static func appLabels(_ labels: [Label], dockBand: CGFloat = 0.13) -> [Label] {
        labels.filter { l in
            let t = l.text.trimmingCharacters(in: .whitespaces)
            guard t.count >= 1, t.count <= 16, l.center.y > 0.08, l.center.y < 1 - dockBand else { return false }
            guard !["검색", "search", "Search"].contains(t) else { return false }
            if t.range(of: #"^[0-9:°%\s.,+-]+$"#, options: .regularExpression) != nil { return false }
            if t.contains("°") { return false }
            if l.box.width > 0.27 { return false }
            return columnCenters.contains { abs($0 - l.center.x) < 0.075 }
        }
        .sorted { a, b in abs(a.center.y - b.center.y) < 0.025 ? a.center.x < b.center.x : a.center.y < b.center.y }
    }

    /// Square crop (in pixels) of the icon sitting above a label, inset so the original rounded corners
    /// (and wallpaper behind them) are cut away.
    static func iconRect(above label: Label, imageSize: CGSize) -> CGRect {
        let side = iconWidthRatio * imageSize.width
        let gap = 0.014 * imageSize.width
        let labelTop = (label.box == .zero ? label.center.y - 0.01 : label.box.minY) * imageSize.height
        let rect = CGRect(x: label.center.x * imageSize.width - side / 2, y: labelTop - gap - side, width: side, height: side)
        return rect.insetBy(dx: side * 0.1, dy: side * 0.1).integral
    }

    /// The dock strip (bottom band) of a home-screen screenshot. iOS 26+ docks have no labels and a
    /// variable number of centered icons, so the user assigns dock apps while looking at this strip.
    static func dockStripRect(imageSize: CGSize) -> CGRect {
        CGRect(x: 0, y: imageSize.height * 0.855, width: imageSize.width, height: imageSize.height * 0.12).integral
    }

    static let folderNames: Set<String> = Set([
        "유틸리티", "소셜", "생산성", "엔터테인먼트", "금융", "쇼핑", "여행", "게임", "교육", "사진및비디오", "건강및피트니스",
        "음식및음료", "뉴스", "정보및도서", "비즈니스", "라이프스타일", "스포츠", "내비게이션", "도구", "기타", "추가", "폴더",
        "utilities", "social", "productivity", "entertainment", "finance", "shopping", "travel", "games", "education",
        "photo&video", "health&fitness", "food&drink", "news", "business", "lifestyle", "sports", "navigation", "other",
    ].map(normalize))

    static func isLikelyFolder(_ text: String) -> Bool {
        let n = normalize(text)
        return folderNames.contains(n) || text.unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }

    static func match(_ text: String) -> AppID? { aliases[normalize(text)] }

    static func crop(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let r = rect.intersection(bounds)
        guard r.width > 8, r.height > 8, let piece = cg.cropping(to: r) else { return nil }
        return UIImage(cgImage: piece)
    }

    nonisolated static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && $0 != "·" && $0 != "." }
    }

    /// Pure layout reconstruction (unit-tested).
    /// - Labels in the bottom `dockBand` of the screen are treated as dock apps.
    /// - The top status-bar area is ignored (time, battery %).
    static func draft(from labels: [Label], dockBand: CGFloat = 0.14) -> Draft {
        let candidates = labels.filter { $0.center.y > 0.07 }
        // Reading order: group into rows by y (tolerance 3% of height), then sort by x.
        let sorted = candidates.sorted { $0.center.y < $1.center.y }
        var rows: [[Label]] = []
        for l in sorted {
            if let last = rows.last?.first, abs(last.center.y - l.center.y) < 0.03 { rows[rows.count - 1].append(l) }
            else { rows.append([l]) }
        }
        var page: [AppID] = [], dock: [AppID] = [], unmatched: [String] = []
        var seen = Set<AppID>()
        for row in rows {
            for l in row.sorted(by: { $0.center.x < $1.center.x }) {
                let key = normalize(l.text)
                guard key.count >= 2, key.rangeOfCharacter(from: .decimalDigits) == nil || key.count > 4 else { continue }
                if let app = aliases[key] {
                    guard !seen.contains(app) else { continue }
                    seen.insert(app)
                    if l.center.y > 1 - dockBand, dock.count < HomeLayout.dockCapacity { dock.append(app) } else { page.append(app) }
                } else if l.text.count <= 14 {
                    unmatched.append(l.text)
                }
            }
        }
        return Draft(pageApps: page, dockApps: dock, unmatched: unmatched)
    }

    /// Turns a confirmed draft into a layout (widgets page kept, unused built-ins appended).
    static func layout(from draft: Draft, base: HomeLayout = .default) -> HomeLayout {
        var l = base
        let dock = draft.dockApps.isEmpty ? base.dock : draft.dockApps
        l.dock = dock
        var first: [HomeItem] = draft.pageApps.filter { !dock.contains($0) }.map { HomeItem.app($0) }
        // Keep every built-in reachable.
        let placed = Set(first.compactMap(\.appID)).union(dock)
        first += BuiltinApp.allCases.map(\.appID).filter { !placed.contains($0) }.map { HomeItem.app($0) }
        l.pages = [first] + base.pages.filter { page in page.allSatisfy { $0.widget != nil } }
        l.normalize()
        return l
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up; case .down: self = .down; case .left: self = .left; case .right: self = .right
        case .upMirrored: self = .upMirrored; case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored; case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
