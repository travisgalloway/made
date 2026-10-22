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

    // MARK: - Interactive Drag Lifecycle and Undo Coalescing (BL-ASM-06)

    @Test func testInteractiveAssemblyDragUndoCoalescing() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let instance = ComponentInstance(
            name: "FreePart",
            reference: .internalPart(name: "Part"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        _ = doc.addComponentInstance(instance)
        undoManager.removeAllActions()

        doc.beginInteractiveAssemblyDrag(instanceId: instance.id)
        #expect(doc.activeAssemblyDragInitialTransforms != nil)

        // Multiple solve passes during drag gesture
        _ = doc.solveAssemblyConstraints(
            dragTarget: AssemblyDragTarget(instanceId: instance.id, targetPosition: SIMD3<Float>(10, 0, 0)),
            registerUndo: false
        )
        _ = doc.solveAssemblyConstraints(
            dragTarget: AssemblyDragTarget(instanceId: instance.id, targetPosition: SIMD3<Float>(20, 0, 0)),
            registerUndo: false
        )
        _ = doc.solveAssemblyConstraints(
            dragTarget: AssemblyDragTarget(instanceId: instance.id, targetPosition: SIMD3<Float>(30, 0, 0)),
            registerUndo: false
        )

        #expect(doc.componentInstances.first?.transform.position == SIMD3<Float>(30, 0, 0))
        // No per-frame undo records were emitted during the drag
        #expect(!undoManager.canUndo)

        // End drag commits 1 coalesced undo record
        doc.endInteractiveAssemblyDrag(instanceId: instance.id)
        #expect(doc.activeAssemblyDragInitialTransforms == nil)
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(doc.componentInstances.first?.transform.position == SIMD3<Float>(0, 0, 0))

        undoManager.redo()
        #expect(doc.componentInstances.first?.transform.position == SIMD3<Float>(30, 0, 0))
    }

    @Test func testCancelInteractiveAssemblyDragRestoresInitialTransforms() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let instance = ComponentInstance(
            name: "FreePart",
            reference: .internalPart(name: "Part"),
            transform: Transform(position: SIMD3<Float>(5, 10, 15))
        )
        _ = doc.addComponentInstance(instance)
        undoManager.removeAllActions()

        doc.beginInteractiveAssemblyDrag(instanceId: instance.id)
        _ = doc.solveAssemblyConstraints(
            dragTarget: AssemblyDragTarget(instanceId: instance.id, targetPosition: SIMD3<Float>(50, 60, 70)),
            registerUndo: false
        )
        #expect(doc.componentInstances.first?.transform.position == SIMD3<Float>(50, 60, 70))

        // Canceling drag reverts back to initial position without undo pollution
        doc.cancelInteractiveAssemblyDrag()
        #expect(doc.activeAssemblyDragInitialTransforms == nil)
        #expect(doc.componentInstances.first?.transform.position == SIMD3<Float>(5, 10, 15))
        #expect(!undoManager.canUndo)
    }

    // MARK: - Subassemblies (BL-ASM-07)

    @Test func testGroupAsSubassemblyAndUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "BasePart"), transform: .identity, isGrounded: true)
        let partA = ComponentInstance(name: "PartA", reference: .internalPart(name: "PartA"), transform: Transform(position: SIMD3<Float>(10, 0, 0)))
        let partB = ComponentInstance(name: "PartB", reference: .internalPart(name: "PartB"), transform: Transform(position: SIMD3<Float>(20, 0, 0)))

        _ = doc.addComponentInstance(base)
        _ = doc.addComponentInstance(partA)
        _ = doc.addComponentInstance(partB)

        // Internal constraint between A and B
        let internalMate = AssemblyConstraint(
            name: "A to B",
            kind: .distance,
            firstFeature: AssemblyFeature(componentInstanceId: partA.id, origin: .zero),
            secondFeature: AssemblyFeature(componentInstanceId: partB.id, origin: .zero),
            value: 10.0
        )
        // External constraint between Base and A
        let externalMate = AssemblyConstraint(
            name: "Base to A",
            kind: .coincident,
            firstFeature: AssemblyFeature(componentInstanceId: base.id, origin: .zero),
            secondFeature: AssemblyFeature(componentInstanceId: partA.id, origin: .zero)
        )
        _ = doc.addAssemblyConstraint(internalMate)
        _ = doc.addAssemblyConstraint(externalMate)

        undoManager.removeAllActions()

        // Group A and B into subassembly
        let groupResult = doc.groupAsSubassembly(instanceIds: [partA.id, partB.id], name: "SubAB")
        guard case .success(let subassembly) = groupResult else {
            Issue.record("Failed to group as subassembly")
            return
        }

        #expect(doc.componentInstances.count == 2) // Base + SubAB
        #expect(doc.componentInstances.contains(where: { $0.id == subassembly.id }))
        #expect(subassembly.isSubassembly)
        #expect(subassembly.childInstances.count == 2)
        #expect(subassembly.childConstraints.count == 1)
        #expect(subassembly.childConstraints.first?.name == "A to B")
        #expect(doc.assemblyConstraints.count == 1) // Base to A remains in parent
        #expect(doc.assemblyConstraints.first?.name == "Base to A")

        // Undo grouping
        undoManager.undo()
        #expect(doc.componentInstances.count == 3)
        #expect(doc.componentInstances.contains(where: { $0.id == partA.id }))
        #expect(doc.componentInstances.contains(where: { $0.id == partB.id }))
        #expect(doc.assemblyConstraints.count == 2)

        // Redo grouping
        undoManager.redo()
        #expect(doc.componentInstances.count == 2)
        #expect(doc.componentInstances.contains(where: { $0.id == subassembly.id }))
        #expect(doc.assemblyConstraints.count == 1)
    }

    @Test func testDissolveSubassemblyAndUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let child1 = ComponentInstance(name: "Child1", reference: .internalPart(name: "P1"), transform: Transform(position: SIMD3<Float>(5, 0, 0)))
        let child2 = ComponentInstance(name: "Child2", reference: .internalPart(name: "P2"), transform: Transform(position: SIMD3<Float>(15, 0, 0)))
        let mate = AssemblyConstraint(
            kind: .concentric,
            firstFeature: AssemblyFeature(componentInstanceId: child1.id, origin: .zero),
            secondFeature: AssemblyFeature(componentInstanceId: child2.id, origin: .zero)
        )
        let sub = ComponentInstance(
            name: "Sub",
            reference: .subassembly(name: "Sub"),
            transform: Transform(position: SIMD3<Float>(100, 0, 0)),
            subassemblyBehavior: .rigid,
            childInstances: [child1, child2],
            childConstraints: [mate]
        )

        _ = doc.addComponentInstance(sub)
        undoManager.removeAllActions()

        let dissolveResult = doc.dissolveSubassembly(id: sub.id)
        guard case .success = dissolveResult else {
            Issue.record("Failed to dissolve subassembly")
            return
        }

        #expect(doc.componentInstances.count == 2)
        #expect(!doc.componentInstances.contains(where: { $0.id == sub.id }))
        #expect(doc.assemblyConstraints.count == 1)

        // World transform of child1: (100, 0, 0) + (5, 0, 0) = (105, 0, 0)
        let dissolvedChild1 = doc.componentInstances.first(where: { $0.id == child1.id })
        #expect(dissolvedChild1 != nil)
        #expect(abs((dissolvedChild1?.transform.position.x ?? 0) - 105) < 1e-3)

        // Undo dissolve
        undoManager.undo()
        #expect(doc.componentInstances.count == 1)
        #expect(doc.componentInstances.first?.id == sub.id)
        #expect(doc.assemblyConstraints.isEmpty)

        // Redo dissolve
        undoManager.redo()
        #expect(doc.componentInstances.count == 2)
        #expect(doc.assemblyConstraints.count == 1)
    }

    @Test func testSetSubassemblyBehaviorAndUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let child = ComponentInstance(name: "Child", reference: .internalPart(name: "P"))
        let sub = ComponentInstance(
            name: "Sub",
            reference: .subassembly(name: "Sub"),
            subassemblyBehavior: .rigid,
            childInstances: [child]
        )
        _ = doc.addComponentInstance(sub)
        undoManager.removeAllActions()

        let setResult = doc.setSubassemblyBehavior(id: sub.id, behavior: .flexible)
        guard case .success = setResult else {
            Issue.record("Failed to set subassembly behavior")
            return
        }

        #expect(doc.componentInstances.first?.subassemblyBehavior == .flexible)

        undoManager.undo()
        #expect(doc.componentInstances.first?.subassemblyBehavior == .rigid)

        undoManager.redo()
        #expect(doc.componentInstances.first?.subassemblyBehavior == .flexible)
    }

    @Test func testRecursiveComponentLookupInDocument() {
        let leaf = ComponentInstance(name: "LeafPart", reference: .internalPart(name: "Leaf"))
        let sub = ComponentInstance(
            name: "ParentSub",
            reference: .subassembly(name: "ParentSub"),
            childInstances: [leaf]
        )
        let doc = DocumentModel(documentType: .assembly, componentInstances: [sub])

        #expect(doc.findComponentInstance(id: leaf.id)?.name == "LeafPart")
        #expect(doc.findComponentInstance(solidId: leaf.solidId)?.name == "LeafPart")
        #expect(doc.allComponentInstances.count == 2)
    }

    // MARK: - Component Patterns & Mirrors Tests (BL-ASM-08, #169)

    @Test func testLinearComponentPatternCreationAndTransforms() {
        let doc = DocumentModel(documentType: .assembly)
        let source = ComponentInstance(
            name: "Bolt",
            reference: .internalPart(name: "BoltPart"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0)),
            isGrounded: true
        )
        _ = doc.addComponentInstance(source)
        #expect(doc.componentInstances.count == 1)

        let params = AssemblyPatternParams(
            sourceInstanceId: source.id,
            patternType: .linear,
            count: 4,
            linearSpacing: 25.0,
            linearDirection: SIMD3<Float>(1, 0, 0)
        )
        let result = doc.patternComponentInstance(params: params)
        guard case .success(let pattern) = result else {
            Issue.record("Expected successful linear pattern creation")
            return
        }

        #expect(doc.componentPatterns.count == 1)
        #expect(doc.componentPatterns.first?.id == pattern.id)
        #expect(pattern.replicaInstanceIds.count == 3)
        #expect(doc.componentInstances.count == 4)

        // Verify replicas are ungrounded by default and correctly spaced
        let replicas = doc.componentInstances.filter { $0.patternId == pattern.id }
        #expect(replicas.count == 3)
        for (idx, replica) in replicas.enumerated() {
            #expect(!replica.isGrounded)
            #expect(replica.name == "Bolt (Pattern \(idx + 2))")
            let expectedX = Float(10 + (idx + 1) * 25)
            #expect(abs(replica.transform.position.x - expectedX) < 1e-4)
            #expect(abs(replica.transform.position.y) < 1e-4)
            #expect(abs(replica.transform.position.z) < 1e-4)
        }
    }

    @Test func testLinearComponentPatternSymmetricAndSkippedIndices() {
        let doc = DocumentModel(documentType: .assembly)
        let source = ComponentInstance(
            name: "Bracket",
            reference: .internalPart(name: "BracketPart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        _ = doc.addComponentInstance(source)

        // Symmetric pattern with count = 3: index 1 is +1 step (+20), index 2 is -1 step (-20)
        // Skip index 2 -> only index 1 should be generated
        let params = AssemblyPatternParams(
            sourceInstanceId: source.id,
            patternType: .linear,
            count: 3,
            linearSpacing: 20.0,
            linearDirection: SIMD3<Float>(0, 1, 0),
            isSymmetric: true,
            skippedIndices: [2]
        )
        let result = doc.patternComponentInstance(params: params)
        guard case .success(let pattern) = result else {
            Issue.record("Expected successful pattern creation with skipped indices")
            return
        }

        #expect(pattern.replicaInstanceIds.count == 1)
        #expect(doc.componentInstances.count == 2)
        let replica = doc.componentInstances.first(where: { $0.id == pattern.replicaInstanceIds.first })
        #expect(replica != nil)
        #expect(replica?.name == "Bracket (Pattern 2)")
        #expect(abs((replica?.transform.position.y ?? 0) - 20.0) < 1e-4)
    }

    @Test func testLinearComponentPatternCountOneNoOp() {
        let doc = DocumentModel(documentType: .assembly)
        let source = ComponentInstance(name: "SolePart", reference: .internalPart(name: "Sole"))
        _ = doc.addComponentInstance(source)

        let params = AssemblyPatternParams(
            sourceInstanceId: source.id,
            patternType: .linear,
            count: 1
        )
        let result = doc.patternComponentInstance(params: params)
        guard case .success(let pattern) = result else {
            Issue.record("Expected success for count = 1 no-op")
            return
        }

        #expect(pattern.replicaInstanceIds.isEmpty)
        #expect(doc.componentInstances.count == 1)
        #expect(doc.componentPatterns.count == 1)
    }

    @Test func testCircularComponentPatternFullCircleAndArc() {
        let doc = DocumentModel(documentType: .assembly)
        let source = ComponentInstance(
            name: "Spoke",
            reference: .internalPart(name: "SpokePart"),
            transform: Transform(position: SIMD3<Float>(20, 0, 0))
        )
        _ = doc.addComponentInstance(source)

        // 4 instances around Z axis centered at (0, 0, 0)
        let params = AssemblyPatternParams(
            sourceInstanceId: source.id,
            patternType: .circular,
            count: 4,
            axisOrigin: SIMD3<Float>(0, 0, 0),
            axisDirection: SIMD3<Float>(0, 0, 1),
            totalAngle: 360.0,
            isFullCircle: true
        )
        let result = doc.patternComponentInstance(params: params)
        guard case .success(let pattern) = result else {
            Issue.record("Expected circular pattern creation")
            return
        }

        #expect(pattern.replicaInstanceIds.count == 3)
        #expect(doc.componentInstances.count == 4)

        // 90 degrees around Z -> (0, 20, 0)
        let rep1 = doc.componentInstances.first(where: { $0.name == "Spoke (Pattern 2)" })
        #expect(rep1 != nil)
        #expect(abs(rep1!.transform.position.x - 0.0) < 1e-3)
        #expect(abs(rep1!.transform.position.y - 20.0) < 1e-3)

        // 180 degrees around Z -> (-20, 0, 0)
        let rep2 = doc.componentInstances.first(where: { $0.name == "Spoke (Pattern 3)" })
        #expect(rep2 != nil)
        #expect(abs(rep2!.transform.position.x - (-20.0)) < 1e-3)
        #expect(abs(rep2!.transform.position.y - 0.0) < 1e-3)

        // 270 degrees around Z -> (0, -20, 0)
        let rep3 = doc.componentInstances.first(where: { $0.name == "Spoke (Pattern 4)" })
        #expect(rep3 != nil)
        #expect(abs(rep3!.transform.position.x - 0.0) < 1e-3)
        #expect(abs(rep3!.transform.position.y - (-20.0)) < 1e-3)
    }

    @Test func testFeatureDrivenComponentPattern() {
        let driverPatternFeat = Feature(
            name: "Hole Pattern",
            operation: .pattern(PatternParams(
                targetSolidId: SolidId("hole-solid"),
                patternType: .linear,
                count: 3,
                linearSpacing: 15.0,
                linearDirection: SIMD3<Double>(0, 0, 1)
            )),
            outputSolidId: ObjectId("hole-solid")
        )
        let source = ComponentInstance(
            name: "Pin",
            reference: .internalPart(name: "PinPart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 5))
        )
        let doc = DocumentModel(
            features: [driverPatternFeat],
            documentType: .assembly,
            componentInstances: [source]
        )

        let result = doc.patternComponentInstanceByFeaturePattern(
            instanceId: source.id,
            featurePatternId: driverPatternFeat.id
        )
        guard case .success(let pattern) = result else {
            Issue.record("Expected successful feature-driven pattern creation")
            return
        }

        #expect(pattern.params.patternType == .featureDriven)
        #expect(pattern.params.featurePatternId == driverPatternFeat.id)
        #expect(pattern.replicaInstanceIds.count == 2)
        #expect(doc.componentInstances.count == 3)

        let rep1 = doc.componentInstances.first(where: { $0.name == "Pin (Pattern 2)" })
        #expect(rep1 != nil)
        #expect(abs(rep1!.transform.position.z - 20.0) < 1e-4) // 5 + 15

        let rep2 = doc.componentInstances.first(where: { $0.name == "Pin (Pattern 3)" })
        #expect(rep2 != nil)
        #expect(abs(rep2!.transform.position.z - 35.0) < 1e-4) // 5 + 30
    }

    @Test func testComponentMirrorSymmetricReorient() {
        let doc = DocumentModel(documentType: .assembly)
        let source = ComponentInstance(
            name: "Wing Left",
            reference: .internalPart(name: "WingPart"),
            transform: Transform(position: SIMD3<Float>(15, 25, 35)),
            isGrounded: true
        )
        _ = doc.addComponentInstance(source)

        // Mirror across YZ plane (normal X = 1, origin = (0, 0, 0))
        let params = AssemblyMirrorParams(
            sourceInstanceId: source.id,
            planeNormal: SIMD3<Float>(1, 0, 0),
            planeOrigin: .zero,
            keepOriginal: true,
            mirrorMode: .symmetricReorient
        )
        let result = doc.mirrorComponentInstance(params: params)
        guard case .success(let mirror) = result else {
            Issue.record("Expected successful mirror creation")
            return
        }

        #expect(doc.componentMirrors.count == 1)
        #expect(mirror.replicaInstanceIds.count == 1)
        #expect(doc.componentInstances.count == 2)

        let replica = doc.componentInstances.first(where: { $0.id == mirror.replicaInstanceIds.first })
        #expect(replica != nil)
        #expect(replica?.name == "Wing Left (Mirrored)")
        #expect(replica?.mirrorId == mirror.id)
        #expect(!replica!.isGrounded)

        // Reflected position: X becomes -15, Y and Z unchanged
        #expect(abs(replica!.transform.position.x - (-15.0)) < 1e-4)
        #expect(abs(replica!.transform.position.y - 25.0) < 1e-4)
        #expect(abs(replica!.transform.position.z - 35.0) < 1e-4)
        #expect(replica!.transform.scale == SIMD3<Float>(1, 1, 1))
    }

    @Test func testComponentMirrorOppositeHandAndKeepOriginalFalse() {
        let doc = DocumentModel(documentType: .assembly)
        let source = ComponentInstance(
            name: "Glove Left",
            reference: .internalPart(name: "GlovePart"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0))
        )
        _ = doc.addComponentInstance(source)

        let params = AssemblyMirrorParams(
            sourceInstanceId: source.id,
            planeNormal: SIMD3<Float>(1, 0, 0),
            planeOrigin: .zero,
            keepOriginal: false,
            mirrorMode: .oppositeHand
        )
        let result = doc.mirrorComponentInstance(params: params)
        guard case .success(let mirror) = result else {
            Issue.record("Expected successful opposite-hand mirror")
            return
        }

        let replica = doc.componentInstances.first(where: { $0.id == mirror.replicaInstanceIds.first })
        #expect(replica != nil)
        #expect(abs(replica!.transform.position.x - (-10.0)) < 1e-4)
        #expect(replica!.transform.scale.z < 0) // inverted local Z for opposite hand

        // Source component should be hidden when keepOriginal is false
        let updatedSource = doc.componentInstances.first(where: { $0.id == source.id })
        #expect(updatedSource?.isVisible == false)
    }

    @Test func testComponentMirrorZeroNormalValidation() {
        let doc = DocumentModel(documentType: .assembly)
        let source = ComponentInstance(name: "Cube", reference: .internalPart(name: "CubePart"))
        _ = doc.addComponentInstance(source)

        let params = AssemblyMirrorParams(
            sourceInstanceId: source.id,
            planeNormal: SIMD3<Float>(0, 0, 0)
        )
        let result = doc.mirrorComponentInstance(params: params)
        guard case .failure(let err) = result else {
            Issue.record("Expected failure on zero-length normal")
            return
        }
        if case .invalidOperation(let msg) = err {
            #expect(msg.contains("zero-length"))
        } else {
            Issue.record("Unexpected error type: \(err)")
        }
    }

    @Test func testPatternAndMirrorInSubassemblyHierarchy() {
        let doc = DocumentModel(documentType: .assembly)
        let child = ComponentInstance(
            name: "SubChild",
            reference: .internalPart(name: "ChildPart"),
            transform: Transform(position: SIMD3<Float>(5, 0, 0))
        )
        let sub = ComponentInstance(
            name: "EngineAssembly",
            reference: .subassembly(name: "Engine"),
            transform: Transform(position: SIMD3<Float>(100, 0, 0)),
            childInstances: [child]
        )
        _ = doc.addComponentInstance(sub)

        #expect(doc.componentInstances.count == 1)
        #expect(doc.componentInstances.first?.childInstances.count == 1)

        // Pattern the child component inside the subassembly
        let patParams = AssemblyPatternParams(
            sourceInstanceId: child.id,
            patternType: .linear,
            count: 3,
            linearSpacing: 10.0,
            linearDirection: SIMD3<Float>(1, 0, 0)
        )
        let patResult = doc.patternComponentInstance(params: patParams)
        guard case .success(let pattern) = patResult else {
            Issue.record("Failed to pattern child in subassembly")
            return
        }

        // Child replicas should be inside subassembly childInstances
        let updatedSub = doc.componentInstances.first(where: { $0.id == sub.id })
        #expect(updatedSub != nil)
        #expect(updatedSub?.childInstances.count == 3)
        #expect(pattern.replicaInstanceIds.count == 2)

        // Mirror the child component inside the subassembly
        let mirParams = AssemblyMirrorParams(
            sourceInstanceId: child.id,
            planeNormal: SIMD3<Float>(1, 0, 0),
            planeOrigin: .zero
        )
        let mirResult = doc.mirrorComponentInstance(params: mirParams)
        guard case .success = mirResult else {
            Issue.record("Failed to mirror child in subassembly")
            return
        }

        let updatedSubAfterMirror = doc.componentInstances.first(where: { $0.id == sub.id })
        #expect(updatedSubAfterMirror?.childInstances.count == 4)
    }

    @Test func testComponentPatternMultiStepUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let source = ComponentInstance(
            name: "Stanchion",
            reference: .internalPart(name: "StanchionPart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        _ = doc.addComponentInstance(source)
        undoManager.removeAllActions()

        let params = AssemblyPatternParams(
            sourceInstanceId: source.id,
            patternType: .linear,
            count: 3,
            linearSpacing: 15.0,
            linearDirection: SIMD3<Float>(1, 0, 0)
        )
        let result = doc.patternComponentInstance(params: params)
        guard case .success(let pattern) = result else {
            Issue.record("Expected successful pattern")
            return
        }

        #expect(doc.componentInstances.count == 3)
        #expect(doc.componentPatterns.count == 1)

        // Undo pattern creation
        undoManager.undo()
        #expect(doc.componentInstances.count == 1)
        #expect(doc.componentPatterns.isEmpty)

        // Redo pattern creation
        undoManager.redo()
        #expect(doc.componentInstances.count == 3)
        #expect(doc.componentPatterns.count == 1)
        #expect(doc.componentPatterns.first?.id == pattern.id)

        // Undo again
        undoManager.undo()
        #expect(doc.componentInstances.count == 1)
        #expect(doc.componentPatterns.isEmpty)
    }

    @Test func testComponentMirrorMultiStepUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let source = ComponentInstance(
            name: "Arm",
            reference: .internalPart(name: "ArmPart"),
            transform: Transform(position: SIMD3<Float>(20, 10, 0))
        )
        _ = doc.addComponentInstance(source)
        undoManager.removeAllActions()

        let params = AssemblyMirrorParams(
            sourceInstanceId: source.id,
            planeNormal: SIMD3<Float>(1, 0, 0),
            planeOrigin: .zero,
            keepOriginal: true
        )
        let result = doc.mirrorComponentInstance(params: params)
        guard case .success(let mirror) = result else {
            Issue.record("Expected successful mirror")
            return
        }

        #expect(doc.componentInstances.count == 2)
        #expect(doc.componentMirrors.count == 1)

        // Undo mirror
        undoManager.undo()
        #expect(doc.componentInstances.count == 1)
        #expect(doc.componentMirrors.isEmpty)

        // Redo mirror
        undoManager.redo()
        #expect(doc.componentInstances.count == 2)
        #expect(doc.componentMirrors.count == 1)
        #expect(doc.componentMirrors.first?.id == mirror.id)

        // Remove mirror explicitly
        let removeResult = doc.removeComponentMirror(id: mirror.id)
        guard case .success = removeResult else {
            Issue.record("Failed to remove mirror")
            return
        }
        #expect(doc.componentInstances.count == 1)
        #expect(doc.componentMirrors.isEmpty)

        // Undo removal restores mirror
        undoManager.undo()
        #expect(doc.componentInstances.count == 2)
        #expect(doc.componentMirrors.count == 1)
    }

    // MARK: - Exploded Views (BL-ASM-12)

    @Test func testExplodedViewLifecycleAndUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        // Add exploded view
        let addRes = doc.addExplodedView(name: "Default Exploded")
        guard case .success(let view) = addRes else {
            Issue.record("Failed to add exploded view")
            return
        }
        #expect(doc.explodedViews.count == 1)
        #expect(doc.explodedViews.first?.name == "Default Exploded")
        undoManager.removeAllActions()

        // Rename
        let renameRes = doc.renameExplodedView(id: view.id, name: "Disassembly View")
        guard case .success = renameRes else {
            Issue.record("Failed to rename exploded view")
            return
        }
        #expect(doc.explodedViews.first?.name == "Disassembly View")

        // Undo rename
        undoManager.undo()
        #expect(doc.explodedViews.first?.name == "Default Exploded")

        // Redo rename
        undoManager.redo()
        #expect(doc.explodedViews.first?.name == "Disassembly View")
        undoManager.removeAllActions()

        // Remove
        let removeRes = doc.removeExplodedView(id: view.id)
        guard case .success = removeRes else {
            Issue.record("Failed to remove exploded view")
            return
        }
        #expect(doc.explodedViews.isEmpty)

        // Undo removal
        undoManager.undo()
        #expect(doc.explodedViews.count == 1)
        #expect(doc.explodedViews.first?.id == view.id)

        // Redo removal
        undoManager.redo()
        #expect(doc.explodedViews.isEmpty)
    }

    @Test func testExplodedViewActiveAndCollapsedSceneObjectTransforms() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let comp = ComponentInstance(
            name: "Shaft",
            reference: .internalPart(name: "ShaftPart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        _ = doc.addComponentInstance(comp)

        let step = ExplodeStep(
            name: "Pull Out",
            targetInstanceIds: [comp.id],
            direction: SIMD3<Float>(0, 0, 1),
            distance: 80.0
        )
        let view = ExplodedView(name: "Assembly Explode", steps: [step], isCollapsed: false)
        _ = doc.addExplodedView(view)

        // Initial unexploded state: scene object is at (0, 0, 0)
        let initialObj = doc.objects.first(where: { $0.id == comp.solidId })
        #expect(initialObj?.transform.position == SIMD3<Float>(0, 0, 0))

        // Activate exploded view
        _ = doc.setActiveExplodedView(id: view.id)
        #expect(doc.activeExplodedViewId == view.id)
        let explodedObj = doc.objects.first(where: { $0.id == comp.solidId })
        #expect(explodedObj?.transform.position == SIMD3<Float>(0, 0, 80))

        // Toggle collapsed
        _ = doc.toggleExplodedViewCollapsed(id: view.id)
        #expect(doc.explodedView(id: view.id)?.isCollapsed == true)
        let collapsedObj = doc.objects.first(where: { $0.id == comp.solidId })
        #expect(collapsedObj?.transform.position == SIMD3<Float>(0, 0, 0))

        // Toggle expanded
        _ = doc.toggleExplodedViewCollapsed(id: view.id)
        #expect(doc.explodedView(id: view.id)?.isCollapsed == false)
        let reExpandedObj = doc.objects.first(where: { $0.id == comp.solidId })
        #expect(reExpandedObj?.transform.position == SIMD3<Float>(0, 0, 80))

        // Deactivate
        undoManager.removeAllActions()
        _ = doc.setActiveExplodedView(id: nil)
        #expect(doc.activeExplodedViewId == nil)
        let deactivatedObj = doc.objects.first(where: { $0.id == comp.solidId })
        #expect(deactivatedObj?.transform.position == SIMD3<Float>(0, 0, 0))

        // Undo deactivation
        undoManager.undo()
        #expect(doc.activeExplodedViewId == view.id)
        #expect(doc.objects.first(where: { $0.id == comp.solidId })?.transform.position == SIMD3<Float>(0, 0, 80))
    }

    @Test func testExplodeStepMutationsAndUndoRedo() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let addViewRes = doc.addExplodedView(name: "Test View")
        guard case .success(let view) = addViewRes else {
            Issue.record("Failed to create view")
            return
        }

        let step1 = ExplodeStep(name: "Step 1", distance: 10.0)
        let step2 = ExplodeStep(name: "Step 2", distance: 20.0)

        // Add step1
        let addStep1Res = doc.addExplodeStep(viewId: view.id, step: step1)
        guard case .success = addStep1Res else {
            Issue.record("Failed to add step1")
            return
        }
        #expect(doc.explodedView(id: view.id)?.steps.count == 1)

        // Add step2
        _ = doc.addExplodeStep(viewId: view.id, step: step2)
        #expect(doc.explodedView(id: view.id)?.steps.count == 2)
        undoManager.removeAllActions()

        // Update step1 distance
        var updatedStep1 = step1
        updatedStep1.distance = 50.0
        let updateRes = doc.updateExplodeStep(viewId: view.id, step: updatedStep1)
        guard case .success = updateRes else {
            Issue.record("Failed to update step1")
            return
        }
        #expect(doc.explodedView(id: view.id)?.steps.first?.distance == 50.0)

        // Undo update
        undoManager.undo()
        #expect(doc.explodedView(id: view.id)?.steps.first?.distance == 10.0)

        // Redo update
        undoManager.redo()
        #expect(doc.explodedView(id: view.id)?.steps.first?.distance == 50.0)
        undoManager.removeAllActions()

        // Reorder steps
        let reorderRes = doc.reorderExplodeSteps(viewId: view.id, stepIds: [step2.id, step1.id])
        guard case .success = reorderRes else {
            Issue.record("Failed to reorder steps")
            return
        }
        #expect(doc.explodedView(id: view.id)?.steps.map(\.id) == [step2.id, step1.id])

        // Undo reorder
        undoManager.undo()
        #expect(doc.explodedView(id: view.id)?.steps.map(\.id) == [step1.id, step2.id])

        // Redo reorder
        undoManager.redo()
        #expect(doc.explodedView(id: view.id)?.steps.map(\.id) == [step2.id, step1.id])
        undoManager.removeAllActions()

        // Remove step2
        let removeStepRes = doc.removeExplodeStep(viewId: view.id, stepId: step2.id)
        guard case .success = removeStepRes else {
            Issue.record("Failed to remove step2")
            return
        }
        #expect(doc.explodedView(id: view.id)?.steps.count == 1)

        // Undo remove step2
        undoManager.undo()
        #expect(doc.explodedView(id: view.id)?.steps.count == 2)
    }

    @Test func testPruningDeletedComponentFromExplodeSteps() {
        let doc = DocumentModel(documentType: .assembly)
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let comp1 = ComponentInstance(name: "Pin 1", reference: .internalPart(name: "PinPart"))
        let comp2 = ComponentInstance(name: "Pin 2", reference: .internalPart(name: "PinPart"))
        _ = doc.addComponentInstance(comp1)
        _ = doc.addComponentInstance(comp2)

        let step = ExplodeStep(
            name: "Extract Pins",
            targetInstanceIds: [comp1.id, comp2.id],
            distance: 30.0
        )
        let view = ExplodedView(steps: [step])
        _ = doc.addExplodedView(view)

        #expect(doc.explodedView(id: view.id)?.steps.first?.targetInstanceIds.count == 2)
        undoManager.removeAllActions()

        // Remove comp1
        let removeRes = doc.removeComponentInstance(id: comp1.id)
        guard case .success = removeRes else {
            Issue.record("Failed to remove component")
            return
        }

        // comp1.id should be pruned from step
        let prunedStep = doc.explodedView(id: view.id)?.steps.first
        #expect(prunedStep?.targetInstanceIds == [comp2.id])

        // Undo component removal should restore comp1 into step targets
        undoManager.undo()
        let restoredStep = doc.explodedView(id: view.id)?.steps.first
        #expect(restoredStep?.targetInstanceIds.contains(comp1.id) == true)
        #expect(restoredStep?.targetInstanceIds.contains(comp2.id) == true)
    }

    @Test func testDrawingQueryAccessors() {
        let doc = DocumentModel(documentType: .assembly)
        let comp = ComponentInstance(
            name: "Bracket",
            reference: .internalPart(name: "BracketPart"),
            transform: Transform(position: SIMD3<Float>(10, 20, 30))
        )
        _ = doc.addComponentInstance(comp)

        let step = ExplodeStep(
            name: "Pull Forward",
            targetInstanceIds: [comp.id],
            direction: SIMD3<Float>(0, 1, 0),
            distance: 50.0,
            hasTrail: true
        )
        let view = ExplodedView(steps: [step], isCollapsed: false)
        _ = doc.addExplodedView(view)

        // Query when no view is active
        #expect(doc.effectiveTransform(for: comp.id)?.position == SIMD3<Float>(10, 20, 30))

        // Query specific view
        let specificTransform = doc.effectiveTransform(for: comp.id, in: view.id)
        #expect(specificTransform?.position == SIMD3<Float>(10, 70, 30))

        // Query when active
        _ = doc.setActiveExplodedView(id: view.id)
        #expect(doc.effectiveTransform(for: comp.id)?.position == SIMD3<Float>(10, 70, 30))

        // Trails query
        let trails = doc.computeTrails(for: view.id)
        #expect(trails.count == 1)
        #expect(trails.first?.startPoint == SIMD3<Float>(10, 20, 30))
        #expect(trails.first?.endPoint == SIMD3<Float>(10, 70, 30))
    }
}

