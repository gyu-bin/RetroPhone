import XCTest

/// Taps folders on a home screen built from the user's (git-ignored) screenshot.
/// Skipped when the private fixture isn't on this Mac.
final class ImportedHomeUITests: XCTestCase {
    func testImportedFolderOpens() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RetroPhoneTests/Fixtures/private/user-home.png").path
        guard FileManager.default.fileExists(atPath: fixture) else { throw XCTSkip("private fixture not present") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetState", "-skipSetup", "-language", "ko", "-importScreenshot", fixture]
        app.launch()
        let slider = app.descendants(matching: .any)["unlockSlider"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 8))
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5)))

        let folder = app.descendants(matching: .any)["folder.폴더 1"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10), "imported folder on the home screen")
        folder.tap()
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        // The open panel shows the folder name as a title (a second "폴더 1" text besides the icon label).
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "folderTitle").count, 1, "folder panel opened")
    }
}
