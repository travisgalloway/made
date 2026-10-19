import Testing
import SwiftUI
import AppKit
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct NavigatorRowAccessibilityTests {

    @Test func testDefaultAccessibilityTraitsContainButton() {
        #expect(NavigatorSketchRow.defaultAccessibilityTraits.contains(.isButton))
        #expect(NavigatorDatumPlaneRow.defaultAccessibilityTraits.contains(.isButton))
        #expect(NavigatorDatumAxisRow.defaultAccessibilityTraits.contains(.isButton))
        #expect(NavigatorDatumPointRow.defaultAccessibilityTraits.contains(.isButton))
        #expect(NavigatorDatumCoordinateSystemRow.defaultAccessibilityTraits.contains(.isButton))
    }

    @Test func testAccessibilityLabelFormattingAcrossAllRowTypes() {
        // Sketch row
        #expect(NavigatorSketchRow.accessibilityLabel(
            featureName: "Sketch 1",
            entityCount: 3,
            status: .underConstrained(dof: 2),
            isLocked: false
        ) == "Sketch 1, Sketch, 3 entities, DOF: 2 under")
        #expect(NavigatorSketchRow.accessibilityLabel(
            featureName: "Sketch 1",
            entityCount: 3,
            status: .underConstrained(dof: 2),
            isLocked: true
        ) == "Sketch 1, Sketch, 3 entities, DOF: 2 under, Locked")

        // Datum Plane row
        #expect(NavigatorDatumPlaneRow.accessibilityLabel(featureName: "Datum Plane 1", isLocked: false) == "Datum Plane 1, Datum Plane")
        #expect(NavigatorDatumPlaneRow.accessibilityLabel(featureName: "Datum Plane 1", isLocked: true) == "Datum Plane 1, Datum Plane, Locked")

        // Datum Axis row
        #expect(NavigatorDatumAxisRow.accessibilityLabel(featureName: "Datum Axis 1", isLocked: false) == "Datum Axis 1, Datum Axis")
        #expect(NavigatorDatumAxisRow.accessibilityLabel(featureName: "Datum Axis 1", isLocked: true) == "Datum Axis 1, Datum Axis, Locked")

        // Datum Point row
        #expect(NavigatorDatumPointRow.accessibilityLabel(featureName: "Datum Point 1", isLocked: false) == "Datum Point 1, Datum Point")
        #expect(NavigatorDatumPointRow.accessibilityLabel(featureName: "Datum Point 1", isLocked: true) == "Datum Point 1, Datum Point, Locked")

        // Datum UCS row
        #expect(NavigatorDatumCoordinateSystemRow.accessibilityLabel(featureName: "UCS 1", isLocked: false) == "UCS 1, Datum UCS")
        #expect(NavigatorDatumCoordinateSystemRow.accessibilityLabel(featureName: "UCS 1", isLocked: true) == "UCS 1, Datum UCS, Locked")
    }

    @Test @MainActor func testFeatureSelectionViaWorkspaceSelectFeature() {
        let workspace = WorkspaceModel()

        let sketchFeature = Feature(
            name: "Base Sketch",
            operation: .sketch(SketchFeatureData(planeName: "XY", entities: [
                .line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            ]))
        )
        let datumPlaneFeature = Feature(
            name: "Offset Plane",
            operation: .datumPlane(DatumPlaneFeatureData(mode: .offset, offsetDistance: 10))
        )
        let datumAxisFeature = Feature(
            name: "Primary Axis",
            operation: .datumAxis(DatumAxisFeatureData(mode: .preset, presetName: "X"))
        )
        let datumPointFeature = Feature(
            name: "Center Point",
            operation: .datumPoint(DatumPointFeatureData(mode: .coordinates, coordinates: SIMD3<Float>(0, 0, 0)))
        )
        let datumUCSFeature = Feature(
            name: "Work Coordinate System",
            operation: .datumCoordinateSystem(DatumCoordinateSystemFeatureData(mode: .originAndAxes, origin: SIMD3<Float>(0, 0, 0)))
        )

        let features = [sketchFeature, datumPlaneFeature, datumAxisFeature, datumPointFeature, datumUCSFeature]
        for feature in features {
            workspace.document.addFeature(feature)
        }

        // Test each feature's selection updates selection reference and isFeatureSelected
        for (index, feature) in features.enumerated() {
            workspace.selectFeature(feature.id)

            #expect(workspace.document.selection == [Reference.feature(feature.id)])
            #expect(workspace.isFeatureSelected(feature))

            // Verify all other features report false for isFeatureSelected
            for (otherIndex, otherFeature) in features.enumerated() where otherIndex != index {
                #expect(!workspace.isFeatureSelected(otherFeature))
            }
        }
    }

    @Test @MainActor func testSelectionIdempotencyAndRapidSwitching() {
        let workspace = WorkspaceModel()

        let featA = Feature(name: "Plane A", operation: .datumPlane(DatumPlaneFeatureData(mode: .offset, offsetDistance: 5)))
        let featB = Feature(name: "Axis B", operation: .datumAxis(DatumAxisFeatureData(mode: .preset, presetName: "Y")))
        let featC = Feature(name: "Point C", operation: .datumPoint(DatumPointFeatureData(mode: .coordinates, coordinates: .zero)))
        workspace.document.addFeature(featA)
        workspace.document.addFeature(featB)
        workspace.document.addFeature(featC)

        // Multiple rapid selection calls to the same feature
        workspace.selectFeature(featA.id)
        workspace.selectFeature(featA.id)
        workspace.selectFeature(featA.id)
        #expect(workspace.document.selection == [Reference.feature(featA.id)])
        #expect(workspace.isFeatureSelected(featA))
        #expect(!workspace.isFeatureSelected(featB))

        // Rapid switching back and forth
        for _ in 0..<5 {
            workspace.selectFeature(featB.id)
            #expect(workspace.document.selection == [Reference.feature(featB.id)])
            workspace.selectFeature(featC.id)
            #expect(workspace.document.selection == [Reference.feature(featC.id)])
            workspace.selectFeature(featA.id)
            #expect(workspace.document.selection == [Reference.feature(featA.id)])
        }
    }

    @Test @MainActor func testLockedFeatureSelectionAndDeletionProtection() {
        let workspace = WorkspaceModel()

        var lockedPlane = Feature(name: "Locked Plane", operation: .datumPlane(DatumPlaneFeatureData(mode: .offset, offsetDistance: 12)))
        lockedPlane.isLocked = true
        workspace.document.addFeature(lockedPlane)

        var lockedUCS = Feature(name: "Locked UCS", operation: .datumCoordinateSystem(DatumCoordinateSystemFeatureData(mode: .originAndAxes, origin: .zero)))
        lockedUCS.isLocked = true
        workspace.document.addFeature(lockedUCS)

        // Selecting locked plane
        workspace.selectFeature(lockedPlane.id)
        #expect(workspace.isFeatureSelected(lockedPlane))
        #expect(workspace.selectedFeature?.id == lockedPlane.id)
        #expect(workspace.canDeleteSelectedFeature == false)

        // Unlock feature
        workspace.toggleFeatureLocked(lockedPlane.id)
        #expect(workspace.selectedFeature?.isLocked == false)
        #expect(workspace.canDeleteSelectedFeature == true)

        // Selecting locked UCS
        workspace.selectFeature(lockedUCS.id)
        #expect(workspace.isFeatureSelected(lockedUCS))
        #expect(workspace.selectedFeature?.id == lockedUCS.id)
        #expect(workspace.canDeleteSelectedFeature == false)
    }

    @Test @MainActor func testNSHostingViewLayoutWithAllRowTypes() {
        let workspace = WorkspaceModel()

        let sketchFeature = Feature(
            name: "Base Sketch",
            operation: .sketch(SketchFeatureData(planeName: "XY", entities: [
                .line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            ]))
        )
        let datumPlaneFeature = Feature(
            name: "Offset Plane",
            operation: .datumPlane(DatumPlaneFeatureData(mode: .offset, offsetDistance: 10))
        )
        let datumAxisFeature = Feature(
            name: "Primary Axis",
            operation: .datumAxis(DatumAxisFeatureData(mode: .preset, presetName: "X"))
        )
        let datumPointFeature = Feature(
            name: "Center Point",
            operation: .datumPoint(DatumPointFeatureData(mode: .coordinates, coordinates: SIMD3<Float>(0, 0, 0)))
        )
        let datumUCSFeature = Feature(
            name: "Work Coordinate System",
            operation: .datumCoordinateSystem(DatumCoordinateSystemFeatureData(mode: .originAndAxes, origin: SIMD3<Float>(0, 0, 0)))
        )

        workspace.document.addFeature(sketchFeature)
        workspace.document.addFeature(datumPlaneFeature)
        workspace.document.addFeature(datumAxisFeature)
        workspace.document.addFeature(datumPointFeature)
        workspace.document.addFeature(datumUCSFeature)

        // Host individual rows
        let rows: [AnyView] = [
            AnyView(NavigatorSketchRow(feature: sketchFeature).environment(workspace)),
            AnyView(NavigatorDatumPlaneRow(feature: datumPlaneFeature).environment(workspace)),
            AnyView(NavigatorDatumAxisRow(feature: datumAxisFeature).environment(workspace)),
            AnyView(NavigatorDatumPointRow(feature: datumPointFeature).environment(workspace)),
            AnyView(NavigatorDatumCoordinateSystemRow(feature: datumUCSFeature).environment(workspace))
        ]

        for row in rows {
            let hostingView = NSHostingView(rootView: row)
            hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 32)
            hostingView.layoutSubtreeIfNeeded()
            #expect(hostingView.frame.width == 260)
            #expect(hostingView.frame.height == 32)
        }

        // Host full sidebar view
        let sidebar = NavigatorSidebarView().environment(workspace)
        let sidebarHosting = NSHostingView(rootView: sidebar)
        sidebarHosting.frame = NSRect(x: 0, y: 0, width: 260, height: 600)
        sidebarHosting.layoutSubtreeIfNeeded()
        #expect(sidebarHosting.frame.width == 260)
        #expect(sidebarHosting.frame.height == 600)
    }
}
