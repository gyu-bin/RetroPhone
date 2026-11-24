import XCTest

/// Captures screenshots of the main screens as test attachments. Runs only when RP_SCREENSHOTS=1:
///   TEST_RUNNER_RP_SCREENSHOTS=1 xcodebuild test … -resultBundlePath build/Tour.xcresult -only-testing:RetroPhoneUITests/ScreenshotTour
///   xcrun xcresulttool export attachments --path build/Tour.xcresult --output-path docs/screenshots
final class ScreenshotTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["RP_SCREENSHOTS"] == "1" else {
            throw XCTSkip("RP_SCREENSHOTS not set")
        }
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetState", "-skipSetup", "-language", "ko"]
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Dismiss iOS permission prompts conservatively ("Don't Allow").
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<2 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1) else { return }
            let deny = alert.buttons["허용 안 함"].firstMatch
            let denyEN = alert.buttons["Don’t Allow"].firstMatch
            if deny.exists { deny.tap() }
            else if denyEN.exists { denyEN.tap() }
            else { alert.buttons.element(boundBy: alert.buttons.count - 1).tap() }
        }
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func home() {
        let button = element("homeButton")
        if button.exists { button.tap() }
        sleep(1)
    }

    func testTour() {
        shot("01-lock")
        let slider = element("unlockSlider")
        XCTAssertTrue(slider.waitForExistence(timeout: 6))
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)))
        sleep(1)
        shot("02-home")

        let apps: [(String, String)] = [
            ("builtin.phone", "10-phone"), ("builtin.messages", "11-messages"), ("builtin.contacts", "12-contacts"),
            ("builtin.calendar", "13-calendar"), ("builtin.clock", "14-clock"), ("builtin.photos", "15-photos"),
            ("builtin.camera", "16-camera"), ("builtin.music", "17-music"), ("builtin.voiceMemos", "18-voice-memos"),
            ("builtin.browser", "19-browser"), ("builtin.notes", "20-notes"), ("builtin.weather", "21-weather"),
            ("builtin.calculator", "22-calculator"), ("builtin.maps", "23-maps"), ("builtin.settings", "24-settings"),
        ]
        for (id, name) in apps {
            let icon = element("icon.\(id)")
            guard icon.waitForExistence(timeout: 3) else { continue }
            icon.tap()
            sleep(2)
            dismissSystemAlerts()
            shot(name)
            home()
            dismissSystemAlerts()
        }

        // Multitasking tray (double press of the virtual home button)
        element("homeButton").doubleTap()
        shot("30-multitasking")
        home()

        // Edit mode
        let notes = element("icon.builtin.notes")
        if notes.waitForExistence(timeout: 3) {
            notes.press(forDuration: 1.2)
            shot("31-edit-mode")
            element("homeAddButton").tap()
            shot("32-add-to-home")
        }
    }
}
