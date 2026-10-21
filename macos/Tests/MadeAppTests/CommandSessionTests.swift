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

    @Test @MainActor func testMakeExtrudeCommandSessionLifecycle() async {
        let workspace = WorkspaceModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let l2 = SketchEntity.line(start: SIMD2(20, 0), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(0, 20))
        let l4 = SketchEntity.line(start: SIMD2(0, 20), end: SIMD2(0, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])

        let session = CommandSession.makeExtrude(workspace: workspace, sketchFeatureId: sketch.id)
        #expect(session.canCommit)
        #expect(session.numberValue(for: "distance") == 20.0)
        #expect(session.toggleValue(for: "symmetric") == false)

        session.setNumberValue(35.0, for: "distance")
        session.setToggleValue(true, for: "symmetric")
        #expect(session.canCommit)

        let initialDocCount = workspace.document.objects.count
        session.commit()

        // Yield to allow Task @MainActor onCommit to run
        await Task.yield()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        #expect(workspace.selectedId == added?.id)
        if case .extrude(let params)? = added?.def {
            #expect(params.distance == 35.0)
            #expect(params.isSymmetric == true)
            #expect(params.sketchFeatureId == sketch.id)
        } else {
            Issue.record("Expected .extrude def on scene object")
        }
    }

    @Test @MainActor func testMakeExtrudeValidationRejectsOpenProfile() {
        let workspace = WorkspaceModel()
        // Open sketch: two disconnected lines
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let l2 = SketchEntity.line(start: SIMD2(10, 0), end: SIMD2(10, 10))
        let openSketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2])

        let session = CommandSession.makeExtrude(workspace: workspace, sketchFeatureId: openSketch.id)
        // Custom validation should fail because profile is open
        #expect(!session.canCommit)
    }

    @Test @MainActor func testMakeRevolveLifecycle() async {
        let workspace = WorkspaceModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let l2 = SketchEntity.line(start: SIMD2(20, 0), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(0, 20))
        let l4 = SketchEntity.line(start: SIMD2(0, 20), end: SIMD2(0, 0))
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])

        let session = CommandSession.makeRevolve(workspace: workspace, sketchFeatureId: sketch.id)
        #expect(session.canCommit)
        #expect(session.choiceValue(for: "mode") == "Full")
        #expect(session.numberValue(for: "angle") == 360.0)

        session.setChoiceValue("Angle", for: "mode")
        session.setNumberValue(90.0, for: "angle")
        #expect(session.canCommit)

        let initialDocCount = workspace.document.objects.count
        session.commit()

        await Task.yield()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        #expect(workspace.selectedId == added?.id)
        if case .revolve(let params)? = added?.def {
            #expect(params.mode == .angle)
            #expect(params.angle == 90.0)
            #expect(params.sketchFeatureId == sketch.id)
        } else {
            Issue.record("Expected .revolve def on scene object")
        }
    }

    @Test @MainActor func testMakeRevolveValidationRejectsOpenProfile() {
        let workspace = WorkspaceModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let l2 = SketchEntity.line(start: SIMD2(10, 0), end: SIMD2(10, 10))
        let openSketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2])

        let session = CommandSession.makeRevolve(workspace: workspace, sketchFeatureId: openSketch.id)
        #expect(!session.canCommit)
    }

    @Test @MainActor func testMakeRevolveValidationRejectsCrossingAxis() {
        let workspace = WorkspaceModel()
        let l1 = SketchEntity.line(start: SIMD2(-5, 0), end: SIMD2(5, 0))
        let l2 = SketchEntity.line(start: SIMD2(5, 0), end: SIMD2(5, 10))
        let l3 = SketchEntity.line(start: SIMD2(5, 10), end: SIMD2(-5, 10))
        let l4 = SketchEntity.line(start: SIMD2(-5, 10), end: SIMD2(-5, 0))
        let crossingSketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])

        let datumAxis = workspace.document.addDatumAxisFeature(data: DatumAxisFeatureData(mode: .preset, presetName: "Y"))

        let session = CommandSession.makeRevolve(workspace: workspace, sketchFeatureId: crossingSketch.id)
        session.setChoiceValue(datumAxis.name, for: "axis")
        #expect(!session.canCommit)
    }

    @Test @MainActor func testMakeDatumPlaneLifecycle() async {
        let workspace = WorkspaceModel()
        let initialFeatureCount = workspace.document.features.count

        let session = CommandSession.makeDatumPlane(workspace: workspace)
        #expect(session.canCommit)
        #expect(session.choiceValue(for: "mode") == "Origin")
        #expect(session.choiceValue(for: "originPreset") == "XY")
        #expect(session.numberValue(for: "offset") == 0.0)
        #expect(session.toggleValue(for: "flip") == false)

        // Test parameter mutations
        session.setNumberValue(25.0, for: "offset")
        session.setToggleValue(true, for: "flip")
        #expect(session.numberValue(for: "offset") == 25.0)
        #expect(session.toggleValue(for: "flip") == true)
        #expect(session.canCommit)

        // Test custom validation for Three Points mode
        session.setChoiceValue("Three Points", for: "mode")
        // Default points: (0,0,0), (10,0,0), (0,10,0) -> non-collinear
        #expect(session.canCommit)

        // Make points collinear
        session.setNumberValue(20.0, for: "point3X")
        session.setNumberValue(0.0, for: "point3Y")
        session.setNumberValue(0.0, for: "point3Z")
        #expect(!session.canCommit)

        // Restore valid non-collinear points
        session.setNumberValue(0.0, for: "point3X")
        session.setNumberValue(15.0, for: "point3Y")
        #expect(session.canCommit)

        // Commit datum plane
        session.commit()
        await Task.yield()

        #expect(workspace.document.features.count == initialFeatureCount + 1)
        let addedFeature = workspace.document.features.last
        #expect(addedFeature != nil)
        #expect(workspace.selectedDatumPlaneFeature?.id == addedFeature?.id)

        if case .datumPlane(let data) = addedFeature?.operation {
            #expect(data.mode == .threePoints)
            #expect(data.point3?.y == 15.0)
            #expect(data.cachedPlane != nil)
        } else {
            Issue.record("Expected .datumPlane feature operation")
        }
    }

    @Test @MainActor func testMakeDatumAxisLifecycle() async {
        let workspace = WorkspaceModel()
        let initialFeatureCount = workspace.document.features.count

        let session = CommandSession.makeDatumAxis(workspace: workspace)
        #expect(session.canCommit)
        #expect(session.choiceValue(for: "mode") == "Preset")
        #expect(session.choiceValue(for: "preset") == "Z")
        #expect(session.toggleValue(for: "flip") == false)

        // Mutate parameters
        session.setChoiceValue("X", for: "preset")
        session.setToggleValue(true, for: "flip")
        #expect(session.choiceValue(for: "preset") == "X")
        #expect(session.toggleValue(for: "flip") == true)
        #expect(session.canCommit)

        // Switch to Two Points mode
        session.setChoiceValue("Two Points", for: "mode")
        #expect(session.canCommit)

        // Make coincident -> validation fails
        session.setNumberValue(0.0, for: "point2Z")
        #expect(!session.canCommit)

        // Restore valid endpoints
        session.setNumberValue(50.0, for: "point2Z")
        #expect(session.canCommit)

        // Commit
        session.commit()
        await Task.yield()

        #expect(workspace.document.features.count == initialFeatureCount + 1)
        let addedFeature = workspace.document.features.last
        #expect(addedFeature != nil)
        #expect(workspace.selectedDatumAxisFeature?.id == addedFeature?.id)

        if case .datumAxis(let data) = addedFeature?.operation {
            #expect(data.mode == .twoPoints)
            #expect(data.point2?.z == 50.0)
            #expect(data.cachedAxis != nil)
        } else {
            Issue.record("Expected .datumAxis feature operation")
        }
    }

    @Test @MainActor func testMakeDatumPointLifecycle() async {
        let workspace = WorkspaceModel()
        let initialFeatureCount = workspace.document.features.count

        let session = CommandSession.makeDatumPoint(workspace: workspace)
        #expect(session.canCommit)
        #expect(session.choiceValue(for: "mode") == "Coordinates")

        // Mutate coordinates
        session.setNumberValue(10.0, for: "coordX")
        session.setNumberValue(20.0, for: "coordY")
        session.setNumberValue(30.0, for: "coordZ")
        #expect(session.canCommit)

        // Switch to Midpoint mode
        session.setChoiceValue("Midpoint", for: "mode")
        #expect(session.canCommit)

        // Make points coincident -> validation fails
        session.setNumberValue(0.0, for: "point1X")
        session.setNumberValue(0.0, for: "point1Y")
        session.setNumberValue(0.0, for: "point1Z")
        session.setNumberValue(0.0, for: "point2X")
        session.setNumberValue(0.0, for: "point2Y")
        session.setNumberValue(0.0, for: "point2Z")
        #expect(!session.canCommit)

        // Restore distinct points
        session.setNumberValue(100.0, for: "point2X")
        #expect(session.canCommit)

        // Commit
        session.commit()
        await Task.yield()

        #expect(workspace.document.features.count == initialFeatureCount + 1)
        let addedFeature = workspace.document.features.last
        #expect(addedFeature != nil)
        #expect(workspace.selectedDatumPointFeature?.id == addedFeature?.id)

        if case .datumPoint(let data) = addedFeature?.operation {
            #expect(data.mode == .midpoint)
            #expect(data.cachedPoint?.position == SIMD3<Float>(50, 0, 0))
        } else {
            Issue.record("Expected .datumPoint feature operation")
        }
    }

    @Test @MainActor func testMakeDatumCoordinateSystemLifecycle() async {
        let workspace = WorkspaceModel()
        let initialFeatureCount = workspace.document.features.count

        let session = CommandSession.makeDatumCoordinateSystem(workspace: workspace)
        #expect(session.canCommit)
        #expect(session.choiceValue(for: "mode") == "Origin and Axes")

        // Switch to Three Points mode
        session.setChoiceValue("Three Points", for: "mode")
        #expect(session.canCommit)

        // Make points collinear -> validation fails
        session.setNumberValue(0.0, for: "point1X")
        session.setNumberValue(0.0, for: "point1Y")
        session.setNumberValue(0.0, for: "point1Z")
        session.setNumberValue(10.0, for: "point2X")
        session.setNumberValue(0.0, for: "point2Y")
        session.setNumberValue(0.0, for: "point2Z")
        session.setNumberValue(20.0, for: "point3X")
        session.setNumberValue(0.0, for: "point3Y")
        session.setNumberValue(0.0, for: "point3Z")
        #expect(!session.canCommit)

        // Restore valid non-collinear points
        session.setNumberValue(0.0, for: "point3X")
        session.setNumberValue(10.0, for: "point3Y")
        #expect(session.canCommit)

        // Commit
        session.commit()
        await Task.yield()

        #expect(workspace.document.features.count == initialFeatureCount + 1)
        let addedFeature = workspace.document.features.last
        #expect(addedFeature != nil)
        #expect(workspace.selectedDatumCoordinateSystemFeature?.id == addedFeature?.id)

        if case .datumCoordinateSystem(let data) = addedFeature?.operation {
            #expect(data.mode == .threePoints)
            #expect(data.cachedCoordinateSystem != nil)
            #expect(data.cachedCoordinateSystem?.zAxis == SIMD3<Float>(0, 0, 1))
        } else {
            Issue.record("Expected .datumCoordinateSystem feature operation")
        }
    }

    @Test @MainActor func testMakeDimensionCommandSessionLifecycle() {
        let workspace = WorkspaceModel()
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let sketchData = SketchFeatureData(planeName: "XY", entities: [line])
        let feature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        workspace.document.addFeature(feature)
        workspace.selectSketchEntity(featureId: feature.id, entityId: line.id)

        let session = CommandSession.makeDimension(workspace: workspace)
        #expect(session.title == "Dimension Line")
        #expect(session.numberValue(for: "length") == 10.0)
        #expect(session.canCommit)

        // Invalid negative value
        session.setNumberValue(-5.0, for: "length")
        #expect(!session.canCommit)

        // Invalid below minimum range (0.01)
        session.setNumberValue(0.001, for: "length")
        #expect(!session.canCommit)

        // Invalid above maximum range (10000.0)
        session.setNumberValue(20000.0, for: "length")
        #expect(!session.canCommit)

        // Valid value
        session.setNumberValue(25.0, for: "length")
        #expect(session.canCommit)

        // Commit updates line in document
        session.commit()
        if case .sketch(let data) = workspace.document.feature(for: feature.id)?.operation {
            #expect(data.entities.first?.length == 25.0)
            #expect(data.entities.first?.endPoint == SIMD2(25, 0))
        } else {
            Issue.record("Expected sketch feature with updated entity")
        }

        // Over-constrained sketch blocks commit
        let line2 = SketchEntity.line(start: SIMD2(0, 5), end: SIMD2(10, 5))
        _ = workspace.document.addSketchEntity(to: feature.id, entity: line2)
        let c1 = SketchConstraint(kind: .parallel, entityIds: [line.id, line2.id])
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [line.id, line2.id])
        workspace.addSketchConstraint(to: feature.id, constraint: c1)
        workspace.addSketchConstraint(to: feature.id, constraint: c2)

        let overConstrainedSession = CommandSession.makeDimension(workspace: workspace, sketchFeatureId: feature.id, entityId: line.id)
        #expect(!overConstrainedSession.canCommit)
    }

    @Test @MainActor func testMeasureCommandSessionInitialization() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeMeasure(workspace: workspace)

        #expect(session.title == "Measure")
        #expect(!session.isPreviewEnabled)
        #expect(session.selectionSlots.count == 2)
        #expect(session.selectionSlots[0].id == "element1")
        #expect(session.selectionSlots[0].isActive)
        #expect(session.selectionSlots[1].id == "element2")
        #expect(!session.selectionSlots[1].isActive)
        #expect(session.canCommit)

        workspace.startCommand(session)
        #expect(workspace.activeCommand === session)
        session.cancel()
        #expect(workspace.activeCommand == nil)
    }

    @Test @MainActor func testMeasureCommandSessionInputFormatting() {
        let testDefaults = UserDefaults(suiteName: "test-measure-\(UUID())")!
        let workspace = WorkspaceModel(defaults: testDefaults)
        workspace.setDocumentUnits(UnitSettings(lengthUnit: .millimeters, decimalPrecision: 2))
        let boxId = SolidId("box-1")
        let boxFeat = Feature.makeBox(
            solidId: boxId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        _ = workspace.document.addFeature(boxFeat)

        workspace.startMeasureCommand()
        guard let session = workspace.activeCommand else {
            Issue.record("Expected active Measure command session")
            return
        }

        let topSub = SelectedSubElement(solidId: boxId, elementType: .face, elementId: 0)
        let bottomSub = SelectedSubElement(solidId: boxId, elementType: .face, elementId: 1)

        workspace.selectElementForActiveCommand(boxId, subElement: topSub)
        #expect(session.selectionSlots[0].selectedObjectId == boxId)
        #expect(session.selectionSlots[0].selectedSubElement == topSub)
        #expect(session.selectionSlots[1].isActive)

        workspace.selectElementForActiveCommand(boxId, subElement: bottomSub)
        #expect(session.selectionSlots[1].selectedObjectId == boxId)
        #expect(session.selectionSlots[1].selectedSubElement == bottomSub)

        let minInput = session.inputs.first(where: { $0.id == "minDistance" })
        #expect(minInput != nil)
        if case .readOnlyText(let val, let unit) = minInput?.value {
            #expect(val == "10.00")
            #expect(unit == "mm")
        } else {
            Issue.record("Expected readOnlyText value for minDistance")
        }

        let centerInput = session.inputs.first(where: { $0.id == "centerDistance" })
        #expect(centerInput != nil)
        if case .readOnlyText(let val, let unit) = centerInput?.value {
            #expect(val == "10.00")
            #expect(unit == "mm")
        }

        let normInput = session.inputs.first(where: { $0.id == "normalDistance" })
        #expect(normInput != nil)
        if case .readOnlyText(let val, let unit) = normInput?.value {
            #expect(val == "10.00")
            #expect(unit == "mm")
        }

        let angleInput = session.inputs.first(where: { $0.id == "angle" })
        #expect(angleInput != nil)
        if case .readOnlyText(let val, let unit) = angleInput?.value {
            #expect(val == "0.00")
            #expect(unit == "deg")
        }

        let areaInput = session.inputs.first(where: { $0.id == "area" })
        #expect(areaInput != nil)
        if case .readOnlyText(let val, let unit) = areaInput?.value {
            #expect(val == "100.00")
            #expect(unit == "mm²")
        }
    }

    @Test @MainActor func testMakeChamferLifecycle() async {
        let workspace = WorkspaceModel()
        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        workspace.document.addFeature(boxFeat)
        let edgeRef = TopologicalReference(
            sourceFeatureId: boxFeat.id,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:top-front")]
        )

        let session = CommandSession.makeChamfer(
            workspace: workspace,
            targetSolidId: boxFeat.outputSolidId,
            edgeReferences: [edgeRef]
        )
        #expect(session.canCommit)
        #expect(session.choiceValue(for: "mode") == "Equal Distance")
        #expect(session.numberValue(for: "distance") == 1.0)

        session.setChoiceValue("Two Distances", for: "mode")
        session.setNumberValue(2.0, for: "distance")
        session.setNumberValue(3.0, for: "distance2")
        #expect(session.canCommit)

        let initialDocCount = workspace.document.objects.count
        session.commit()

        await Task.yield()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        #expect(workspace.selectedId == added?.id)
        if case .chamfer(let params)? = added?.def {
            #expect(params.distance == 2.0)
            #expect(params.distance2 == 3.0)
            #expect(params.mode == .twoDistances)
            #expect(params.edgeReferences == [edgeRef])
        } else {
            Issue.record("Expected .chamfer def on scene object")
        }
    }

    @Test @MainActor func testMakeChamferValidation() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeChamfer(workspace: workspace)
        #expect(!session.canCommit)

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        workspace.document.addFeature(boxFeat)
        let edgeRef = TopologicalReference(sourceFeatureId: boxFeat.id, elementType: .edge, historyPath: [HistoryStep(kind: .generated, label: "edge:top-front")])

        let sessionWithEdge = CommandSession.makeChamfer(workspace: workspace, targetSolidId: boxFeat.outputSolidId, edgeReferences: [edgeRef])
        #expect(sessionWithEdge.canCommit)

        sessionWithEdge.setNumberValue(-1.0, for: "distance")
        #expect(!sessionWithEdge.canCommit)

        sessionWithEdge.setNumberValue(1.0, for: "distance")
        #expect(sessionWithEdge.canCommit)

        sessionWithEdge.setChoiceValue("Two Distances", for: "mode")
        sessionWithEdge.setNumberValue(0.0, for: "distance2")
        #expect(!sessionWithEdge.canCommit)

        sessionWithEdge.setNumberValue(1.5, for: "distance2")
        #expect(sessionWithEdge.canCommit)

        sessionWithEdge.setChoiceValue("Distance-Angle", for: "mode")
        sessionWithEdge.setNumberValue(0.0, for: "angle")
        #expect(!sessionWithEdge.canCommit)
        sessionWithEdge.setNumberValue(90.0, for: "angle")
        #expect(!sessionWithEdge.canCommit)
        sessionWithEdge.setNumberValue(45.0, for: "angle")
        #expect(sessionWithEdge.canCommit)
    }

    @Test @MainActor func testMakeChamferCancellation() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeChamfer(workspace: workspace)
        session.cancel()
        #expect(workspace.viewportManager.renderer?.candidateMeshes().contains(where: { $0.id == CommandSession.previewSolidId }) != true)
    }

    // MARK: - Shell Command Session Tests (BL-PRT-08)

    @Test @MainActor func testMakeShellLifecycle() async {
        let workspace = WorkspaceModel()
        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 20, depth: 20, height: 20)
        )
        workspace.document.addFeature(boxFeat)
        let faceRef = TopologicalReference(
            sourceFeatureId: boxFeat.id,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")]
        )

        let session = CommandSession.makeShell(
            workspace: workspace,
            targetSolidId: boxFeat.outputSolidId,
            removedFaceReferences: [faceRef]
        )
        #expect(session.canCommit)
        #expect(session.numberValue(for: "thickness") == 1.0)

        session.setNumberValue(2.0, for: "thickness")
        #expect(session.canCommit)

        let initialDocCount = workspace.document.objects.count
        session.commit()

        await Task.yield()

        #expect(workspace.document.objects.count == initialDocCount + 1)
        let added = workspace.document.objects.last
        #expect(workspace.selectedId == added?.id)
        if case .shell(let params)? = added?.def {
            #expect(params.thickness == 2.0)
            #expect(params.removedFaceReferences == [faceRef])
        } else {
            Issue.record("Expected .shell def on scene object")
        }
    }

    @Test @MainActor func testMakeShellValidation() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeShell(workspace: workspace)
        #expect(!session.canCommit)

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box",
            params: BoxParams(width: 20, depth: 20, height: 20)
        )
        workspace.document.addFeature(boxFeat)

        let sessionWithBox = CommandSession.makeShell(workspace: workspace, targetSolidId: boxFeat.outputSolidId)
        #expect(sessionWithBox.canCommit)

        sessionWithBox.setNumberValue(-1.0, for: "thickness")
        #expect(!sessionWithBox.canCommit)

        sessionWithBox.setNumberValue(0.0, for: "thickness")
        #expect(!sessionWithBox.canCommit)

        sessionWithBox.setNumberValue(2.0, for: "thickness")
        #expect(sessionWithBox.canCommit)
    }

    @Test @MainActor func testMakeShellCancellation() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeShell(workspace: workspace)
        session.cancel()
        #expect(workspace.viewportManager.renderer?.candidateMeshes().contains(where: { $0.id == CommandSession.previewSolidId }) != true)
    }
}

}
