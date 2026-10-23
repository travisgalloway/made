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
}
