import Testing
import SwiftUI
import simd
@testable import MadeApp
@testable import MadeCore

@Suite struct SketchTextAppTests {

    @MainActor
    @Test func testWorkspaceAddSketchTextAndUndoRedo() throws {
        let workspace = WorkspaceModel()
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [])

        workspace.undoManager?.removeAllActions()

        // Add text entity
        let textEntity = try workspace.addSketchText(
            to: sketch.id,
            text: "CAD",
            origin: SIMD2(5.0, 10.0),
            fontSize: 14.0,
            fontName: "Helvetica"
        )

        #expect(textEntity.kind == "text")
        #expect(textEntity.text == "CAD")

        guard case .sketch(let data1) = workspace.document.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        #expect(data1.entities.count == 1)
        #expect(data1.entities[0].text == "CAD")

        // Undo
        #expect(workspace.canUndo)
        workspace.undo()

        guard case .sketch(let data2) = workspace.document.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch after undo")
            return
        }
        #expect(data2.entities.isEmpty)

        // Redo
        #expect(workspace.canRedo)
        workspace.redo()

        guard case .sketch(let data3) = workspace.document.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch after redo")
            return
        }
        #expect(data3.entities.count == 1)
        #expect(data3.entities[0].text == "CAD")
    }

    @MainActor
    @Test func testInspectorTextControls() throws {
        let workspace = WorkspaceModel()
        let entity = SketchEntity.text(text: "Initial", origin: SIMD2(0, 0), fontSize: 12.0)
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [entity])

        var updated = entity
        updated.text = "Modified"
        updated.fontName = "Courier"
        updated.fontSize = 18.0
        workspace.updateSketchEntity(in: sketch.id, entity: updated)

        guard case .sketch(let data) = workspace.document.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        let stored = try #require(data.entities.first(where: { $0.id == entity.id }))
        #expect(stored.text == "Modified")
        #expect(stored.fontName == "Courier")
        #expect(stored.fontSize == 18.0)
    }

    @Test func testSketchTextWireframeGeneration() {
        let regularText = SketchEntity.text(text: "Wire", origin: SIMD2(0, 0), fontSize: 16.0, isConstruction: false)
        let regularGeom = SketchGeometryGenerator.generateGeometry(entities: [regularText], plane: .xy)

        #expect(!regularGeom.items.isEmpty)
        #expect(regularGeom.items[0].kind == "text")
        #expect(regularGeom.items[0].isConstruction == false)
        #expect(!regularGeom.positions.isEmpty)

        // Construction text entity with dashed wireframe
        let constText = SketchEntity.text(text: "Dash", origin: SIMD2(0, 0), fontSize: 16.0, isConstruction: true)
        let constGeom = SketchGeometryGenerator.generateGeometry(entities: [constText], plane: .xy)

        #expect(!constGeom.items.isEmpty)
        #expect(constGeom.items[0].isConstruction == true)
        #expect(!constGeom.positions.isEmpty)
    }

    @MainActor
    @Test func testCADAddSketchEntityText() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let sketch = doc.addSketchFeature(planeName: "xy", entities: [])
        let sketchIdStr = sketch.id.uuidString

        let res = await registry.callTool(name: "cad_add_sketch_entity", arguments: [
            "sketchId": .string(sketchIdStr),
            "type": .string("text"),
            "text": .string("Design"),
            "fontSize": .double(18.0),
            "fontName": .string("Helvetica"),
            "originX": .double(10.0),
            "originY": .double(20.0)
        ])

        #expect(res.isError == false)

        guard case .sketch(let data) = doc.feature(for: sketch.id)?.operation else {
            Issue.record("Missing sketch")
            return
        }
        let entity = try #require(data.entities.first)
        #expect(entity.kind == "text")
        #expect(entity.text == "Design")
        #expect(entity.fontSize == 18.0)
        #expect(entity.origin == SIMD2(10.0, 20.0))
    }
}
