import Testing
import Foundation
import SwiftUI
import simd
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct AssemblyAppTests {

    @Test func testNewAssemblyShortcutConstants() {
        #expect(WorkspaceModel.newAssemblyShortcutKey == "n")
        #expect(WorkspaceModel.newAssemblyShortcutModifiers == [.option, .command])
    }

    @Test func testNewAssemblyDocumentInWorkspace() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        #expect(ws.document.documentType == .assembly)
        #expect(ws.document.componentInstances.isEmpty)
        #expect(ws.document.objects.isEmpty)
        #expect(!ws.isDocumentModified)
        #expect(ws.currentDocumentURL == nil)
    }

    @Test func testComponentInstanceOperationsInWorkspace() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let instance = ws.addComponentInstance(
            name: "Bracket Left",
            reference: .internalPart(name: "BracketPart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )

        #expect(ws.document.componentInstances.count == 1)
        #expect(ws.isDocumentModified)
        #expect(ws.selectedId == instance.solidId)
        ws.document.undoManager?.removeAllActions()

        let targetTransform = Transform(
            position: SIMD3<Float>(50, 100, 150),
            rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(0, 90, 0)),
            scale: SIMD3<Float>(1, 1, 1)
        )
        let updated = ws.updateComponentInstanceTransform(id: instance.id, transform: targetTransform)
        #expect(updated)
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(50, 100, 150))

        ws.undo()
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(0, 0, 0))

        ws.redo()
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(50, 100, 150))

        ws.setComponentInstanceName(id: instance.id, name: "Bracket Front")
        #expect(ws.document.componentInstances.first?.name == "Bracket Front")
        ws.document.undoManager?.removeAllActions()

        let removed = ws.removeComponentInstance(id: instance.id)
        #expect(removed)
        #expect(ws.document.componentInstances.isEmpty)
        #expect(ws.selectedId == nil)

        ws.undo()
        #expect(ws.document.componentInstances.count == 1)
        #expect(ws.document.componentInstances.first?.name == "Bracket Front")
    }

    @Test func testSaveAndOpenAssemblyPackageInWorkspace() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AssemblyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("MechanicalAssembly.made")

        let ws1 = WorkspaceModel()
        ws1.newAssemblyDocument()

        _ = ws1.addComponentInstance(
            name: "Pinion",
            reference: .internalPart(name: "PinionPart"),
            transform: Transform(position: SIMD3<Float>(10, 20, 30))
        )
        _ = ws1.addComponentInstance(
            name: "Spur",
            reference: .externalDocument(url: URL(fileURLWithPath: "/models/spur.made")),
            transform: Transform(position: SIMD3<Float>(40, 50, 60))
        )

        let saved = ws1.saveDocument(to: packageURL)
        #expect(saved)
        #expect(!ws1.isDocumentModified)
        #expect(FileManager.default.fileExists(atPath: packageURL.path))

        let ws2 = WorkspaceModel()
        let opened = ws2.openDocument(at: packageURL)
        #expect(opened)
        #expect(ws2.document.documentType == .assembly)
        #expect(ws2.document.componentInstances.count == 2)

        let pinion = ws2.document.componentInstances.first(where: { $0.name == "Pinion" })
        #expect(pinion != nil)
        #expect(pinion?.transform.position == SIMD3<Float>(10, 20, 30))

        let spur = ws2.document.componentInstances.first(where: { $0.name == "Spur" })
        #expect(spur != nil)
        #expect(spur?.transform.position == SIMD3<Float>(40, 50, 60))
    }

    @Test func testBeginAndCancelPendingPlacement() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()
        let initialModified = ws.isDocumentModified

        ws.beginInsertComponent(
            name: "Gear",
            reference: .externalDocument(url: URL(fileURLWithPath: "/models/gear.step"))
        )

        #expect(ws.pendingComponentPlacement != nil)
        #expect(ws.pendingComponentPlacement?.name == "Gear")
        #expect(ws.isDocumentModified == initialModified)

        ws.cancelPendingPlacement()

        #expect(ws.pendingComponentPlacement == nil)
        #expect(ws.document.componentInstances.isEmpty)
        #expect(ws.isDocumentModified == initialModified)
        #expect(!ws.canUndo)
    }

    @Test func testPlacePendingComponentAtPositionAndUndoRedo() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        ws.beginInsertComponent(
            name: "Mount",
            reference: .internalPart(name: "MountBody", bodyId: SolidId("part-1"))
        )

        let placed = ws.placePendingComponent(at: SIMD3<Float>(15, 25, 0))

        #expect(placed != nil)
        #expect(ws.pendingComponentPlacement == nil)
        #expect(ws.document.componentInstances.count == 1)
        #expect(ws.document.componentInstances.first?.name == "Mount")
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(15, 25, 0))
        #expect(ws.selectedId == placed?.solidId)
        #expect(ws.canUndo)

        ws.undo()
        #expect(ws.document.componentInstances.isEmpty)

        ws.redo()
        #expect(ws.document.componentInstances.count == 1)
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(15, 25, 0))
    }

    @Test func testPlacePendingComponentWithoutPendingReturnsNil() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let placed = ws.placePendingComponent(at: SIMD3<Float>(10, 20, 30))
        #expect(placed == nil)
        #expect(ws.document.componentInstances.isEmpty)
    }

    @Test func testPromptInsertComponentFromDocument_EmptyBodies() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()
        #expect(ws.document.bodies.isEmpty)

        ws.promptInsertComponentFromDocument()

        #expect(ws.pendingComponentPlacement == nil)
        #expect(!ws.isShowingBodyPickerForInsertion)
    }

    @Test func testPromptInsertComponentFromDocument_SingleBody() {
        let ws = WorkspaceModel()
        ws.document.reset(with: [
            Feature.makeBox(solidId: SolidId("single-box"), params: BoxParams(width: 20, depth: 20, height: 20))
        ])
        #expect(ws.document.bodies.count == 1)

        let body = ws.document.bodies[0]
        ws.promptInsertComponentFromDocument()

        #expect(ws.pendingComponentPlacement != nil)
        #expect(ws.pendingComponentPlacement?.name == body.name)
        #expect(ws.pendingComponentPlacement?.reference == .internalPart(name: body.name, bodyId: body.id))
        #expect(!ws.isShowingBodyPickerForInsertion)
    }

    @Test func testPromptInsertComponentFromDocument_MultipleBodies() {
        let ws = WorkspaceModel()
        ws.document.reset(with: [
            Feature.makeBox(solidId: SolidId("box-1"), params: BoxParams(width: 20, depth: 20, height: 20)),
            Feature.makeCylinder(solidId: SolidId("cyl-1"), params: CylinderParams(radius: 10, height: 30))
        ])
        #expect(ws.document.bodies.count == 2)

        ws.promptInsertComponentFromDocument()

        #expect(ws.isShowingBodyPickerForInsertion)
        #expect(ws.pendingComponentPlacement == nil)

        let targetBody = ws.document.bodies[1]
        ws.insertComponentFromInternalBody(targetBody)

        #expect(!ws.isShowingBodyPickerForInsertion)
        #expect(ws.pendingComponentPlacement != nil)
        #expect(ws.pendingComponentPlacement?.name == targetBody.name)
        #expect(ws.pendingComponentPlacement?.reference == .internalPart(name: targetBody.name, bodyId: targetBody.id))
    }

    @Test func testInsertMultipleInstancesOfSamePartPreservesUniqueIDsAndTransforms() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let ref = ComponentReference.internalPart(name: "Bracket", bodyId: SolidId("bracket-part"))

        ws.beginInsertComponent(name: "Bracket 1", reference: ref)
        let inst1 = ws.placePendingComponent(at: SIMD3<Float>(0, 0, 0))

        ws.beginInsertComponent(name: "Bracket 2", reference: ref)
        let inst2 = ws.placePendingComponent(at: SIMD3<Float>(50, 100, 0))

        #expect(inst1 != nil)
        #expect(inst2 != nil)
        guard let inst1, let inst2 else { return }

        #expect(inst1.id != inst2.id)
        #expect(inst1.solidId != inst2.solidId)
        #expect(inst1.transform.position == SIMD3<Float>(0, 0, 0))
        #expect(inst2.transform.position == SIMD3<Float>(50, 100, 0))
        #expect(ws.document.componentInstances.count == 2)
    }

    @Test func testFirstPlacedComponentGroundedByDefaultAndSubsequentFloat() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let ref = ComponentReference.internalPart(name: "BasePart")

        ws.beginInsertComponent(name: "Base", reference: ref)
        let first = ws.placePendingComponent(at: SIMD3<Float>(0, 0, 0))
        #expect(first != nil)
        #expect(first?.isGrounded == true)
        #expect(ws.document.componentInstances.first?.isGrounded == true)

        ws.beginInsertComponent(name: "Arm", reference: ref)
        let second = ws.placePendingComponent(at: SIMD3<Float>(10, 20, 0))
        #expect(second != nil)
        #expect(second?.isGrounded == false)
        #expect(ws.document.componentInstances.last?.isGrounded == false)
    }

    @Test func testWorkspaceGroundAndFloatOperations() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let ref = ComponentReference.internalPart(name: "ChassisPart")
        ws.beginInsertComponent(name: "Chassis", reference: ref)
        let first = ws.placePendingComponent(at: SIMD3<Float>(0, 0, 0))
        guard let first else {
            Issue.record("Failed to place component")
            return
        }

        #expect(first.isGrounded == true)

        let moveGrounded = ws.updateComponentInstanceTransform(id: first.id, transform: Transform(position: SIMD3<Float>(5, 5, 5)))
        #expect(!moveGrounded)
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(0, 0, 0))

        let toggled = ws.toggleComponentInstanceGrounded(id: first.id)
        #expect(toggled)
        #expect(ws.document.componentInstances.first?.isGrounded == false)

        let moveFloated = ws.updateComponentInstanceTransform(id: first.id, transform: Transform(position: SIMD3<Float>(5, 5, 5)))
        #expect(moveFloated)
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(5, 5, 5))

        ws.document.undoManager?.removeAllActions()

        let groundedAgain = ws.setComponentInstanceGrounded(id: first.id, isGrounded: true)
        #expect(groundedAgain)
        #expect(ws.document.componentInstances.first?.isGrounded == true)

        ws.undo()
        #expect(ws.document.componentInstances.first?.isGrounded == false)

        ws.redo()
        #expect(ws.document.componentInstances.first?.isGrounded == true)
    }

    @Test func testPackageSaveAndReopenPreservesGroundedState() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("GroundedAssemblyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("GroundedAssembly.made")

        let ws1 = WorkspaceModel()
        ws1.newAssemblyDocument()

        _ = ws1.addComponentInstance(
            name: "Anchor",
            reference: .internalPart(name: "AnchorPart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0)),
            isGrounded: true
        )
        _ = ws1.addComponentInstance(
            name: "FloatingLink",
            reference: .internalPart(name: "LinkPart"),
            transform: Transform(position: SIMD3<Float>(20, 0, 0)),
            isGrounded: false
        )

        let saved = ws1.saveDocument(to: packageURL)
        #expect(saved)

        let ws2 = WorkspaceModel()
        let opened = ws2.openDocument(at: packageURL)
        #expect(opened)
        #expect(ws2.document.componentInstances.count == 2)

        let anchor = ws2.document.componentInstances.first(where: { $0.name == "Anchor" })
        #expect(anchor?.isGrounded == true)
        #expect(anchor?.isFixed == true)

        let link = ws2.document.componentInstances.first(where: { $0.name == "FloatingLink" })
        #expect(link?.isGrounded == false)
        #expect(link?.isFixed == false)
    }

    @Test func testWorkspaceAssemblyShortcuts() {
        #expect(WorkspaceModel.solveAssemblyShortcutKey == "s")
        #expect(WorkspaceModel.solveAssemblyShortcutModifiers == [.option, .command])
    }

    @Test func testWorkspaceAssemblyConstraintMutatorsAndSolve() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let base = ws.addComponentInstance(
            name: "Base",
            reference: .internalPart(name: "BasePart"),
            transform: .identity
        )
        let arm = ws.addComponentInstance(
            name: "Arm",
            reference: .internalPart(name: "ArmPart"),
            transform: Transform(position: SIMD3<Float>(10, 20, 30))
        )
        _ = ws.setComponentInstanceGrounded(id: base.id, isGrounded: true)
        _ = ws.setComponentInstanceGrounded(id: arm.id, isGrounded: false)

        // Add revolute joint via workspace helper
        let joint = ws.addDefaultAssemblyConstraint(kind: .revolute)
        #expect(joint != nil)
        #expect(ws.document.assemblyConstraints.count == 1)
        #expect(ws.selectedAssemblyConstraintId == joint?.id)
        #expect(ws.selectedAssemblyConstraint?.kind == .revolute)

        // Clear selection and select by ID
        ws.selectAssemblyConstraint(nil)
        #expect(ws.selectedAssemblyConstraintId == nil)
        ws.selectAssemblyConstraint(joint?.id)
        #expect(ws.selectedAssemblyConstraintId == joint?.id)

        // Suppress and unsuppress
        guard let jointId = joint?.id else {
            Issue.record("Missing joint ID")
            return
        }

        let toggled = ws.toggleAssemblyConstraintSuppressed(id: jointId)
        #expect(toggled)
        #expect(ws.document.assemblyConstraints.first?.isSuppressed == true)

        let toggledBack = ws.toggleAssemblyConstraintSuppressed(id: jointId)
        #expect(toggledBack)
        #expect(ws.document.assemblyConstraints.first?.isSuppressed == false)

        // Solve assembly
        let solveResult = ws.solveAssemblyConstraints()
        #expect(solveResult.status.isConverged)

        // Update joint
        if var current = ws.selectedAssemblyConstraint {
            current.name = "Custom Hinge"
            current.value = 45.0
            let updated = ws.updateAssemblyConstraint(current)
            #expect(updated)
            #expect(ws.document.assemblyConstraints.first?.name == "Custom Hinge")
            #expect(ws.document.assemblyConstraints.first?.value == 45.0)
        }

        // Remove joint
        ws.document.undoManager?.removeAllActions()
        let removed = ws.removeAssemblyConstraint(id: jointId)
        #expect(removed)
        #expect(ws.document.assemblyConstraints.isEmpty)
        #expect(ws.selectedAssemblyConstraintId == nil)

        // Undo removal
        ws.undo()
        #expect(ws.document.assemblyConstraints.count == 1)
        #expect(ws.document.assemblyConstraints.first?.id == jointId)

        // Redo removal
        ws.redo()
        #expect(ws.document.assemblyConstraints.isEmpty)
    }

    @Test func testWorkspaceRemainingAssemblyDOFAndGroundedStatus() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        // Empty assembly has 0 total DOF
        #expect(ws.totalAssemblyDOF == 0)

        let base = ws.addComponentInstance(
            name: "Base",
            reference: .internalPart(name: "BasePart"),
            transform: .identity,
            isGrounded: true
        )
        // Base component is grounded
        #expect(base.isGrounded)
        #expect(ws.remainingAssemblyDOF(for: base.id) == 0)
        #expect(ws.totalAssemblyDOF == 0)

        // Add a second, floating component
        let arm = ws.addComponentInstance(
            name: "Arm",
            reference: .internalPart(name: "ArmPart"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0))
        )
        #expect(!arm.isGrounded)
        // Free component with no mates has 6 DOF
        #expect(ws.remainingAssemblyDOF(for: arm.id) == 6)
        #expect(ws.totalAssemblyDOF == 6)

        // Add a revolute joint between Base and Arm
        let joint = ws.addDefaultAssemblyConstraint(kind: .revolute)
        #expect(joint != nil)

        // Solve assembly; revolute joint leaves 1 free rotational DOF
        let solveResult = ws.solveAssemblyConstraints()
        #expect(solveResult.status.isConverged)
        #expect(ws.lastAssemblySolverResult != nil)
        #expect(ws.remainingAssemblyDOF(for: base.id) == 0)
        #expect(ws.remainingAssemblyDOF(for: arm.id) == 1)
        #expect(ws.totalAssemblyDOF == 1)

        // Float base -> both are free, diagnostics invalidated
        _ = ws.setComponentInstanceGrounded(id: base.id, isGrounded: false)
        #expect(ws.lastAssemblySolverResult == nil)
        #expect(ws.remainingAssemblyDOF(for: base.id) > 0)
    }

    @Test func testWorkspaceAssemblySolverConflictDiagnosis() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let base = ws.addComponentInstance(
            name: "Base",
            reference: .internalPart(name: "BasePart"),
            transform: .identity
        )
        let block = ws.addComponentInstance(
            name: "Block",
            reference: .internalPart(name: "BlockPart"),
            transform: Transform(position: SIMD3<Float>(5, 0, 0))
        )
        _ = ws.setComponentInstanceGrounded(id: base.id, isGrounded: true)
        _ = ws.setComponentInstanceGrounded(id: block.id, isGrounded: false)

        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero)
        let fBlock = AssemblyFeature(componentInstanceId: block.id, origin: .zero)

        // Two conflicting distance constraints: distance = 10 vs distance = 30
        let mate1 = AssemblyConstraint(kind: .distance, firstFeature: fBase, secondFeature: fBlock, value: 10.0)
        let mate2 = AssemblyConstraint(kind: .distance, firstFeature: fBase, secondFeature: fBlock, value: 30.0)

        #expect(ws.addAssemblyConstraint(mate1))
        #expect(ws.addAssemblyConstraint(mate2))

        let solveResult = ws.solveAssemblyConstraints()
        #expect(!solveResult.status.isConverged)
        #expect(solveResult.status.isOverConstrained)
        #expect(!solveResult.status.isRedundant)
        #expect(ws.lastAssemblySolverResult?.status.isOverConstrained == true)
        #expect(!ws.conflictingAssemblyConstraintIds.isEmpty)
        #expect(ws.isAssemblyConstraintConflicting(mate1.id) || ws.isAssemblyConstraintConflicting(mate2.id))
        #expect(!ws.isAssemblyConstraintRedundant(mate1.id))

        // Check summaryText
        #expect(solveResult.status.summaryText.contains("Over-constrained"))

        // Removing the conflicting mate clears the solver diagnostic
        #expect(ws.removeAssemblyConstraint(id: mate2.id))
        #expect(ws.lastAssemblySolverResult == nil)
        #expect(ws.conflictingAssemblyConstraintIds.isEmpty)
        #expect(!ws.isAssemblyConstraintConflicting(mate1.id))

        // Re-solve converges cleanly
        let reSolve = ws.solveAssemblyConstraints()
        #expect(reSolve.status.isConverged)
        #expect(ws.conflictingAssemblyConstraintIds.isEmpty)
    }

    @Test func testWorkspaceAssemblySolverRedundantDiagnosis() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let base = ws.addComponentInstance(
            name: "Base",
            reference: .internalPart(name: "BasePart"),
            transform: .identity
        )
        let arm = ws.addComponentInstance(
            name: "Arm",
            reference: .internalPart(name: "ArmPart"),
            transform: Transform(position: SIMD3<Float>(5, 0, 0))
        )
        _ = ws.setComponentInstanceGrounded(id: base.id, isGrounded: true)
        _ = ws.setComponentInstanceGrounded(id: arm.id, isGrounded: false)

        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fArm = AssemblyFeature(componentInstanceId: arm.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))

        // Two identical parallel mates
        let mate1 = AssemblyConstraint(kind: .parallel, firstFeature: fBase, secondFeature: fArm)
        let mate2 = AssemblyConstraint(kind: .parallel, firstFeature: fBase, secondFeature: fArm)

        #expect(ws.addAssemblyConstraint(mate1))
        #expect(ws.addAssemblyConstraint(mate2))

        let solveResult = ws.solveAssemblyConstraints()
        #expect(solveResult.status.isConverged)
        #expect(solveResult.status.isRedundant)
        #expect(!solveResult.status.isOverConstrained)
        #expect(ws.lastAssemblySolverResult?.status.isRedundant == true)
        #expect(!ws.redundantAssemblyConstraintIds.isEmpty)
        #expect(ws.isAssemblyConstraintRedundant(mate1.id) || ws.isAssemblyConstraintRedundant(mate2.id))
        #expect(!ws.isAssemblyConstraintConflicting(mate1.id))

        // Check summaryText
        #expect(solveResult.status.summaryText.contains("Redundant"))

        // Modifying the redundant mate clears solver diagnostics
        var updatedMate2 = mate2
        updatedMate2.name = "Modified Parallel"
        #expect(ws.updateAssemblyConstraint(updatedMate2))
        #expect(ws.lastAssemblySolverResult == nil)
        #expect(ws.redundantAssemblyConstraintIds.isEmpty)
    }

    // MARK: - Workspace Interactive Assembly Drag (BL-ASM-06)

    @Test func testWorkspaceInteractiveAssemblyDragLifecycle() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let base = ws.addComponentInstance(
            name: "Base",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        #expect(ws.document.componentInstances.first?.isGrounded == true)

        let slider = ws.addComponentInstance(
            name: "Slider",
            reference: .internalPart(name: "Slider"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        #expect(ws.document.componentInstances.count == 2)
        #expect(ws.document.componentInstances[1].isGrounded == false)

        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fSlider = AssemblyFeature(componentInstanceId: slider.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        #expect(ws.addAssemblyConstraint(AssemblyConstraint(kind: .planar, firstFeature: fBase, secondFeature: fSlider, value: 0.0)))

        ws.document.undoManager?.removeAllActions()

        ws.beginInteractiveAssemblyDrag(instanceId: slider.id)
        let solveResult = ws.solveAssemblyDrag(
            dragTarget: AssemblyDragTarget(instanceId: slider.id, targetPosition: SIMD3<Float>(30, 40, 50))
        )
        #expect(solveResult.status.isConverged)

        // Intermediate drag state: Z is constrained to 0
        let currentPos = ws.document.componentInstances[1].transform.position
        #expect(abs(currentPos.z) < 1e-3)
        #expect(abs(currentPos.x - 30) < 1.0)
        #expect(abs(currentPos.y - 40) < 1.0)
        #expect(ws.document.undoManager?.canUndo == false)

        ws.endInteractiveAssemblyDrag(instanceId: slider.id)
        #expect(ws.isDocumentModified)
        #expect(ws.document.undoManager?.canUndo == true)

        ws.undo()
        #expect(ws.document.componentInstances[1].transform.position == SIMD3<Float>(0, 0, 0))

        ws.redo()
        let redoPos = ws.document.componentInstances[1].transform.position
        #expect(abs(redoPos.z) < 1e-3)
        #expect(abs(redoPos.x - 30) < 1.0)
    }
}
