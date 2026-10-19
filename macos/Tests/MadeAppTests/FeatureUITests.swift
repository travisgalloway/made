import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct FeatureUITests {

    @Test @MainActor func testSketchLockAndUnlockUndoRedo() async {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1])
        #expect(sketch.isLocked == false)

        workspace.document.undoManager?.removeAllActions()
        workspace.document.undoManager?.groupsByEvent = false

        // Select sketch
        workspace.selectFeature(sketch.id)
        #expect(workspace.canDeleteSelectedFeature == true)
        #expect(workspace.canDeleteSelectedObject == true)

        // Lock the sketch
        workspace.document.undoManager?.beginUndoGrouping()
        workspace.toggleFeatureLocked(sketch.id)
        workspace.document.undoManager?.endUndoGrouping()

        #expect(workspace.document.feature(for: sketch.id)?.isLocked == true)
        #expect(workspace.canDeleteSelectedFeature == false)
        #expect(workspace.canDeleteSelectedObject == false)

        // Locked feature rejects deletion request
        workspace.requestDeleteFeature(sketch.id)
        #expect(workspace.pendingDeleteFeatureId == nil)

        // Unlock the sketch
        workspace.document.undoManager?.beginUndoGrouping()
        workspace.toggleFeatureLocked(sketch.id)
        workspace.document.undoManager?.endUndoGrouping()

        #expect(workspace.document.feature(for: sketch.id)?.isLocked == false)
        #expect(workspace.canDeleteSelectedFeature == true)

        // Undo unlock -> locked again
        await workspace.undo().value
        #expect(workspace.document.feature(for: sketch.id)?.isLocked == true)
        #expect(workspace.canDeleteSelectedFeature == false)

        // Redo unlock -> unlocked
        await workspace.redo().value
        #expect(workspace.document.feature(for: sketch.id)?.isLocked == false)
        #expect(workspace.canDeleteSelectedFeature == true)
    }

    @Test @MainActor func testDatumPlaneLockAndUnlockUndoRedo() async {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let datumPlane = workspace.document.addDatumPlaneFeature(
            name: "Test Plane",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 10.0)
        )
        #expect(datumPlane.isLocked == false)

        workspace.document.undoManager?.removeAllActions()
        workspace.document.undoManager?.groupsByEvent = false

        workspace.selectFeature(datumPlane.id)
        #expect(workspace.canDeleteSelectedFeature == true)
        #expect(workspace.canDeleteSelectedObject == true)

        // Lock datum plane
        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setFeatureLocked(id: datumPlane.id, isLocked: true)
        workspace.document.undoManager?.endUndoGrouping()

        #expect(workspace.document.feature(for: datumPlane.id)?.isLocked == true)
        #expect(workspace.canDeleteSelectedFeature == false)
        #expect(workspace.canDeleteSelectedObject == false)

        // Deletion is refused
        workspace.requestDeleteFeature(datumPlane.id)
        #expect(workspace.pendingDeleteFeatureId == nil)

        // Unlock datum plane
        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setFeatureLocked(id: datumPlane.id, isLocked: false)
        workspace.document.undoManager?.endUndoGrouping()

        #expect(workspace.document.feature(for: datumPlane.id)?.isLocked == false)

        // Undo unlock
        await workspace.undo().value
        #expect(workspace.document.feature(for: datumPlane.id)?.isLocked == true)

        // Redo unlock
        await workspace.redo().value
        #expect(workspace.document.feature(for: datumPlane.id)?.isLocked == false)
    }

    @Test @MainActor func testDeleteSketchFeatureWorkflow() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1])

        #expect(workspace.pendingDeleteFeatureId == nil)
        #expect(workspace.featurePendingDeletion == nil)

        // 1. Request deletion
        workspace.requestDeleteFeature(sketch.id)
        #expect(workspace.pendingDeleteFeatureId == sketch.id)
        #expect(workspace.featurePendingDeletion?.id == sketch.id)

        // 2. Cancel deletion
        workspace.cancelDeleteFeature()
        #expect(workspace.pendingDeleteFeatureId == nil)
        #expect(workspace.featurePendingDeletion == nil)
        #expect(workspace.document.feature(for: sketch.id) != nil)

        // 3. Request and Confirm deletion
        workspace.requestDeleteFeature(sketch.id)
        #expect(workspace.pendingDeleteFeatureId == sketch.id)
        workspace.confirmDeleteFeature()
        #expect(workspace.pendingDeleteFeatureId == nil)
        #expect(workspace.document.feature(for: sketch.id) == nil)
    }

    @Test @MainActor func testDeleteDatumFeatureCascadesErrorsToDownstreamSketch() async throws {
        let workspace = WorkspaceModel()
        workspace.setUp()

        // 1. Datum Plane
        let datumPlane = workspace.document.addDatumPlaneFeature(
            name: "Base Datum Plane",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 10.0)
        )

        // 2. Closed sketch referencing Datum Plane
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let l2 = SketchEntity.line(start: SIMD2(20, 0), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(0, 20))
        let l4 = SketchEntity.line(start: SIMD2(0, 20), end: SIMD2(0, 0))
        let sketch = workspace.document.addSketchFeature(planeName: datumPlane.name, entities: [l1, l2, l3, l4])
        var updatedSketch = sketch
        updatedSketch.references = [Reference.feature(datumPlane.id)]
        if case .sketch(var sData) = updatedSketch.operation {
            sData.datumPlaneFeatureId = datumPlane.id
            updatedSketch.operation = .sketch(sData)
        }
        _ = workspace.document.updateFeature(updatedSketch)

        // 3. Extrude referencing Sketch
        let extrude = try workspace.document.extrudeSketch(sketchFeatureId: sketch.id, distance: 15.0)

        // Initial regeneration: all healthy
        await KernelRegeneration.regenerate(document: workspace.document, client: workspace.kernelClient)
        #expect(workspace.document.feature(for: datumPlane.id)?.errorState == nil)
        #expect(workspace.document.feature(for: sketch.id)?.errorState == nil)
        #expect(workspace.document.feature(for: extrude.id)?.errorState == nil)

        workspace.document.undoManager?.removeAllActions()
        workspace.document.undoManager?.groupsByEvent = false

        // 4. Delete the Datum Plane
        workspace.document.undoManager?.beginUndoGrouping()
        await workspace.removeFeature(datumPlane.id).value
        workspace.document.undoManager?.endUndoGrouping()

        #expect(workspace.document.feature(for: datumPlane.id) == nil)

        // Downstream Sketch gets typed reference-broken error
        let brokenSketch = workspace.document.feature(for: sketch.id)
        #expect(brokenSketch?.errorState?.code == "reference-broken")
        #expect(brokenSketch?.errorState?.severity == .error)

        // Downstream Extrude gets parent-failed warning cascade
        let brokenExtrude = workspace.document.feature(for: extrude.id)
        #expect(brokenExtrude?.errorState?.code == "parent-failed")
        #expect(brokenExtrude?.errorState?.severity == .warning)

        // 5. Undo deletion
        await workspace.undo().value

        // Datum Plane restored
        #expect(workspace.document.feature(for: datumPlane.id) != nil)

        // Downstream errors cleared
        let restoredSketch = workspace.document.feature(for: sketch.id)
        #expect(restoredSketch?.errorState == nil)

        let restoredExtrude = workspace.document.feature(for: extrude.id)
        #expect(restoredExtrude?.errorState == nil)

        // 6. Redo deletion
        await workspace.redo().value

        #expect(workspace.document.feature(for: datumPlane.id) == nil)
        #expect(workspace.document.feature(for: sketch.id)?.errorState?.code == "reference-broken")
        #expect(workspace.document.feature(for: extrude.id)?.errorState?.code == "parent-failed")
    }

    @Test @MainActor func testDeleteLockedFeatureRefused() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let datumPlane = workspace.document.addDatumPlaneFeature(
            name: "Locked Plane",
            data: DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 5.0)
        )
        workspace.setFeatureLocked(id: datumPlane.id, isLocked: true)

        workspace.selectFeature(datumPlane.id)
        #expect(workspace.canDeleteSelectedFeature == false)
        #expect(workspace.canDeleteSelectedObject == false)

        workspace.deleteSelectedObject()
        #expect(workspace.pendingDeleteFeatureId == nil)

        workspace.requestDeleteFeature(datumPlane.id)
        #expect(workspace.pendingDeleteFeatureId == nil)
        #expect(workspace.document.feature(for: datumPlane.id) != nil)
    }

    @Test @MainActor func testKeyboardDeleteSelectedFeature() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1])

        // Select the sketch
        workspace.selectFeature(sketch.id)
        #expect(workspace.canDeleteSelectedObject == true)
        #expect(workspace.canDeleteSelectedFeature == true)
        #expect(workspace.pendingDeleteFeatureId == nil)

        // Edit > Delete triggers deleteSelectedObject()
        workspace.deleteSelectedObject()
        #expect(workspace.pendingDeleteFeatureId == sketch.id)

        // Confirm deletion removes the sketch
        workspace.confirmDeleteFeature()
        #expect(workspace.pendingDeleteFeatureId == nil)
        #expect(workspace.document.feature(for: sketch.id) == nil)
    }

    @Test @MainActor func testConfirmDeleteOnExternallyDeletedFeatureSafelyNoOps() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1])

        workspace.requestDeleteFeature(sketch.id)
        #expect(workspace.pendingDeleteFeatureId == sketch.id)

        // Simulate concurrent or external deletion before confirmation
        _ = workspace.document.removeFeature(id: sketch.id)
        #expect(workspace.document.feature(for: sketch.id) == nil)

        // Confirming deletion clears pending ID and safely no-ops without crashing
        workspace.confirmDeleteFeature()
        #expect(workspace.pendingDeleteFeatureId == nil)
    }

    @Test @MainActor func testDatumAxesPointsAndUCSLockingAndDeletion() {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let axis = workspace.document.addDatumAxisFeature(
            name: "Test Axis",
            data: DatumAxisFeatureData(mode: .preset, presetName: "X")
        )
        let point = workspace.document.addDatumPointFeature(
            name: "Test Point",
            data: DatumPointFeatureData(mode: .coordinates, coordinates: .zero)
        )
        let ucs = workspace.document.addDatumCoordinateSystemFeature(
            name: "Test UCS",
            data: DatumCoordinateSystemFeatureData(mode: .originAndAxes)
        )

        // Test axis lock & delete
        workspace.toggleFeatureLocked(axis.id)
        #expect(workspace.document.feature(for: axis.id)?.isLocked == true)
        workspace.requestDeleteFeature(axis.id)
        #expect(workspace.pendingDeleteFeatureId == nil)
        workspace.toggleFeatureLocked(axis.id)
        #expect(workspace.document.feature(for: axis.id)?.isLocked == false)
        workspace.requestDeleteFeature(axis.id)
        #expect(workspace.pendingDeleteFeatureId == axis.id)
        workspace.confirmDeleteFeature()
        #expect(workspace.document.feature(for: axis.id) == nil)

        // Test point lock & delete
        workspace.toggleFeatureLocked(point.id)
        #expect(workspace.document.feature(for: point.id)?.isLocked == true)
        workspace.toggleFeatureLocked(point.id)
        #expect(workspace.document.feature(for: point.id)?.isLocked == false)
        workspace.requestDeleteFeature(point.id)
        workspace.confirmDeleteFeature()
        #expect(workspace.document.feature(for: point.id) == nil)

        // Test UCS lock & delete
        workspace.toggleFeatureLocked(ucs.id)
        #expect(workspace.document.feature(for: ucs.id)?.isLocked == true)
        workspace.toggleFeatureLocked(ucs.id)
        #expect(workspace.document.feature(for: ucs.id)?.isLocked == false)
        workspace.requestDeleteFeature(ucs.id)
        workspace.confirmDeleteFeature()
        #expect(workspace.document.feature(for: ucs.id) == nil)
    }
}
