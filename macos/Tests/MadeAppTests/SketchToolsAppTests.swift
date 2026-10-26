import Testing
import Foundation
import simd
@testable import MadeCore
@testable import MadeApp

@Suite struct SketchToolsAppTests {

    @Test @MainActor func testDocumentModelAtomicSlotAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        document.undoManager?.removeAllActions()

        let slot = try SketchSlot.makeStraightSlot(center1: SIMD2(0, 0), center2: SIMD2(30, 0), width: 10)
        let addResult = document.addSketchEntitiesAndConstraints(
            to: sketch.id,
            entities: slot.entities,
            constraints: slot.constraints,
            actionName: "Add Straight Slot"
        )
        guard case .success = addResult else {
            Issue.record("Expected successful atomic batch addition for slot")
            return
        }

        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == slot.entities.count)
            #expect(data.constraints.count == slot.constraints.count)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single undo step rolls back all entities and constraints
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.isEmpty)
            #expect(data.constraints.isEmpty)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single redo step restores everything
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == slot.entities.count)
            #expect(data.constraints.count == slot.constraints.count)
        } else {
            Issue.record("Expected sketch operation")
        }
    }

    @Test @MainActor func testDocumentModelAtomicPolygonAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        document.undoManager?.removeAllActions()

        let poly = try SketchPolygon.makeRegularPolygon(center: SIMD2(0, 0), radius: 20, sides: 6)
        let addResult = document.addSketchEntitiesAndConstraints(
            to: sketch.id,
            entities: poly.entities,
            constraints: poly.constraints,
            actionName: "Add Regular Polygon"
        )
        guard case .success = addResult else {
            Issue.record("Expected successful atomic batch addition for polygon")
            return
        }

        // Undo
        document.undoManager?.undo()
        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.isEmpty)
        }

        // Redo
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 6)
        }
    }

    @Test @MainActor func testDocumentModelAtomicEllipseAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        document.undoManager?.removeAllActions()

        let ellipse = try SketchEllipse.makeEllipse(center: SIMD2(0, 0), radiusX: 25, radiusY: 15, addAxes: true)
        let addResult = document.addSketchEntitiesAndConstraints(
            to: sketch.id,
            entities: ellipse.entities,
            constraints: ellipse.constraints,
            actionName: "Add Ellipse"
        )
        guard case .success = addResult else {
            Issue.record("Expected successful atomic batch addition for ellipse")
            return
        }

        // Undo
        document.undoManager?.undo()
        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.isEmpty)
        }

        // Redo
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 3)
        }
    }

    @Test @MainActor func testLockedFeatureRejection() throws {
        let document = DocumentModel()
        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        _ = document.setFeatureLocked(id: sketch.id, isLocked: true)

        let slot = try SketchSlot.makeStraightSlot(center1: SIMD2(0, 0), center2: SIMD2(30, 0), width: 10)
        let result = document.addSketchEntitiesAndConstraints(
            to: sketch.id,
            entities: slot.entities,
            constraints: slot.constraints
        )
        if case .failure(let error) = result {
            if case .objectLocked = error {
                // Expected rejection
            } else {
                Issue.record("Expected .objectLocked error, got \(error)")
            }
        } else {
            Issue.record("Expected mutation on locked feature to fail")
        }
    }

    @Test @MainActor func testWorkspaceMutatorsAndExtrusion() async throws {
        let workspace = WorkspaceModel()
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        // Straight slot
        let slotRes = try workspace.addStraightSlot(to: sketch.id, center1: SIMD2(0, 0), center2: SIMD2(40, 0), width: 10)
        #expect(slotRes.entities.count == 4)

        let solidId = await workspace.extrudeSketch(sketchFeatureId: sketch.id, distance: 10.0)
        let sid = try #require(solidId)
        let extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)

        // Arc slot in a new sketch
        let sketch2 = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        let arcSlotRes = try workspace.addArcSlot(to: sketch2.id, center: SIMD2(0, 0), radius: 30, startAngle: 0, endAngle: .pi, width: 10)
        #expect(arcSlotRes.entities.count == 4)

        let solidId2 = await workspace.extrudeSketch(sketchFeatureId: sketch2.id, distance: 10.0)
        let sid2 = try #require(solidId2)
        let extrudeFeat2 = try #require(workspace.document.feature(for: sid2))
        #expect(extrudeFeat2.errorState == nil)

        // Regular polygon in a new sketch
        let sketch3 = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        let polyRes = try workspace.addRegularPolygon(to: sketch3.id, center: SIMD2(0, 0), radius: 20, sides: 6)
        #expect(polyRes.entities.count == 6)

        let solidId3 = await workspace.extrudeSketch(sketchFeatureId: sketch3.id, distance: 10.0)
        let sid3 = try #require(solidId3)
        let extrudeFeat3 = try #require(workspace.document.feature(for: sid3))
        #expect(extrudeFeat3.errorState == nil)

        // Ellipse in a new sketch
        let sketch4 = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        let ellipseRes = try workspace.addEllipse(to: sketch4.id, center: SIMD2(0, 0), radiusX: 25, radiusY: 15)
        #expect(ellipseRes.entities.count == 1)

        let solidId4 = await workspace.extrudeSketch(sketchFeatureId: sketch4.id, distance: 10.0)
        let sid4 = try #require(solidId4)
        let extrudeFeat4 = try #require(workspace.document.feature(for: sid4))
        #expect(extrudeFeat4.errorState == nil)
    }

    @Test @MainActor func testViewportToolPropertiesAndShortcuts() {
        // Slot
        let slotTool = ViewportTool.slot
        #expect(slotTool.title == "Slot")
        #expect(slotTool.systemImage == "capsule")
        #expect(slotTool.shortcutKey == "s")
        #expect(ViewportTool.forShortcutKey("s") == .slot)
        #expect(WorkspaceModel.toolSlotShortcutKey == "7")

        // Polygon
        let polyTool = ViewportTool.polygon
        #expect(polyTool.title == "Polygon")
        #expect(polyTool.systemImage == "hexagon")
        #expect(polyTool.shortcutKey == "g")
        #expect(ViewportTool.forShortcutKey("g") == .polygon)
        #expect(WorkspaceModel.toolPolygonShortcutKey == "8")

        // Ellipse
        let ellipseTool = ViewportTool.ellipse
        #expect(ellipseTool.title == "Ellipse")
        #expect(ellipseTool.systemImage == "oval")
        #expect(ellipseTool.shortcutKey == "e")
        #expect(ViewportTool.forShortcutKey("e") == .ellipse)
        #expect(WorkspaceModel.toolEllipseShortcutKey == "9")

        let cheatsheet = WorkspaceModel.standardShortcuts
        #expect(cheatsheet.contains { $0.title == "Slot" && $0.shortcut == "S / ⌥⌘7" })
        #expect(cheatsheet.contains { $0.title == "Polygon" && $0.shortcut == "G / ⌥⌘8" })
        #expect(cheatsheet.contains { $0.title == "Ellipse" && $0.shortcut == "E / ⌥⌘9" })
    }

    @Test @MainActor func testInspectorAndMenuCommands() throws {
        let workspace = WorkspaceModel()
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        // Switching activeSlotKind
        #expect(workspace.activeSlotKind == .straight)
        workspace.activeSlotKind = .arc
        #expect(workspace.activeSlotKind == .arc)

        // Switching activePolygonKind and sides
        #expect(workspace.activePolygonKind == .inscribed)
        workspace.activePolygonKind = .circumscribed
        #expect(workspace.activePolygonKind == .circumscribed)
        workspace.activePolygonSides = 8
        #expect(workspace.activePolygonSides == 8)

        // Default additions without parameters
        let resSlot = try workspace.addStraightSlot()
        #expect(resSlot.entities.count == 4)

        let resArcSlot = try workspace.addArcSlot()
        #expect(resArcSlot.entities.count == 4)

        let resPoly = try workspace.addRegularPolygon()
        #expect(resPoly.entities.count == 8)

        let resEllipse = try workspace.addEllipse()
        #expect(resEllipse.entities.count == 1)

        let resArc = try workspace.addEllipticalArc()
        #expect(resArc.entities.count == 1)
    }
}
