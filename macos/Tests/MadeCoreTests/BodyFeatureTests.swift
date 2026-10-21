import Testing
import Foundation
import simd
@testable import MadeCore

@MainActor
@Suite struct BodyFeatureTests {

    // MARK: - Combine Bodies (BL-PRT-18)

    @Test func testCombineBodiesRecordsFeatureAndHidesOperands() throws {
        let doc = DocumentModel()
        let initialCount = doc.features.count
        let initialObjCount = doc.objects.count

        let feature = try doc.combineBodies(
            targetBodyId: boxSolidId,
            toolBodyId: cylinderSolidId,
            operation: .union,
            keepTool: false
        )

        // 1. Appends exactly one feature
        #expect(doc.features.count == initialCount + 1)
        #expect(doc.features.last?.id == feature.id)
        #expect(feature.references.count == 2)
        #expect(feature.references.contains(where: { $0.role == "targetBody" }))
        #expect(feature.references.contains(where: { $0.role == "toolBody" }))

        // 2. Objects projection: compound object added, operands hidden
        #expect(doc.objects.count == initialObjCount + 1)
        guard let outputSolidId = feature.outputSolidId else {
            Issue.record("Expected outputSolidId on combine feature")
            return
        }
        let compound = doc.objects.first(where: { $0.id == outputSolidId })
        #expect(compound != nil)
        if case .boolean(let op, let a, let b)? = compound?.def {
            #expect(op == .union)
            #expect(a == boxSolidId)
            #expect(b == cylinderSolidId)
        } else {
            Issue.record("Expected boolean ObjectDef on compound object")
        }

        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.isVisible == false)
        #expect(doc.objects.first(where: { $0.id == cylinderSolidId })?.isVisible == false)
    }

    @Test func testCombineBodiesWithKeepToolPreservesToolVisibility() throws {
        let doc = DocumentModel()

        let feature = try doc.combineBodies(
            targetBodyId: boxSolidId,
            toolBodyId: cylinderSolidId,
            operation: .subtract,
            keepTool: true
        )

        guard let outputSolidId = feature.outputSolidId else {
            Issue.record("Expected outputSolidId")
            return
        }
        #expect(doc.objects.contains(where: { $0.id == outputSolidId }))
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.isVisible == false)
        #expect(doc.objects.first(where: { $0.id == cylinderSolidId })?.isVisible == true)
    }

    @Test func testCombineBodyWithItselfRejected() {
        let doc = DocumentModel()
        let initialCount = doc.features.count

        #expect(throws: DocumentMutationError.self) {
            try doc.combineBodies(
                targetBodyId: boxSolidId,
                toolBodyId: boxSolidId,
                operation: .intersect
            )
        }

        #expect(doc.features.count == initialCount)
    }

    // MARK: - Move Body (BL-PRT-18)

    @Test func testMoveBodyRecordsFeatureAndAppliesTransform() throws {
        let doc = DocumentModel()
        let initialCount = doc.features.count
        let initialTransform = doc.objects.first(where: { $0.id == boxSolidId })!.transform

        let delta = Transform(position: SIMD3<Float>(15, -20, 5))
        let feature = try doc.moveBody(
            targetBodyId: boxSolidId,
            transform: delta
        )

        // Exactly one feature appended
        #expect(doc.features.count == initialCount + 1)
        #expect(doc.features.last?.id == feature.id)
        if case .moveBody(let data) = feature.operation {
            #expect(data.targetBodyId == boxSolidId)
            #expect(data.transform.position == delta.position)
        } else {
            Issue.record("Expected .moveBody operation")
        }

        // Object transform updated
        let updatedTransform = doc.objects.first(where: { $0.id == boxSolidId })!.transform
        let expectedPos = delta.position + initialTransform.position
        #expect(abs(updatedTransform.position.x - expectedPos.x) < 0.001)
        #expect(abs(updatedTransform.position.y - expectedPos.y) < 0.001)
        #expect(abs(updatedTransform.position.z - expectedPos.z) < 0.001)
    }

    @Test func testMoveBodyZeroTransformRejected() throws {
        let doc = DocumentModel()
        let initialCount = doc.features.count

        #expect(throws: DocumentMutationError.self) {
            try doc.moveBody(targetBodyId: boxSolidId, transform: .identity)
        }

        #expect(doc.features.count == initialCount)
    }

    // MARK: - Copy Body (BL-PRT-18)

    @Test func testCopyBodyGeneratesUniqueNonCollidingNames() throws {
        let doc = DocumentModel()
        let initialCount = doc.features.count

        let copy1 = try doc.copyBody(
            sourceBodyId: boxSolidId,
            transform: Transform(position: SIMD3<Float>(10, 0, 0))
        )
        #expect(doc.features.count == initialCount + 1)
        #expect(copy1.name == "box-1 Copy")
        guard let copy1Id = copy1.outputSolidId else {
            Issue.record("Expected outputSolidId on copy1")
            return
        }
        #expect(doc.objects.contains(where: { $0.id == copy1Id }))

        let copy2 = try doc.copyBody(
            sourceBodyId: boxSolidId,
            transform: Transform(position: SIMD3<Float>(20, 0, 0))
        )
        #expect(doc.features.count == initialCount + 2)
        #expect(copy2.name == "box-1 Copy 2")
        guard let copy2Id = copy2.outputSolidId else {
            Issue.record("Expected outputSolidId on copy2")
            return
        }
        #expect(doc.objects.contains(where: { $0.id == copy2Id }))
        #expect(copy1Id != copy2Id)
    }

    // MARK: - Locked Body Mutations (BL-PRT-18)

    @Test func testLockedBodyCannotBeMovedOrDeleted() throws {
        let doc = DocumentModel()
        doc.setLocked(id: boxSolidId, isLocked: true)

        let initialCount = doc.features.count

        // Move rejected
        #expect(throws: DocumentMutationError.objectLocked(boxSolidId)) {
            try doc.moveBody(targetBodyId: boxSolidId, transform: Transform(position: SIMD3<Float>(10, 0, 0)))
        }

        // Delete rejected
        #expect(throws: DocumentMutationError.objectLocked(boxSolidId)) {
            try doc.deleteBody(targetBodyId: boxSolidId)
        }

        // Combine as target rejected
        #expect(throws: DocumentMutationError.objectLocked(boxSolidId)) {
            try doc.combineBodies(targetBodyId: boxSolidId, toolBodyId: cylinderSolidId, operation: .union)
        }

        // Combine as tool rejected when keepTool is false
        #expect(throws: DocumentMutationError.objectLocked(boxSolidId)) {
            try doc.combineBodies(targetBodyId: cylinderSolidId, toolBodyId: boxSolidId, operation: .union, keepTool: false)
        }

        #expect(doc.features.count == initialCount)
    }

    // MARK: - Delete Body Lifecycle & Selection (BL-PRT-18)

    @Test func testDeleteBodyRemovesObjectAndClearsSelection() throws {
        let doc = DocumentModel()
        doc.selectedId = boxSolidId
        #expect(doc.selectedId == boxSolidId)

        let initialCount = doc.features.count
        let feature = try doc.deleteBody(targetBodyId: boxSolidId)

        #expect(doc.features.count == initialCount + 1)
        #expect(feature.operation == .deleteBody(DeleteBodyFeatureData(targetBodyId: boxSolidId)))
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
        #expect(doc.selectedId == nil)
    }

    // MARK: - Cascading Missing Reference Error (BL-PRT-18)

    @Test func testDeleteBodyCascadesMissingReferenceToDependents() throws {
        let doc = DocumentModel()

        // Delete the box first
        _ = try doc.deleteBody(targetBodyId: boxSolidId)

        // Create a dependent feature downstream in timeline referencing deleted boxSolidId
        let depFeature = Feature(
            name: "Chamfer Box",
            operation: .chamfer(ChamferFeatureData(targetSolidId: boxSolidId, distance: 2.0, edgeReferences: [])),
            references: [Reference.body(boxSolidId, role: "targetBody")],
            outputSolidId: SolidId("chamfer-box")
        )
        doc.addFeature(depFeature)

        // Add a child dependent of the chamfer
        let childFeature = Feature(
            name: "Child Of Chamfer",
            operation: .primitive(.box(BoxParams(width: 5, depth: 5, height: 5))),
            references: [Reference.feature(depFeature.id, role: "parentChamfer")],
            outputSolidId: SolidId("child-box")
        )
        doc.addFeature(childFeature)

        // Verify reference resolution failure
        let res = doc.resolve(reference: Reference.body(boxSolidId), for: depFeature)
        guard case .failure = res else {
            Issue.record("Expected reference resolution failure")
            return
        }

        // Validate error state on dependent feature
        let validationError = ReferenceResolver.validateReferences(for: depFeature, in: doc)
        #expect(validationError != nil)

        // Timeline validation cascades error to direct dependent and warning to child
        doc.validateTimelineFeatureErrors()

        let updatedDep = doc.feature(for: depFeature.id)
        #expect(updatedDep?.errorState != nil)
        #expect(updatedDep?.errorState?.code == "reference-broken")

        let updatedChild = doc.feature(for: childFeature.id)
        #expect(updatedChild?.errorState != nil)
        #expect(updatedChild?.errorState?.code == "parent-failed")
        #expect(updatedChild?.errorState?.severity == FeatureErrorSeverity.warning)
    }

    // MARK: - Timeline Rollback Restoration (BL-PRT-18)

    @Test func testTimelineRollbackRestoresPreviousBodyStates() throws {
        let doc = DocumentModel()
        let initialBoxTransform = doc.objects.first(where: { $0.id == boxSolidId })!.transform

        // 1. Move box
        let moveFeat = try doc.moveBody(targetBodyId: boxSolidId, transform: Transform(position: SIMD3<Float>(30, 0, 0)))
        #expect(doc.objects.first(where: { $0.id == boxSolidId })!.transform.position.x != initialBoxTransform.position.x)

        // 2. Copy cylinder
        let copyFeat = try doc.copyBody(sourceBodyId: cylinderSolidId, transform: Transform(position: SIMD3<Float>(0, 30, 0)))
        guard let copyId = copyFeat.outputSolidId else {
            Issue.record("Missing copyId")
            return
        }
        #expect(doc.objects.contains(where: { $0.id == copyId }))

        // 3. Delete box
        let deleteFeat = try doc.deleteBody(targetBodyId: boxSolidId)
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))

        // Roll back before delete feature: box is restored
        let deleteIndex = doc.features.firstIndex(where: { $0.id == deleteFeat.id })!
        doc.setRollbackIndex(deleteIndex)
        #expect(doc.objects.contains(where: { $0.id == boxSolidId }))

        // Roll back before copy feature: copy is removed
        let copyIndex = doc.features.firstIndex(where: { $0.id == copyFeat.id })!
        doc.setRollbackIndex(copyIndex)
        #expect(!doc.objects.contains(where: { $0.id == copyId }))

        // Roll back before move feature: box returns to initial transform
        let moveIndex = doc.features.firstIndex(where: { $0.id == moveFeat.id })!
        doc.setRollbackIndex(moveIndex)
        let restoredTransform = doc.objects.first(where: { $0.id == boxSolidId })!.transform
        #expect(abs(restoredTransform.position.x - initialBoxTransform.position.x) < 0.001)

        // Roll forward to end: all operations are reapplied
        doc.setRollbackIndex(nil)
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
        #expect(doc.objects.contains(where: { $0.id == copyId }))
    }

    // MARK: - LocalKernelEngine Copy Solid (BL-PRT-18)

    @Test func testLocalKernelEngineCopySolid() async {
        let engine = LocalKernelEngine()
        let srcSolid = SolidId("src-box")
        let copySolid = SolidId("copy-box")

        // 1. Create source solid
        let makeReq = KernelRequest.makeBox(
            jobId: JobId("make-1"),
            solidId: srcSolid,
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        let makeRes = await engine.execute(makeReq)
        guard case .success(_, let payload) = makeRes else {
            Issue.record("Failed to create source solid")
            return
        }
        #expect(!payload.isEmpty)

        // 2. Copy solid
        let copyReq = KernelRequest.copySolid(
            jobId: JobId("copy-1"),
            solidId: copySolid,
            sourceSolidId: srcSolid
        )
        let copyRes = await engine.execute(copyReq)
        guard case .success(_, let copyPayload) = copyRes else {
            Issue.record("Failed to copy solid in kernel")
            return
        }
        #expect(copyPayload.positions.count == payload.positions.count)
        #expect(copyPayload.indices.count == payload.indices.count)

        // 3. Copying unknown solid returns error
        let badCopyReq = KernelRequest.copySolid(
            jobId: JobId("bad-copy"),
            solidId: SolidId("new-solid"),
            sourceSolidId: SolidId("nonexistent")
        )
        let badRes = await engine.execute(badCopyReq)
        if case .failure(_, let error) = badRes {
            #expect(error.code == .unknownSolid)
        } else {
            Issue.record("Expected failure for copying nonexistent solid")
        }
    }
}
