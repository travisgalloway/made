import Testing
import SwiftUI
@testable import MadeApp
import MadeCore
import simd

extension WorkspaceModelTests {
    @Suite(.serialized) struct CommandSessionTests {
    @Test @MainActor func testCommandSessionDefaultsAndCanCommit() {
        let session = CommandSession(
            title: "Test Command",
            selectionSlots: [
                CommandSelectionSlot(id: "target", label: "Target", isRequired: true)
            ],
            inputs: [
                CommandInput(id: "size", label: "Size", value: .number(20.0, range: 5.0...100.0, step: 1.0, unit: "mm")),
                CommandInput(id: "name", label: "Name", value: .text("custom")),
                CommandInput(id: "flag", label: "Flag", value: .toggle(true)),
                CommandInput(id: "type", label: "Type", value: .choice("A", options: ["A", "B", "C"]))
            ]
        )

        // Required slot is empty -> canCommit is false
        #expect(!session.canCommit)

        // Assign object to required slot
        session.setSlotSelection(slotId: "target", objectId: ObjectId("obj-1"), objectName: "Box")
        #expect(session.canCommit)

        // Invalid number out of range
        session.setNumberValue(150.0, for: "size")
        #expect(!session.canCommit)

        // Restore valid number
        session.setNumberValue(50.0, for: "size")
        #expect(session.canCommit)

        // NaN number
        session.setNumberValue(.nan, for: "size")
        #expect(!session.canCommit)

        // Restore valid number
        session.setNumberValue(30.0, for: "size")
        #expect(session.canCommit)

        // Invalid choice
        session.setChoiceValue("InvalidChoice", for: "type")
        #expect(!session.canCommit)

        session.setChoiceValue("B", for: "type")
        #expect(session.canCommit)
    }

    @Test @MainActor func testParameterMutationsAndCallbacks() {
        var paramChangedKey: String? = nil
        var previewUpdateCalled = false

        let session = CommandSession(
            title: "Param Test",
            inputs: [
                CommandInput(id: "dim", label: "Dimension", value: .number(10.0, range: 1.0...50.0, step: 1.0, unit: "mm")),
                CommandInput(id: "label", label: "Label", value: .text("Initial")),
                CommandInput(id: "active", label: "Active", value: .toggle(false)),
                CommandInput(id: "opt", label: "Option", value: .choice("X", options: ["X", "Y"]))
            ],
            isPreviewEnabled: true,
            onParamChanged: { key, _ in
                paramChangedKey = key
            },
            onPreviewUpdate: {
                previewUpdateCalled = true
            }
        )

        #expect(session.numberValue(for: "dim") == 10.0)
        session.setNumberValue(25.0, for: "dim")
        #expect(session.numberValue(for: "dim") == 25.0)
        #expect(paramChangedKey == "dim")
        #expect(previewUpdateCalled)

        previewUpdateCalled = false
        session.setTextValue("Updated", for: "label")
        #expect(session.textValue(for: "label") == "Updated")
        #expect(paramChangedKey == "label")
        #expect(previewUpdateCalled)

        previewUpdateCalled = false
        session.setToggleValue(true, for: "active")
        #expect(session.toggleValue(for: "active") == true)
        #expect(paramChangedKey == "active")
        #expect(previewUpdateCalled)

        previewUpdateCalled = false
        session.setChoiceValue("Y", for: "opt")
        #expect(session.choiceValue(for: "opt") == "Y")
        #expect(paramChangedKey == "opt")
        #expect(previewUpdateCalled)
    }

    @Test @MainActor func testPreviewToggleTriggersCallback() {
        var previewUpdateCount = 0
        let session = CommandSession(
            title: "Preview Test",
            isPreviewEnabled: true,
            onPreviewUpdate: {
                previewUpdateCount += 1
            }
        )

        session.isPreviewEnabled = false
        #expect(previewUpdateCount == 1)

        session.isPreviewEnabled = true
        #expect(previewUpdateCount == 2)

        // Setting same value should not trigger callback
        session.isPreviewEnabled = true
        #expect(previewUpdateCount == 2)
    }

    @Test @MainActor func testCommitAndCancelSemantics() {
        var commitCalled = false
        var cancelCalled = false

        let session = CommandSession(
            title: "Commit Cancel Test",
            selectionSlots: [
                CommandSelectionSlot(id: "req", label: "Required Slot", isRequired: true)
            ],
            onCommit: {
                commitCalled = true
            },
            onCancel: {
                cancelCalled = true
            }
        )

        // canCommit is false -> commit() should do nothing
        session.commit()
        #expect(!commitCalled)

        // satisfy requirements
        session.setSlotSelection(slotId: "req", objectId: ObjectId("obj-1"), objectName: "Obj")
        #expect(session.canCommit)

        session.commit()
        #expect(commitCalled)

        session.cancel()
        #expect(cancelCalled)
    }

    @Test @MainActor func testMakeAddBoxLifecycle() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeAddBox(workspace: workspace)

