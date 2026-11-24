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
        let slider = app.descendants(matching: .any)["unlockSlider"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 8), "lock screen slider visible")
        // Grab the knob at the left end of the track and drag it all the way right.
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.5))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func testSlideToUnlockShowsHomeScreen() {
        unlock()
        XCTAssertTrue(app.descendants(matching: .any)["icon.builtin.settings"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["unlockSlider"].firstMatch.exists)
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

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testEditModeTapOpensIconEditor() {
        unlock()
        let notes = element("icon.builtin.notes")
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.press(forDuration: 1.2)                       // enter edit mode
        XCTAssertTrue(element("homeDoneButton").waitForExistence(timeout: 3))
        notes.tap()                                         // tap while editing → rename / icon sheet
        XCTAssertTrue(app.staticTexts["아이콘 편집"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("iconNameField").exists)
    }

    func testDragAppOntoAppCreatesFolderThatOpens() {
        unlock()
        let calendar = element("icon.builtin.calendar")
        let camera = element("icon.builtin.camera")
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        calendar.press(forDuration: 1.2)                    // enter edit mode
        XCTAssertTrue(element("homeDoneButton").waitForExistence(timeout: 3))
        // Drag the camera onto the calendar and hold until the folder forms.
        let from = camera.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let to = calendar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 1.2)
        sleep(1)
        let dots = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '페이지'")).firstMatch
        XCTAssertFalse(dots.label.hasSuffix("/3"), "drag finished (no extra drop page left over)")
        XCTAssertFalse(camera.exists, "camera moved into the folder")
        element("homeDoneButton").tap()
        sleep(1)
        let folder = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '앱 2개'")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 3), "folder icon on the home screen")
        folder.tap()
        XCTAssertTrue(element("icon.builtin.camera").waitForExistence(timeout: 3), "folder panel shows its apps")
    }

    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
