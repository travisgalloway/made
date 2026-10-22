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
}
