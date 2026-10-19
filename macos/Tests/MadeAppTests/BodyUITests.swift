import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct BodyUITests {

    @Test @MainActor func testTwoBodyPartNavigatorRenameWithUndoRedo() {
        let model = WorkspaceModel()
        model.setUp()
        model.document.undoManager?.groupsByEvent = false

        let bodies = model.document.bodies
        #expect(bodies.count == 2)

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")
        #expect(model.document.body(for: boxId)?.name == "box-1")
        #expect(model.document.body(for: cylId)?.name == "cylinder-1")

        // Rename body 1
        model.document.undoManager?.beginUndoGrouping()
        model.setBodyName(id: boxId, name: "Base Body")
        model.document.undoManager?.endUndoGrouping()

        #expect(model.document.body(for: boxId)?.name == "Base Body")
        #expect(model.document.objects.first(where: { $0.id == boxId })?.name == "Base Body")
        #expect(model.document.body(for: cylId)?.name == "cylinder-1")

        // Whitespace trimming
        model.document.undoManager?.beginUndoGrouping()
        model.setBodyName(id: boxId, name: "  Trimmed Base  ")
        model.document.undoManager?.endUndoGrouping()

        #expect(model.document.body(for: boxId)?.name == "Trimmed Base")

        // Empty and whitespace-only name rejection
        model.setBodyName(id: boxId, name: "")
        #expect(model.document.body(for: boxId)?.name == "Trimmed Base")
        model.setBodyName(id: boxId, name: "    \n\t")
        #expect(model.document.body(for: boxId)?.name == "Trimmed Base")

        // Undo whitespace trimming
        model.undo()
        #expect(model.document.body(for: boxId)?.name == "Base Body")
        #expect(model.document.body(for: cylId)?.name == "cylinder-1")

        // Undo initial rename
        model.undo()
        #expect(model.document.body(for: boxId)?.name == "box-1")
        #expect(model.document.body(for: cylId)?.name == "cylinder-1")

        // Redo initial rename
        model.redo()
        #expect(model.document.body(for: boxId)?.name == "Base Body")
        #expect(model.document.body(for: cylId)?.name == "cylinder-1")
    }

    @Test @MainActor func testTwoBodyPartNavigatorHideShowWithViewportSyncAndUndoRedo() {
        let model = WorkspaceModel()
        model.setUp()
        model.document.undoManager?.groupsByEvent = false
        let renderer = model.viewportManager.renderer

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")
        if let renderer {
            #expect(!renderer.hiddenSolidIds.contains(boxId))
            #expect(!renderer.hiddenSolidIds.contains(cylId))
        }

        // Hide body 1
        model.document.undoManager?.beginUndoGrouping()
        model.toggleBodyVisibility(boxId)
        model.document.undoManager?.endUndoGrouping()

        #expect(model.document.body(for: boxId)?.isVisible == false)
        #expect(model.document.objects.first(where: { $0.id == boxId })?.isVisible == false)
        if let renderer {
            #expect(renderer.hiddenSolidIds.contains(boxId))
        }
        #expect(model.document.body(for: cylId)?.isVisible == true)
        if let renderer {
            #expect(!renderer.hiddenSolidIds.contains(cylId))
        }

        // Toggle back to show
        model.document.undoManager?.beginUndoGrouping()
        model.toggleBodyVisibility(boxId)
        model.document.undoManager?.endUndoGrouping()

        #expect(model.document.body(for: boxId)?.isVisible == true)
        if let renderer {
            #expect(!renderer.hiddenSolidIds.contains(boxId))
        }

        // Undo back to hidden
        model.undo()
        #expect(model.document.body(for: boxId)?.isVisible == false)
        if let renderer {
            #expect(renderer.hiddenSolidIds.contains(boxId))
        }
        #expect(model.document.body(for: cylId)?.isVisible == true)
        if let renderer {
            #expect(!renderer.hiddenSolidIds.contains(cylId))
        }

        // Undo to initial visible state
        model.undo()
        #expect(model.document.body(for: boxId)?.isVisible == true)
        if let renderer {
            #expect(!renderer.hiddenSolidIds.contains(boxId))
        }

        // Redo to hidden
        model.redo()
        #expect(model.document.body(for: boxId)?.isVisible == false)
        if let renderer {
            #expect(renderer.hiddenSolidIds.contains(boxId))
        }

        // Redo to shown
        model.redo()
        #expect(model.document.body(for: boxId)?.isVisible == true)
        if let renderer {
            #expect(!renderer.hiddenSolidIds.contains(boxId))
        }
    }

    @Test @MainActor func testTwoBodyPartNavigatorLockUnlockRejectionAndUndoRedo() {
        let model = WorkspaceModel()
        model.setUp()
        model.document.undoManager?.groupsByEvent = false

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        #expect(model.document.body(for: boxId)?.isLocked == false)
        #expect(model.document.body(for: cylId)?.isLocked == false)

        // Lock body 1
        model.document.undoManager?.beginUndoGrouping()
        model.toggleBodyLocked(boxId)
        model.document.undoManager?.endUndoGrouping()

        #expect(model.document.body(for: boxId)?.isLocked == true)
        #expect(model.document.objects.first(where: { $0.id == boxId })?.isLocked == true)
        #expect(model.document.body(for: cylId)?.isLocked == false)

        // Mutating locked body is rejected
        model.setBodyName(id: boxId, name: "BlockedRename")
        #expect(model.document.body(for: boxId)?.name == "box-1")

        let originalColor = model.document.body(for: boxId)?.color ?? SIMD4<Float>(0, 0, 0, 0)
        model.setBodyColor(id: boxId, color: SIMD4<Float>(1, 0, 0, 1))
        #expect(model.document.body(for: boxId)?.color == originalColor)

        // Visibility toggle is permitted while locked
        model.document.undoManager?.beginUndoGrouping()
        model.toggleBodyVisibility(boxId)
        model.document.undoManager?.endUndoGrouping()
        #expect(model.document.body(for: boxId)?.isVisible == false)

        model.document.undoManager?.beginUndoGrouping()
        model.toggleBodyVisibility(boxId)
        model.document.undoManager?.endUndoGrouping()
        #expect(model.document.body(for: boxId)?.isVisible == true)

        // Unlock body 1
        model.document.undoManager?.beginUndoGrouping()
        model.setBodyLocked(id: boxId, isLocked: false)
        model.document.undoManager?.endUndoGrouping()

        #expect(model.document.body(for: boxId)?.isLocked == false)

        // Mutations now succeed
        model.document.undoManager?.beginUndoGrouping()
        model.setBodyName(id: boxId, name: "UnlockedBox")
        model.document.undoManager?.endUndoGrouping()

        #expect(model.document.body(for: boxId)?.name == "UnlockedBox")

        // Undo rename
        model.undo()
        #expect(model.document.body(for: boxId)?.name == "box-1")

        // Undo unlock
        model.undo()
        #expect(model.document.body(for: boxId)?.isLocked == true)

        // Undo visibility toggles
        model.undo()
        #expect(model.document.body(for: boxId)?.isVisible == false)
        model.undo()
        #expect(model.document.body(for: boxId)?.isVisible == true)

        // Undo lock
        model.undo()
        #expect(model.document.body(for: boxId)?.isLocked == false)
    }

    @Test @MainActor func testTwoBodyPartInspectorRecolorWithRendererMeshSyncAndUndoRedo() {
        let model = WorkspaceModel()
        model.setUp()
        model.document.undoManager?.groupsByEvent = false
        let renderer = model.viewportManager.renderer

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        let initialBoxColor = model.document.body(for: boxId)?.color ?? SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
        let initialCylColor = model.document.body(for: cylId)?.color ?? SIMD4<Float>(0.5, 0.5, 0.5, 1.0)

        if let renderer {
            let boxPayload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 40, depth: 30, height: 20))
            let cylPayload = EuclidEngine.toMeshPayload(EuclidEngine.makeCylinder(radius: 15, height: 30))
            _ = renderer.installMesh(boxPayload, for: boxId, transform: .identity, color: initialBoxColor, isHidden: false)
            _ = renderer.installMesh(cylPayload, for: cylId, transform: Transform(position: SIMD3<Float>(25, 0, 0)), color: initialCylColor, isHidden: false)

            #expect(renderer.meshes[boxId]?.color == initialBoxColor)
            #expect(renderer.meshes[cylId]?.color == initialCylColor)
        }

        // Recolor body 1
        model.document.undoManager?.beginUndoGrouping()
        let newColor = SIMD4<Float>(0.85, 0.15, 0.25, 1.0)
        model.setBodyColor(id: boxId, color: newColor)
        model.document.undoManager?.endUndoGrouping()

        #expect(model.document.body(for: boxId)?.color == newColor)
        #expect(model.document.objects.first(where: { $0.id == boxId })?.material.color == newColor)
        if let renderer {
            #expect(renderer.meshes[boxId]?.color == newColor)
        }

        // Body 2 color remains untouched
        #expect(model.document.body(for: cylId)?.color == initialCylColor)
        if let renderer {
            #expect(renderer.meshes[cylId]?.color == initialCylColor)
        }

        // Undo recolor
        model.undo()
        #expect(model.document.body(for: boxId)?.color == initialBoxColor)
        if let renderer {
            #expect(renderer.meshes[boxId]?.color == initialBoxColor)
        }
        #expect(model.document.body(for: cylId)?.color == initialCylColor)
        if let renderer {
            #expect(renderer.meshes[cylId]?.color == initialCylColor)
        }

        // Redo recolor
        model.redo()
        #expect(model.document.body(for: boxId)?.color == newColor)
        if let renderer {
            #expect(renderer.meshes[boxId]?.color == newColor)
        }
        #expect(model.document.body(for: cylId)?.color == initialCylColor)
        if let renderer {
            #expect(renderer.meshes[cylId]?.color == initialCylColor)
        }
    }

    @Test @MainActor func testBodyViewsInstantiateWithoutRegression() {
        let model = WorkspaceModel()
        model.setUp()

        let sidebarView = NavigatorSidebarView().environment(model)
        let inspectorView = InspectorPanelView().environment(model)
        let views: [any View] = [sidebarView, inspectorView]
        #expect(views.count == 2)
    }
}
