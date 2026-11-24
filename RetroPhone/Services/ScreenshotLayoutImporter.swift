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
                    return Label(text: text, center: CGPoint(x: b.midX, y: 1 - b.midY))
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
        }
        map[normalize("Instagram")] = "ext.instagram"
        map[normalize("네이버지도")] = "ext.navermap"
        map[normalize("naver")] = "ext.naver"
        return map
    }()

    static func normalize(_ s: String) -> String {
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
