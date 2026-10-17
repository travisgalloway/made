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

    @Test @MainActor func testWorkspaceInteractiveSketchDragCoalescedUndo() {
        let workspace = WorkspaceModel()
        let undo = UndoManager()
        workspace.document.undoManager = undo

        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let sketchData = SketchFeatureData(planeName: "XY", entities: [line])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)
        undo.removeAllActions()

        workspace.selectFeature(feature.id)

        // Begin interactive drag
        workspace.beginInteractiveSketchDrag(featureId: feature.id, entityId: line.id)

        // Intermediate high-frequency drag events (e.g. 10 updates)
        for i in 1...10 {
            let targetPos = SIMD2<Double>(Double(10 + i), Double(i))
            let drag = DragTarget(entityId: line.id, endpoint: .end, targetPosition: targetPos)
            workspace.solveSketchDrag(featureId: feature.id, dragTarget: drag)
        }

        // End interactive drag
        workspace.endInteractiveSketchDrag(featureId: feature.id)

        // Verify entity moved to final position
        if case .sketch(let finalSketch) = workspace.document.feature(for: feature.id)?.operation {
            let solvedLine = finalSketch.entities.first(where: { $0.id == line.id })
            #expect(abs((solvedLine?.endPoint?.x ?? 0) - 20.0) < 1e-3)
            #expect(abs((solvedLine?.endPoint?.y ?? 0) - 10.0) < 1e-3)
        } else {
            Issue.record("Expected sketch feature")
        }

        // Verify undo: only a SINGLE undo step exists
        #expect(undo.canUndo)
        #expect(undo.undoActionName == "Drag Sketch Entity")

        undo.undo()

        // Verify undo restores initial geometry
        if case .sketch(let restoredSketch) = workspace.document.feature(for: feature.id)?.operation {
            let restoredLine = restoredSketch.entities.first(where: { $0.id == line.id })
            #expect(abs((restoredLine?.endPoint?.x ?? 0) - 10.0) < 1e-3)
            #expect(abs((restoredLine?.endPoint?.y ?? 0) - 0.0) < 1e-3)
        } else {
            Issue.record("Expected sketch feature")
        }

        // Verify cannot undo again (it was coalesced into exactly 1 step)
        #expect(!undo.canUndo)

        // Redo restores final geometry
        #expect(undo.canRedo)
        undo.redo()
        if case .sketch(let redoneSketch) = workspace.document.feature(for: feature.id)?.operation {
            let redoneLine = redoneSketch.entities.first(where: { $0.id == line.id })
            #expect(abs((redoneLine?.endPoint?.x ?? 0) - 20.0) < 1e-3)
            #expect(abs((redoneLine?.endPoint?.y ?? 0) - 10.0) < 1e-3)
        }
    }

    @Test @MainActor func testWorkspaceSketchDragSolving() {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(0, 10))
        let perp = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB], constraints: [perp])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)

        workspace.selectFeature(feature.id)

        // Drag lineA endpoint
        let drag = DragTarget(entityId: lineA.id, endpoint: .end, targetPosition: SIMD2<Double>(10, 10))
        workspace.solveSketchDrag(featureId: feature.id, dragTarget: drag)

        if case .sketch(let updated) = workspace.document.feature(for: feature.id)?.operation {
            let sA = updated.entities.first(where: { $0.id == lineA.id })
            let sB = updated.entities.first(where: { $0.id == lineB.id })
            guard let sAp = sA?.startPoint, let eAp = sA?.endPoint,
                  let sBp = sB?.startPoint, let eBp = sB?.endPoint else {
                Issue.record("Expected line entities")
                return
            }
            #expect(abs(eAp.x - 10.0) < 1e-2)
            #expect(abs(eAp.y - 10.0) < 1e-2)
            let vA = eAp - sAp
            let vB = eBp - sBp
            let dot = vA.x * vB.x + vA.y * vB.y
            #expect(abs(dot) < 1e-2, "Perpendicularity must hold after drag solve")
        }

        #expect(workspace.dofStatus(for: lineA.id) != .inactive)
        #expect(workspace.overConstrainedMessage == nil)
    }

    @Test @MainActor func testDocumentModelSetSketchConstraintDrivenUndoRedo() {
        let doc = DocumentModel()
        let undo = UndoManager()
        doc.undoManager = undo

        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 10), end: SIMD2<Double>(10, 10))
        let constraint = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id], isDriven: false)
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB], constraints: [constraint])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        doc.addFeature(feature)
        undo.removeAllActions()

        // Mutate to driven
        let result = doc.setSketchConstraintDriven(in: feature.id, constraintId: constraint.id, isDriven: true)
        #expect(result == .success(()))

        if case .sketch(let data) = doc.feature(for: feature.id)?.operation {
            #expect(data.constraints.first?.isDriven == true)
        } else {
            Issue.record("Expected sketch feature")
        }
        #expect(undo.canUndo)
        #expect(undo.undoActionName == "Convert Constraint to Driven")

        // Undo mutation
        undo.undo()
        if case .sketch(let data) = doc.feature(for: feature.id)?.operation {
            #expect(data.constraints.first?.isDriven == false)
        } else {
            Issue.record("Expected sketch feature")
        }
        #expect(undo.canRedo)
        #expect(undo.redoActionName == "Convert Constraint to Driven")

        // Redo mutation
        undo.redo()
        if case .sketch(let data) = doc.feature(for: feature.id)?.operation {
            #expect(data.constraints.first?.isDriven == true)
        } else {
            Issue.record("Expected sketch feature")
        }

        // Mutate back to driving
        let drivingResult = doc.setSketchConstraintDriven(in: feature.id, constraintId: constraint.id, isDriven: false)
        #expect(drivingResult == .success(()))
        #expect(undo.undoActionName == "Convert Constraint to Driving")
        if case .sketch(let data) = doc.feature(for: feature.id)?.operation {
            #expect(data.constraints.first?.isDriven == false)
        }
    }

    @Test @MainActor func testWorkspaceConflictingConstraintsDiagnosisAndDrivenResolution() {
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

        // Conflicting diagnosis populated
        #expect(workspace.conflictingConstraintIds.contains(c1.id))
        #expect(workspace.conflictingConstraintIds.contains(c2.id))
        #expect(workspace.overConstrainedMessage != nil)
        if case .overConstrained = workspace.sketchDOFStatus {} else {
            Issue.record("Expected overConstrained DOF status, got \(workspace.sketchDOFStatus)")
        }

        // Convert perpendicular constraint to driven
        workspace.setSketchConstraintDriven(in: feature.id, constraintId: c2.id, isDriven: true)

        #expect(workspace.conflictingConstraintIds.isEmpty)
        #expect(workspace.overConstrainedMessage == nil)
        if case .overConstrained = workspace.sketchDOFStatus {
            Issue.record("Expected status to recover from over-constrained after driven conversion")
        }

        // Convert back to driving: conflict reappears
        workspace.toggleSketchConstraintDriven(in: feature.id, constraintId: c2.id)
        #expect(workspace.conflictingConstraintIds.contains(c1.id))
        #expect(workspace.conflictingConstraintIds.contains(c2.id))
        #expect(workspace.overConstrainedMessage != nil)
        if case .overConstrained = workspace.sketchDOFStatus {} else {
            Issue.record("Expected overConstrained DOF status to return")
        }
    }

    @Test @MainActor func testWorkspaceRedundantConstraintsDiagnosisAndDrivenResolution() {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)

        workspace.selectFeature(feature.id)

        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        workspace.addSketchConstraint(to: feature.id, constraint: c1)

        let c2 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        workspace.addSketchConstraint(to: feature.id, constraint: c2)

        // Redundancy detected
        #expect(workspace.redundantConstraintIds.contains(c1.id) || workspace.redundantConstraintIds.contains(c2.id))
        #expect(workspace.redundantConstraintsMessage != nil)
        if case .overConstrained = workspace.sketchDOFStatus {
            Issue.record("Redundant system should converge, not report overConstrained")
        }

        // Target whichever constraint was marked redundant
        let redundantId = workspace.redundantConstraintIds.first ?? c2.id
        workspace.setSketchConstraintDriven(in: feature.id, constraintId: redundantId, isDriven: true)

        #expect(workspace.redundantConstraintIds.isEmpty)
        #expect(workspace.redundantConstraintsMessage == nil)

        // Toggling back to driving restores redundancy diagnosis
        workspace.toggleSketchConstraintDriven(in: feature.id, constraintId: redundantId)
        #expect(!workspace.redundantConstraintIds.isEmpty)
        #expect(workspace.redundantConstraintsMessage != nil)
    }

    @Test @MainActor func testWorkspaceUndoRedoRestoresConstraintDiagnostics() {
        let workspace = WorkspaceModel()
        let undo = UndoManager()
        workspace.document.undoManager = undo

        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB], constraints: [c1, c2])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)
        undo.removeAllActions()

        workspace.selectFeature(feature.id)

        #expect(workspace.conflictingConstraintIds.contains(c1.id))
        #expect(workspace.conflictingConstraintIds.contains(c2.id))
        #expect(workspace.overConstrainedMessage != nil)

        // Convert c2 to driven
        workspace.setSketchConstraintDriven(in: feature.id, constraintId: c2.id, isDriven: true)
        #expect(workspace.conflictingConstraintIds.isEmpty)
        #expect(workspace.overConstrainedMessage == nil)

        // Undo restores conflict diagnostics
        workspace.undo()
        #expect(workspace.conflictingConstraintIds.contains(c1.id))
        #expect(workspace.conflictingConstraintIds.contains(c2.id))
        #expect(workspace.overConstrainedMessage != nil)

        // Redo restores resolution
        workspace.redo()
        #expect(workspace.conflictingConstraintIds.isEmpty)
        #expect(workspace.overConstrainedMessage == nil)
    }

    @Test @MainActor func testWorkspaceDeselectClearsDiagnosticState() {
        let workspace = WorkspaceModel()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])
        let sketchData = SketchFeatureData(planeName: "XY", entities: [lineA, lineB], constraints: [c1, c2])
        let sketchFeature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        let nonSketchFeature = Feature(name: "Box 1", operation: .primitive(.box(BoxParams(width: 10, depth: 10, height: 10))))
        workspace.document.addFeature(sketchFeature)
        workspace.document.addFeature(nonSketchFeature)

        workspace.selectFeature(sketchFeature.id)
        #expect(!workspace.conflictingConstraintIds.isEmpty)
        #expect(workspace.overConstrainedMessage != nil)

        // Selecting a non-sketch feature clears diagnostic state
        workspace.selectFeature(nonSketchFeature.id)
        #expect(workspace.conflictingConstraintIds.isEmpty)
        #expect(workspace.redundantConstraintIds.isEmpty)
        #expect(workspace.overConstrainedMessage == nil)
        #expect(workspace.redundantConstraintsMessage == nil)
        #expect(workspace.sketchDOFStatus == .inactive)

        // Select sketch feature again
        workspace.selectFeature(sketchFeature.id)
        #expect(!workspace.conflictingConstraintIds.isEmpty)

        // Explicit .inactive status clears diagnostic state
        workspace.setSketchDOFStatus(.inactive)
        #expect(workspace.conflictingConstraintIds.isEmpty)
        #expect(workspace.redundantConstraintIds.isEmpty)
        #expect(workspace.overConstrainedMessage == nil)
        #expect(workspace.redundantConstraintsMessage == nil)
    }
}
