import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct FeaturePatternTests {

    // MARK: - Definition of Done: Golden Volume Verification (BL-PRT-12, #299)

    /// Golden volume test: A 3-instance linear pattern of a 5 mm diameter cylinder
    /// (radius 2.5 mm, height 10 mm) yields 3 times the volume of a single cylinder
    /// within 0.1% tolerance.
    @Test func testGoldenVolume3InstanceLinearPattern() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-golden"),
            name: "Cylinder 1",
            params: CylinderParams(radius: 2.5, height: 10.0)
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        // Measure single cylinder volume
        await KernelRegeneration.regenerate(document: document, client: client)
        let singleRes = await client.request(.tessellate(jobId: JobId("cyl-golden-single"), solidId: cylSolidId))
        let singleAnalysis = try #require(singleRes.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let singleVolume = try #require(singleAnalysis.measurements?.volume)

        let patternFeat = try document.patternBody(
            targetSolidId: cylSolidId,
            patternType: .linear,
            count: 3,
            linearSpacing: 20.0,
            linearDirection: SIMD3<Double>(1.0, 0.0, 0.0)
        )
        guard let patternSolidId = patternFeat.outputSolidId else {
            Issue.record("Missing pattern outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("pattern-vol-golden"), solidId: patternSolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let measurements = try #require(analysis.measurements)

        let expectedVolume = singleVolume * 3.0
        let tolerance = expectedVolume * 0.001 // 0.1% tolerance
        #expect(abs(measurements.volume - expectedVolume) <= tolerance)
    }

    // MARK: - Edge Cases: Count 0 and Count 1

    @Test func testCountZeroRejection() async throws {
        let document = DocumentModel(features: [])
        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-zero"),
            name: "Cylinder Zero",
            params: CylinderParams(radius: 2.5, height: 10.0)
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        #expect(throws: DocumentMutationError.self) {
            try document.patternBody(
                targetSolidId: cylSolidId,
                patternType: .linear,
                count: 0
            )
        }

        let engine = LocalKernelEngine()
        _ = await engine.execute(.makeCylinder(
            jobId: JobId("cyl-zero-job"),
            solidId: cylSolidId,
            params: CylinderParams(radius: 2.5, height: 10.0)
        ))
        let patternParams = PatternParams(
            targetSolidId: cylSolidId,
            count: 0
        )
        let res = await engine.execute(.pattern(
            jobId: JobId("pattern-zero-job"),
            solidId: SolidId("pattern-zero"),
            params: patternParams
        ))
        #expect(res.value == nil)
        #expect(res.error?.code == KernelErrorCode.invalidParams)
    }

    @Test func testCountOneOutput() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-one"),
            name: "Cylinder One",
            params: CylinderParams(radius: 2.5, height: 10.0)
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        // Measure single cylinder volume
        await KernelRegeneration.regenerate(document: document, client: client)
        let singleRes = await client.request(.tessellate(jobId: JobId("cyl-one-single"), solidId: cylSolidId))
        let singleAnalysis = try #require(singleRes.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let singleVolume = try #require(singleAnalysis.measurements?.volume)

        let patternFeat = try document.patternBody(
            targetSolidId: cylSolidId,
            patternType: .linear,
            count: 1,
            linearSpacing: 20.0,
            linearDirection: SIMD3<Double>(1.0, 0.0, 0.0)
        )
        guard let patternSolidId = patternFeat.outputSolidId else {
            Issue.record("Missing pattern outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("pattern-one-job"), solidId: patternSolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let measurements = try #require(analysis.measurements)

        let expectedVolume = singleVolume * 1.0
        let tolerance = expectedVolume * 0.001
        #expect(abs(measurements.volume - expectedVolume) <= tolerance)
    }

    // MARK: - Instance Skipping

    @Test func testSkippedIndexExclusion() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-skip"),
            name: "Cylinder Skip",
            params: CylinderParams(radius: 2.5, height: 10.0)
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        // Measure single cylinder volume
        await KernelRegeneration.regenerate(document: document, client: client)
        let singleRes = await client.request(.tessellate(jobId: JobId("cyl-skip-single"), solidId: cylSolidId))
        let singleAnalysis = try #require(singleRes.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let singleVolume = try #require(singleAnalysis.measurements?.volume)

        // 3 instances with index 1 skipped -> only 2 instances rendered
        let patternFeat = try document.patternBody(
            targetSolidId: cylSolidId,
            patternType: .linear,
            count: 3,
            linearSpacing: 20.0,
            linearDirection: SIMD3<Double>(1.0, 0.0, 0.0),
            skippedIndices: [1]
        )
        guard let patternSolidId = patternFeat.outputSolidId else {
            Issue.record("Missing pattern outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("pattern-skip-job"), solidId: patternSolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let measurements = try #require(analysis.measurements)

        let expectedVolume = singleVolume * 2.0
        let tolerance = expectedVolume * 0.001
        #expect(abs(measurements.volume - expectedVolume) <= tolerance)
    }

    @Test func testOutOfBoundsSkippedIndicesTolerance() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-out-bounds"),
            name: "Cylinder Out Bounds",
            params: CylinderParams(radius: 2.5, height: 10.0)
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        // Measure single cylinder volume
        await KernelRegeneration.regenerate(document: document, client: client)
        let singleRes = await client.request(.tessellate(jobId: JobId("cyl-out-bounds-single"), solidId: cylSolidId))
        let singleAnalysis = try #require(singleRes.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let singleVolume = try #require(singleAnalysis.measurements?.volume)

        // Out-of-bounds skip indices (-1, 5, 99) should be ignored, yielding all 3 instances
        let patternFeat = try document.patternBody(
            targetSolidId: cylSolidId,
            patternType: .linear,
            count: 3,
            linearSpacing: 20.0,
            linearDirection: SIMD3<Double>(1.0, 0.0, 0.0),
            skippedIndices: [-1, 5, 99]
        )
        guard let patternSolidId = patternFeat.outputSolidId else {
            Issue.record("Missing pattern outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("pattern-out-bounds-job"), solidId: patternSolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let measurements = try #require(analysis.measurements)

        let expectedVolume = singleVolume * 3.0
        let tolerance = expectedVolume * 0.001
        #expect(abs(measurements.volume - expectedVolume) <= tolerance)
    }

    // MARK: - Circular Patterns: Partial Arc and Full Circle

    @Test func testCircularPatternPartialAngleSpacing() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        // Position cylinder at (30, 0, 0)
        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-circ-part"),
            name: "Cylinder Circ Part",
            params: CylinderParams(radius: 2.5, height: 10.0),
            transform: Transform(position: SIMD3<Float>(30, 0, 0))
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        // Measure single cylinder volume
        await KernelRegeneration.regenerate(document: document, client: client)
        let singleRes = await client.request(.tessellate(jobId: JobId("cyl-circ-part-single"), solidId: cylSolidId))
        let singleAnalysis = try #require(singleRes.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let singleVolume = try #require(singleAnalysis.measurements?.volume)

        // 3 instances spaced across 180 degrees -> angular step = 180 / (3 - 1) = 90 deg
        let patternFeat = try document.patternBody(
            targetSolidId: cylSolidId,
            patternType: .circular,
            count: 3,
            axisOrigin: SIMD3<Double>(0.0, 0.0, 0.0),
            axisDirection: SIMD3<Double>(0.0, 0.0, 1.0),
            totalAngle: 180.0,
            isFullCircle: false
        )
        guard let patternSolidId = patternFeat.outputSolidId else {
            Issue.record("Missing pattern outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("pattern-circ-part-job"), solidId: patternSolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let measurements = try #require(analysis.measurements)

        let expectedVolume = singleVolume * 3.0
        let tolerance = expectedVolume * 0.001
        #expect(abs(measurements.volume - expectedVolume) <= tolerance)
    }

    @Test func testCircularPatternFullCircleSpacing() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-circ-full"),
            name: "Cylinder Circ Full",
            params: CylinderParams(radius: 2.5, height: 10.0),
            transform: Transform(position: SIMD3<Float>(30, 0, 0))
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        // Measure single cylinder volume
        await KernelRegeneration.regenerate(document: document, client: client)
        let singleRes = await client.request(.tessellate(jobId: JobId("cyl-circ-full-single"), solidId: cylSolidId))
        let singleAnalysis = try #require(singleRes.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let singleVolume = try #require(singleAnalysis.measurements?.volume)

        // 4 instances full circle -> step = 360 / 4 = 90 deg
        let patternFeat = try document.patternBody(
            targetSolidId: cylSolidId,
            patternType: .circular,
            count: 4,
            axisOrigin: SIMD3<Double>(0.0, 0.0, 0.0),
            axisDirection: SIMD3<Double>(0.0, 0.0, 1.0),
            totalAngle: 360.0,
            isFullCircle: true
        )
        guard let patternSolidId = patternFeat.outputSolidId else {
            Issue.record("Missing pattern outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("pattern-circ-full-job"), solidId: patternSolidId))
        let analysis = try #require(res.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let measurements = try #require(analysis.measurements)

        let expectedVolume = singleVolume * 4.0
        let tolerance = expectedVolume * 0.001
        #expect(abs(measurements.volume - expectedVolume) <= tolerance)
    }

    // MARK: - Diagnostics: Overlap and Out-of-Bounds Warnings

    @Test func testOverlapWarningDetection() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-overlap"),
            name: "Cylinder Overlap",
            params: CylinderParams(radius: 2.5, height: 10.0)
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        // Cylinder diameter is 5.0 mm. Spacing of 3.0 mm along X causes overlap.
        let patternFeat = try document.patternBody(
            targetSolidId: cylSolidId,
            patternType: .linear,
            count: 3,
            linearSpacing: 3.0,
            linearDirection: SIMD3<Double>(1.0, 0.0, 0.0)
        )

        await KernelRegeneration.regenerate(document: document, client: client)

        let updatedPattern = document.feature(for: patternFeat.id)
        #expect(updatedPattern?.errorState != nil)
        #expect(updatedPattern?.errorState?.code == "pattern-overlap")
        #expect(updatedPattern?.errorState?.severity == FeatureErrorSeverity.warning)
    }

    @Test func testInstanceOutsideBodyWarning() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        // Base plate: 30 mm width
        let plateFeat = Feature.makeBox(
            solidId: ObjectId("plate-base"),
            name: "Plate Base",
            params: BoxParams(width: 30, depth: 30, height: 10)
        )
        document.addFeature(plateFeat)
        guard let plateSolidId = plateFeat.outputSolidId else {
            Issue.record("Missing plate outputSolidId")
            return
        }

        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-target"),
            name: "Cylinder Target",
            params: CylinderParams(radius: 2.5, height: 10.0)
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        // Pattern 4 instances @ 15 mm spacing -> max offset is 45 mm, far exceeding plate width (30 mm)
        let patternFeat = try document.patternBody(
            targetSolidId: cylSolidId,
            patternType: .linear,
            count: 4,
            linearSpacing: 15.0,
            linearDirection: SIMD3<Double>(1.0, 0.0, 0.0)
        )

        // Set baseBodySolidId on pattern params to trigger containment evaluation
        if case .pattern(var data) = patternFeat.operation {
            data.baseBodySolidId = plateSolidId
            var updatedFeat = patternFeat
            updatedFeat.operation = .pattern(data)
            document.updateFeature(updatedFeat)
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let updatedPattern = document.feature(for: patternFeat.id)
        #expect(updatedPattern?.errorState != nil)
        #expect(updatedPattern?.errorState?.code == "pattern-instance-outside")
        #expect(updatedPattern?.errorState?.severity == FeatureErrorSeverity.warning)
    }

    // MARK: - Undo / Redo Lifecycle

    @Test func testUndoRedoSingleStepLifecycle() throws {
        let doc = DocumentModel(features: [])
        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-undo"),
            name: "Cylinder Undo",
            params: CylinderParams(radius: 2.5, height: 10.0)
        )
        doc.addFeature(cylFeat)
        doc.undoManager?.removeAllActions()

        #expect(doc.features.count == 1)

        let patternFeat = try doc.patternBody(
            targetSolidId: cylFeat.outputSolidId!,
            patternType: .linear,
            count: 3,
            linearSpacing: 20.0,
            linearDirection: SIMD3<Double>(1.0, 0.0, 0.0)
        )

        #expect(doc.features.count == 2)
        #expect(doc.feature(for: cylFeat.id)?.isVisible == false)
        #expect(doc.feature(for: patternFeat.id)?.isVisible == true)
        #expect(doc.canUndo)

        doc.undo()

        #expect(doc.features.count == 1)
        #expect(doc.canRedo)
        #expect(doc.features.first?.id == cylFeat.id)
        #expect(doc.feature(for: cylFeat.id)?.isVisible == true)
        #expect(doc.feature(for: patternFeat.id) == nil)

        doc.redo()

        #expect(doc.features.count == 2)
        #expect(doc.features.last?.id == patternFeat.id)
        #expect(doc.feature(for: cylFeat.id)?.isVisible == false)
        #expect(doc.feature(for: patternFeat.id)?.isVisible == true)
    }

    // MARK: - Timeline Regeneration on Upstream Geometry Edit

    @Test func testTimelineRegenerationOnUpstreamRadiusEdit() async throws {
        let document = DocumentModel(features: [])
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let cylFeat = Feature.makeCylinder(
            solidId: ObjectId("cyl-regen"),
            name: "Cylinder Regen",
            params: CylinderParams(radius: 2.5, height: 10.0)
        )
        document.addFeature(cylFeat)
        guard let cylSolidId = cylFeat.outputSolidId else {
            Issue.record("Missing cylinder outputSolidId")
            return
        }

        let patternFeat = try document.patternBody(
            targetSolidId: cylSolidId,
            patternType: .linear,
            count: 3,
            linearSpacing: 20.0,
            linearDirection: SIMD3<Double>(1.0, 0.0, 0.0)
        )
        guard let patternSolidId = patternFeat.outputSolidId else {
            Issue.record("Missing pattern outputSolidId")
            return
        }

        await KernelRegeneration.regenerate(document: document, client: client)

        let initialRes = await client.request(.tessellate(jobId: JobId("regen-init"), solidId: patternSolidId))
        let initialAnalysis = try #require(initialRes.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let initialVolume = try #require(initialAnalysis.measurements?.volume)

        // Mutate upstream cylinder radius from 2.5 to 5.0 (2x radius -> 4x volume)
        document.setParam(id: cylSolidId, key: "radius", value: 5.0)

        await KernelRegeneration.regenerate(document: document, client: client)

        let updatedRes = await client.request(.tessellate(jobId: JobId("regen-updated"), solidId: patternSolidId))
        let updatedAnalysis = try #require(updatedRes.value.flatMap { SolidVerifier.analyzeMesh($0) })
        let updatedVolume = try #require(updatedAnalysis.measurements?.volume)

        // Volume should scale by (5.0 / 2.5)^2 = 4x
        let expectedRatio = 4.0
        let actualRatio = updatedVolume / initialVolume
        #expect(abs(actualRatio - expectedRatio) <= 0.01)
    }
}
