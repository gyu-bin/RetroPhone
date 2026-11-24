import XCTest

final class RetroPhoneUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetState", "-skipSetup", "-language", "ko"]
        app.launch()
    }

    private func unlock() {
        let knob = app.otherElements["unlockKnob"].firstMatch
        XCTAssertTrue(knob.waitForExistence(timeout: 5), "lock screen slider visible")
        let start = knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 320, dy: 0))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func testSlideToUnlockShowsHomeScreen() {
        unlock()
        XCTAssertTrue(app.otherElements["homeScreen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["icon.builtin.settings"].waitForExistence(timeout: 3) || app.otherElements["icon.builtin.settings"].exists)
    }

    func testOpenAppAndReturnWithHomeButton() {
        unlock()
        let settingsIcon = app.descendants(matching: .any)["icon.builtin.settings"].firstMatch
        XCTAssertTrue(settingsIcon.waitForExistence(timeout: 5))
        settingsIcon.tap()
        XCTAssertTrue(app.staticTexts["설정"].waitForExistence(timeout: 5))
        let home = app.descendants(matching: .any)["homeButton"].firstMatch
        XCTAssertTrue(home.exists)
        home.tap()
        sleep(1)
        XCTAssertTrue(settingsIcon.waitForExistence(timeout: 5))
    }

    func testLongPressEntersEditMode() {
        unlock()
        let icon = app.descendants(matching: .any)["icon.builtin.notes"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        icon.press(forDuration: 1.2)
        XCTAssertTrue(app.descendants(matching: .any)["homeDoneButton"].firstMatch.waitForExistence(timeout: 3))
        app.descendants(matching: .any)["homeDoneButton"].firstMatch.tap()
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
