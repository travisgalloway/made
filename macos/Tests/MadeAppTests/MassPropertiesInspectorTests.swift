import Testing
import Foundation
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct MassPropertiesInspectorTests {

    @Test func testInspectorUnitConversionVolumeAndMass() {
        // Volume conversions
        let volMM3 = 1_000_000.0 // 1,000,000 mm³ = 1000 cm³ = 0.001 m³
        let volMM = InspectorUnitConversion.displayVolume(volMM3, unit: .millimeters)
        #expect(abs(volMM - 1_000_000.0) < 1e-4)

        let volCM = InspectorUnitConversion.displayVolume(volMM3, unit: .centimeters)
        #expect(abs(volCM - 1000.0) < 1e-4)

        let volM = InspectorUnitConversion.displayVolume(volMM3, unit: .meters)
        #expect(abs(volM - 0.001) < 1e-6)

        let volSpoken = InspectorUnitConversion.volumeAccessibilityValue(volMM, unit: .millimeters)
        #expect(volSpoken.contains("mm³"))

        // Mass conversions
        let smallMass = 0.025 // 25 g (< 0.1 kg)
        let (smallVal, smallUnit) = InspectorUnitConversion.displayMass(smallMass)
        #expect(abs(smallVal - 25.0) < 1e-4)
        #expect(smallUnit == "g")

        let largeMass = 5.25 // 5.25 kg (>= 0.1 kg)
        let (largeVal, largeUnit) = InspectorUnitConversion.displayMass(largeMass)
        #expect(abs(largeVal - 5.25) < 1e-4)
        #expect(largeUnit == "kg")

        let massSpoken = InspectorUnitConversion.massAccessibilityValue(smallMass)
        #expect(massSpoken.contains("g"))
    }

    @Test @MainActor func testWorkspaceMassPropertiesForBox() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let boxDef = ObjectDef.box(BoxParams(width: 10, depth: 20, height: 30))
        workspace.addObject(boxDef)

        guard let solidId = workspace.selectedId else {
            Issue.record("No object selected after adding box")
            return
        }

        // Test centroid coordinate system
        let centroidProps = workspace.massProperties(for: solidId, coordinateSystem: .centroid)
        #expect(centroidProps != nil)
        if let centroidProps {
            #expect(abs(centroidProps.volume - 6000.0) < 1e-4)
            #expect(abs(centroidProps.surfaceArea - 2200.0) < 1e-4)
            #expect(abs(centroidProps.mass - 0.006) < 1e-7)
            #expect(centroidProps.coordinateSystem == .centroid)
            #expect(abs(centroidProps.centerOfMass.x) < 1e-6)
            #expect(abs(centroidProps.centerOfMass.y) < 1e-6)
            #expect(abs(centroidProps.centerOfMass.z) < 1e-6)
        }

        // Test body local coordinate system
        let bodyLocalProps = workspace.massProperties(for: solidId, coordinateSystem: .bodyLocal)
        #expect(bodyLocalProps != nil)
        if let bodyLocalProps {
            #expect(bodyLocalProps.coordinateSystem == .bodyLocal)
            #expect(abs(bodyLocalProps.volume - 6000.0) < 1e-4)
        }

        // Test world coordinate system
        let worldProps = workspace.massProperties(for: solidId, coordinateSystem: .world)
        #expect(worldProps != nil)
        if let worldProps {
            #expect(worldProps.coordinateSystem == .world)
            #expect(abs(worldProps.volume - 6000.0) < 1e-4)
        }
    }

    @Test @MainActor func testMassPropertiesClipboardString() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let boxDef = ObjectDef.box(BoxParams(width: 10, depth: 20, height: 30))
        workspace.addObject(boxDef)

        guard let solidId = workspace.selectedId,
              let props = workspace.massProperties(for: solidId, coordinateSystem: .centroid) else {
            Issue.record("Failed to calculate mass properties for box")
            return
        }

        let report = props.formattedReport(units: workspace.document.settings.units)
        #expect(!report.isEmpty)
        #expect(report.contains("Mass Properties Report"))
        #expect(report.contains("Coordinate System: Center of Mass"))
        #expect(report.contains("Mass:"))
        #expect(report.contains("Volume:"))
        #expect(report.contains("Surface Area:"))
        #expect(report.contains("Center of Mass:"))
        #expect(report.contains("Moments of Inertia"))
        #expect(report.contains("Principal Moments of Inertia"))
    }

    // MARK: - Mass Override Tests (BL-MAT-05, #258)

    @Test @MainActor func testWorkspaceMassOverrideForBox() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let boxDef = ObjectDef.box(BoxParams(width: 10, depth: 20, height: 30))
        workspace.addObject(boxDef)

        guard let solidId = workspace.selectedId else {
            Issue.record("No object selected after adding box")
            return
        }

        // Initially no override
        let initialProps = workspace.massProperties(for: solidId, coordinateSystem: .centroid)
        #expect(initialProps?.isMassOverridden == false)
        #expect(initialProps?.isCenterOfMassOverridden == false)
        #expect(abs((initialProps?.mass ?? 0) - 0.006) < 1e-7)

        // Enable purchased override
        workspace.setPurchasedOverride(id: solidId, isPurchased: true)
        workspace.setOverrideMass(id: solidId, massKg: 0.015)
        workspace.setOverrideCenterOfMass(id: solidId, centerOfMassLocal: SIMD3<Double>(10, 20, 30))

        let overriddenProps = workspace.massProperties(for: solidId, coordinateSystem: .bodyLocal)
        #expect(overriddenProps != nil)
        if let overriddenProps {
            #expect(overriddenProps.isMassOverridden)
            #expect(overriddenProps.isCenterOfMassOverridden)
            #expect(abs(overriddenProps.mass - 0.015) < 1e-7)
            #expect(abs(overriddenProps.centerOfMass.x - 10.0) < 1e-5)
            #expect(abs(overriddenProps.centerOfMass.y - 20.0) < 1e-5)
            #expect(abs(overriddenProps.centerOfMass.z - 30.0) < 1e-5)
        }
    }

    @Test @MainActor func testWorkspaceMassOverrideUndoRedo() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let boxDef = ObjectDef.box(BoxParams(width: 10, depth: 20, height: 30))
        workspace.addObject(boxDef)

        guard let solidId = workspace.selectedId else {
            Issue.record("No object selected after adding box")
            return
        }

        let undoManager = UndoManager()
        workspace.document.undoManager = undoManager
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        workspace.setPurchasedOverride(id: solidId, isPurchased: true)
        undoManager.endUndoGrouping()

        undoManager.beginUndoGrouping()
        workspace.setOverrideMass(id: solidId, massKg: 0.050)
        undoManager.endUndoGrouping()

        let propsWithOverride = workspace.massProperties(for: solidId, coordinateSystem: .centroid)
        #expect(propsWithOverride?.isMassOverridden == true)
        #expect(abs((propsWithOverride?.mass ?? 0) - 0.050) < 1e-7)

        // Undo mass override
        undoManager.undo()
        let propsUndone = workspace.massProperties(for: solidId, coordinateSystem: .centroid)
        #expect(propsUndone?.isMassOverridden == false)
        #expect(abs((propsUndone?.mass ?? 0) - 0.006) < 1e-7)

        // Redo mass override
        undoManager.redo()
        let propsRedone = workspace.massProperties(for: solidId, coordinateSystem: .centroid)
        #expect(propsRedone?.isMassOverridden == true)
        #expect(abs((propsRedone?.mass ?? 0) - 0.050) < 1e-7)
    }

    @Test @MainActor func testWorkspaceClearMassOverrides() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let boxDef = ObjectDef.box(BoxParams(width: 10, depth: 20, height: 30))
        workspace.addObject(boxDef)

        guard let solidId = workspace.selectedId else {
            Issue.record("No object selected after adding box")
            return
        }

        workspace.setPurchasedOverride(id: solidId, isPurchased: true)
        workspace.setOverrideMass(id: solidId, massKg: 0.100)
        workspace.setOverrideCenterOfMass(id: solidId, centerOfMassLocal: SIMD3<Double>(5, 10, 15))

        let overridden = workspace.massProperties(for: solidId, coordinateSystem: .centroid)
        #expect(overridden?.isMassOverridden == true)

        workspace.clearMassOverrides(id: solidId)

        let cleared = workspace.massProperties(for: solidId, coordinateSystem: .centroid)
        #expect(cleared?.isMassOverridden == false)
        #expect(cleared?.isCenterOfMassOverridden == false)
        #expect(abs((cleared?.mass ?? 0) - 0.006) < 1e-7)
    }

    @Test func testInspectorMassOverrideUnitConversion() {
        // Mass unit conversions: display and commit
        let kgValue = 0.025 // 25 g
        let (valG, symG) = InspectorUnitConversion.displayMass(kgValue)
        #expect(abs(valG - 25.0) < 1e-4)
        #expect(symG == "g")

        let committedFromG = InspectorUnitConversion.commitMass(25.0, unitSymbol: "g")
        #expect(abs(committedFromG - 0.025) < 1e-6)

        let committedFromKg = InspectorUnitConversion.commitMass(1.5, unitSymbol: "kg")
        #expect(abs(committedFromKg - 1.5) < 1e-6)

        // Length unit conversions for center of mass coordinates
        let lengthMm = 25.4
        let dispInches = InspectorUnitConversion.displayLength(lengthMm, unit: .inches)
        #expect(abs(dispInches - 1.0) < 1e-4)

        let committedMm = InspectorUnitConversion.commitLengthDouble(1.0, unit: .inches)
        #expect(abs(committedMm - 25.4) < 1e-4)

        let committedCm = InspectorUnitConversion.commitLengthDouble(2.5, unit: .centimeters)
        #expect(abs(committedCm - 25.0) < 1e-4)
    }
}
