import XCTest

final class AddBoxFromMenuUITests: MadeUITestCase {
    func testAddBoxAppearsInNavigatorAndInspector() throws {
        let app = launchApp(extraArguments: ["--force-no-gpu"])

        let metalUnavailableHeading = app.staticTexts["Metal Unavailable"]
        XCTAssertTrue(metalUnavailableHeading.waitForExistence(timeout: 5.0), "Expected 'Metal Unavailable' heading in viewport")

        let metalUnavailableStatus = app.staticTexts["Metal unavailable"]
        XCTAssertTrue(metalUnavailableStatus.waitForExistence(timeout: 5.0), "Expected 'Metal unavailable' in status bar")

        let solidMenuBarItem = app.menuBars.menuBarItems["Solid"]
        XCTAssertTrue(solidMenuBarItem.waitForExistence(timeout: 5.0), "Expected 'Solid' menu bar item")
        solidMenuBarItem.click()

        let addBoxMenuItem = solidMenuBarItem.menus.menuItems["Add Box Solid"]
        if addBoxMenuItem.waitForExistence(timeout: 5.0) {
            addBoxMenuItem.click()
        } else {
            let fallbackItem = app.menuItems["Add Box Solid"]
            XCTAssertTrue(fallbackItem.waitForExistence(timeout: 5.0), "Expected 'Add Box Solid' menu item")
            fallbackItem.click()
        }

        let navigatorRow = app.descendants(matching: .any)["navigator-object-box-2"]
        XCTAssertTrue(navigatorRow.waitForExistence(timeout: 5.0), "Expected 'navigator-object-box-2' in Navigator")
        let rowLabel = (!navigatorRow.label.isEmpty ? navigatorRow.label : (navigatorRow.value as? String)) ?? ""
        XCTAssertTrue(rowLabel.contains("box-2"), "Expected navigator row label to contain 'box-2', got: \(rowLabel)")
        XCTAssertFalse(rowLabel.contains("Error"), "Expected navigator row label not to contain 'Error', got: \(rowLabel)")
        XCTAssertFalse(rowLabel.contains("Warning"), "Expected navigator row label not to contain 'Warning', got: \(rowLabel)")

        let inspectorSelected = app.descendants(matching: .any)["inspector-selected-object"]
        XCTAssertTrue(inspectorSelected.waitForExistence(timeout: 5.0), "Expected 'inspector-selected-object' in Inspector")
        let inspectorValue = (inspectorSelected.value as? String) ?? inspectorSelected.label
        XCTAssertTrue(inspectorValue == "box-2" || inspectorSelected.label == "box-2", "Expected inspector object ID to be 'box-2', got label '\(inspectorSelected.label)', value '\(String(describing: inspectorSelected.value))'")
    }
}
