import XCTest
@testable import RetroPhone

/// Runs the home-screen importer on a personal screenshot kept in the git-ignored
/// `Fixtures/private/user-home.png`. Skipped when the file isn't present (e.g. in a fresh clone).
final class UserHomeImportTests: XCTestCase {
    func testUserHomeScreenLayout() async throws {
        guard let url = Bundle(for: Self.self).url(forResource: "user-home", withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else { throw XCTSkip("private fixture not present") }
        let size = CGSize(width: image.cgImage!.width, height: image.cgImage!.height)
        let labels = try await ScreenshotLayoutImporter.recognizeLabels(in: image)
        let analysis = ScreenshotLayoutImporter.analyzeHome(labels, aspect: size.width / size.height)
        for e in analysis.entries { print("RPENTRY r\(e.row) c\(e.col) \(e.kind)") }

        func entry(_ r: Int, _ c: Int) -> ScreenshotLayoutImporter.EntryKind? {
            analysis.entries.first { $0.row == r && $0.col == c }?.kind
        }
        XCTAssertEqual(entry(0, 0), .widget(kind: .weather, size: .wide, text: "날씨"))
        XCTAssertEqual(entry(2, 0), .widget(kind: .battery, size: .small, text: "배터리"))
        XCTAssertEqual(entry(3, 3), .app(text: "Instagram", match: "ext.instagram"))
        XCTAssertEqual(entry(4, 2), .widget(kind: .calendar, size: .small, text: "캘린더"))
        if case .app(let text, _)? = entry(5, 1) { XCTAssertEqual(text, "시온") } else { XCTFail("시온 missing") }
        // Six emoji-named folders whose labels OCR can't read.
        for (r, c) in [(2, 2), (2, 3), (3, 2), (4, 0), (4, 1), (5, 0)] {
            XCTAssertEqual(entry(r, c), .unlabeled, "folder at r\(r) c\(c)")
        }
        XCTAssertEqual(analysis.grid.rows, 6)
        XCTAssertEqual(analysis.entries.count, 11, "4 widgets/apps… exactly the items on the page, nothing from wallpaper text")

        // Folder tiles should look "busy" (mini icons); this decides their default include toggle.
        for (r, c) in [(2, 2), (4, 0)] {
            let crop = try XCTUnwrap(ScreenshotLayoutImporter.crop(image, to: ScreenshotLayoutImporter.cellIconRect(analysis.grid, row: r, col: c, imageSize: size)))
            XCTAssertGreaterThan(ScreenshotLayoutImporter.busyness(crop), 0.3, "folder r\(r) c\(c)")
        }
    }
}