        #expect(session.title == "Add Box")
        #expect(session.numberValue(for: "width") == 30.0)
        #expect(session.numberValue(for: "depth") == 30.0)
        #expect(session.numberValue(for: "height") == 30.0)
        #expect(session.canCommit)

        // Initial doc object count
        let initialDocCount = workspace.document.objects.count

        // Update preview
        session.onPreviewUpdate?()
        // Preview does NOT dirty or alter DocumentModel
        #expect(workspace.document.objects.count == initialDocCount)

        // Modify parameter
        session.setNumberValue(45.0, for: "width")
        #expect(session.numberValue(for: "width") == 45.0)

        // Commit adds object to DocumentModel
        session.commit()
        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        if case .box(let params)? = added?.def {
            #expect(params.width == 45.0)
            #expect(params.depth == 30.0)
            #expect(params.height == 30.0)
        } else {
            Issue.record("Expected box object in DocumentModel")
        }
    }

    @Test @MainActor func testMakeAddBoxCancellationDiscardsPreviewWithoutDirtyingDocument() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeAddBox(workspace: workspace)
        let initialDocCount = workspace.document.objects.count

        session.onPreviewUpdate?()
        session.cancel()

        #expect(workspace.document.objects.count == initialDocCount)
    }

    @Test @MainActor func testMakeAddCylinderLifecycle() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeAddCylinder(workspace: workspace)

        #expect(session.title == "Add Cylinder")
        #expect(session.numberValue(for: "radius") == 12.0)
        #expect(session.numberValue(for: "height") == 35.0)
        #expect(session.canCommit)

        let initialDocCount = workspace.document.objects.count
        session.setNumberValue(20.0, for: "radius")
        session.commit()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        if case .cylinder(let params)? = added?.def {
            #expect(params.radius == 20.0)
            #expect(params.height == 35.0)
        } else {
            Issue.record("Expected cylinder object in DocumentModel")
        }
    }

    @Test @MainActor func testMakeAddSphereLifecycle() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeAddSphere(workspace: workspace)

        #expect(session.title == "Add Sphere")
        #expect(session.numberValue(for: "radius") == 15.0)
        #expect(session.canCommit)

        let initialDocCount = workspace.document.objects.count
        session.setNumberValue(25.0, for: "radius")
        session.commit()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        if case .sphere(let params)? = added?.def {
            #expect(params.radius == 25.0)
        } else {
            Issue.record("Expected sphere object in DocumentModel")
        }
    }

    @Test @MainActor func testMakeAddConeLifecycle() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeAddCone(workspace: workspace)

        #expect(session.title == "Add Cone")
        #expect(session.numberValue(for: "bottomRadius") == 15.0)
        #expect(session.numberValue(for: "topRadius") == 0.0)
        #expect(session.numberValue(for: "height") == 30.0)
        #expect(session.canCommit)

        // Invalid when both radii are 0
        session.setNumberValue(0.0, for: "bottomRadius")
        session.setNumberValue(0.0, for: "topRadius")
        #expect(!session.canCommit)

        let initialDocCount = workspace.document.objects.count
        session.setNumberValue(18.0, for: "bottomRadius")
        session.setNumberValue(6.0, for: "topRadius")
        session.setNumberValue(45.0, for: "height")
        #expect(session.canCommit)
        session.commit()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        if case .cone(let params)? = added?.def {
            #expect(params.bottomRadius == 18.0)
            #expect(params.topRadius == 6.0)
            #expect(params.height == 45.0)
        } else {
            Issue.record("Expected cone object in DocumentModel")
        }
    }

    @Test @MainActor func testMakeAddTorusLifecycle() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeAddTorus(workspace: workspace)

        #expect(session.title == "Add Torus")
        #expect(session.numberValue(for: "majorRadius") == 20.0)
        #expect(session.numberValue(for: "minorRadius") == 5.0)
        #expect(session.canCommit)

        // Invalid when majorRadius <= minorRadius
        session.setNumberValue(10.0, for: "majorRadius")
        session.setNumberValue(15.0, for: "minorRadius")
        #expect(!session.canCommit)

        let initialDocCount = workspace.document.objects.count
        session.setNumberValue(28.0, for: "majorRadius")
        session.setNumberValue(7.0, for: "minorRadius")
        #expect(session.canCommit)
        session.commit()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        if case .torus(let params)? = added?.def {
            #expect(params.majorRadius == 28.0)
            #expect(params.minorRadius == 7.0)
        } else {
            Issue.record("Expected torus object in DocumentModel")
        }
    }

    @Test @MainActor func testMakeAddWedgeLifecycle() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeAddWedge(workspace: workspace)

        #expect(session.title == "Add Wedge")
        #expect(session.numberValue(for: "width") == 30.0)
        #expect(session.numberValue(for: "depth") == 30.0)
        #expect(session.numberValue(for: "height") == 30.0)
        #expect(session.numberValue(for: "topWidth") == 0.0)
        #expect(session.canCommit)

        // Invalid when topWidth > width
        session.setNumberValue(20.0, for: "width")
        session.setNumberValue(35.0, for: "topWidth")
        #expect(!session.canCommit)

        let initialDocCount = workspace.document.objects.count
        session.setNumberValue(35.0, for: "width")
        session.setNumberValue(25.0, for: "depth")
        session.setNumberValue(40.0, for: "height")
        session.setNumberValue(10.0, for: "topWidth")
        #expect(session.canCommit)
        session.commit()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        if case .wedge(let params)? = added?.def {
            #expect(params.width == 35.0)
            #expect(params.depth == 25.0)
            #expect(params.height == 40.0)
            #expect(params.topWidth == 10.0)
        } else {
            Issue.record("Expected wedge object in DocumentModel")
        }
    }

    @Test @MainActor func testMakeTransformLifecycle() {
        let workspace = WorkspaceModel()
        let boxId = ObjectId("box-1")
        workspace.selectedId = boxId

        let session = CommandSession.makeTransform(workspace: workspace, targetId: boxId)
        #expect(session.title == "Transform Solid")
        #expect(session.selectionSlots.first?.selectedObjectId == boxId)
        #expect(session.canCommit)

        let originalTransform = workspace.document.objects.first(where: { $0.id == boxId })?.transform
        #expect(originalTransform != nil)

        // Modify position
        session.setNumberValue(50.0, for: "posX")
        session.setNumberValue(-25.0, for: "posY")
        session.setNumberValue(10.0, for: "posZ")

        // DocumentModel is not modified until commit
        #expect(workspace.document.objects.first(where: { $0.id == boxId })?.transform.position == originalTransform?.position)

        // Cancel restores state
        session.cancel()
        #expect(workspace.document.objects.first(where: { $0.id == boxId })?.transform.position == originalTransform?.position)

        // Commit applies state
        session.commit()
        let updatedTransform = workspace.document.objects.first(where: { $0.id == boxId })?.transform
        #expect(updatedTransform?.position.x == 50.0)
        #expect(updatedTransform?.position.y == -25.0)
        #expect(updatedTransform?.position.z == 10.0)
    }

    @Test @MainActor func testMakeBooleanLifecycle() {
        let workspace = WorkspaceModel()
        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")
        workspace.selectedId = boxId

        let session = CommandSession.makeBoolean(workspace: workspace, selectedId: boxId)
        #expect(session.title == "Boolean Operation")
        #expect(session.selectionSlots.first(where: { $0.id == "solidA" })?.selectedObjectId == boxId)
        #expect(session.selectionSlots.first(where: { $0.id == "solidA" })?.isActive == false)
        #expect(session.selectionSlots.first(where: { $0.id == "solidB" })?.selectedObjectId == nil)
        #expect(session.selectionSlots.first(where: { $0.id == "solidB" })?.isActive == true)
        #expect(!session.canCommit)

        // Invalid: selecting same solid for both slots
        session.setSlotSelection(slotId: "solidB", objectId: boxId, objectName: "Box")
        #expect(!session.canCommit)

        // Valid: selecting different solid
        session.setSlotSelection(slotId: "solidB", objectId: cylId, objectName: "Cylinder")
        #expect(session.canCommit)

        // Operation choice and keepTool toggle default
        #expect(session.choiceValue(for: "operation") == "Subtract")
        #expect(session.toggleValue(for: "keepTool") == false)
        session.setChoiceValue("Union", for: "operation")
        #expect(session.choiceValue(for: "operation") == "Union")

        // Cancel does not mutate document
        let initialDocCount = workspace.document.objects.count
        session.cancel()
        #expect(workspace.document.objects.count == initialDocCount)

        // Commit with keepTool: false creates boolean solid, hides both operands, and selects result
        session.commit()
        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        #expect(workspace.selectedId == added?.id)
        #expect(workspace.document.objects.first(where: { $0.id == boxId })?.isVisible == false)
        #expect(workspace.document.objects.first(where: { $0.id == cylId })?.isVisible == false)

        if case .boolean(let op, let a, let b)? = added?.def {
            #expect(op == .union)
            #expect(a == boxId)
            #expect(b == cylId)
        } else {
            Issue.record("Expected boolean object in DocumentModel")
        }
    }

    @Test @MainActor func testMakeBooleanWithKeepToolPreservesToolVisibility() {
        let workspace = WorkspaceModel()
        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")
        workspace.selectedId = boxId

        let session = CommandSession.makeBoolean(workspace: workspace, selectedId: boxId)
        session.setSlotSelection(slotId: "solidB", objectId: cylId, objectName: "Cylinder")
        #expect(session.canCommit)

        session.setToggleValue(true, for: "keepTool")
        #expect(session.toggleValue(for: "keepTool") == true)

        let initialDocCount = workspace.document.objects.count
        session.commit()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        #expect(workspace.selectedId == added?.id)
        // Target solid A is hidden; tool solid B remains visible
        #expect(workspace.document.objects.first(where: { $0.id == boxId })?.isVisible == false)
        #expect(workspace.document.objects.first(where: { $0.id == cylId })?.isVisible == true)
    }
}

}
