import Testing
import Foundation
import simd
@testable import MadeCore
@testable import MadeApp

@Suite struct SketchRectangleAppTests {

    // MARK: - DocumentModel Atomic Batch Mutations & Symmetric Undo/Redo

    @Test @MainActor func testDocumentModelAtomicRectangleAddAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        document.undoManager?.removeAllActions()

        let rect = try SketchRectangle.makeCenterRectangle(center: SIMD2(0, 0), corner: SIMD2(20, 15))
        #expect(rect.entities.count == 6)
        #expect(rect.constraints.count == 12)

        let addResult = document.addSketchEntitiesAndConstraints(
            to: sketch.id,
            entities: rect.entities,
            constraints: rect.constraints,
            actionName: "Add Center Rectangle"
        )

        guard case .success = addResult else {
            Issue.record("Expected successful atomic batch addition")
            return
        }

        // Verify all entities and constraints are added in single mutation
        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 6)
            #expect(data.constraints.count == 12)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single undo step rolls back all 6 entities and 12 constraints
        document.undoManager?.undo()

        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.isEmpty)
            #expect(data.constraints.isEmpty)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single redo step restores all 6 entities and 12 constraints
        document.undoManager?.redo()

        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 6)
            #expect(data.constraints.count == 12)
        } else {
            Issue.record("Expected sketch operation")
        }
    }

    @Test @MainActor func testDocumentModelLockedFeatureRejectsRectangle() throws {
        let document = DocumentModel()
        let sketch = document.addSketchFeature(planeName: "xy", entities: [])

        // Lock the sketch feature
        _ = document.setFeatureLocked(id: sketch.id, isLocked: true)

        let rect = try SketchRectangle.makeCornerRectangle(corner1: SIMD2(0, 0), corner2: SIMD2(40, 30))
        let result = document.addSketchEntitiesAndConstraints(
            to: sketch.id,
            entities: rect.entities,
            constraints: rect.constraints
        )

        if case .failure(let error) = result {
            if case .objectLocked = error {
                // Expected rejection on locked feature
            } else {
                Issue.record("Expected .objectLocked error, got \(error)")
            }
        } else {
            Issue.record("Expected mutation on locked feature to fail")
        }
    }

    // MARK: - WorkspaceModel Integration & Downstream Extrusion Rebuild

    @Test @MainActor func testWorkspaceAddCornerRectangleRecomputesExtrusion() async throws {
        let workspace = WorkspaceModel()
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        let result = try workspace.addCornerRectangle(to: sketch.id, corner1: SIMD2(0, 0), corner2: SIMD2(50, 40))
        #expect(result.entities.count == 4)

        let solidId = await workspace.extrudeSketch(
            sketchFeatureId: sketch.id,
            distance: 10.0,
            isSymmetric: false
        )
        let sid = try #require(solidId)
        let extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)
    }

    @Test @MainActor func testWorkspaceAddCenterRectangleRecomputesExtrusion() async throws {
        let workspace = WorkspaceModel()
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        let result = try workspace.addCenterRectangle(to: sketch.id, center: SIMD2(0, 0), corner: SIMD2(25, 20))
        #expect(result.entities.count == 6)

        let solidId = await workspace.extrudeSketch(
            sketchFeatureId: sketch.id,
            distance: 15.0,
            isSymmetric: false
        )
        let sid = try #require(solidId)
        let extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)
    }

    @Test @MainActor func testWorkspaceAddThreePointRectangleRecomputesExtrusion() async throws {
        let workspace = WorkspaceModel()
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        let result = try workspace.addThreePointRectangle(
            to: sketch.id,
            point1: SIMD2(0, 0),
            point2: SIMD2(30, 0),
            point3: SIMD2(30, 20)
        )
        #expect(result.entities.count == 4)

        let solidId = await workspace.extrudeSketch(
            sketchFeatureId: sketch.id,
            distance: 10.0,
            isSymmetric: false
        )
        let sid = try #require(solidId)
        let extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)
    }

    // MARK: - ViewportTool & Shortcut Cheatsheet

    @Test @MainActor func testViewportToolRectanglePropertiesAndCheatsheet() {
        let tool = ViewportTool.rectangle
        #expect(tool.title == "Rectangle")
        #expect(tool.systemImage == "rectangle")
        #expect(tool.shortcutKey == "r")

        #expect(WorkspaceModel.toolRectangleShortcutKey == "6")

        let cheatsheet = WorkspaceModel.standardShortcuts
        let entry = cheatsheet.first(where: { $0.title == "Rectangle" })
        #expect(entry != nil)
        #expect(entry?.shortcut == "R / ⌥⌘6")
        #expect(entry?.category == .tools)
    }

    // MARK: - Inspector & Menu State

    @Test @MainActor func testInspectorPanelAndMenuRectangleCommands() throws {
        let workspace = WorkspaceModel()
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        // Verify activeRectangleKind switching
        #expect(workspace.activeRectangleKind == .corner)
        workspace.activeRectangleKind = .center
        #expect(workspace.activeRectangleKind == .center)
        workspace.activeRectangleKind = .threePoint
        #expect(workspace.activeRectangleKind == .threePoint)

        // Adding through workspace defaults without parameters
        let resCorner = try workspace.addCornerRectangle()
        #expect(resCorner.entities.count == 4)

        let resCenter = try workspace.addCenterRectangle()
        #expect(resCenter.entities.count == 6)

        let resThreePoint = try workspace.addThreePointRectangle()
        #expect(resThreePoint.entities.count == 4)
    }
}
