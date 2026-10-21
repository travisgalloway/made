import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct ChamferTests {

    // MARK: - Definition of Done: Volume Verification (BL-PRT-07)

    @Test func testChamferVolume10mmCube1mmDistance() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let edgeRef = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge:top-front topology reference on box")
            return
        }

        let chamferFeat = try document.chamferEdges(
            targetSolidId: boxFeat.outputSolidId!,
            edgeReferences: [edgeRef],
            mode: .equalDistance,
            distance: 1.0
        )

        guard let chamferSolidId = chamferFeat.outputSolidId else {
            Issue.record("Missing chamfer outputSolidId")
            return
        }
        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("chamfer-vol-1"), solidId: chamferSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }

        let analysis = SolidVerifier.analyzeMesh(payload)
        guard let measurements = analysis.measurements else {
            Issue.record("Mesh analysis returned nil measurements")
            return
        }

        // 10x10x10 cube volume = 1000 mm³.
        // 1 mm chamfer along 10 mm edge removes prism of 0.5 * 1 * 1 * 10 = 5 mm³.
        // Expected volume: 995 mm³ (within 0.1% = ±1.0 mm³).
        #expect(abs(measurements.volume - 995.0) < 1.0)
    }

    @Test func testChamferTwoDistances() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let edgeRef = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge:top-front topology reference on box")
            return
        }

        let chamferFeat = try document.chamferEdges(
            targetSolidId: boxFeat.outputSolidId!,
            edgeReferences: [edgeRef],
            mode: .twoDistances,
            distance: 1.0,
            distance2: 2.0
        )

        guard let chamferSolidId = chamferFeat.outputSolidId else {
            Issue.record("Missing chamfer outputSolidId")
            return
        }
        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("chamfer-vol-2"), solidId: chamferSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }

        let analysis = SolidVerifier.analyzeMesh(payload)
        guard let measurements = analysis.measurements else {
            Issue.record("Mesh analysis returned nil measurements")
            return
        }

        // 10x10x10 cube volume = 1000 mm³.
        // 1 mm x 2 mm chamfer removes prism of 0.5 * 1 * 2 * 10 = 10 mm³.
        // Expected volume: 990 mm³ (within 0.1% = ±1.0 mm³).
        #expect(abs(measurements.volume - 990.0) < 1.0)
    }

    @Test func testChamferDistanceAngle() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let edgeRef = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge:top-front topology reference on box")
            return
        }

        let chamferFeat = try document.chamferEdges(
            targetSolidId: boxFeat.outputSolidId!,
            edgeReferences: [edgeRef],
            mode: .distanceAngle,
            distance: 1.0,
            angle: 45.0
        )

        guard let chamferSolidId = chamferFeat.outputSolidId else {
            Issue.record("Missing chamfer outputSolidId")
            return
        }
        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("chamfer-vol-3"), solidId: chamferSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }

        let analysis = SolidVerifier.analyzeMesh(payload)
        guard let measurements = analysis.measurements else {
            Issue.record("Mesh analysis returned nil measurements")
            return
        }

        // 1 mm at 45° produces 1 mm adjacent leg, removing 5 mm³.
        // Expected volume: 995 mm³ (within 0.1% = ±1.0 mm³).
        #expect(abs(measurements.volume - 995.0) < 1.0)
    }

    // MARK: - Edge Cases

    @Test func testChamferTangentChain() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-1"),
            name: "Cylinder 1",
            params: CylinderParams(radius: 10, height: 20)
        )
        document.addFeature(cylFeat)
        guard let topEdgeRef = cylFeat.generatedTopology["edge:top"] else {
            Issue.record("Missing edge:top topology reference on cylinder")
            return
        }

        // Passing the same tangent contour edge multiple times validates tangent-chain handling
        let chamferFeat = try document.chamferEdges(
            targetSolidId: cylFeat.outputSolidId!,
            edgeReferences: [topEdgeRef, topEdgeRef],
            mode: .equalDistance,
            distance: 1.0
        )

        guard let chamferSolidId = chamferFeat.outputSolidId else {
            Issue.record("Missing chamfer outputSolidId")
            return
        }
        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("chamfer-tangent"), solidId: chamferSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }
        #expect(!payload.isEmpty)
    }

    @Test func testChamferRejectsZeroOrNegativeDistance() async throws {
        let document = DocumentModel(features: [])
        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let edgeRef = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge:top-front topology reference on box")
            return
        }

        #expect(throws: DocumentMutationError.self) {
            try document.chamferEdges(
                targetSolidId: boxFeat.outputSolidId!,
                edgeReferences: [edgeRef],
                mode: .equalDistance,
                distance: 0.0
            )
        }

        #expect(throws: DocumentMutationError.self) {
            try document.chamferEdges(
                targetSolidId: boxFeat.outputSolidId!,
                edgeReferences: [edgeRef],
                mode: .equalDistance,
                distance: -2.0
            )
        }

        let engine = LocalKernelEngine()
        let res = await engine.chamfer(
            solidId: SolidId("chamfer-err"),
            targetSolidId: boxFeat.outputSolidId!,
            edgeReferences: [edgeRef],
            distance: -1.0
        )
        #expect(res.error?.code == KernelErrorCode.invalidParams)
    }

    @Test func testChamferRejectsDistanceLargerThanAdjacentFace() async throws {
        let engine = LocalKernelEngine()
        let boxId = SolidId("box-large-face")
        _ = await engine.execute(.makeBox(
            jobId: JobId("box-job"),
            solidId: boxId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        ))

        let boxFeat = Feature.makeBox(
            solidId: boxId,
            name: "Box 1",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        guard let edgeRef = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge:top-front topology reference on box")
            return
        }

        let res = await engine.chamfer(
            solidId: SolidId("chamfer-too-large"),
            targetSolidId: boxId,
            edgeReferences: [edgeRef],
            mode: .equalDistance,
            distance: 15.0
        )

        #expect(res.error != nil)
        #expect(res.error?.code == KernelErrorCode.geometryFailed)
        #expect(res.error?.message.contains("adjacent face") == true)
    }

    @Test func testChamferUpstreamEditMissingReference() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        guard let edgeRef = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge:top-front topology reference on box")
            return
        }

        let chamferFeat = try document.chamferEdges(
            targetSolidId: boxFeat.outputSolidId!,
            edgeReferences: [edgeRef],
            mode: .equalDistance,
            distance: 1.0
        )

        // Downstream dependent feature referencing chamfer feature
        let dependentFeat = Feature(
            name: "Dependent Feature",
            operation: .primitive(.box(BoxParams(width: 5, depth: 5, height: 5))),
            references: [.feature(chamferFeat.id)],
            outputSolidId: ObjectId("dep-1")
        )
        document.addFeature(dependentFeat)

        // Upstream edit: remove the box object so chamfer's edge reference is broken
        document.removeObject(id: boxFeat.outputSolidId!)

        await KernelRegeneration.regenerate(document: document, client: client)

        guard let updatedChamfer = document.feature(for: chamferFeat.id) else {
            Issue.record("Chamfer feature was unexpectedly missing")
            return
        }
        #expect(updatedChamfer.errorState?.code == "reference-broken")

        guard let updatedDependent = document.feature(for: dependentFeat.id) else {
            Issue.record("Dependent feature was unexpectedly missing")
            return
        }
        #expect(updatedDependent.errorState?.code == "parent-failed")
    }

    @Test func testChamferUndoRedo() throws {
        let document = DocumentModel(features: [])
        let boxFeat = Feature.makeBox(
            solidId: ObjectId("box-1"),
            name: "Box 1",
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        document.addFeature(boxFeat)
        document.undoManager?.removeAllActions()
        guard let edgeRef = boxFeat.generatedTopology["edge:top-front"] else {
            Issue.record("Missing edge:top-front topology reference on box")
            return
        }

        let initialFeatureCount = document.features.count
        let chamferFeat = try document.chamferEdges(
            targetSolidId: boxFeat.outputSolidId!,
            edgeReferences: [edgeRef],
            mode: .equalDistance,
            distance: 1.0
        )

        #expect(document.features.count == initialFeatureCount + 1)
        #expect(document.feature(for: boxFeat.id)?.isVisible == false)
        #expect(document.feature(for: chamferFeat.id)?.isVisible == true)

        // Undo restores unchamfered solid visibility and removes chamfer feature
        document.undo()
        #expect(document.features.count == initialFeatureCount)
        #expect(document.feature(for: boxFeat.id)?.isVisible == true)
        #expect(document.feature(for: chamferFeat.id) == nil)

        // Redo restores chamfered solid
        document.redo()
        #expect(document.features.count == initialFeatureCount + 1)
        #expect(document.feature(for: boxFeat.id)?.isVisible == false)
        #expect(document.feature(for: chamferFeat.id)?.isVisible == true)
    }
}
