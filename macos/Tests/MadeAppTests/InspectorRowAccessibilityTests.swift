import Testing
import SwiftUI
import AppKit
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct InspectorRowAccessibilityTests {

    @Test func testDefaultAccessibilityTraitsContainButton() {
        #expect(InspectorSketchEntityRow.defaultAccessibilityTraits.contains(.isButton))
        #expect(InspectorSketchRegionRow.defaultAccessibilityTraits.contains(.isButton))
    }

    @Test func testAccessibilityTraitsSelectedAndUnselected() {
        let types: [(unselected: AccessibilityTraits, selected: AccessibilityTraits)] = [
            (InspectorSketchEntityRow.accessibilityTraits(isSelected: false), InspectorSketchEntityRow.accessibilityTraits(isSelected: true)),
            (InspectorSketchRegionRow.accessibilityTraits(isSelected: false), InspectorSketchRegionRow.accessibilityTraits(isSelected: true)),
        ]

        for (unselected, selected) in types {
            #expect(unselected.contains(.isButton))
            #expect(!unselected.contains(.isSelected))
            #expect(selected.contains(.isButton))
            #expect(selected.contains(.isSelected))
        }

        #expect(InspectorSketchEntityRow.accessibilityTraits() == InspectorSketchEntityRow.defaultAccessibilityTraits)
        #expect(InspectorSketchRegionRow.accessibilityTraits() == InspectorSketchRegionRow.defaultAccessibilityTraits)
    }

    @Test func testAccessibilityLabelFormattingForSketchEntityRow() {
        // Line tests
        #expect(InspectorSketchEntityRow.accessibilityLabel(
            kind: "line",
            status: .inactive
        ) == "Line, DOF: --")

        #expect(InspectorSketchEntityRow.accessibilityLabel(
            kind: "line",
            status: .underConstrained(dof: 2),
            isConstruction: true
        ) == "Line, DOF: 2 under, Construction")

        #expect(InspectorSketchEntityRow.accessibilityLabel(
            kind: "line",
            status: .underConstrained(dof: 1),
            isConstruction: false,
            isProjected: true
        ) == "Line, DOF: 1 under, Projected")

        #expect(InspectorSketchEntityRow.accessibilityLabel(
            kind: "line",
            status: .fullyConstrained,
            isConstruction: true,
            isProjected: true
        ) == "Line, DOF: fully constrained, Construction, Projected")

        // Arc tests
        #expect(InspectorSketchEntityRow.accessibilityLabel(
            kind: "arc",
            status: .fullyConstrained,
            isProjected: true
        ) == "Arc, DOF: fully constrained, Projected")

        #expect(InspectorSketchEntityRow.accessibilityLabel(
            kind: "arc",
            status: .overConstrained(),
            isConstruction: false,
            isProjected: false
        ) == "Arc, DOF: over-constrained")

        // Circle tests
        #expect(InspectorSketchEntityRow.accessibilityLabel(
            kind: "circle",
            status: .overConstrained(dof: 1),
            isConstruction: true,
            isProjected: true
        ) == "Circle, DOF: over-constrained, Construction, Projected")

        #expect(InspectorSketchEntityRow.accessibilityLabel(
            kind: "circle",
            status: .underConstrained(dof: 3)
        ) == "Circle, DOF: 3 under")
    }

    @Test func testAccessibilityLabelFormattingForSketchRegionRow() {
        // Zero holes
        #expect(InspectorSketchRegionRow.accessibilityLabel(
            regionNumber: 1,
            area: 100.0,
            holeCount: 0
        ) == "Region 1, Area: 100.0 mm²")

        // Default hole count parameter (0)
        #expect(InspectorSketchRegionRow.accessibilityLabel(
            regionNumber: 1,
            area: 15.0
        ) == "Region 1, Area: 15.0 mm²")

        // Single hole
        #expect(InspectorSketchRegionRow.accessibilityLabel(
            regionNumber: 2,
            area: 250.5,
            holeCount: 1
        ) == "Region 2, Area: 250.5 mm², 1 hole")

        // Multiple holes
        #expect(InspectorSketchRegionRow.accessibilityLabel(
            regionNumber: 3,
            area: 420.75,
            holeCount: 3
        ) == "Region 3, Area: 420.8 mm², 3 holes")
    }

    @Test @MainActor func testSketchEntitySelectionViaWorkspace() {
        let workspace = WorkspaceModel()
        let lineEntity = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(10, 0)
        )
        let sketchFeature = Feature(
            name: "Test Sketch",
            operation: .sketch(SketchFeatureData(planeName: "XY", entities: [lineEntity]))
        )
        workspace.document.addFeature(sketchFeature)

        #expect(workspace.selectedSketchEntity == nil)

        workspace.selectSketchEntity(featureId: sketchFeature.id, entityId: lineEntity.id)

        #expect(workspace.selectedSketchEntity?.featureId == sketchFeature.id)
        #expect(workspace.selectedSketchEntity?.entity.id == lineEntity.id)
    }

    @Test @MainActor func testSketchRegionSelectionViaWorkspace() {
        let workspace = WorkspaceModel()
        let sketchFeature = Feature(
            name: "Test Sketch",
            operation: .sketch(SketchFeatureData(planeName: "XY", entities: []))
        )
        workspace.document.addFeature(sketchFeature)

        let regionId = UUID()
        #expect(workspace.selectedSketchRegionId == nil)

        workspace.selectSketchRegion(featureId: sketchFeature.id, regionId: regionId)
        #expect(workspace.selectedSketchRegionId == regionId)

        workspace.selectSketchRegion(featureId: sketchFeature.id, regionId: nil)
        #expect(workspace.selectedSketchRegionId == nil)
    }

    @Test @MainActor func testSketchRegionSelectionIdempotencyAndRapidSwitching() {
        let workspace = WorkspaceModel()
        let sketchFeature = Feature(
            name: "Test Sketch",
            operation: .sketch(SketchFeatureData(planeName: "XY", entities: []))
        )
        workspace.document.addFeature(sketchFeature)

        let region1 = UUID()
        let region2 = UUID()

        #expect(workspace.selectedSketchRegionId == nil)

        // Select region 1
        workspace.selectSketchRegion(featureId: sketchFeature.id, regionId: region1)
        #expect(workspace.selectedSketchRegionId == region1)

        // Select region 1 again (idempotent)
        workspace.selectSketchRegion(featureId: sketchFeature.id, regionId: region1)
        #expect(workspace.selectedSketchRegionId == region1)

        // Rapid switch directly to region 2 without prior deselection
        workspace.selectSketchRegion(featureId: sketchFeature.id, regionId: region2)
        #expect(workspace.selectedSketchRegionId == region2)

        // Deselection clearing selectedSketchRegionId to nil
        workspace.selectSketchRegion(featureId: sketchFeature.id, regionId: nil)
        #expect(workspace.selectedSketchRegionId == nil)
    }

    @Test @MainActor func testNSHostingViewLayoutForInspectorRows() {
        let workspace = WorkspaceModel()
        let lineEntity = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(10, 0)
        )
        let sketchFeature = Feature(
            name: "Test Sketch",
            operation: .sketch(SketchFeatureData(planeName: "XY", entities: [lineEntity]))
        )
        workspace.document.addFeature(sketchFeature)

        let region = SketchRegion(
            outerLoop: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(10, 0),
                SIMD2<Float>(10, 10),
                SIMD2<Float>(0, 10)
            ],
            innerLoops: [],
            area: 100.0,
            centroid: SIMD2<Float>(5, 5)
        )

        let entityRow = InspectorSketchEntityRow(sketchId: sketchFeature.id, entity: lineEntity)
            .environment(workspace)
        let regionRow = InspectorSketchRegionRow(sketchId: sketchFeature.id, regionNumber: 1, region: region)
            .environment(workspace)

        let entityHosting = NSHostingView(rootView: AnyView(entityRow))
        entityHosting.frame = NSRect(x: 0, y: 0, width: 260, height: 80)
        entityHosting.layoutSubtreeIfNeeded()
        #expect(entityHosting.frame.width == 260)
        #expect(entityHosting.frame.height == 80)

        let regionHosting = NSHostingView(rootView: AnyView(regionRow))
        regionHosting.frame = NSRect(x: 0, y: 0, width: 260, height: 40)
        regionHosting.layoutSubtreeIfNeeded()
        #expect(regionHosting.frame.width == 260)
        #expect(regionHosting.frame.height == 40)
    }

    @Test func testSketchEntityDeleteButtonAccessibilityAndHelp() {
        #expect(InspectorSketchEntityRow.deleteEntityAccessibilityLabel == "Delete Entity")
        #expect(InspectorSketchEntityRow.deleteEntityHelpText == "Delete Entity")
    }
}
