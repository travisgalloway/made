import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite struct SketchConstructionAppTests {

    @MainActor
    @Test func testWorkspaceConstructionToggleAndUndoRedo() throws {
        let workspace = WorkspaceModel()
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [line])

        // Clear setup undo actions so undo strictly targets the construction toggle
        workspace.undoManager?.removeAllActions()

        workspace.selectSketchEntity(featureId: sketch.id, entityId: line.id)
        #expect(workspace.selectedSketchEntity != nil)
        #expect(workspace.selectedSketchEntity?.entity.isConstruction == false)

        // Toggle construction
        workspace.toggleSelectedSketchEntityConstruction()
        #expect(workspace.selectedSketchEntity?.entity.isConstruction == true)

        // Verify undo manager registered symmetric undo step
        #expect(workspace.canUndo)
        workspace.undo()
        #expect(workspace.selectedSketchEntity?.entity.isConstruction == false)

        // Verify redo
        #expect(workspace.canRedo)
        workspace.redo()
        #expect(workspace.selectedSketchEntity?.entity.isConstruction == true)
    }

    @MainActor
    @Test func testConstructionToggleRegeneratesDownstreamExtrusion() async throws {
        let workspace = WorkspaceModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let l2 = SketchEntity.line(start: SIMD2(20, 0), end: SIMD2(20, 10))
        let l3 = SketchEntity.line(start: SIMD2(20, 10), end: SIMD2(0, 10))
        let l4 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(0, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])

        // Extrude closed rectangle
        let solidId = await workspace.extrudeSketch(
            sketchFeatureId: sketch.id,
            distance: 25.0,
            isSymmetric: false
        )
        let sid = try #require(solidId)
        var extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)

        // Clear setup undo actions so undo strictly targets the construction toggle
        workspace.undoManager?.removeAllActions()

        // Mark l4 as construction -> breaks the closed profile into open 3-line path
        workspace.selectSketchEntity(featureId: sketch.id, entityId: l4.id)
        workspace.toggleSelectedSketchEntityConstruction()

        // Recompute downstream features via incremental regeneration
        await KernelRegeneration.regenerateIncremental(from: sketch.id, in: workspace.document, client: workspace.kernelClient)

        extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState != nil)
        #expect(extrudeFeat.errorState?.code == "sketch-error")

        // Undo -> l4 is normal entity again -> closed profile restored and extrude regenerates cleanly
        workspace.undo()
        try await Task.sleep(for: .milliseconds(150))
        await KernelRegeneration.regenerateIncremental(from: sketch.id, in: workspace.document, client: workspace.kernelClient)
        try await Task.sleep(for: .milliseconds(150))
        extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)
    }

    @MainActor
    @Test func testConstructionShortcutAndMenuConstants() {
        #expect(WorkspaceModel.toggleConstructionShortcutKey == "x")
        #expect(WorkspaceModel.toggleConstructionShortcutModifiers == [.command, .shift])

        let workspace = WorkspaceModel()
        let hasEntry = workspace.shortcuts.contains {
            $0.title == "Toggle Construction" && $0.shortcut == "⇧⌘X" && $0.category == .editing
        }
        #expect(hasEntry)

        // When a sketch entity is selected, selectedSketchFeature is non-nil
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [line])
        workspace.selectSketchEntity(featureId: sketch.id, entityId: line.id)
        #expect(workspace.selectedSketchFeature?.id == sketch.id)
    }
}
