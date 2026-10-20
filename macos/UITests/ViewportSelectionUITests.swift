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
}
