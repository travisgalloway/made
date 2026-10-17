import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct ConstraintUITests {

    @Test @MainActor func testDocumentModelConstraintMutationsWithUndoRedo() {
        let doc = DocumentModel()
        let undo = UndoManager()
        doc.undoManager = undo

        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 10), end: SIMD2<Double>(10, 10))
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        doc.addFeature(feature)
        undo.removeAllActions()

        let constraint = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])

        // Add constraint
        let addResult = doc.addSketchConstraint(to: feature.id, constraint: constraint)
        #expect(addResult == .success(()))

        if case .sketch(let data) = doc.feature(for: feature.id)?.operation {
            #expect(data.constraints.count == 1)
            #expect(data.constraints.first?.id == constraint.id)
        } else {
            Issue.record("Expected sketch feature")
        }

        // Undo
        undo.undo()
        if case .sketch(let data) = doc.feature(for: feature.id)?.operation {
            #expect(data.constraints.isEmpty)
        } else {
            Issue.record("Expected sketch feature")
        }

        // Redo
        undo.redo()
        if case .sketch(let data) = doc.feature(for: feature.id)?.operation {
            #expect(data.constraints.count == 1)
            #expect(data.constraints.first?.id == constraint.id)
        } else {
            Issue.record("Expected sketch feature")
        }

        // Remove constraint
        let removeResult = doc.removeSketchConstraint(from: feature.id, constraintId: constraint.id)
        #expect(removeResult == .success(()))
        if case .sketch(let data) = doc.feature(for: feature.id)?.operation {
            #expect(data.constraints.isEmpty)
        }

        // Undo remove
        undo.undo()
        if case .sketch(let data) = doc.feature(for: feature.id)?.operation {
            #expect(data.constraints.count == 1)
        }
    }

    @Test @MainActor func testWorkspaceModelLiveInferenceAndSolving() {
        let workspace = WorkspaceModel()
        let undo = UndoManager()
        workspace.document.undoManager = undo

        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(100, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 20), end: SIMD2<Double>(100, 22)) // ~1.1 degrees off horizontal
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)

        // Select sketch feature
        workspace.selectFeature(feature.id)

        #expect(workspace.isLiveInferenceEnabled)
        #expect(!workspace.inferredConstraints.isEmpty)
        guard let inferred = workspace.inferredConstraints.first(where: { $0.kind == .parallel }) else {
            Issue.record("Expected parallel inference candidate")
            return
        }

        // Apply inferred constraint
        workspace.applyInferredConstraint(inferred)

        if case .sketch(let updated) = workspace.document.feature(for: feature.id)?.operation {
            #expect(updated.constraints.count == 1)
            #expect(updated.constraints.first?.kind == .parallel)
        }

        // Toggle live inference off
        workspace.toggleLiveInference()
        #expect(!workspace.isLiveInferenceEnabled)
        #expect(workspace.inferredConstraints.isEmpty)
    }

    @Test @MainActor func testWorkspaceOverConstrainedStateAndMessage() {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)

        workspace.selectFeature(feature.id)

        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        workspace.addSketchConstraint(to: feature.id, constraint: c1)

        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])
        workspace.addSketchConstraint(to: feature.id, constraint: c2)

        if case .overConstrained = workspace.sketchDOFStatus {
            // Expected
        } else {
            Issue.record("Expected overConstrained DOF status, got \(workspace.sketchDOFStatus)")
        }
        #expect(workspace.overConstrainedMessage != nil)

        // Remove one conflicting constraint
        workspace.removeSketchConstraint(from: feature.id, constraintId: c2.id)
        if case .overConstrained = workspace.sketchDOFStatus {
            Issue.record("Expected status to recover from over-constrained after removing conflict")
        } else {
            // Expected recovery
        }
        #expect(workspace.overConstrainedMessage == nil)
    }

    @Test @MainActor func testWorkspaceApplyConstraintCommands() {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 8))
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)

        workspace.selectFeature(feature.id)

        workspace.applyConstraintToSelectedSketch(.parallel)

        if case .sketch(let updated) = workspace.document.feature(for: feature.id)?.operation {
            #expect(updated.constraints.count == 1)
            #expect(updated.constraints.first?.kind == .parallel)
        } else {
            Issue.record("Expected sketch feature with parallel constraint")
        }
    }

    @Test @MainActor func testWorkspaceDimensionSketchLineAndSelection() throws {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)

        // Select sketch entity
        workspace.selectSketchEntity(featureId: feature.id, entityId: lineA.id)
        #expect(workspace.selectedSketchEntity?.entity.id == lineA.id)
        #expect(workspace.selectedSketchLineEntity?.entity.id == lineA.id)
        #expect(workspace.hasAvailableSketchLine)

        // Dimension sketch line
        let updated = try workspace.dimensionSketchLine(featureId: feature.id, entityId: lineA.id, length: 30.0)
        #expect(updated.length == 30.0)
        #expect(updated.endPoint == SIMD2<Double>(30, 0))

        if case .sketch(let data) = workspace.document.feature(for: feature.id)?.operation {
            #expect(data.entities.first?.length == 30.0)
        } else {
            Issue.record("Expected sketch feature with updated entity")
        }
    }

    @Test @MainActor func testWorkspaceDimensionSelectionInvariance() {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let circle = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 5.0)
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB, circle])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)

        // Select line A
        workspace.selectSketchEntity(featureId: feature.id, entityId: lineA.id)
        #expect(workspace.selectedSketchLineEntity?.entity.id == lineA.id)

        // Switch selection to line B
        workspace.selectSketchEntity(featureId: feature.id, entityId: lineB.id)
        #expect(workspace.selectedSketchLineEntity?.entity.id == lineB.id)

        // Switch selection to circle
        workspace.selectSketchEntity(featureId: feature.id, entityId: circle.id)
        #expect(workspace.selectedSketchEntity?.entity.id == circle.id)
        #expect(workspace.selectedSketchLineEntity == nil)

        // Clear selection
        workspace.document.selection = []
        #expect(workspace.selectedSketchEntity == nil)
        #expect(workspace.selectedSketchLineEntity == nil)
    }

    @Test @MainActor func testWorkspaceDimensionOverConstrainedThrows() {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)

        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        workspace.addSketchConstraint(to: feature.id, constraint: c1)
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])
        workspace.addSketchConstraint(to: feature.id, constraint: c2)

        #expect(throws: SketchError.self) {
            try workspace.dimensionSketchLine(featureId: feature.id, entityId: lineA.id, length: 25.0)
        }
    }

    @Test @MainActor func testWorkspaceEntityDOFTrackingAndAccessor() {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 8))
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)

        // Select sketch feature
        workspace.selectFeature(feature.id)

        // Initially without constraints: lineA and lineB report 4 DOF
        #expect(workspace.dofStatus(for: lineA.id) == .underConstrained(dof: 4))
        #expect(workspace.dofStatus(for: lineB.id) == .underConstrained(dof: 4))
        #expect(workspace.dofStatus(for: UUID()) == .inactive)

        // Add horizontal constraint on lineA
        let c1 = SketchConstraint(kind: .horizontal, entityIds: [lineA.id])
        workspace.addSketchConstraint(to: feature.id, constraint: c1)

        // Solving updates entity DOF status: lineA reduced to 3 DOF, lineB unchanged at 4 DOF
        #expect(workspace.dofStatus(for: lineA.id) == .underConstrained(dof: 3))
        #expect(workspace.dofStatus(for: lineB.id) == .underConstrained(dof: 4))

        // Deselect sketch: entityDOFStatus is cleared
        workspace.setSketchDOFStatus(.inactive)
        #expect(workspace.entityDOFStatus.isEmpty)
        #expect(workspace.dofStatus(for: lineA.id) == .inactive)
    }

    @Test @MainActor func testViewportStatusBarSemanticColorMapping() {
        #expect(ViewportStatusBar.dofColor(for: .inactive) == nil)
        #expect(ViewportStatusBar.dofColor(for: .underConstrained(dof: 3)) == .blue)
        #expect(ViewportStatusBar.dofColor(for: .fullyConstrained) == .green)
        #expect(ViewportStatusBar.dofColor(for: .overConstrained(dof: 0)) == .red)
    }
}
