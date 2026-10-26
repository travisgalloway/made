import XCTest
import Metal

final class ViewportSelectionUITests: MadeUITestCase {
    private struct ProbeHit {
        let id: String
        let x: Double
        let y: Double
    }

    private struct ProbeSnapshot {
        let state: String
        let renders: Int
        let draws: Int
        let reason: String
        let selection: String
        let hits: [ProbeHit]

        static func parse(_ raw: String) -> ProbeSnapshot {
            var state = ""
            var renders = 0
            var draws = 0
            var reason = ""
            var selection = ""
            var hits: [ProbeHit] = []

            let components = raw.components(separatedBy: ";")
            for component in components {
                guard let eqIndex = component.firstIndex(of: "=") else { continue }
                let key = String(component[..<eqIndex])
                let value = String(component[component.index(after: eqIndex)...])
                switch key {
                case "state":
                    state = value
                case "renders":
                    renders = Int(value) ?? 0
                case "draws":
                    draws = Int(value) ?? 0
                case "reason":
                    reason = value
                case "selection":
                    selection = value
                case "hits":
                    if !value.isEmpty {
                        let hitItems = value.components(separatedBy: "|")
                        for item in hitItems {
                            guard let colonIndex = item.firstIndex(of: ":") else { continue }
                            let idStr = String(item[..<colonIndex])
                            let coordsStr = String(item[item.index(after: colonIndex)...])
                            let coords = coordsStr.components(separatedBy: ",")
                            if coords.count == 2,
                               let x = Double(coords[0]),
                               let y = Double(coords[1]) {
                                hits.append(ProbeHit(id: idStr, x: x, y: y))
                            }
                        }
                    }
                default:
                    break
                }
            }
            return ProbeSnapshot(
                state: state,
                renders: renders,
                draws: draws,
                reason: reason,
                selection: selection,
                hits: hits
            )
        }
    }

