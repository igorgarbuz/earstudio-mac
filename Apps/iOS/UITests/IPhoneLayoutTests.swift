import XCTest

/// Run on a compact iPhone and a larger iPhone. Screenshots are retained in the
/// test result bundle for visual review; no Bluetooth hardware is required.
@MainActor
final class IPhoneLayoutTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testDisconnectedControlsRequireConnection() {
        launch()
        XCTAssertFalse(app.buttons["device.demo"].exists)
        XCTAssertFalse(app.buttons["demo.exit"].exists)
        XCTAssertFalse(app.staticTexts["Explore without a device"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Launching must not show a device authorization prompt.")
        XCTAssertEqual(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.count, 0,
                       "Launching must not request Bluetooth permission before the user chooses Find EarStudio.")
        let status = app.staticTexts["Not connected"]
        XCTAssertTrue(status.exists)
        let card = app.collectionViews.cells.firstMatch
        XCTAssertTrue(card.exists)
        XCTAssertLessThan(card.frame.height, 360, "Disconnected card must stay content-sized.")
        XCTAssertLessThan(status.frame.maxY, card.frame.maxY)
        XCTAssertTrue(app.buttons["device.connect"].isHittable)
        capture("device-disconnected-portrait")

        tab("Equalizer")
        let enabled = app.switches["eq.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        XCTAssertFalse(enabled.isEnabled)
        capture("equalizer-disconnected-portrait")

    }

    func testDebugDemoLaunchEnablesControlsWithoutPublicDemoUI() {
        launch(demo: true, tab: "equalizer")
        let enabled = app.switches["eq.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertFalse(app.buttons["demo.exit"].exists)
        tab("Device")
        XCTAssertFalse(app.buttons["device.demo"].exists)
        XCTAssertTrue(app.buttons["device.connect"].exists)
        let card = app.collectionViews.cells.firstMatch
        XCTAssertLessThan(card.frame.height, 360, "Battery status must not stretch the device card.")
        XCTAssertTrue(app.staticTexts["Demo mode"].exists)
        let battery = app.descendants(matching: .any).matching(identifier: "device.battery").firstMatch
        XCTAssertTrue(battery.exists)
        XCTAssertEqual(battery.value as? String, "82 percent")
        capture("device-demo-battery")
    }

    func testAllTenBandsAreReachableAndPresetCanBeSaved() {
        launch(demo: true, tab: "equalizer")
        XCTAssertTrue(app.switches["eq.enabled"].waitForExistence(timeout: 5))
        capture("equalizer-demo-portrait")

        for index in 0..<10 {
            let band = app.sliders["eq.band.\(index)"]
            reveal(band)
            assertControlFits(band)
            let curve = app.descendants(matching: .any).matching(identifier: "eq.curve").firstMatch
            XCTAssertTrue(curve.exists)
            XCTAssertGreaterThanOrEqual(curve.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1)
            XCTAssertLessThanOrEqual(curve.frame.maxY, band.frame.minY,
                                     "The curve must stay visible above the band being adjusted.")
            if index == 0 {
                band.adjust(toNormalizedSliderPosition: 0.65)
                capture("equalizer-first-band-portrait")
            } else if index == 9 {
                band.adjust(toNormalizedSliderPosition: 0.40)
                capture("equalizer-last-band-portrait")
            }
        }

        let presets = app.buttons["eq.presets"]
        reveal(presets, direction: .down)
        presets.tap()
        let save = app.buttons["presets.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let alert = app.alerts["Save preset"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let name = alert.textFields.firstMatch
        name.tap()
        if let existing = name.value as? String, existing != "Preset name" {
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        name.typeText("Phone layout test")
        // SwiftUI alerts expose a container and nested button with the same ID.
        alert.buttons.matching(identifier: "presets.confirm").firstMatch.tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Phone layout test")).firstMatch
        reveal(saved)
        XCTAssertTrue(saved.isHittable)
        capture("presets-saved-portrait")
    }

    func testLandscapeKeepsTabsAndSettingsReachable() {
        launch(demo: true, tab: "equalizer")
        XCTAssertTrue(app.switches["eq.enabled"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        let first = app.sliders["eq.band.0"]
        reveal(first)
        assertControlFits(first)
        capture("equalizer-demo-landscape")
        tab("Settings")
        let sound = app.buttons["settings.sound"]
        reveal(sound)
        sound.tap()
        let crossfeed = app.sliders["slider.Crossfeed"]
        reveal(crossfeed)
        assertControlFits(crossfeed)
        capture("sound-settings-landscape")
    }

    func testLargestAccessibilityTextStillAllowsBandAndSettingsNavigation() {
        launch(demo: true, tab: "equalizer", accessibilityText: true)
        XCTAssertTrue(app.switches["eq.enabled"].waitForExistence(timeout: 5))
        capture("equalizer-accessibility-text-top")
        let first = app.sliders["eq.band.0"]
        reveal(first)
        assertControlFits(first)
        capture("equalizer-accessibility-text-band")
        let last = app.sliders["eq.band.9"]
        reveal(last)
        assertControlFits(last)
        capture("equalizer-accessibility-text-last-band")
        tab("Settings")
        let sound = app.buttons["settings.sound"]
        reveal(sound)
        assertControlFits(sound)
        capture("settings-accessibility-text")
        sound.tap()
        let crossfeed = app.sliders["slider.Crossfeed"]
        reveal(crossfeed)
        assertControlFits(crossfeed)
        capture("sound-accessibility-text")
    }

    private func launch(demo: Bool = false, tab: String = "device", accessibilityText: Bool = false) {
        app.launchArguments = ["--ui-testing", "--screenshot-tab=\(tab)"]
        if demo { app.launchArguments.append("--demo") }
        if accessibilityText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Device"].waitForExistence(timeout: 10))
    }

    private func tab(_ label: String) {
        let button = app.tabBars.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable, "The \(label) tab must stay reachable.")
        button.tap()
    }

    private enum ScrollDirection { case up, down }

    private func reveal(_ element: XCUIElement, direction: ScrollDirection = .up,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<40 {
            let list = app.collectionViews.firstMatch
            let scroll = list.exists ? list : app.scrollViews.firstMatch
            let surface = scroll.exists ? scroll : app!
            var viewport = surface.frame.intersection(app.frame)
            let navigation = app.navigationBars.firstMatch
            let tabs = app.tabBars.firstMatch
            var top = navigation.exists ? max(viewport.minY, navigation.frame.maxY) : viewport.minY
            let curve = app.descendants(matching: .any).matching(identifier: "eq.curve").firstMatch
            if element.exists && element.elementType == .slider && curve.exists && curve.frame.minY <= top + 1 {
                top = max(top, curve.frame.maxY)
            }
            let bottom = tabs.exists ? min(viewport.maxY, tabs.frame.minY) : viewport.maxY
            viewport = CGRect(x: viewport.minX, y: top + 6,
                              width: viewport.width, height: max(1, bottom - top - 12))

            var nextDirection = direction
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.minY >= viewport.minY && frame.maxY <= viewport.maxY { return }
                // A large flick can jump past the target, especially in landscape.
                // Correct direction from the target's geometry rather than continuing
                // toward the end of the list forever.
                if frame.width > 0 && frame.height > 0 {
                    if frame.minY < viewport.minY { nextDirection = .down }
                    else if frame.maxY > viewport.maxY { nextDirection = .up }
                }
            }
            // A native slider can consume a vertical swipe started on its thumb.
            // Drag from the List's leading gutter with a modest distance and no
            // momentum, keeping the gesture clear of navigation and the tab bar.
            // Landscape on a notched phone adds a side safe area. Derive the
            // gutter from an actual row, since the collection spans that margin.
            let cell = list.cells.firstMatch
            let leading = list.exists && cell.exists ? cell.frame.minX : viewport.minX
            let x = min(viewport.maxX - 8, max(viewport.minX, leading) + 8)
            let low = viewport.minY + viewport.height * 0.72
            let high = viewport.minY + viewport.height * 0.28
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: x - app.frame.minX,
                                                   dy: (nextDirection == .up ? low : high) - app.frame.minY))
            let finish = origin.withOffset(CGVector(dx: x - app.frame.minX,
                                                    dy: (nextDirection == .up ? high : low) - app.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        capture("unreachable-\(element.identifier)")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Hierarchy for unreachable \(element.identifier)"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("Control was not reachable by scrolling: \(element)", file: file, line: line)
    }

    private func assertControlFits(_ element: XCUIElement,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.isHittable, file: file, line: line)
        let frame = element.frame
        let screen = app.frame
        // UIKit reports the native UISlider's 31-point accessibility frame even
        // when SwiftUI allocates a 44-point touch area. Check its identified
        // layout row rather than mistaking the thumb's frame for the layout.
        let layoutElement: XCUIElement
        if element.elementType == .slider {
            let rowID = "row.\(element.identifier)"
            let other = app.otherElements[rowID]
            layoutElement = other.exists ? other : app.descendants(matching: .any).matching(identifier: rowID).firstMatch
        } else {
            layoutElement = element
        }
        XCTAssertTrue(layoutElement.exists, "The control needs an identifiable layout container.", file: file, line: line)
        XCTAssertGreaterThanOrEqual(layoutElement.frame.height, 44,
                                   "Control layout must reserve at least 44 points vertically.", file: file, line: line)
        XCTAssertGreaterThanOrEqual(layoutElement.frame.minX, screen.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(layoutElement.frame.maxX, screen.maxX,
                                 "The control's labels or layout row extend beyond the screen.", file: file, line: line)
        XCTAssertGreaterThan(frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX, "Control extends beyond the iPhone screen.", file: file, line: line)
    }

    private func capture(_ name: String) {
        // Whole-screen capture avoids XCUIApplication's stale portrait crop
        // after rotation on recent iOS Simulator runtimes.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
