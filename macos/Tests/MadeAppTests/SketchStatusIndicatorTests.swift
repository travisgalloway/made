import Testing
import SwiftUI
import AppKit
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct SketchStatusIndicatorTests {

    @Test func testTreeIconSystemImageAndColorMapping() {
        #expect(NavigatorSketchRow.treeIconSystemImage(for: .inactive) == "pencil.and.ruler.fill")
        #expect(NavigatorSketchRow.treeIconColor(for: .inactive) == .purple)

        #expect(NavigatorSketchRow.treeIconSystemImage(for: .underConstrained(dof: 4)) == "pencil.and.ruler.fill")
        #expect(NavigatorSketchRow.treeIconColor(for: .underConstrained(dof: 4)) == .blue)

        #expect(NavigatorSketchRow.treeIconSystemImage(for: .fullyConstrained) == "checkmark.circle.fill")
        #expect(NavigatorSketchRow.treeIconColor(for: .fullyConstrained) == .green)

        #expect(NavigatorSketchRow.treeIconSystemImage(for: .overConstrained(dof: 1)) == "exclamationmark.triangle.fill")
        #expect(NavigatorSketchRow.treeIconColor(for: .overConstrained(dof: 1)) == .red)
    }

    @Test func testSketchDOFBadgeFormatting() {
        #expect(NavigatorSketchRow.badgeText(for: .inactive) == "")
        #expect(NavigatorSketchRow.badgeText(for: .underConstrained(dof: 2)) == "2 DOF")
        #expect(NavigatorSketchRow.badgeText(for: .fullyConstrained) == "Fully Defined")
        #expect(NavigatorSketchRow.badgeText(for: .overConstrained(dof: 0)) == "Over-constrained")
        #expect(NavigatorSketchRow.badgeText(for: .overConstrained(dof: 3)) == "Over-constrained")

        #expect(ViewportStatusBar.dofColor(for: .inactive) == nil)
        #expect(ViewportStatusBar.dofColor(for: .underConstrained(dof: 2)) == .blue)
        #expect(ViewportStatusBar.dofColor(for: .fullyConstrained) == .green)
        #expect(ViewportStatusBar.dofColor(for: .overConstrained(dof: 0)) == .red)
    }

    @Test func testSketchRowSubtitleSummaryFormatting() {
        #expect(NavigatorSketchRow.subtitle(entityCount: 0, status: .inactive) == "0 entities")
        #expect(NavigatorSketchRow.subtitle(entityCount: 3, status: .inactive) == "3 entities")
        #expect(NavigatorSketchRow.subtitle(entityCount: 1, status: .underConstrained(dof: 4)) == "1 entities • 4 DOF remaining")
        #expect(NavigatorSketchRow.subtitle(entityCount: 4, status: .fullyConstrained) == "4 entities • Fully constrained")
        #expect(NavigatorSketchRow.subtitle(entityCount: 2, status: .overConstrained(dof: 2)) == "2 entities • Over-constrained")

        #expect(NavigatorSketchRow.accessibilityLabel(featureName: "Base Sketch", entityCount: 4, status: .underConstrained(dof: 2)) == "Base Sketch, Sketch, 4 entities, DOF: 2 under")
        #expect(NavigatorSketchRow.accessibilityLabel(featureName: "Profile", entityCount: 3, status: .fullyConstrained) == "Profile, Sketch, 3 entities, DOF: fully constrained")
    }

    @Test @MainActor func testWorkspaceSketchDOFStatusForSelectedAndUnselectedFeatures() {
        let workspace = WorkspaceModel()

        // Create unselected sketch with 1 line
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let sketchDataA = SketchFeatureData(planeName: "XY", entities: [line], constraints: [])
        let featureA = Feature(name: "Sketch A", operation: .sketch(sketchDataA))
        workspace.document.addFeature(featureA)

        // Initially nothing selected
        workspace.document.clearSelection()

        // Unselected feature query evaluates solver directly
        let statusUnselected = workspace.sketchDOFStatus(for: featureA)
        #expect(statusUnselected == .underConstrained(dof: 4))
        #expect(workspace.sketchDOFStatus(for: featureA.id) == .underConstrained(dof: 4))

        // Select featureA
        workspace.selectFeature(featureA.id)
        #expect(workspace.selectedSketchFeature?.id == featureA.id)
        #expect(workspace.sketchDOFStatus == .underConstrained(dof: 4))
        #expect(workspace.sketchDOFStatus(for: featureA) == .underConstrained(dof: 4))

        // Mutate live workspace status to verify it returns live status when selected
        workspace.setSketchDOFStatus(.fullyConstrained)
        #expect(workspace.sketchDOFStatus(for: featureA) == .fullyConstrained)
        #expect(workspace.sketchDOFStatus(for: featureA.id) == .fullyConstrained)
    }

    @Test @MainActor func testEmptySketchStatusIsInactive() {
        let workspace = WorkspaceModel()
        let emptySketch = Feature(name: "Empty", operation: .sketch(SketchFeatureData(planeName: "XY", entities: [])))
        workspace.document.addFeature(emptySketch)

        let status = workspace.sketchDOFStatus(for: emptySketch)
        #expect(status == .inactive)
        #expect(status.remainingDOF == nil)
        #expect(status.isInactive)
        #expect(status.badgeText == "")
        #expect(status.summaryDescription == "No entities")
    }

    @Test @MainActor func testSingleLineUnderConstrained() {
        let workspace = WorkspaceModel()
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(20, 0))
        let feature = Feature(name: "Line Sketch", operation: .sketch(SketchFeatureData(planeName: "XY", entities: [line])))
        workspace.document.addFeature(feature)

        let statusInitial = workspace.sketchDOFStatus(for: feature)
        #expect(statusInitial == .underConstrained(dof: 4))
        #expect(statusInitial.remainingDOF == 4)
        #expect(statusInitial.isUnderConstrained)

        // Add horizontal constraint
        let horiz = SketchConstraint(kind: .horizontal, entityIds: [line.id])
        _ = workspace.document.addSketchConstraint(to: feature.id, constraint: horiz)

        guard let updatedFeat = workspace.document.feature(for: feature.id) else {
            Issue.record("Expected updated feature")
            return
        }
        let statusConstrained = workspace.sketchDOFStatus(for: updatedFeat)
        #expect(statusConstrained == .underConstrained(dof: 3))
        #expect(statusConstrained.remainingDOF == 3)
    }

    @Test @MainActor func testFullyConstrainedSketch() {
        let workspace = WorkspaceModel()
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let feature = Feature(name: "Sketch", operation: .sketch(SketchFeatureData(planeName: "XY", entities: [line])))
        workspace.document.addFeature(feature)

        // Select feature and mark fully constrained
        workspace.selectFeature(feature.id)
        workspace.setSketchDOFStatus(.fullyConstrained)

        let status = workspace.sketchDOFStatus(for: feature)
        #expect(status == .fullyConstrained)
        #expect(status.remainingDOF == 0)
        #expect(status.isFullyConstrained)
        #expect(status.badgeText == "Fully Defined")
        #expect(status.summaryDescription == "Fully constrained")

        // Also test constraint solver computeDOFStatus directly for a fully constrained system
        let axis = SketchEntity.line(start: SIMD2<Double>(0, -50), end: SIMD2<Double>(0, 50))
        let lineA = SketchEntity.line(start: SIMD2<Double>(-15, 0), end: SIMD2<Double>(-15, 30))
        let lineB = SketchEntity.line(start: SIMD2<Double>(10, 2), end: SIMD2<Double>(12, 32))
        let cSym = SketchConstraint(kind: .symmetric, entityIds: [lineA.id, lineB.id], referenceEntityId: axis.id)
        let system = ConstraintSystem(
            entities: [axis, lineA, lineB],
            constraints: [cSym],
            fixedEntityIds: [axis.id, lineA.id]
        )
        let solverStatus = ConstraintSolver.computeDOFStatus(system: system)
        #expect(solverStatus == .fullyConstrained)
        #expect(solverStatus.remainingDOF == 0)
    }

    @Test @MainActor func testOverConstrainedSketch() {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))

        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])

        let feature = Feature(
            name: "Conflicting Sketch",
            operation: .sketch(SketchFeatureData(planeName: "XY", entities: [lineA, lineB], constraints: [c1, c2]))
        )
        workspace.document.addFeature(feature)

        let status = workspace.sketchDOFStatus(for: feature)
        #expect(status.isOverConstrained)
        #expect(status.badgeText == "Over-constrained")
        #expect(status.summaryDescription == "Over-constrained")
    }

    @Test @MainActor func testSwitchingSelectedFeaturePreservesTreeStatus() {
        let workspace = WorkspaceModel()

        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let sketchA = Feature(name: "Sketch A", operation: .sketch(SketchFeatureData(planeName: "XY", entities: [lineA])))
        workspace.document.addFeature(sketchA)

        let lineB1 = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB2 = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineB1.id, lineB2.id])
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineB1.id, lineB2.id])
        let sketchB = Feature(name: "Sketch B", operation: .sketch(SketchFeatureData(planeName: "XY", entities: [lineB1, lineB2], constraints: [c1, c2])))
        workspace.document.addFeature(sketchB)

        // Select sketchA
        workspace.selectFeature(sketchA.id)
        #expect(workspace.sketchDOFStatus(for: sketchA) == .underConstrained(dof: 4))
        #expect(workspace.sketchDOFStatus(for: sketchB).isOverConstrained)

        // Select sketchB
        workspace.selectFeature(sketchB.id)
        #expect(workspace.sketchDOFStatus(for: sketchA) == .underConstrained(dof: 4))
        #expect(workspace.sketchDOFStatus(for: sketchB).isOverConstrained)

        // Clear selection
        workspace.document.clearSelection()
        #expect(workspace.sketchDOFStatus(for: sketchA) == .underConstrained(dof: 4))
        #expect(workspace.sketchDOFStatus(for: sketchB).isOverConstrained)
    }

    @Test @MainActor func testNavigatorSidebarViewInstantiationWithSketchesInAllStates() {
        let workspace = WorkspaceModel()

        // 1. Inactive sketch (empty)
        let inactiveFeat = Feature(name: "Inactive Sketch", operation: .sketch(SketchFeatureData(planeName: "XY", entities: [])))
        workspace.document.addFeature(inactiveFeat)

        // 2. Under-constrained sketch
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let underFeat = Feature(name: "Under Sketch", operation: .sketch(SketchFeatureData(planeName: "XY", entities: [line])))
        workspace.document.addFeature(underFeat)

        // 3. Over-constrained sketch
        let l1 = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let l2 = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let c1 = SketchConstraint(kind: .parallel, entityIds: [l1.id, l2.id])
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [l1.id, l2.id])
        let overFeat = Feature(name: "Over Sketch", operation: .sketch(SketchFeatureData(planeName: "XY", entities: [l1, l2], constraints: [c1, c2])))
        workspace.document.addFeature(overFeat)

        let sidebar = NavigatorSidebarView().environment(workspace)
        let hostingView = NSHostingView(rootView: sidebar)
        hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 600)
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.frame.width == 260)
        #expect(hostingView.frame.height == 600)
    }
}