    func testClickSolidSelectsAndFollowsToNavigatorAndInspector() throws {
        let env = ProcessInfo.processInfo.environment
        let forceNoGPU = env["MADE_FORCE_NO_GPU"] == "1"
        let requireMetal4 = env["MADE_UI_REQUIRE_METAL4"] == "1"
        let isMetal4 = !forceNoGPU && (MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true)

        if requireMetal4 {
            XCTAssertTrue(isMetal4, "Metal 4 is required by MADE_UI_REQUIRE_METAL4=1")
        } else {
            try XCTSkipUnless(isMetal4, "Metal 4 is unavailable")
        }

        let app = launchApp()

        let canvas = app.descendants(matching: .any)["viewport-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10.0), "Expected 'viewport-canvas' in viewport")

        // Deselect initial selection by clicking empty space
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).click()

        // Assert probe reports selection= with empty value
        let initialProbeString = try XCTUnwrap(canvas.value as? String, "Missing probe value")
        let initialSnapshot = ProbeSnapshot.parse(initialProbeString)
        XCTAssertTrue(initialSnapshot.selection.isEmpty, "Expected empty selection after clicking background, got: '\(initialSnapshot.selection)'")

        // Parse probe hits and locate entry for box-1
        guard let boxHit = initialSnapshot.hits.first(where: { $0.id == "box-1" }) else {
            XCTFail("box-1 hit not found in probe hits: \(initialSnapshot.hits)")
            return
        }

        // Click box-1 at its normalized offset
        canvas.coordinate(withNormalizedOffset: CGVector(dx: boxHit.x, dy: boxHit.y)).click()

        // Assert Navigator row exists and is selected
        let navigatorRow = app.descendants(matching: .any)["navigator-object-box-1"]
        XCTAssertTrue(navigatorRow.waitForExistence(timeout: 5.0), "Expected 'navigator-object-box-1' in Navigator")
        XCTAssertTrue(navigatorRow.isSelected, "Expected navigator row to be selected")

        // Assert Inspector object ID shows box-1
        let inspectorSelected = app.descendants(matching: .any)["inspector-selected-object"]
        XCTAssertTrue(inspectorSelected.waitForExistence(timeout: 5.0), "Expected 'inspector-selected-object' in Inspector")
        let inspectorValue = (inspectorSelected.value as? String) ?? inspectorSelected.label
        XCTAssertTrue(inspectorValue == "box-1" || inspectorSelected.label == "box-1", "Expected inspector object ID to be 'box-1', got '\(inspectorValue)'")

        // Assert probe value contains selection=box-1
        let selectedProbeString = try XCTUnwrap(canvas.value as? String, "Missing probe value after click")
        let selectedSnapshot = ProbeSnapshot.parse(selectedProbeString)
        XCTAssertEqual(selectedSnapshot.selection, "box-1", "Expected probe selection to be 'box-1'")

        // Idle verification: read renders counter r1, sleep for 1.0 s, read r2, assert r1 == r2
        let r1 = ProbeSnapshot.parse(try XCTUnwrap(canvas.value as? String)).renders
        Thread.sleep(forTimeInterval: 1.0)
        let r2 = ProbeSnapshot.parse(try XCTUnwrap(canvas.value as? String)).renders
        XCTAssertEqual(r1, r2, "Invariant 2 violated: renderCount changed while idle (\(r1) -> \(r2))")

        // Click empty space at (0.05, 0.05) and assert probe reports selection= with empty value
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05)).click()
        let clearedProbeString = try XCTUnwrap(canvas.value as? String, "Missing probe value after background click")
        let clearedSnapshot = ProbeSnapshot.parse(clearedProbeString)
        XCTAssertTrue(clearedSnapshot.selection.isEmpty, "Expected selection to be cleared, got: '\(clearedSnapshot.selection)'")
    }

    func testSelectingCylinderThenBoxAndInspectorTabAlignment() throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        let forceNoGPU = env["MADE_FORCE_NO_GPU"] == "1"
        let requireMetal4 = env["MADE_UI_REQUIRE_METAL4"] == "1"
        let isMetal4 = !forceNoGPU && (MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true)

        if requireMetal4 {
            XCTAssertTrue(isMetal4, "Metal 4 is required by MADE_UI_REQUIRE_METAL4=1")
        } else {
            try XCTSkipUnless(isMetal4, "Metal 4 is unavailable")
        }

        let app = launchApp()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10.0), "Expected main window")

        let canvas = app.descendants(matching: .any)["viewport-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10.0), "Expected 'viewport-canvas' in viewport")

        // 1. Check Navigator & Inspector tab buttons via macOS Accessibility
        let sceneTab = app.buttons["Scene"]
        let constrTab = app.buttons["Construction"]
        let simTab = app.buttons["Simulation"]
        let attrTab = app.buttons["Attributes"]
        let metaTab = app.buttons["Metadata"]
        let physTab = app.buttons["Physical"]
        let docTab = app.buttons["Document"]
        XCTAssertTrue(sceneTab.waitForExistence(timeout: 5.0), "Expected 'Scene' tab button")
        XCTAssertTrue(constrTab.exists, "Expected 'Construction' tab button")
        XCTAssertTrue(simTab.exists, "Expected 'Simulation' tab button")
        XCTAssertTrue(attrTab.waitForExistence(timeout: 5.0), "Expected 'Attributes' tab button")
        XCTAssertTrue(metaTab.exists, "Expected 'Metadata' tab button")
        XCTAssertTrue(physTab.exists, "Expected 'Physical' tab button")
        XCTAssertTrue(docTab.exists, "Expected 'Document' tab button")

        let winFrame = window.frame
        let canvasFrame = canvas.frame
        let sceneFrame = sceneTab.frame
        let attrFrame = attrTab.frame
        let metaFrame = metaTab.frame
        let physFrame = physTab.frame
        let docFrame = docTab.frame
        print("AX_FRAMES window=\(winFrame) canvas=\(canvasFrame) scene=\(sceneFrame) attr=\(attrFrame) meta=\(metaFrame) phys=\(physFrame) doc=\(docFrame)")

        // All 4 Inspector tabs must be horizontally inside the Inspector column (to the right of canvas, inside window)
        XCTAssertGreaterThanOrEqual(attrFrame.minX, canvasFrame.maxX - 2.0, "Attributes tab clipped to the left of inspector column: attr=\(attrFrame), canvas=\(canvasFrame)")
        XCTAssertLessThanOrEqual(docFrame.maxX, winFrame.maxX + 2.0, "Document tab clipped to the right of window: doc=\(docFrame), win=\(winFrame)")
        XCTAssertEqual(attrFrame.midY, docFrame.midY, accuracy: 2.0, "Inspector tabs should be vertically aligned on the same row")
        XCTAssertEqual(sceneFrame.midY, attrFrame.midY, accuracy: 2.0, "Navigator and Inspector tab bars should be vertically aligned")

        // 2. Test selecting cylinder-1 then selecting box-1 in the 3D scene
        let initialProbeString = try XCTUnwrap(canvas.value as? String, "Missing initial probe value")
        let initialSnapshot = ProbeSnapshot.parse(initialProbeString)
        print("AX_PROBE initial=\(initialProbeString)")

        guard let cylHit = initialSnapshot.hits.first(where: { $0.id == "cylinder-1" }) else {
            XCTFail("cylinder-1 hit not found in probe hits: \(initialSnapshot.hits)")
            return
        }
        guard let boxHit = initialSnapshot.hits.first(where: { $0.id == "box-1" }) else {
            XCTFail("box-1 hit not found in probe hits: \(initialSnapshot.hits)")
            return
        }

        // Click cylinder-1 first
        canvas.coordinate(withNormalizedOffset: CGVector(dx: cylHit.x, dy: cylHit.y)).click()
        let afterCylProbe = try XCTUnwrap(canvas.value as? String)
        let afterCylSnapshot = ProbeSnapshot.parse(afterCylProbe)
        print("AX_PROBE afterCylinderClick=\(afterCylProbe)")
        XCTAssertEqual(afterCylSnapshot.selection, "cylinder-1", "Expected selection to be 'cylinder-1' after clicking cylinder")

        // Verify Inspector controls for cylinder-1 are inside the Inspector column bounds
        let inspectorSelected = app.staticTexts["inspector-selected-object"]
        XCTAssertTrue(inspectorSelected.waitForExistence(timeout: 5.0))
        XCTAssertEqual(inspectorSelected.value as? String, "cylinder-1")
        XCTAssertGreaterThanOrEqual(inspectorSelected.frame.minX, canvasFrame.maxX - 2.0, "Inspector label clipped to the left")
        XCTAssertLessThanOrEqual(inspectorSelected.frame.maxX, winFrame.maxX + 2.0, "Inspector label clipped to the right")

        // Now click box-1 after cylinder-1 is selected
        canvas.coordinate(withNormalizedOffset: CGVector(dx: boxHit.x, dy: boxHit.y)).click()
        let afterBoxProbe = try XCTUnwrap(canvas.value as? String)
        let afterBoxSnapshot = ProbeSnapshot.parse(afterBoxProbe)
        print("AX_PROBE afterBoxClick=\(afterBoxProbe)")
        XCTAssertEqual(afterBoxSnapshot.selection, "box-1", "Expected selection to switch to 'box-1' after clicking box")
        XCTAssertEqual(inspectorSelected.value as? String, "box-1", "Expected Inspector to follow selection back to 'box-1'")

        // 3. Test selecting bodies in the left sidebar (Navigator)
        let navCyl = app.descendants(matching: .any)["navigator-object-cylinder-1"].firstMatch
        let navBox = app.descendants(matching: .any)["navigator-object-box-1"].firstMatch
        XCTAssertTrue(navCyl.waitForExistence(timeout: 5.0), "Expected 'navigator-object-cylinder-1' in left sidebar")
        XCTAssertTrue(navBox.waitForExistence(timeout: 5.0), "Expected 'navigator-object-box-1' in left sidebar")

        navCyl.click()
        let afterNavCylProbe = try XCTUnwrap(canvas.value as? String)
        let afterNavCylSnapshot = ProbeSnapshot.parse(afterNavCylProbe)
        print("AX_PROBE afterNavCylClick=\(afterNavCylProbe)")
        XCTAssertEqual(afterNavCylSnapshot.selection, "cylinder-1", "Clicking cylinder-1 in left sidebar should select cylinder-1")
        XCTAssertEqual(inspectorSelected.value as? String, "cylinder-1", "Inspector should show cylinder-1 after left sidebar click")

        navBox.click()
        let afterNavBoxProbe = try XCTUnwrap(canvas.value as? String)
        let afterNavBoxSnapshot = ProbeSnapshot.parse(afterNavBoxProbe)
        print("AX_PROBE afterNavBoxClick=\(afterNavBoxProbe)")
        XCTAssertEqual(afterNavBoxSnapshot.selection, "box-1", "Clicking box-1 in left sidebar should select box-1")
        XCTAssertEqual(inspectorSelected.value as? String, "box-1", "Inspector should show box-1 after left sidebar click")

        // 4. Verify right sidebar (Inspector) content alignment across tabs via macOS Accessibility
        let inspectorLeftMargin = canvasFrame.maxX + 12.0
        let inspectorRightMargin = winFrame.maxX - 12.0

        let identityHeader = app.staticTexts["Identity"]
        let transformHeader = app.staticTexts["Transform"]
        let dimensionsHeader = app.staticTexts["Dimensions"]
        let aabbValue = app.staticTexts["inspector-aabb-size"]
        XCTAssertTrue(identityHeader.exists, "Expected 'Identity' section header in Attributes tab")
        XCTAssertTrue(transformHeader.exists, "Expected 'Transform' section header in Attributes tab")
        XCTAssertTrue(dimensionsHeader.exists, "Expected 'Dimensions' section header in Attributes tab")
        XCTAssertTrue(aabbValue.exists, "Expected 'inspector-aabb-size' in Attributes tab")

        print("AX_INSPECTOR_ATTR identity=\(identityHeader.frame) transform=\(transformHeader.frame) dims=\(dimensionsHeader.frame) selectedID=\(inspectorSelected.frame) aabb=\(aabbValue.frame) expectedLeft=\(inspectorLeftMargin) expectedRight=\(inspectorRightMargin)")

        // Section headers must be flush-left at inspectorLeftMargin (not indented into a right column)
        XCTAssertEqual(identityHeader.frame.minX, inspectorLeftMargin, accuracy: 6.0, "Identity header should align with left margin of Inspector")
        XCTAssertEqual(transformHeader.frame.minX, inspectorLeftMargin, accuracy: 6.0, "Transform header should align with left margin of Inspector")
        XCTAssertEqual(dimensionsHeader.frame.minX, inspectorLeftMargin, accuracy: 6.0, "Dimensions header should align with left margin of Inspector")

        // Right-aligned values must be flush-right at inspectorRightMargin and never clipped
        XCTAssertGreaterThanOrEqual(inspectorSelected.frame.minX, canvasFrame.maxX, "Selected ID clipped left")
        XCTAssertEqual(inspectorSelected.frame.maxX, inspectorRightMargin, accuracy: 16.0, "Selected ID should align near right margin of Inspector")
        XCTAssertGreaterThanOrEqual(aabbValue.frame.minX, canvasFrame.maxX, "AABB size clipped left")
        XCTAssertLessThanOrEqual(aabbValue.frame.maxX, winFrame.maxX, "AABB size clipped right")

        // Check Metadata tab content alignment
        metaTab.click()
        let stdPropsHeader = app.staticTexts["Standard Properties"]
        let partNumField = app.textFields["inspector-part-part-number"]
        XCTAssertTrue(stdPropsHeader.waitForExistence(timeout: 5.0), "Expected 'Standard Properties' header in Metadata tab")
        XCTAssertTrue(partNumField.exists, "Expected 'inspector-part-part-number' text field in Metadata tab")
        print("AX_INSPECTOR_META stdProps=\(stdPropsHeader.frame) partNumField=\(partNumField.frame)")
        XCTAssertEqual(stdPropsHeader.frame.minX, inspectorLeftMargin, accuracy: 6.0, "Standard Properties header should align with left margin of Inspector")
        XCTAssertGreaterThanOrEqual(partNumField.frame.minX, canvasFrame.maxX, "Part Number field clipped left")
        XCTAssertEqual(partNumField.frame.maxX, inspectorRightMargin, accuracy: 8.0, "Part Number field should align with right margin of Inspector")

        // Check Physical tab content alignment
        physTab.click()
        let materialHeader = app.staticTexts["Material"]
        let massDensity = app.staticTexts["inspector-mass-density"]
        XCTAssertTrue(materialHeader.waitForExistence(timeout: 5.0), "Expected 'Material' header in Physical tab")
        XCTAssertTrue(massDensity.exists, "Expected 'inspector-mass-density' in Physical tab")
        print("AX_INSPECTOR_PHYS material=\(materialHeader.frame) massDensity=\(massDensity.frame)")
        XCTAssertEqual(materialHeader.frame.minX, inspectorLeftMargin, accuracy: 6.0, "Material header should align with left margin of Inspector")
        XCTAssertGreaterThanOrEqual(massDensity.frame.minX, canvasFrame.maxX, "Mass density value clipped left")
        XCTAssertLessThanOrEqual(massDensity.frame.maxX, winFrame.maxX, "Mass density value clipped right")
    }
}
