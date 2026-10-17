import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite struct SketchOperationsAppTests {

    // MARK: - DocumentModel Mutators & Symmetric Undo/Redo

    @MainActor
    @Test func testDocumentTrimSketchEntityAndUndoRedo() throws {
        let doc = DocumentModel()
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let cross = SketchEntity.line(start: SIMD2(4, -5), end: SIMD2(4, 5))
        let sketch = doc.addSketchFeature(planeName: "xy", entities: [line, cross])

        doc.undoManager?.removeAllActions()

        // Trim end segment of line
        let res = doc.trimSketchEntity(in: sketch.id, entityId: line.id, clickPoint: SIMD2(8, 0))
        guard case .success(let trimResult) = res, case .updated(let updated) = trimResult else {
            Issue.record("Expected .updated trim result")
            return
        }
        #expect(abs(updated.endPoint!.x - 4.0) < 1e-4)

        // Verify entity in document
        guard case .sketch(let data1) = doc.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        let storedLine1 = data1.entities.first(where: { $0.id == line.id })!
        #expect(abs(storedLine1.endPoint!.x - 4.0) < 1e-4)

        // Undo
        #expect(doc.canUndo)
        doc.undo()

        guard case .sketch(let data2) = doc.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch after undo")
            return
        }
        let restoredLine = data2.entities.first(where: { $0.id == line.id })!
        #expect(abs(restoredLine.endPoint!.x - 10.0) < 1e-4)

        // Redo
        #expect(doc.canRedo)
        doc.redo()

        guard case .sketch(let data3) = doc.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch after redo")
            return
        }
        let retrimmedLine = data3.entities.first(where: { $0.id == line.id })!
        #expect(abs(retrimmedLine.endPoint!.x - 4.0) < 1e-4)
    }

    @MainActor
    @Test func testDocumentExtendSketchEntityAndUndoRedo() throws {
        let doc = DocumentModel()
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(5, 0))
        let boundary = SketchEntity.line(start: SIMD2(15, -10), end: SIMD2(15, 10))
        let sketch = doc.addSketchFeature(planeName: "xy", entities: [line, boundary])

        doc.undoManager?.removeAllActions()

        let res = doc.extendSketchEntity(in: sketch.id, entityId: line.id, targetEnd: .end)
        guard case .success(let extended) = res else {
            Issue.record("Expected successful extend")
            return
        }
        #expect(abs(extended.endPoint!.x - 15.0) < 1e-4)

        #expect(doc.canUndo)
        doc.undo()

        guard case .sketch(let data) = doc.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        let restored = data.entities.first(where: { $0.id == line.id })!
        #expect(abs(restored.endPoint!.x - 5.0) < 1e-4)

        #expect(doc.canRedo)
        doc.redo()

        guard case .sketch(let redoData) = doc.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        let reExtended = redoData.entities.first(where: { $0.id == line.id })!
        #expect(abs(reExtended.endPoint!.x - 15.0) < 1e-4)
    }

    @MainActor
    @Test func testDocumentSplitSketchEntityAndUndoRedo() throws {
        let doc = DocumentModel()
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketch = doc.addSketchFeature(planeName: "xy", entities: [line])

        doc.undoManager?.removeAllActions()

        let res = doc.splitSketchEntity(in: sketch.id, entityId: line.id, at: SIMD2(6, 0))
        guard case .success(let parts) = res else {
            Issue.record("Expected successful split")
            return
        }
        #expect(parts.0.id == line.id)
        #expect(parts.1.id != line.id)

        guard case .sketch(let splitData) = doc.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        #expect(splitData.entities.count == 2)

        #expect(doc.canUndo)
        doc.undo()

        guard case .sketch(let undoData) = doc.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        #expect(undoData.entities.count == 1)
        #expect(abs(undoData.entities[0].endPoint!.x - 10.0) < 1e-4)

        #expect(doc.canRedo)
        doc.redo()

        guard case .sketch(let redoData) = doc.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        #expect(redoData.entities.count == 2)
    }

    @MainActor
    @Test func testLockedSketchMutationRejection() throws {
        let doc = DocumentModel()
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        var sketch = Feature(name: "Sketch 1", operation: .sketch(SketchFeatureData(entities: [line])))
        sketch.isLocked = true
        _ = doc.addFeature(sketch)

        let trimRes = doc.trimSketchEntity(in: sketch.id, entityId: line.id, clickPoint: SIMD2(5, 0))
        guard case .failure(.objectLocked) = trimRes else {
            Issue.record("Expected .objectLocked on locked sketch trim")
            return
        }

        let extendRes = doc.extendSketchEntity(in: sketch.id, entityId: line.id, targetEnd: .end)
        guard case .failure(.objectLocked) = extendRes else {
            Issue.record("Expected .objectLocked on locked sketch extend")
            return
        }

        let splitRes = doc.splitSketchEntity(in: sketch.id, entityId: line.id, at: SIMD2(5, 0))
        guard case .failure(.objectLocked) = splitRes else {
            Issue.record("Expected .objectLocked on locked sketch split")
            return
        }
    }

    // MARK: - Downstream Timeline Recomputation

    @MainActor
    @Test func testTrimRegeneratesDownstreamExtrude() async throws {
        let workspace = WorkspaceModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let l2 = SketchEntity.line(start: SIMD2(20, 0), end: SIMD2(20, 10))
        let l3 = SketchEntity.line(start: SIMD2(20, 10), end: SIMD2(0, 10))
        let l4 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(0, 0))

        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        let solidId = await workspace.extrudeSketch(
            sketchFeatureId: sketch.id,
            distance: 10.0,
            isSymmetric: false
        )
        let sid = try #require(solidId)
        var extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)

        // Add dangling segment attached to corner (20, 10)
        let dangle = SketchEntity.line(start: SIMD2(20, 10), end: SIMD2(25, 10))
        workspace.addSketchEntity(to: sketch.id, entity: dangle)

        await KernelRegeneration.regenerateIncremental(from: sketch.id, in: workspace.document, client: workspace.kernelClient)
        extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState != nil)

        // Trim dangling entity
        let trimRes = workspace.trimSketchEntity(in: sketch.id, entityId: dangle.id, clickPoint: SIMD2(23, 10))
        guard case .success = trimRes else {
            Issue.record("Expected successful trim")
            return
        }

        try await Task.sleep(for: .milliseconds(150))
        // Recompute downstream features via incremental regeneration
        await KernelRegeneration.regenerateIncremental(from: sketch.id, in: workspace.document, client: workspace.kernelClient)
        try await Task.sleep(for: .milliseconds(150))

        // Verify downstream extrude recovers cleanly
        extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)
    }

    // MARK: - ViewportTool & UI Wiring

    @Test func testViewportToolTrimProperties() {
        let tool = ViewportTool.trim
        #expect(tool.title == "Trim")
        #expect(tool.systemImage == "scissors")
        #expect(tool.shortcutKey == "t")
        #expect(ViewportTool.forShortcutKey("t") == .trim)
        #expect(ViewportTool.forShortcutKey("T") == .trim)
    }

    @MainActor
    @Test func testWorkspaceTrimShortcutsAndDelegators() throws {
        #expect(WorkspaceModel.toolTrimShortcutKey == "5")

        let workspace = WorkspaceModel()
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [line])

        workspace.selectSketchEntity(featureId: sketch.id, entityId: line.id)
        #expect(workspace.selectedSketchEntity != nil)

        // Test split at midpoint helper
        workspace.splitSelectedSketchEntityAtMidpoint()
        guard case .sketch(let data) = workspace.document.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        #expect(data.entities.count == 2)
        #expect(abs(data.entities[0].endPoint!.x - 5.0) < 1e-4)
    }
}
