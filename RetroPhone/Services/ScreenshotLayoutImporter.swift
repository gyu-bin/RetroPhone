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

// MARK: - Grid-fitted analysis (v3)

extension ScreenshotLayoutImporter {
    /// iOS home-screen grid fitted to one screenshot (normalized coordinates).
    struct GridModel: Equatable {
        var colX0: CGFloat          // center x of column 0
        var colPitch: CGFloat       // distance between column centers
        var rowY0: CGFloat          // label center y of row 0
        var rowPitch: CGFloat       // distance between label rows
        var rows: Int
        var aspect: CGFloat         // image width / height

        func colX(_ c: CGFloat) -> CGFloat { colX0 + c * colPitch }
        func rowY(_ r: Int) -> CGFloat { rowY0 + CGFloat(r) * rowPitch }
        /// Icon side in normalized *width* units.
        var iconSide: CGFloat { colPitch * 0.68 }
    }

    enum EntryKind: Equatable {
        case app(text: String, match: AppID?)
        case widget(kind: WidgetKind?, size: WidgetSize, text: String)
        /// A filled grid cell whose label couldn't be read (typically a folder named with emoji).
        case unlabeled
    }

    struct Entry: Equatable {
        var row: Int
        var col: Int
        var kind: EntryKind
    }

    struct HomeAnalysis: Equatable {
        var grid: GridModel
        var entries: [Entry]   // ordered by (row, col) of the top-left cell
    }

    static let widgetNames: [String: WidgetKind] = {
        var m: [String: WidgetKind] = [:]
        let pairs: [(String, WidgetKind)] = [
            ("날씨", .weather), ("weather", .weather), ("배터리", .battery), ("batteries", .battery), ("battery", .battery),
            ("캘린더", .calendar), ("calendar", .calendar), ("시계", .analogClock), ("clock", .analogClock),
            ("사진", .photo), ("photos", .photo), ("메모", .notes), ("notes", .notes), ("음악", .music), ("music", .music),
        ]
        for (k, v) in pairs { m[normalize(k)] = v }
        return m
    }()

