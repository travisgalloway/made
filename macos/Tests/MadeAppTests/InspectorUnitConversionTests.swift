import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct InspectorUnitConversionTests {

    @Test @MainActor func testBoxWidthAndPositionInInches() {
        let workspace = WorkspaceModel()
        workspace.setUp()
        workspace.setDocumentUnits(UnitSettings(lengthUnit: .inches))

        // Create a box with width 25.4 mm and position (25.4, 0, 0)
        let boxDef = ObjectDef.box(BoxParams(width: 25.4, depth: 20.0, height: 10.0))
        workspace.addObject(boxDef)

        guard let selectedId = workspace.selectedId,
              let obj = workspace.selectedObject,
              case .box(let params) = obj.def else {
            Issue.record("Failed to create and select box")
            return
        }

        #expect(abs(params.width - 25.4) < 1e-4)

        // 1. Verify displayLength converts 25.4 mm to 1.0 inch
        let displayWidth = InspectorUnitConversion.displayLength(Double(params.width), unit: .inches)
        #expect(abs(displayWidth - 1.0) < 1e-4)

        // 2. Verify lengthAccessibilityValue produces "1.0 in"
        let spoken = InspectorUnitConversion.lengthAccessibilityValue(displayWidth, unit: .inches)
        #expect(spoken == "1.0 in")

        // 3. Verify committing 2 inches commits 50.8 mm via commitLength
        let committedWidth = InspectorUnitConversion.commitLength(2.0, unit: .inches)
        #expect(abs(committedWidth - 50.8) < 1e-4)

        // Apply parameter update to workspace
        workspace.setParam(selectedId, "width", committedWidth)
        if let updatedObj = workspace.document.objects.first(where: { $0.id == selectedId }),
           case .box(let updatedParams) = updatedObj.def {
            #expect(abs(updatedParams.width - 50.8) < 1e-4)
        } else {
            Issue.record("Failed to find updated box")
        }

        // 4. Test position in inches
        var t = obj.transform
        t.position = SIMD3<Float>(25.4, 0, 0)
        workspace.setTransform(selectedId, t)

        let posX = InspectorUnitConversion.displayLength(Double(t.position.x), unit: .inches)
        #expect(abs(posX - 1.0) < 1e-4)
        let posSpoken = InspectorUnitConversion.lengthAccessibilityValue(posX, unit: .inches)
        #expect(posSpoken == "1.0 in")

        // Committing 2 inches updates position X to 50.8 mm
        let newPosX = InspectorUnitConversion.commitLength(2.0, unit: .inches)
        var updatedT = t
        updatedT.position.x = newPosX
        workspace.setTransform(selectedId, updatedT)

        if let currentObj = workspace.document.objects.first(where: { $0.id == selectedId }) {
            #expect(abs(currentObj.transform.position.x - 50.8) < 1e-4)
        }
    }

    @Test func testLengthUnitsConversionRoundtrip() {
        let testValueMM = 1000.0

        // Millimeters
        let mmDisplay = InspectorUnitConversion.displayLength(testValueMM, unit: .millimeters)
        #expect(mmDisplay == 1000.0)
        #expect(LengthUnit.millimeters.defaultStep == 1.0)
        #expect(InspectorUnitConversion.lengthAccessibilityValue(mmDisplay, unit: .millimeters) == "1,000.0 mm" || InspectorUnitConversion.lengthAccessibilityValue(mmDisplay, unit: .millimeters) == "1000.0 mm")
        #expect(InspectorUnitConversion.commitLength(mmDisplay, unit: .millimeters) == 1000.0)

        // Centimeters
        let cmDisplay = InspectorUnitConversion.displayLength(testValueMM, unit: .centimeters)
        #expect(cmDisplay == 100.0)
        #expect(LengthUnit.centimeters.defaultStep == 0.1)
        #expect(InspectorUnitConversion.lengthAccessibilityValue(cmDisplay, unit: .centimeters) == "100.0 cm")
        #expect(InspectorUnitConversion.commitLength(cmDisplay, unit: .centimeters) == 1000.0)

        // Inches (1000 mm / 25.4)
        let inDisplay = InspectorUnitConversion.displayLength(testValueMM, unit: .inches)
        #expect(abs(inDisplay - (1000.0 / 25.4)) < 1e-5)
        #expect(LengthUnit.inches.defaultStep == 0.1)
        #expect(abs(InspectorUnitConversion.commitLength(inDisplay, unit: .inches) - 1000.0) < 1e-4)

        // Meters
        let mDisplay = InspectorUnitConversion.displayLength(testValueMM, unit: .meters)
        #expect(mDisplay == 1.0)
        #expect(LengthUnit.meters.defaultStep == 0.001)
        #expect(InspectorUnitConversion.lengthAccessibilityValue(mDisplay, unit: .meters) == "1.0 m")
        #expect(InspectorUnitConversion.commitLength(mDisplay, unit: .meters) == 1000.0)

        // Feet (1000 mm / 304.8)
        let ftDisplay = InspectorUnitConversion.displayLength(testValueMM, unit: .feet)
        #expect(abs(ftDisplay - (1000.0 / 304.8)) < 1e-5)
        #expect(LengthUnit.feet.defaultStep == 0.01)
        #expect(abs(InspectorUnitConversion.commitLength(ftDisplay, unit: .feet) - 1000.0) < 1e-4)
    }

    @Test func testAngleUnitsConversionRoundtrip() {
        // Degrees
        let degDisplay = InspectorUnitConversion.displayAngle(45.0, unit: .degrees)
        #expect(degDisplay == 45.0)
        #expect(AngleUnit.degrees.defaultStep == 1.0)
        #expect(InspectorUnitConversion.angleAccessibilityValue(degDisplay, unit: .degrees) == "45.0 deg")
        let degCommit = InspectorUnitConversion.commitAngle(90.0, unit: .degrees)
        #expect(degCommit == 90.0)

        // Radians
        let radDisplay = InspectorUnitConversion.displayAngle(180.0, unit: .radians)
        #expect(abs(radDisplay - .pi) < 1e-6)
        #expect(AngleUnit.radians.defaultStep == 0.1)
        let radCommit = InspectorUnitConversion.commitAngle(.pi / 2.0, unit: .radians)
        #expect(abs(radCommit - 90.0) < 1e-6)
    }

    @Test @MainActor func testCommitNumberFieldInputSanitization() {
        // Raw numbers
        #expect(CommitNumberField.cleanDraft("2") == "2")
        #expect(CommitNumberField.parseDraft("2") == 2.0)
        #expect(CommitNumberField.cleanDraft("50.8") == "50.8")
        #expect(CommitNumberField.parseDraft("50.8") == 50.8)

        // Unit suffixes
        #expect(CommitNumberField.cleanDraft("2 in") == "2")
        #expect(CommitNumberField.parseDraft("2 in") == 2.0)
        #expect(CommitNumberField.cleanDraft("2in") == "2")
        #expect(CommitNumberField.parseDraft("2in") == 2.0)
        #expect(CommitNumberField.cleanDraft("50.8 mm") == "50.8")
        #expect(CommitNumberField.parseDraft("50.8 mm") == 50.8)
        #expect(CommitNumberField.cleanDraft("45°") == "45")
        #expect(CommitNumberField.parseDraft("45°") == 45.0)
        #expect(CommitNumberField.cleanDraft("45 deg") == "45")
        #expect(CommitNumberField.parseDraft("45 deg") == 45.0)
        #expect(CommitNumberField.cleanDraft("1.5 rad") == "1.5")
        #expect(CommitNumberField.parseDraft("1.5 rad") == 1.5)
        #expect(CommitNumberField.cleanDraft("1.5rad") == "1.5")
        #expect(CommitNumberField.parseDraft("1.5rad") == 1.5)

        // Negative numbers
        #expect(CommitNumberField.cleanDraft("-25.4 mm") == "-25.4")
        #expect(CommitNumberField.parseDraft("-25.4 mm") == -25.4)

        // Invalid inputs
        #expect(CommitNumberField.parseDraft("xyz") == nil)
        #expect(CommitNumberField.parseDraft("") == nil)
    }

    @Test @MainActor func testDatumPlaneAngleEditingWithUnits() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        // Create datum plane at angle
        let planeData = DatumPlaneFeatureData(
            mode: .atAngle,
            originPreset: "XY",
            offsetDistance: 0.0,
            angleDegrees: 45.0
        )
        let feature = workspace.document.addDatumPlaneFeature(data: planeData)

        // Display in radians
        workspace.setDocumentUnits(UnitSettings(angleUnit: .radians))
        let radDisplay = InspectorUnitConversion.displayAngle(planeData.angleDegrees, unit: .radians)
        #expect(abs(radDisplay - (45.0 * .pi / 180.0)) < 1e-5)

        // Commit 90 degrees in radians (pi / 2)
        let committedDeg = InspectorUnitConversion.commitAngle(.pi / 2.0, unit: .radians)
        #expect(abs(committedDeg - 90.0) < 1e-5)

        var updatedData = planeData
        updatedData.angleDegrees = committedDeg
        var updatedFeature = feature
        updatedFeature.operation = .datumPlane(updatedData)
        workspace.document.updateFeature(updatedFeature)

        if let fetched = workspace.document.feature(for: feature.id),
           case .datumPlane(let fetchedData) = fetched.operation {
            #expect(abs(fetchedData.angleDegrees - 90.0) < 1e-5)
        } else {
            Issue.record("Failed to fetch updated datum plane feature")
        }
    }

    @Test @MainActor func testInspectorPanelViewInstantiationWithUnits() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let units: [LengthUnit] = [.millimeters, .centimeters, .meters, .inches, .feet]
        for unit in units {
            workspace.setDocumentUnits(UnitSettings(lengthUnit: unit))
            let view = InspectorPanelView().environment(workspace)
            let views: [any View] = [view]
            #expect(views.count == 1)
        }

        // Add a box, datum plane, and datum coordinate system to ensure all inspector branches instantiate
        workspace.addObject(.box(BoxParams(width: 25.4, depth: 20.0, height: 10.0)))
        _ = workspace.document.addDatumPlaneFeature(data: DatumPlaneFeatureData(mode: .atAngle, angleDegrees: 30.0))
        _ = workspace.document.addDatumCoordinateSystemFeature(
            data: DatumCoordinateSystemFeatureData(
                mode: .offsetFromParent,
                offsetDistance: SIMD3<Float>(10, 20, 30),
                rotationAngles: SIMD3<Float>(0, 45, 90)
            )
        )

        for unit in units {
            workspace.setDocumentUnits(UnitSettings(lengthUnit: unit))
            let view = InspectorPanelView().environment(workspace)
            let views: [any View] = [view]
            #expect(views.count == 1)
        }
    }
}
