import Testing
import Foundation
import simd
import OCCTSwift
@testable import MadeCore

@Suite @MainActor struct ShellTests {

    // MARK: - Definition of Done: Volume Verification (BL-PRT-08)

    @Test func testShellVolume20mmCube2mmThicknessTopFaceRemoved() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 20, depth: 20, height: 20)
        )
        document.addFeature(boxFeat)
        guard let topFaceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top topology reference on box")
            return
        }

        let shellFeat = try document.shellBody(
            targetSolidId: boxFeat.outputSolidId!,
            thickness: 2.0,
            removedFaceReferences: [topFaceRef]
        )

        guard let shellSolidId = shellFeat.outputSolidId else {
            Issue.record("Missing shell outputSolidId")
            return
        }
        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("shell-vol-1"), solidId: shellSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }

        let analysis = SolidVerifier.analyzeMesh(payload)
        guard let measurements = analysis.measurements else {
            Issue.record("Mesh analysis returned nil measurements")
            return
        }

        // 20x20x20 cube volume = 8,000 mm³.
        // 2 mm wall thickness with top face removed leaves 16x16x18 mm cavity = 4,608 mm³.
        // Solid volume = 8,000 - 4,608 = 3,392 mm³ (within 0.1% = ±3.4 mm³).
        #expect(abs(measurements.volume - 3392.0) < 3.4)
    }

    @Test func testShellClosedHollowBodyWithoutRemovedFaces() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 20, depth: 20, height: 20)
        )
        document.addFeature(boxFeat)

        let shellFeat = try document.shellBody(
            targetSolidId: boxFeat.outputSolidId!,
            thickness: 2.0,
            removedFaceReferences: []
        )

        guard let shellSolidId = shellFeat.outputSolidId else {
            Issue.record("Missing shell outputSolidId")
            return
        }
        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("shell-vol-2"), solidId: shellSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }

        let analysis = SolidVerifier.analyzeMesh(payload)
        guard let measurements = analysis.measurements else {
            Issue.record("Mesh analysis returned nil measurements")
            return
        }

        // 20x20x20 outer cube (8,000 mm³) minus 16x16x16 mm inner void (4,096 mm³) = 3,904 mm³.
        // Expected volume: 3,904 mm³ (within 0.1% = ±3.9 mm³).
        #expect(abs(measurements.volume - 3904.0) < 3.9)
    }

    // MARK: - Edge Cases

    @Test func testShellRejectsThicknessExceedingHalfDimension() async throws {
        let engine = LocalKernelEngine()
        let boxId = SolidId("box-half-dim")
        _ = await engine.execute(.makeBox(
            jobId: JobId("box-job"),
            solidId: boxId,
            params: BoxParams(width: 20, depth: 20, height: 20)
        ))

        let boxFeat = Feature.makeBox(
            solidId: boxId,
            name: "Box 1",
            params: BoxParams(width: 20, depth: 20, height: 20)
        )
        let topFaceRef = boxFeat.generatedTopology["face:top"]

        // 20 mm cube has smallest dimension 20 mm. Half dimension is 10 mm.
        // Thickness of 11 mm exceeds half dimension (10 mm) and must fail with geometryFailed.
        let res = await engine.shell(
            solidId: SolidId("shell-too-thick"),
            targetSolidId: boxId,
            thickness: 11.0,
            removedFaceReferences: topFaceRef.map { [$0] } ?? [],
            perFaceOverrides: []
        )
        #expect(res.error?.code == KernelErrorCode.geometryFailed)
        #expect(res.error?.message.contains("exceeds half of smallest dimension") == true)
    }

    @Test func testShellRejectsNonPlanarFaceRemoval() async throws {
        let engine = LocalKernelEngine()
        let cylId = SolidId("cyl-non-planar")
        _ = await engine.execute(.makeCylinder(
            jobId: JobId("cyl-job"),
            solidId: cylId,
            params: CylinderParams(radius: 10, height: 30)
        ))

        let cylFeat = Feature.makeCylinder(
            solidId: cylId,
            params: CylinderParams(radius: 10, height: 30)
        )
        guard let sideFaceRef = cylFeat.generatedTopology["face:side"] else {
            Issue.record("Missing face:side on cylinder")
            return
        }

        let res = await engine.shell(
            solidId: SolidId("shell-non-planar"),
            targetSolidId: cylId,
            thickness: 1.0,
            removedFaceReferences: [sideFaceRef],
            perFaceOverrides: []
        )
        #expect(res.error?.code == KernelErrorCode.geometryFailed)
        #expect(res.error?.message.contains("Removed face must be planar") == true)
    }

    @Test func testShellUpstreamEditErrorCascade() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 20, depth: 20, height: 20)
        )
        document.addFeature(boxFeat)
        guard let topFaceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top topology reference on box")
            return
        }

        let shellFeat = try document.shellBody(
            targetSolidId: boxFeat.outputSolidId!,
            thickness: 2.0,
            removedFaceReferences: [topFaceRef]
        )

        // Add a dependent feature referencing the shell solid
        var depFeat = Feature.makeBox(
            solidId: ObjectId("box-dep"),
            name: "Dependent Box",
            params: BoxParams(width: 5, depth: 5, height: 5)
        )
        depFeat.references = [Reference.body(shellFeat.outputSolidId!, role: "parentBody")]
        document.addFeature(depFeat)

        // Upstream edit: remove the target box object so shell's face reference is broken
        document.removeObject(id: boxFeat.outputSolidId!)

        await KernelRegeneration.regenerate(document: document, client: client)

        guard let updatedShell = document.feature(for: shellFeat.id) else {
            Issue.record("Shell feature was unexpectedly missing")
            return
        }
        #expect(updatedShell.errorState?.code == "reference-broken")

        guard let updatedDependent = document.feature(for: depFeat.id) else {
            Issue.record("Dependent feature was unexpectedly missing")
            return
        }
        #expect(updatedDependent.errorState?.code == "parent-failed")
    }

    @Test func testShellUndoRedo() throws {
        let document = DocumentModel(features: [])
        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 20, depth: 20, height: 20)
        )
        document.addFeature(boxFeat)
        document.undoManager?.removeAllActions()
        guard let topFaceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top topology reference on box")
            return
        }

        let initialFeatureCount = document.features.count
        let shellFeat = try document.shellBody(
            targetSolidId: boxFeat.outputSolidId!,
            thickness: 2.0,
            removedFaceReferences: [topFaceRef]
        )

        #expect(document.features.count == initialFeatureCount + 1)
        #expect(document.feature(for: boxFeat.id)?.isVisible == false)
        #expect(document.feature(for: shellFeat.id)?.isVisible == true)

        // Undo restores unshelled solid visibility and removes shell feature
        document.undo()
        #expect(document.features.count == initialFeatureCount)
        #expect(document.feature(for: boxFeat.id)?.isVisible == true)
        #expect(document.feature(for: shellFeat.id) == nil)

        // Redo restores shell feature and hides target solid
        document.redo()
        #expect(document.features.count == initialFeatureCount + 1)
        #expect(document.feature(for: boxFeat.id)?.isVisible == false)
        #expect(document.feature(for: shellFeat.id)?.isVisible == true)
    }
}
