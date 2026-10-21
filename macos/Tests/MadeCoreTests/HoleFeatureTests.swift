import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct HoleFeatureTests {

    // MARK: - Definition of Done: Golden Volume Verification (BL-PRT-10, #297)

    /// Golden volume test: A 5 mm through hole in a 20 × 20 × 10 mm plate leaves
    /// a solid volume of 3,803.6 mm³ within 0.1% (±3.8 mm³).
    /// Plate: 20 × 20 × 10 = 4,000.0 mm³.
    /// Cylinder: π * (2.5)² * 10 = 62.5 * π ≈ 196.35 mm³.
    /// Expected remaining: 4,000 - 196.35 = 3,803.65 mm³.
    @Test func testGoldenVolume5mmThroughHole() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("plate-1"),
            name: "Plate 1",
            params: BoxParams(width: 20, depth: 20, height: 10)
        )
        document.addFeature(boxFeat)
        guard let faceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top topology reference on box")
            return
        }

        let holeFeat = try document.holeBody(
            targetSolidId: boxFeat.outputSolidId!,
            faceReference: faceRef,
            diameter: 5.0,
            depth: 10.0,
            isThrough: true
        )

        guard let holeSolidId = holeFeat.outputSolidId else {
            Issue.record("Missing hole outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("hole-vol-golden"), solidId: holeSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }

        let analysis = SolidVerifier.analyzeMesh(payload)
        guard let measurements = analysis.measurements else {
            Issue.record("Mesh analysis returned nil measurements")
            return
        }

        let expectedVolume = 3803.6
        let tolerance = 3.8 // 0.1% of 3803.6 mm³
        #expect(abs(measurements.volume - expectedVolume) <= tolerance, "Expected volume \(expectedVolume) ± \(tolerance), got \(measurements.volume)")
    }

    /// Blind hole volume test: A 5 mm diameter, 5 mm deep blind hole in a 20 × 20 × 10 mm plate
    /// leaves a solid volume of 3,901.8 mm³ within 0.1% (±3.9 mm³).
    /// Plate: 4,000.0 mm³.
    /// Removed cylinder: π * (2.5)² * 5 = 31.25 * π ≈ 98.17 mm³.
    /// Expected remaining: 4,000 - 98.17 = 3,901.83 mm³.
    @Test func testBlind5mmDepthHoleVolume() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("plate-2"),
            name: "Plate 2",
            params: BoxParams(width: 20, depth: 20, height: 10)
        )
        document.addFeature(boxFeat)
        guard let faceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top reference")
            return
        }

        let holeFeat = try document.holeBody(
            targetSolidId: boxFeat.outputSolidId!,
            faceReference: faceRef,
            diameter: 5.0,
            depth: 5.0,
            isThrough: false
        )

        guard let holeSolidId = holeFeat.outputSolidId else {
            Issue.record("Missing hole outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("hole-vol-blind"), solidId: holeSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }

        let analysis = SolidVerifier.analyzeMesh(payload)
        guard let measurements = analysis.measurements else {
            Issue.record("Mesh analysis returned nil measurements")
            return
        }

        let expectedVolume = 3901.8
        let tolerance = 3.9
        #expect(abs(measurements.volume - expectedVolume) <= tolerance, "Expected volume \(expectedVolume) ± \(tolerance), got \(measurements.volume)")
    }

    // MARK: - Counterbore & Countersink Hole Geometry

    @Test func testCounterboreHoleVolume() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("plate-cb"),
            name: "Plate CB",
            params: BoxParams(width: 20, depth: 20, height: 10)
        )
        document.addFeature(boxFeat)
        guard let faceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top reference")
            return
        }

        let holeFeat = try document.holeBody(
            targetSolidId: boxFeat.outputSolidId!,
            faceReference: faceRef,
            holeType: .counterbore,
            diameter: 3.4,
            depth: 10.0,
            isThrough: true,
            counterboreDiameter: 6.0,
            counterboreDepth: 3.0
        )

        guard let holeSolidId = holeFeat.outputSolidId else {
            Issue.record("Missing hole outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("hole-vol-cb"), solidId: holeSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }

        let analysis = SolidVerifier.analyzeMesh(payload)
        guard let measurements = analysis.measurements else {
            Issue.record("Mesh analysis returned nil measurements")
            return
        }

        // Base box is 4000 mm³. Counterbore removes extra volume compared to simple 3.4 mm hole.
        #expect(measurements.volume < 4000.0)
        #expect(measurements.volume > 3800.0)
    }

    @Test func testCountersinkHoleVolume() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("plate-cs"),
            name: "Plate CS",
            params: BoxParams(width: 20, depth: 20, height: 10)
        )
        document.addFeature(boxFeat)
        guard let faceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top reference")
            return
        }

        let holeFeat = try document.holeBody(
            targetSolidId: boxFeat.outputSolidId!,
            faceReference: faceRef,
            holeType: .countersink,
            diameter: 3.4,
            depth: 10.0,
            isThrough: true,
            countersinkDiameter: 6.5,
            countersinkAngle: 90.0
        )

        guard let holeSolidId = holeFeat.outputSolidId else {
            Issue.record("Missing hole outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("hole-vol-cs"), solidId: holeSolidId))
        guard let payload = res.value else {
            Issue.record("Tessellate request failed: \(String(describing: res.error))")
            return
        }

        let analysis = SolidVerifier.analyzeMesh(payload)
        guard let measurements = analysis.measurements else {
            Issue.record("Mesh analysis returned nil measurements")
            return
        }

        #expect(measurements.volume < 4000.0)
        #expect(measurements.volume > 3800.0)
    }

    // MARK: - Tapped Hole & ThreadMetadata

    @Test func testTappedHoleTapDrillAndThreadMetadata() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let boxFeat = Feature.makeBox(
            solidId: ObjectId("plate-tap"),
            name: "Plate Tap",
            params: BoxParams(width: 20, depth: 20, height: 10)
        )
        document.addFeature(boxFeat)
        guard let faceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top reference")
            return
        }

        let stdSize = try #require(HoleStandards.lookup(standard: .isoMetric, designation: "M5x0.8"))
        let threadMeta = ThreadMetadata(
            designation: stdSize.designation,
            pitch: stdSize.pitch,
            threadDepth: 10.0,
            threadClass: "6H"
        )

        let holeFeat = try document.holeBody(
            targetSolidId: boxFeat.outputSolidId!,
            faceReference: faceRef,
            holeType: .tapped,
            standard: .isoMetric,
            sizeDesignation: "M5x0.8",
            diameter: stdSize.tapDrillDiameter,
            depth: 10.0,
            isThrough: true,
            threadMetadata: threadMeta
        )

        guard case .hole(let data) = holeFeat.operation else {
            Issue.record("Feature is not a hole")
            return
        }

        #expect(data.holeType == .tapped)
        #expect(abs(data.diameter - 4.2) < 1e-4) // M5 tap drill is 4.2 mm
        #expect(data.threadMetadata?.designation == "M5")
        #expect(data.threadMetadata?.pitch == 0.8)
        #expect(data.threadMetadata?.threadClass == "6H")

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("hole-tap"), solidId: holeFeat.outputSolidId!))
        #expect(res.value != nil)
    }

    // MARK: - Validation & Edge Cases

    /// Edge breakthrough validation rejection: Hole breaking body edge is rejected.
    @Test func testEdgeBreakthroughValidationRejection() async throws {
        let engine = LocalKernelEngine()
        let plateSolidId = SolidId("plate-break")
        let boxRes = await engine.execute(.makeBox(
            jobId: JobId("box-1"),
            solidId: plateSolidId,
            params: BoxParams(width: 20, depth: 20, height: 10)
        ))
        #expect(boxRes.value != nil)

        let faceRef = TopologicalReference(
            sourceFeatureId: UUID(),
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")]
        )

        // On 20x20 plate centered at origin, top face extends from -10 to +10 in x and y.
        // A hole with diameter 6 mm (radius 3) placed at (9, 0) extends to x = 12, breaking the edge.
        let holeData = HoleFeatureData(
            targetSolidId: plateSolidId,
            faceReference: faceRef,
            points: [SIMD2<Double>(9.0, 0.0)],
            holeType: .simple,
            standard: .custom,
            diameter: 6.0,
            depth: 10.0,
            isThrough: true
        )

        let res = await engine.hole(
            solidId: SolidId("hole-res"),
            targetSolidId: plateSolidId,
            faceReference: faceRef,
            holeData: holeData
        )

        #expect(res.value == nil)
        #expect(res.error?.message.contains("Hole breaks through body edge") == true)
    }

    /// Blind hole depth exceeding body thickness is rejected.
    @Test func testBlindDepthExceedsBodyThicknessValidationRejection() async throws {
        let engine = LocalKernelEngine()
        let plateSolidId = SolidId("plate-thick")
        _ = await engine.execute(.makeBox(
            jobId: JobId("box-2"),
            solidId: plateSolidId,
            params: BoxParams(width: 20, depth: 20, height: 10)
        ))

        let faceRef = TopologicalReference(
            sourceFeatureId: UUID(),
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")]
        )

        // Plate thickness along normal is 10 mm. Blind depth 15 mm must be rejected.
        let holeData = HoleFeatureData(
            targetSolidId: plateSolidId,
            faceReference: faceRef,
            points: [SIMD2<Double>(0.0, 0.0)],
            holeType: .simple,
            standard: .custom,
            diameter: 5.0,
            depth: 15.0,
            isThrough: false
        )

        let res = await engine.hole(
            solidId: SolidId("hole-thick-res"),
            targetSolidId: plateSolidId,
            faceReference: faceRef,
            holeData: holeData
        )

        #expect(res.value == nil)
        #expect(res.error?.message.contains("Blind hole depth exceeds body thickness. Choose Through All to cut through the body.") == true)
    }

    /// Unrecognized standard table designations are rejected.
    @Test func testUnrecognizedStandardSizeRejection() async throws {
        let engine = LocalKernelEngine()
        let plateSolidId = SolidId("plate-std-err")
        _ = await engine.execute(.makeBox(
            jobId: JobId("box-3"),
            solidId: plateSolidId,
            params: BoxParams(width: 20, depth: 20, height: 10)
        ))

        let faceRef = TopologicalReference(
            sourceFeatureId: UUID(),
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")]
        )

        let holeData = HoleFeatureData(
            targetSolidId: plateSolidId,
            faceReference: faceRef,
            points: [SIMD2<Double>(0.0, 0.0)],
            holeType: .simple,
            standard: .isoMetric,
            sizeDesignation: "M999x99",
            diameter: 5.0,
            depth: 10.0,
            isThrough: true
        )

        let res = await engine.hole(
            solidId: SolidId("hole-std-res"),
            targetSolidId: plateSolidId,
            faceReference: faceRef,
            holeData: holeData
        )

        #expect(res.value == nil)
        #expect(res.error?.message.contains("Unknown standard hole size") == true)
    }

    // MARK: - Thread Metadata Persistence & Serialization

    @Test func testThreadMetadataSerializationRoundTrip() throws {
        let doc = DocumentModel(features: [])
        let boxFeat = Feature.makeBox(
            solidId: ObjectId("plate-save"),
            name: "Plate Save",
            params: BoxParams(width: 20, depth: 20, height: 10)
        )
        doc.addFeature(boxFeat)
        guard let faceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top reference")
            return
        }

        let threadMeta = ThreadMetadata(
            designation: "1/4\"-20 UNC",
            pitch: 1.27,
            threadDepth: 10.0,
            threadClass: "2B",
            isRightHand: true
        )

        _ = try doc.holeBody(
            targetSolidId: boxFeat.outputSolidId!,
            faceReference: faceRef,
            holeType: .tapped,
            standard: .unc,
            sizeDesignation: "1/4\"-20",
            diameter: 5.1,
            depth: 10.0,
            isThrough: true,
            threadMetadata: threadMeta
        )

        let encoded = try DocumentModelCoder.encode(document: doc)
        let restoredDoc = DocumentModel(features: [])
        try DocumentModelCoder.decode(into: restoredDoc, from: encoded)

        guard let restoredHole = restoredDoc.features.first(where: {
            if case .hole = $0.operation { return true }
            return false
        }) else {
            Issue.record("Decoded document missing hole feature")
            return
        }

        guard case .hole(let data) = restoredHole.operation else {
            Issue.record("Restored feature is not hole")
            return
        }

        #expect(data.holeType == .tapped)
        #expect(data.standard == .unc)
        #expect(data.sizeDesignation == "1/4\"-20")
        #expect(data.threadMetadata?.designation == "1/4\"-20 UNC")
        #expect(data.threadMetadata?.pitch == 1.27)
        #expect(data.threadMetadata?.threadClass == "2B")
        #expect(data.threadMetadata?.isRightHand == true)
    }

    // MARK: - Undo / Redo Lifecycle

    @Test func testUndoRedoLifecycle() throws {
        let doc = DocumentModel(features: [])
        let boxFeat = Feature.makeBox(
            solidId: ObjectId("plate-undo"),
            name: "Plate Undo",
            params: BoxParams(width: 20, depth: 20, height: 10)
        )
        doc.addFeature(boxFeat)
        doc.undoManager?.removeAllActions()
        guard let faceRef = boxFeat.generatedTopology["face:top"] else {
            Issue.record("Missing face:top reference")
            return
        }

        #expect(doc.features.count == 1)

        let holeFeat = try doc.holeBody(
            targetSolidId: boxFeat.outputSolidId!,
            faceReference: faceRef,
            diameter: 5.0,
            depth: 10.0,
            isThrough: true
        )

        #expect(doc.features.count == 2)
        #expect(doc.feature(for: boxFeat.id)?.isVisible == false)
        #expect(doc.feature(for: holeFeat.id)?.isVisible == true)
        #expect(doc.canUndo)

        doc.undo()

        #expect(doc.features.count == 1)
        #expect(doc.canRedo)
        #expect(doc.features.first?.id == boxFeat.id)
        #expect(doc.feature(for: boxFeat.id)?.isVisible == true)
        #expect(doc.feature(for: holeFeat.id) == nil)

        doc.redo()

        #expect(doc.features.count == 2)
        #expect(doc.features.last?.id == holeFeat.id)
        #expect(doc.feature(for: boxFeat.id)?.isVisible == false)
        #expect(doc.feature(for: holeFeat.id)?.isVisible == true)
    }
}
