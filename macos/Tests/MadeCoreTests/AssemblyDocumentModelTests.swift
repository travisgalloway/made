import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct AssemblyDocumentModelTests {

    @Test func testDocumentTypeDefaultsToPart() {
        let doc = DocumentModel()
        #expect(doc.documentType == .part)
        #expect(doc.componentInstances.isEmpty)
    }

    @Test func testSetDocumentTypeWithUndo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        doc.setDocumentType(.assembly)
        #expect(doc.documentType == .assembly)

        undoManager.undo()
        #expect(doc.documentType == .part)

        undoManager.redo()
        #expect(doc.documentType == .assembly)
    }

    @Test func testAddComponentInstanceAndProjection() {
        let doc = DocumentModel(documentType: .assembly)
        #expect(doc.documentType == .assembly)

        let instance = ComponentInstance(
            name: "Bracket A",
            reference: .internalPart(name: "Bracket"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0))
        )

        let result = doc.addComponentInstance(instance)
        guard case .success = result else {
            Issue.record("Expected successful addComponentInstance")
            return
        }
        #expect(doc.componentInstances.count == 1)
        #expect(doc.componentInstances.first?.name == "Bracket A")

        // Verifying projection into objects and bodies
        #expect(doc.objects.contains(where: { $0.id == instance.solidId }))
        #expect(doc.bodies.contains(where: { $0.id == instance.solidId }))

        let projectedBody = doc.body(for: instance.solidId)
        #expect(projectedBody != nil)
        #expect(projectedBody?.name == "Bracket A")
    }

    @Test func testRemoveComponentInstanceWithUndo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let instance = ComponentInstance(
            name: "Gear",
            reference: .internalPart(name: "GearPart"),
            transform: Transform(position: SIMD3<Float>(0, 5, 0))
        )
        _ = doc.addComponentInstance(instance)
        #expect(doc.componentInstances.count == 1)
        undoManager.removeAllActions()

        let removeResult = doc.removeComponentInstance(id: instance.id)
        guard case .success = removeResult else {
            Issue.record("Expected successful removeComponentInstance")
            return
        }
        #expect(doc.componentInstances.isEmpty)
        #expect(!doc.objects.contains(where: { $0.id == instance.solidId }))

        undoManager.undo()
        #expect(doc.componentInstances.count == 1)
        #expect(doc.objects.contains(where: { $0.id == instance.solidId }))

        undoManager.redo()
        #expect(doc.componentInstances.isEmpty)
    }

    @Test func testUpdateComponentInstanceTransformWithUndo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let instance = ComponentInstance(
            name: "Shaft",
            reference: .internalPart(name: "ShaftPart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        _ = doc.addComponentInstance(instance)
        undoManager.removeAllActions()

        let newTransform = Transform(position: SIMD3<Float>(100, 200, 300))
        let updateResult = doc.updateComponentInstanceTransform(id: instance.id, transform: newTransform)
        guard case .success = updateResult else {
            Issue.record("Expected successful updateComponentInstanceTransform")
            return
        }

        #expect(doc.componentInstances.first?.transform.position == SIMD3<Float>(100, 200, 300))
        let projectedObj = doc.objects.first(where: { $0.id == instance.solidId })
        #expect(projectedObj?.transform.position == SIMD3<Float>(100, 200, 300))

        undoManager.undo()
        #expect(doc.componentInstances.first?.transform.position == SIMD3<Float>(0, 0, 0))
        #expect(doc.objects.first(where: { $0.id == instance.solidId })?.transform.position == SIMD3<Float>(0, 0, 0))

        undoManager.redo()
        #expect(doc.componentInstances.first?.transform.position == SIMD3<Float>(100, 200, 300))
    }

    @Test func testMultipleInstancesOfSamePart() {
        let doc = DocumentModel(documentType: .assembly)

        let inst1 = ComponentInstance(
            name: "Bolt 1",
            reference: .internalPart(name: "HexBoltM6"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        let inst2 = ComponentInstance(
            name: "Bolt 2",
            reference: .internalPart(name: "HexBoltM6"),
            transform: Transform(position: SIMD3<Float>(50, 0, 0))
        )

        _ = doc.addComponentInstance(inst1)
        _ = doc.addComponentInstance(inst2)

        #expect(doc.componentInstances.count == 2)
        #expect(inst1.id != inst2.id)
        #expect(inst1.solidId != inst2.solidId)

        #expect(doc.objects.contains(where: { $0.id == inst1.solidId }))
        #expect(doc.objects.contains(where: { $0.id == inst2.solidId }))

        _ = doc.updateComponentInstanceTransform(id: inst1.id, transform: Transform(position: SIMD3<Float>(10, 0, 0)))
        #expect(doc.componentInstances.first(where: { $0.id == inst1.id })?.transform.position == SIMD3<Float>(10, 0, 0))
        #expect(doc.componentInstances.first(where: { $0.id == inst2.id })?.transform.position == SIMD3<Float>(50, 0, 0))
    }

    @Test func testComponentVisibilityAndLockToggles() {
        let doc = DocumentModel(documentType: .assembly)
        let instance = ComponentInstance(
            name: "Plate",
            reference: .internalPart(name: "BasePlate")
        )
        _ = doc.addComponentInstance(instance)

        doc.setBodyVisibility(id: instance.solidId, isVisible: false)
        #expect(doc.componentInstances.first?.isVisible == false)
        #expect(doc.objects.first(where: { $0.id == instance.solidId })?.isVisible == false)

        doc.setBodyLocked(id: instance.solidId, isLocked: true)
        #expect(doc.componentInstances.first?.isLocked == true)
        #expect(doc.objects.first(where: { $0.id == instance.solidId })?.isLocked == true)

        // Attempting to move locked component should fail
        let moveResult = doc.updateComponentInstanceTransform(id: instance.id, transform: Transform(position: SIMD3<Float>(1, 1, 1)))
        guard case .failure = moveResult else {
            Issue.record("Expected failure when moving locked component")
            return
        }
    }

    @Test func testEmptyAssemblyHandling() {
        let doc = DocumentModel(documentType: .assembly)
        #expect(doc.documentType == .assembly)
        #expect(doc.componentInstances.isEmpty)
        #expect(doc.objects.isEmpty)
        #expect(doc.bodies.isEmpty)
    }

    @Test func testResetWithAssemblyTypeAndInstances() {
        let doc = DocumentModel()
        let instance = ComponentInstance(
            name: "Widget",
            reference: .internalPart(name: "WidgetPart")
        )

        doc.reset(
            with: [Feature](),
            documentType: .assembly,
            componentInstances: [instance]
        )

        #expect(doc.documentType == .assembly)
        #expect(doc.componentInstances.count == 1)
        #expect(doc.objects.contains(where: { $0.id == instance.solidId }))
    }

    @Test func testComponentGroundedAndFloatingToggles() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let instance = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "BasePart"),
            isGrounded: false
        )
        _ = doc.addComponentInstance(instance)
        undoManager.removeAllActions()

        #expect(doc.componentInstances.first?.isGrounded == false)
        #expect(doc.objects.first(where: { $0.id == instance.solidId })?.isLocked == false)

        let groundResult = doc.setComponentInstanceGrounded(id: instance.id, isGrounded: true)
        guard case .success = groundResult else {
            Issue.record("Expected successful groundComponent")
            return
        }
        #expect(doc.componentInstances.first?.isGrounded == true)
        #expect(doc.objects.first(where: { $0.id == instance.solidId })?.isLocked == true)

        let moveResult = doc.updateComponentInstanceTransform(id: instance.id, transform: Transform(position: SIMD3<Float>(10, 10, 10)))
        guard case .failure(let err) = moveResult else {
            Issue.record("Expected failure when moving grounded component")
            return
        }
        #expect(err == .invalidOperation("Component 'Base' is grounded and cannot be moved"))

        undoManager.undo()
        #expect(doc.componentInstances.first?.isGrounded == false)
        #expect(doc.objects.first(where: { $0.id == instance.solidId })?.isLocked == false)

        let moveAfterUndo = doc.updateComponentInstanceTransform(id: instance.id, transform: Transform(position: SIMD3<Float>(10, 10, 10)))
        guard case .success = moveAfterUndo else {
            Issue.record("Expected successful move after floating component")
            return
        }
        #expect(doc.componentInstances.first?.transform.position == SIMD3<Float>(10, 10, 10))
    }

    @Test func testComponentGroundedUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let instance = ComponentInstance(
            name: "Anchor",
            reference: .internalPart(name: "AnchorPart"),
            isGrounded: false
        )
        _ = doc.addComponentInstance(instance)
        undoManager.removeAllActions()

        _ = doc.setComponentInstanceGrounded(id: instance.id, isGrounded: true)
        #expect(doc.componentInstances.first?.isGrounded == true)
        #expect(doc.objects.first(where: { $0.id == instance.solidId })?.isLocked == true)

        undoManager.undo()
        #expect(doc.componentInstances.first?.isGrounded == false)
        #expect(doc.objects.first(where: { $0.id == instance.solidId })?.isLocked == false)

        undoManager.redo()
        #expect(doc.componentInstances.first?.isGrounded == true)
        #expect(doc.objects.first(where: { $0.id == instance.solidId })?.isLocked == true)
    }

    @Test func testAddAssemblyConstraintWithUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let constraint = AssemblyConstraint(
            kind: .coincident,
            firstFeature: AssemblyFeature(origin: .zero),
            secondFeature: AssemblyFeature(origin: SIMD3<Float>(10, 0, 0))
        )

        let result = doc.addAssemblyConstraint(constraint)
        guard case .success = result else {
            Issue.record("Expected successful addAssemblyConstraint")
            return
        }
        #expect(doc.assemblyConstraints.count == 1)
        #expect(doc.assemblyConstraints.first?.id == constraint.id)

        undoManager.undo()
        #expect(doc.assemblyConstraints.isEmpty)

        undoManager.redo()
        #expect(doc.assemblyConstraints.count == 1)
        #expect(doc.assemblyConstraints.first?.id == constraint.id)
    }

    @Test func testRemoveAssemblyConstraintWithUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let constraint = AssemblyConstraint(
            kind: .parallel,
            firstFeature: AssemblyFeature(origin: .zero, axis: SIMD3<Float>(0, 1, 0)),
            secondFeature: AssemblyFeature(origin: .zero, axis: SIMD3<Float>(0, 1, 0))
        )
        _ = doc.addAssemblyConstraint(constraint)
        undoManager.removeAllActions()

        let removeResult = doc.removeAssemblyConstraint(id: constraint.id)
        guard case .success = removeResult else {
            Issue.record("Expected successful removeAssemblyConstraint")
            return
        }
        #expect(doc.assemblyConstraints.isEmpty)

        undoManager.undo()
        #expect(doc.assemblyConstraints.count == 1)
        #expect(doc.assemblyConstraints.first?.id == constraint.id)

        undoManager.redo()
        #expect(doc.assemblyConstraints.isEmpty)
    }

    @Test func testUpdateAssemblyConstraintWithUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let constraint = AssemblyConstraint(
            kind: .distance,
            firstFeature: AssemblyFeature(origin: .zero),
            secondFeature: AssemblyFeature(origin: .zero),
            value: 10.0
        )
        _ = doc.addAssemblyConstraint(constraint)
        undoManager.removeAllActions()

        var updated = constraint
        updated.value = 25.0
        let updateResult = doc.updateAssemblyConstraint(updated)
        guard case .success = updateResult else {
            Issue.record("Expected successful updateAssemblyConstraint")
            return
        }
        #expect(doc.assemblyConstraints.first?.value == 25.0)

        undoManager.undo()
        #expect(doc.assemblyConstraints.first?.value == 10.0)

        undoManager.redo()
        #expect(doc.assemblyConstraints.first?.value == 25.0)
    }

    @Test func testSolveAssemblyConstraintsWithUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "BasePart"),
            transform: .identity,
            isGrounded: true
        )
        let slider = ComponentInstance(
            name: "Slider",
            reference: .internalPart(name: "SliderPart"),
            transform: Transform(position: SIMD3<Float>(50, 0, 0)),
            isGrounded: false
        )
        _ = doc.addComponentInstance(base)
        _ = doc.addComponentInstance(slider)

        let mate = AssemblyConstraint(
            kind: .coincident,
            firstFeature: AssemblyFeature(componentInstanceId: base.id, origin: .zero),
            secondFeature: AssemblyFeature(componentInstanceId: slider.id, origin: .zero)
        )
        _ = doc.addAssemblyConstraint(mate)
        undoManager.removeAllActions()

        let solveResult = doc.solveAssemblyConstraints()
        #expect(solveResult.status.isConverged)

        let solvedSlider = doc.componentInstances.first(where: { $0.id == slider.id })
        #expect(solvedSlider != nil)
        #expect(abs(solvedSlider!.transform.position.x) < 1e-3)
        #expect(abs(solvedSlider!.transform.position.y) < 1e-3)
        #expect(abs(solvedSlider!.transform.position.z) < 1e-3)

        // Grounded base must remain unchanged at (0, 0, 0)
        let solvedBase = doc.componentInstances.first(where: { $0.id == base.id })
        #expect(solvedBase?.transform.position == SIMD3<Float>(0, 0, 0))

        // Verify undo restores slider position to (50, 0, 0)
        undoManager.undo()
        let undoneSlider = doc.componentInstances.first(where: { $0.id == slider.id })
        #expect(undoneSlider?.transform.position == SIMD3<Float>(50, 0, 0))

        // Verify redo reapplies solved position (0, 0, 0)
        undoManager.redo()
        let redoneSlider = doc.componentInstances.first(where: { $0.id == slider.id })
        #expect(abs(redoneSlider!.transform.position.x) < 1e-3)
    }

    @Test func testJointConstraintSuppressionAndModificationWithUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "BasePart"), transform: .identity, isGrounded: true)
        let arm = ComponentInstance(name: "Arm", reference: .internalPart(name: "ArmPart"), transform: Transform(position: SIMD3<Float>(10, 20, 30)), isGrounded: false)
        _ = doc.addComponentInstance(base)
        _ = doc.addComponentInstance(arm)

        let joint = AssemblyConstraint(
            name: "Hinge",
            kind: .revolute,
            firstFeature: AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1)),
            secondFeature: AssemblyFeature(componentInstanceId: arm.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        )
        _ = doc.addAssemblyConstraint(joint)
        #expect(doc.assemblyConstraints.count == 1)
        #expect(doc.assemblyConstraints.first?.isJoint == true)
        #expect(doc.assemblyConstraints.first?.isSuppressed == false)
        undoManager.removeAllActions()

        // Toggle suppressed
        var toggled = joint
        toggled.isSuppressed = true
        _ = doc.updateAssemblyConstraint(toggled)
        #expect(doc.assemblyConstraints.first?.isSuppressed == true)

        undoManager.undo()
        #expect(doc.assemblyConstraints.first?.isSuppressed == false)

        undoManager.redo()
        #expect(doc.assemblyConstraints.first?.isSuppressed == true)

        // With suppressed joint, solve leaves arm free (6 DOF)
        let solveSuppressed = doc.solveAssemblyConstraints()
        #expect(solveSuppressed.totalDOF == 6)

        // Unsuppress joint
        undoManager.undo()
        #expect(doc.assemblyConstraints.first?.isSuppressed == false)

        // With unsuppressed revolute joint, solve leaves arm with 1 DOF (rotation about Z)
        let solveUnsuppressed = doc.solveAssemblyConstraints()
        #expect(solveUnsuppressed.status.isConverged)
        #expect(solveUnsuppressed.totalDOF == 1)
    }

    @Test func testDocumentModelAssemblyDOFQueries() {
        let doc = DocumentModel(documentType: .assembly)
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "BasePart"), transform: .identity, isGrounded: true)
        let part = ComponentInstance(name: "Part", reference: .internalPart(name: "Part"), transform: Transform(position: SIMD3<Float>(10, 0, 0)), isGrounded: false)
        _ = doc.addComponentInstance(base)
        _ = doc.addComponentInstance(part)

        let system = doc.assemblyConstraintSystem()
        #expect(system.instances.count == 2)
        #expect(system.constraints.isEmpty)

        let initialDOF = doc.computeAssemblyDOF()
        #expect(initialDOF.totalDOF == 6)
        #expect(initialDOF.instanceDOF[base.id] == 0)
        #expect(initialDOF.instanceDOF[part.id] == 6)

        let mate = AssemblyConstraint(
            kind: .coincident,
            firstFeature: AssemblyFeature(componentInstanceId: base.id, origin: .zero),
            secondFeature: AssemblyFeature(componentInstanceId: part.id, origin: .zero)
        )
        _ = doc.addAssemblyConstraint(mate)

        let matedDOF = doc.computeAssemblyDOF()
        #expect(matedDOF.totalDOF == 3)
        #expect(matedDOF.instanceDOF[base.id] == 0)
        #expect(matedDOF.instanceDOF[part.id] == 3)
    }
}