    /// Fits the 4-column grid to the labels that look like app/widget labels, finds widgets from their
    /// name labels (centered between columns), and marks filled cells without a readable label.
    static func analyzeHome(_ all: [Label], aspect: CGFloat, dockTop: CGFloat = 0.87) -> HomeAnalysis {
        // 1. Plausible label candidates.
        let candidates = all.filter { l in
            let t = l.text.trimmingCharacters(in: .whitespaces)
            guard (1...16).contains(t.count), l.center.y > 0.05, l.center.y < dockTop, l.box.width < 0.3 else { return false }
            if ["검색", "search"].contains(t.lowercased()) || t.contains("°") { return false }
            if t.range(of: #"^[0-9:%\s.,+-]+$"#, options: .regularExpression) != nil { return false }
            return true
        }
        // 2. Anchors: known app names or known widget names.
        var model = GridModel(colX0: 0.159, colPitch: 0.227, rowY0: 0.19, rowPitch: 0.227 * aspect * 1.08, rows: 6, aspect: aspect)
        func colIndex(_ x: CGFloat, _ m: GridModel) -> CGFloat { ((x - m.colX0) / m.colPitch * 2).rounded() / 2 }
        let anchors = candidates.filter { match($0.text) != nil || widgetNames[normalize($0.text)] != nil }
        let colPoints = anchors.map { (colIndex($0.center.x, model), $0.center.x) }.filter { (0...3).contains($0.0) }
        if Set(colPoints.map(\.0)).count >= 2 {
            // Least squares x = a + idx·b
            let n = CGFloat(colPoints.count)
            let sx = colPoints.reduce(0) { $0 + $1.0 }, sy = colPoints.reduce(0) { $0 + $1.1 }
            let sxx = colPoints.reduce(0) { $0 + $1.0 * $1.0 }, sxy = colPoints.reduce(0) { $0 + $1.0 * $1.1 }
            let b = (n * sxy - sx * sy) / max(0.0001, n * sxx - sx * sx)
            if b > 0.15 && b < 0.32 { model.colPitch = b; model.colX0 = (sy - b * sx) / n }
        }
        model.rowPitch = model.colPitch * aspect * 1.08
        // 3. Rows: anchor label rows relative to the top-most anchor.
        let anchorYs = anchors.map(\.center.y).sorted()
        guard let topY = anchorYs.first else { return HomeAnalysis(grid: model, entries: []) }
        func rowIndex(_ y: CGFloat) -> Int { Int(((y - topY) / model.rowPitch).rounded()) }

        // 4. Classify anchors into apps (integer column) and widgets (half column / known widget names).
        struct Raw { var row: Int; var colIdx: CGFloat; var label: Label }
        var raws: [Raw] = []
        for a in candidates {
            let ci = colIndex(a.center.x, model)
            guard (0...3).contains(ci) else { continue }
            let ri = rowIndex(a.center.y)
            // Must sit on a label row (rejects wallpaper text, badge digits, widget content).
            let yErr = abs(a.center.y - (topY + CGFloat(ri) * model.rowPitch))
            guard yErr < model.rowPitch * 0.12, abs(a.center.x - model.colX(ci)) < model.colPitch * 0.18 else { continue }
            raws.append(Raw(row: ri, colIdx: ci, label: a))
        }
        // Widgets first, so their bodies can exclude text inside them.
        var occupied = [[Bool]](repeating: [Bool](repeating: false, count: 4), count: 32)
        var entries: [Entry] = []
        var widgetRects: [(rows: ClosedRange<Int>, cols: ClosedRange<Int>)] = []
        let rowShift = 8 // allow widgets to start above the top anchor row
        for r in raws where r.colIdx != r.colIdx.rounded(.down) || r.colIdx == 1.5 {
            let isWide = r.colIdx == 1.5
            let cols = isWide ? 0...3 : Int(r.colIdx - 0.5)...Int(r.colIdx + 0.5)
            guard cols.lowerBound >= 0, cols.upperBound <= 3 else { continue }
            var span = 2
            if isWide, r.row - 3 >= -rowShift + 0 {
                // 4×4 if the two rows above the usual 4×2 body hold nothing else.
                let above = raws.contains { $0.row == r.row - 2 || $0.row == r.row - 3 }
                if !above && r.row >= 3 { span = 4 }
            }
            let rows = (r.row - span + 1)...r.row
            if widgetRects.contains(where: { $0.rows.overlaps(rows) && $0.cols.overlaps(cols) }) { continue }
            widgetRects.append((rows, cols))
            let size: WidgetSize = isWide ? (span == 4 ? .large : .wide) : .small
            entries.append(Entry(row: rows.lowerBound, col: cols.lowerBound,
                                 kind: .widget(kind: widgetNames[normalize(r.label.text)], size: size, text: r.label.text)))
        }
        func inWidget(_ row: Int, _ col: Int) -> Bool { widgetRects.contains { $0.rows.contains(row) && $0.cols.contains(col) } }
        for r in raws where r.colIdx == r.colIdx.rounded(.down) && r.colIdx != 1.5 {
            let col = Int(r.colIdx)
            guard !inWidget(r.row, col), !entries.contains(where: { $0.row == r.row && $0.col == col }) else { continue }
            entries.append(Entry(row: r.row, col: col, kind: .app(text: r.label.text, match: match(r.label.text))))
        }
        // 5. Normalize rows so the top-most item starts at row 0, then compute the grid extent.
        let minRow = entries.map(\.row).min() ?? 0
        for i in entries.indices { entries[i].row -= minRow }
        widgetRects = widgetRects.map { (($0.rows.lowerBound - minRow)...($0.rows.upperBound - minRow), $0.cols) }
        model.rowY0 = topY + CGFloat(minRow) * model.rowPitch
        var rowCount = 0
        while rowCount < 7 && model.rowY(rowCount) < dockTop { rowCount += 1 }
        model.rows = max(rowCount, (entries.map(\.row).max() ?? 0) + 1)
        // 6. Filled cells without a readable label (emoji-named folders, icon-only labels).
        for row in 0..<model.rows {
            for col in 0..<4 {
                let covered = widgetRects.contains { $0.rows.contains(row) && $0.cols.contains(col) }
                    || entries.contains { $0.row == row && $0.col == col }
                if !covered { entries.append(Entry(row: row, col: col, kind: .unlabeled)) }
            }
        }
        _ = occupied
        occupied.removeAll()
        entries.sort { ($0.row, $0.col) < ($1.row, $1.col) }
        return HomeAnalysis(grid: model, entries: entries)
    }

    /// Pixel rect of the icon in a grid cell (inset so the original rounded corners are cut away).
    static func cellIconRect(_ grid: GridModel, row: Int, col: Int, imageSize: CGSize) -> CGRect {
        let side = grid.iconSide * imageSize.width
        let cx = grid.colX(CGFloat(col)) * imageSize.width
        let labelY = grid.rowY(row) * imageSize.height
        let cy = labelY - 0.032 * imageSize.width - side / 2 - 0.006 * imageSize.height
        return CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
            .insetBy(dx: side * 0.1, dy: side * 0.1).integral
    }

    /// 0…1 "something is drawn here" score for a crop: colorfulness + local contrast. Wallpaper areas
    /// score low; icons and folder tiles (with their colorful mini-icons) score high.
    static func busyness(_ image: UIImage) -> CGFloat {
        guard let cg = image.cgImage else { return 0 }
        let w = 24, h = 24
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var chroma = 0.0, lum: [Double] = []
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            chroma += max(r, g, b) - min(r, g, b)
            lum.append(0.299 * r + 0.587 * g + 0.114 * b)
        }
        let mean = lum.reduce(0, +) / Double(lum.count)
        let sd = (lum.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lum.count)).squareRoot()
        return CGFloat(min(1, (chroma / Double(w * h)) / 120 + sd / 160))
    }
}
