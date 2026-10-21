import Testing
import Foundation
import simd
import OCCTSwift
@testable import MadeCore

@Suite @MainActor struct MirrorFeatureTests {

    // MARK: - Definition of Done: Golden Volume Verification (BL-PRT-14, #302)

    /// Golden volume test: A 10x10x10 mm box 10 mm from the mirror plane (normal (0,0,1))
    /// mirrors to an identical volume, and with keepOriginal: true compound volume = 2x single volume within 0.1%.
    @Test func testGoldenVolume10mmBoxMirror() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-golden"),
            name: "Box 1",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let boxSolidId = boxFeat.outputSolidId else {
            Issue.record("Missing box outputSolidId")
            return
        }

        // Measure single box volume
        await KernelRegeneration.regenerate(document: document, client: client)
        let singleRes = await client.request(.tessellate(jobId: JobId("box-golden-single"), solidId: boxSolidId))
        let singleAnalysis = try #require(singleRes.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let singleVolume = try #require(singleAnalysis.measurements?.volume)

        // Box is centered from z = -5 to +5. Plane at z = 15 is 10 mm away from top face.
        let mirrorFeat = try document.mirrorBody(
            targetSolidId: boxSolidId,
            planeNormal: [0.0, 0.0, 1.0],
            planeOrigin: [0.0, 0.0, 15.0],
            keepOriginal: true
        )
        guard let mirrorSolidId = mirrorFeat.outputSolidId else {
            Issue.record("Missing mirror outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("mirror-vol-golden"), solidId: mirrorSolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let measurements = try #require(analysis.measurements)

        let expectedVolume = singleVolume * 2.0
        let tolerance = expectedVolume * 0.001 // 0.1% tolerance
        #expect(abs(measurements.volume - expectedVolume) <= tolerance)
    }

    // MARK: - Coincident Plane Acceptance

    /// Coincident plane test: A box touching the mirror plane is accepted without error.
    @Test func testCoincidentPlaneAcceptance() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-coincident"),
            name: "Box Coincident",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let boxSolidId = boxFeat.outputSolidId else {
            Issue.record("Missing box outputSolidId")
            return
        }

        // Top face of box is at z = +5. Plane at z = 5 touches the face.
        let mirrorFeat = try document.mirrorBody(
            targetSolidId: boxSolidId,
            planeNormal: [0.0, 0.0, 1.0],
            planeOrigin: [0.0, 0.0, 5.0],
            keepOriginal: true
        )
        guard let mirrorSolidId = mirrorFeat.outputSolidId else {
            Issue.record("Missing mirror outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("mirror-coincident-job"), solidId: mirrorSolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let measurements = try #require(analysis.measurements)

        // Box 10x10x10 touching mirrored 10x10x10 = 2000 mm³
        #expect(abs(measurements.volume - 2000.0) <= 2000.0 * 0.01)
    }

    // MARK: - Cutting Plane Handling & Diagnostics

    /// Cutting plane test: Plane cuts through the body, handled with union and warning diagnostic.
    @Test func testCuttingPlaneHandled() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-cutting"),
            name: "Box Cutting",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let boxSolidId = boxFeat.outputSolidId else {
            Issue.record("Missing box outputSolidId")
            return
        }

        // Plane at z = 2 cuts the box (z from -5 to +5).
        let mirrorFeat = try document.mirrorBody(
            targetSolidId: boxSolidId,
            planeNormal: [0.0, 0.0, 1.0],
            planeOrigin: [0.0, 0.0, 2.0],
            keepOriginal: true
        )
        guard let mirrorSolidId = mirrorFeat.outputSolidId else {
            Issue.record("Missing mirror outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("mirror-cutting-job"), solidId: mirrorSolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        #expect(analysis.measurements?.volume != nil)

        // Verify warning diagnostic is emitted for cutting plane
        if case .mirror(let mirrorData) = mirrorFeat.operation {
            let warning = KernelRegeneration.evaluateMirrorWarning(params: mirrorData, in: document)
            #expect(warning?.code == "cutting-plane-merged")
        } else {
            Issue.record("Expected .mirror operation on mirror feature")
        }
    }

    // MARK: - Mirror of Mirror Chaining

    /// Mirror of mirror test: Chaining mirror features updates both when the base solid changes.
    @Test func testMirrorOfMirrorChaining() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-chain"),
            name: "Box Chain",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let boxSolidId = boxFeat.outputSolidId else {
            Issue.record("Missing box outputSolidId")
            return
        }

        // First mirror across Z=15 (keep original: false for simple 1-to-1 chaining)
        let mirror1 = try document.mirrorBody(
            targetSolidId: boxSolidId,
            planeNormal: [0.0, 0.0, 1.0],
            planeOrigin: [0.0, 0.0, 15.0],
            keepOriginal: false
        )
        guard let m1SolidId = mirror1.outputSolidId else {
            Issue.record("Missing mirror1 outputSolidId")
            return
        }

        // Second mirror across Y=20 reflecting mirror1
        let mirror2 = try document.mirrorBody(
            targetSolidId: m1SolidId,
            planeNormal: [0.0, 1.0, 0.0],
            planeOrigin: [0.0, 20.0, 0.0],
            keepOriginal: false
        )
        guard let m2SolidId = mirror2.outputSolidId else {
            Issue.record("Missing mirror2 outputSolidId")
            return
        }

        let deps = document.directDependencies(of: mirror2)
        #expect(deps.contains(mirror1.id))

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("chain-job"), solidId: m2SolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let vol = try #require(analysis.measurements?.volume)
        #expect(abs(vol - 1000.0) <= 1000.0 * 0.001)
    }

    // MARK: - Plane Deletion Cascading

    /// Plane deletion test: Deleting a referenced datum plane cascades missing-reference to the mirror feature.
    @Test func testPlaneDeletionCascadesMissingReference() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-ref"),
            name: "Box Ref",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let boxSolidId = boxFeat.outputSolidId else {
            Issue.record("Missing box outputSolidId")
            return
        }

        let datumFeat = document.addDatumPlaneFeature(
            name: "Mirror Plane",
            data: DatumPlaneFeatureData(originPreset: "XY", offsetDistance: 15.0)
        )

        let mirrorFeat = try document.mirrorBody(
            targetSolidId: boxSolidId,
            planeNormal: [0.0, 0.0, 1.0],
            planeOrigin: [0.0, 0.0, 15.0],
            keepOriginal: true,
            planeReference: Reference.feature(datumFeat.id)
        )
        guard let mirrorSolidId = mirrorFeat.outputSolidId else {
            Issue.record("Missing mirror outputSolidId")
            return
        }

        // Dependent feature referencing the mirror feature
        let depFeat = Feature(
            name: "Dependent Feature",
            operation: .shell(ShellFeatureData(targetSolidId: mirrorSolidId, thickness: 1.0, removedFaceReferences: [])),
            references: [Reference.feature(mirrorFeat.id)]
        )
        document.addFeature(depFeat)

        // Initially both succeed
        await KernelRegeneration.regenerate(document: document, client: client)
        #expect(document.feature(for: mirrorFeat.id)?.errorState == nil)

        // Delete datum plane
        _ = document.removeFeature(id: datumFeat.id)

        // Regenerate after plane deletion
        await KernelRegeneration.regenerate(document: document, client: client)

        let updatedMirror = document.feature(for: mirrorFeat.id)
        #expect(updatedMirror?.errorState?.code == "missing-reference")

        let updatedDep = document.feature(for: depFeat.id)
        #expect(updatedDep?.errorState?.code == "parent-failed")
    }

    // MARK: - Symmetric Undo and Redo

    /// Symmetric undo/redo test: Single-step undo and redo properly restore mirror feature and target body state.
    @Test func testSymmetricUndoRedo() throws {
        let document = DocumentModel(features: [])

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-undo"),
            name: "Box Undo",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        document.undoManager?.removeAllActions()
        guard let boxSolidId = boxFeat.outputSolidId else {
            Issue.record("Missing box outputSolidId")
            return
        }

        #expect(document.feature(for: boxSolidId)?.isVisible == true)

        let mirrorFeat = try document.mirrorBody(
            targetSolidId: boxSolidId,
            planeNormal: [0.0, 0.0, 1.0],
            planeOrigin: [0.0, 0.0, 15.0],
            keepOriginal: true
        )

        #expect(document.feature(for: boxSolidId)?.isVisible == false)
        #expect(document.features.contains(where: { $0.id == mirrorFeat.id }))

        // Undo
        document.undo()

        #expect(document.feature(for: boxSolidId)?.isVisible == true)
        #expect(!document.features.contains(where: { $0.id == mirrorFeat.id }))

        // Redo
        document.redo()

        #expect(document.feature(for: boxSolidId)?.isVisible == false)
        #expect(document.features.contains(where: { $0.id == mirrorFeat.id }))
    }

    // MARK: - Timeline Regeneration

    /// Timeline regeneration test: Changing upstream box dimensions updates the mirrored solid geometry.
    @Test func testTimelineRegenerationUpstreamBoxEdit() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        var boxFeat = Feature.makeBox(
            solidId: ObjectId("box-edit"),
            name: "Box Edit",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let boxSolidId = boxFeat.outputSolidId else {
            Issue.record("Missing box outputSolidId")
            return
        }

        let mirrorFeat = try document.mirrorBody(
            targetSolidId: boxSolidId,
            planeNormal: [0.0, 0.0, 1.0],
            planeOrigin: [0.0, 0.0, 15.0],
            keepOriginal: false
        )
        guard let mirrorSolidId = mirrorFeat.outputSolidId else {
            Issue.record("Missing mirror outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res1 = await client.request(.tessellate(jobId: JobId("edit-job-1"), solidId: mirrorSolidId))
        let analysis1 = try #require(res1.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let vol1 = try #require(analysis1.measurements?.volume)
        #expect(abs(vol1 - 1000.0) <= 1000.0 * 0.001)

        // Mutate upstream box to width 20 (volume = 20 * 10 * 10 = 2000 mm³)
        boxFeat.operation = .primitive(.box(BoxParams(width: 20, depth: 10, height: 10)))
        _ = document.updateFeature(boxFeat)

        // Regenerate timeline
        await KernelRegeneration.regenerate(document: document, client: client)

        let res2 = await client.request(.tessellate(jobId: JobId("edit-job-2"), solidId: mirrorSolidId))
        let analysis2 = try #require(res2.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let vol2 = try #require(analysis2.measurements?.volume)
        #expect(abs(vol2 - 2000.0) <= 2000.0 * 0.001)
    }
}
