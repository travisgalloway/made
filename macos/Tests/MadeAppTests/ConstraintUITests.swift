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
}
