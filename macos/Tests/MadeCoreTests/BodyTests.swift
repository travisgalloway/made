import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct BodyTests {
    @Test func testBodyCreationAndDefaults() {
        let bodyId = SolidId("body-test-1")
        var body = Body(
            id: bodyId,
            name: "Body 1",
            type: .solid,
            isVisible: true,
            isLocked: false,
            material: MaterialAttributes(color: SIMD4<Float>(0.2, 0.4, 0.6, 1.0)),
            transform: Transform(position: SIMD3<Float>(10, 20, 30))
        )

        #expect(body.id == bodyId)
        #expect(body.name == "Body 1")
        #expect(body.type == .solid)
        #expect(body.isVisible)
        #expect(!body.isLocked)
        #expect(body.color == SIMD4<Float>(0.2, 0.4, 0.6, 1.0))
        #expect(body.transform.position == SIMD3<Float>(10, 20, 30))

        // Color getter / setter forwarding
        body.color = SIMD4<Float>(0.8, 0.1, 0.1, 1.0)
        #expect(body.material.color == SIMD4<Float>(0.8, 0.1, 0.1, 1.0))
        #expect(body.color == SIMD4<Float>(0.8, 0.1, 0.1, 1.0))

        // Surface body type
        let surfaceBody = Body(id: SolidId("surface-1"), name: "Surface 1", type: .surface)
        #expect(surfaceBody.type == .surface)
    }

    @Test func testBodyOperationEnumAndBooleanOpMapping() {
        #expect(BodyOperation.allCases == [.create, .add, .cut, .intersect])
        #expect(BodyType.allCases == [.solid, .surface])

        // Mapping to BooleanOp
        #expect(BodyOperation.create.booleanOp == nil)
        #expect(BodyOperation.add.booleanOp == .union)
        #expect(BodyOperation.cut.booleanOp == .subtract)
        #expect(BodyOperation.intersect.booleanOp == .intersect)

        // Mapping from BooleanOp
        #expect(BodyOperation(booleanOp: .union) == .add)
        #expect(BodyOperation(booleanOp: .subtract) == .cut)
        #expect(BodyOperation(booleanOp: .intersect) == .intersect)
    }

    @Test func testBodySceneObjectConversions() {
        let obj = SceneObject(
            id: SolidId("solid-1"),
            name: "Object 1",
            def: .box(BoxParams(width: 10, depth: 20, height: 30)),
            transform: Transform(position: SIMD3<Float>(5, 0, -5)),
            isVisible: true,
            isLocked: false,
            material: MaterialAttributes(color: SIMD4<Float>(1, 0, 0, 1))
        )

        let body = Body(from: obj)
        #expect(body.id == obj.id)
        #expect(body.name == obj.name)
        #expect(body.type == .solid)
        #expect(body.isVisible == obj.isVisible)
        #expect(body.isLocked == obj.isLocked)
        #expect(body.material == obj.material)
        #expect(body.transform == obj.transform)

        let roundTrippedObj = body.toSceneObject(def: obj.def)
        #expect(roundTrippedObj.id == obj.id)
        #expect(roundTrippedObj.name == obj.name)
        #expect(roundTrippedObj.def == obj.def)
        #expect(roundTrippedObj.isVisible == obj.isVisible)
        #expect(roundTrippedObj.isLocked == obj.isLocked)
        #expect(roundTrippedObj.material == obj.material)
        #expect(roundTrippedObj.transform == obj.transform)
    }

    @Test func testDocumentModelBodiesTracking() {
        let doc = DocumentModel()
        #expect(doc.bodies.count == 2)
        #expect(doc.bodies.map(\.id) == [boxSolidId, cylinderSolidId])
        #expect(doc.body(for: boxSolidId)?.name == "box-1")
        #expect(doc.body(for: cylinderSolidId)?.name == "cylinder-1")
        #expect(doc.body(for: SolidId("nonexistent")) == nil)
    }

    @Test func testDocumentModelBodyMutators() {
        let doc = DocumentModel()

        // Visibility
        doc.setBodyVisibility(id: boxSolidId, isVisible: false)
        #expect(doc.body(for: boxSolidId)?.isVisible == false)
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.isVisible == false)

        doc.setBodyVisibility(id: boxSolidId, isVisible: true)
        #expect(doc.body(for: boxSolidId)?.isVisible == true)

        // Name
        doc.setBodyName(id: boxSolidId, name: "Base Plate")
        #expect(doc.body(for: boxSolidId)?.name == "Base Plate")
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.name == "Base Plate")

        // Material
        let newMat = MaterialAttributes(color: SIMD4<Float>(0.1, 0.9, 0.2, 1.0))
        let matResult = doc.setBodyMaterial(id: boxSolidId, material: newMat)
        #expect(matResult == .success(()))
        #expect(doc.body(for: boxSolidId)?.material == newMat)

        // Color
        let colorResult = doc.setBodyColor(id: boxSolidId, color: SIMD4<Float>(0.9, 0.2, 0.1, 1.0))
        #expect(colorResult == .success(()))
        #expect(doc.body(for: boxSolidId)?.color == SIMD4<Float>(0.9, 0.2, 0.1, 1.0))

        // Locked
        doc.setBodyLocked(id: boxSolidId, isLocked: true)
        #expect(doc.body(for: boxSolidId)?.isLocked == true)
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.isLocked == true)
    }

    @Test func testLockedBodyRejectsMutations() {
        let doc = DocumentModel()
        doc.setBodyLocked(id: boxSolidId, isLocked: true)
        #expect(doc.body(for: boxSolidId)?.isLocked == true)

        let initialName = doc.body(for: boxSolidId)?.name
        let initialMaterial = doc.body(for: boxSolidId)?.material

        // Rename rejected when locked
        doc.setBodyName(id: boxSolidId, name: "Hacked Name")
        #expect(doc.body(for: boxSolidId)?.name == initialName)

        // Material mutation rejected when locked
        let matResult = doc.setBodyMaterial(id: boxSolidId, material: MaterialAttributes(color: SIMD4<Float>(1, 0, 0, 1)))
        #expect(matResult == .failure(.objectLocked(boxSolidId)))
        #expect(doc.body(for: boxSolidId)?.material == initialMaterial)

        // Color mutation rejected when locked
        let colorResult = doc.setBodyColor(id: boxSolidId, color: SIMD4<Float>(0, 1, 0, 1))
        #expect(colorResult == .failure(.objectLocked(boxSolidId)))
        #expect(doc.body(for: boxSolidId)?.material == initialMaterial)

        // Nonexistent body returns objectNotFound
        let ghostId = SolidId("ghost-body")
        #expect(doc.setBodyMaterial(id: ghostId, material: MaterialAttributes()) == .failure(.objectNotFound(ghostId)))
        #expect(doc.setBodyColor(id: ghostId, color: SIMD4<Float>(1, 1, 1, 1)) == .failure(.objectNotFound(ghostId)))
    }

    @Test func testUndoRedoBodyMutations() {
        let doc = DocumentModel()
        let initialName = doc.body(for: boxSolidId)!.name
        let initialVisible = doc.body(for: boxSolidId)!.isVisible
        let initialColor = doc.body(for: boxSolidId)!.color

        // 1. Rename
        doc.setBodyName(id: boxSolidId, name: "Renamed Box")
        #expect(doc.body(for: boxSolidId)?.name == "Renamed Box")
        doc.undo()
        #expect(doc.body(for: boxSolidId)?.name == initialName)
        doc.redo()
        #expect(doc.body(for: boxSolidId)?.name == "Renamed Box")

        // 2. Visibility
        doc.setBodyVisibility(id: boxSolidId, isVisible: false)
        #expect(doc.body(for: boxSolidId)?.isVisible == false)
        doc.undo()
        #expect(doc.body(for: boxSolidId)?.isVisible == initialVisible)
        doc.redo()
        #expect(doc.body(for: boxSolidId)?.isVisible == false)

        // 3. Color
        let newColor = SIMD4<Float>(0.9, 0.5, 0.1, 1.0)
        _ = doc.setBodyColor(id: boxSolidId, color: newColor)
        #expect(doc.body(for: boxSolidId)?.color == newColor)
        doc.undo()
        #expect(doc.body(for: boxSolidId)?.color == initialColor)
        doc.redo()
        #expect(doc.body(for: boxSolidId)?.color == newColor)
    }

    @Test func testRollbackMarkerExcludesBodies() {
        let doc = DocumentModel()
        #expect(doc.bodies.count == 2)
        #expect(doc.bodies.map(\.id) == [boxSolidId, cylinderSolidId])

        // Roll back to 1 feature (excluding cylinder)
        _ = doc.rollBack(to: 1)
        #expect(doc.bodies.count == 1)
        #expect(doc.bodies.first?.id == boxSolidId)
        #expect(doc.body(for: cylinderSolidId) == nil)

        // Roll back to 0 features (excluding everything)
        _ = doc.rollBack(to: 0)
        #expect(doc.bodies.isEmpty)

        // Roll forward to end
        _ = doc.rollForwardToEnd()
        #expect(doc.bodies.count == 2)
        #expect(doc.bodies.map(\.id) == [boxSolidId, cylinderSolidId])
    }

    @Test func testBodyRenameWhitespaceTrimming() {
        let doc = DocumentModel()
        let initialName = doc.body(for: boxSolidId)!.name

        // Whitespace-only name is rejected
        doc.setBodyName(id: boxSolidId, name: "   \t\n  ")
        #expect(doc.body(for: boxSolidId)?.name == initialName)

        // Empty string is rejected
        doc.setBodyName(id: boxSolidId, name: "")
        #expect(doc.body(for: boxSolidId)?.name == initialName)

        // Leading and trailing whitespace is trimmed
        doc.setBodyName(id: boxSolidId, name: "   Trimmed Body   ")
        #expect(doc.body(for: boxSolidId)?.name == "Trimmed Body")
    }
}
