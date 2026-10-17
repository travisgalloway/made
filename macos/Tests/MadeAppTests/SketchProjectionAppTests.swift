import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite struct SketchProjectionAppTests {

    @MainActor
    @Test func testDocumentModelProjectEntityAndUndoRedo() throws {
        let workspace = WorkspaceModel()
        let doc = workspace.document

        // 1. Add upstream Box
        let boxFeat = Feature.makeBox(
            id: UUID(),
            params: BoxParams(width: 30, depth: 20, height: 10)
        )
        _ = doc.addFeature(boxFeat)

        // 2. Add downstream sketch on XY plane
        let sketchFeat = doc.addSketchFeature(planeName: "xy")
        guard let edgeTopFront = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge:top-front in box")
            return
        }

        // Clear undo actions from setup
        workspace.undoManager?.removeAllActions()

        let ref = Reference.edge(edgeTopFront)
        let result = doc.projectEntity(reference: ref, into: sketchFeat.id)
        guard case .success(let entity) = result else {
            Issue.record("Failed to project entity: \(result)")
            return
        }

        #expect(entity.isProjected)
        #expect(entity.reference == ref)

        guard let currentSketch = doc.feature(for: sketchFeat.id),
              case .sketch(let sketchData) = currentSketch.operation else {
            Issue.record("Sketch feature not found")
            return
        }
        #expect(sketchData.entities.contains(where: { $0.id == entity.id }))
        #expect(currentSketch.references.contains(ref))

        // Undo
        #expect(workspace.canUndo)
        workspace.undo()

        guard let afterUndoSketch = doc.feature(for: sketchFeat.id),
              case .sketch(let afterUndoData) = afterUndoSketch.operation else {
            Issue.record("Sketch feature not found after undo")
            return
        }
        #expect(!afterUndoData.entities.contains(where: { $0.id == entity.id }))
        #expect(!afterUndoSketch.references.contains(ref))

        // Redo
        #expect(workspace.canRedo)
        workspace.redo()

        guard let afterRedoSketch = doc.feature(for: sketchFeat.id),
              case .sketch(let afterRedoData) = afterRedoSketch.operation else {
            Issue.record("Sketch feature not found after redo")
            return
        }
        #expect(afterRedoData.entities.contains(where: { $0.id == entity.id }))
        #expect(afterRedoSketch.references.contains(ref))
    }

    @MainActor
    @Test func testWorkspaceModelProjectSelectedGeometry() throws {
        let workspace = WorkspaceModel()
        let doc = workspace.document

        let boxId = ObjectId("box-custom")
        let boxFeat = Feature.makeBox(
            id: UUID(),
            solidId: boxId,
            name: "Box",
            params: BoxParams(width: 40, depth: 30, height: 20)
        )
        _ = doc.addFeature(boxFeat)

        let sketchFeat = doc.addSketchFeature(planeName: "xy")
        workspace.selectedId = ObjectId(sketchFeat.id.uuidString)

        guard let topFrontTopRef = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge")
            return
        }

        // Set selected sub-element to the edge
        doc.selectedSubElement = SelectedSubElement(
            solidId: boxId,
            elementType: .edge,
            elementId: 0,
            deterministicId: topFrontTopRef.id
        )

        let projResult = workspace.projectSelectedGeometry()
        guard let res = projResult, case .success(let entity) = res else {
            Issue.record("projectSelectedGeometry failed: \(String(describing: projResult))")
            return
        }

        #expect(entity.isProjected)
        #expect(workspace.isDocumentModified)

        guard let sketch = doc.feature(for: sketchFeat.id),
              case .sketch(let data) = sketch.operation else {
            Issue.record("Sketch not found")
            return
        }
        #expect(data.entities.contains(where: { $0.id == entity.id }))
    }

    @MainActor
    @Test func testWorkspaceModelProjectUpstreamSketchEntity() throws {
        let workspace = WorkspaceModel()
        let doc = workspace.document

        // Sketch 1 with a line
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(50, 0))
        let sketch1 = doc.addSketchFeature(planeName: "xy", entities: [line])

        // Sketch 2 on parallel plane
        let sketch2 = doc.addSketchFeature(planeName: "xy")

        // Select Sketch 1 entity
        workspace.selectSketchEntity(featureId: sketch1.id, entityId: line.id)

        // Project into Sketch 2
        let res = workspace.projectReference(
            Reference.sketchEntity(featureId: sketch1.id, entityId: line.id),
            into: sketch2.id
        )
        guard case .success(let projLine) = res else {
            Issue.record("Failed to project sketch entity: \(res)")
            return
        }
        #expect(projLine.isProjected)
        #expect(abs((projLine.length ?? 0) - 50.0) < 1e-4)
    }

    @MainActor
    @Test func testShortcutConstantsAndCheatsheet() {
        #expect(WorkspaceModel.projectGeometryShortcutKey == "j")
        #expect(WorkspaceModel.projectGeometryShortcutModifiers == [.command])

        let hasEntry = WorkspaceModel.standardShortcuts.contains {
            $0.title == "Project Geometry" && $0.shortcut == "⌘J"
        }
        #expect(hasEntry)
    }
}
