import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct RevolveFeatureTests {

    /// Helper to create a closed rectangle sketch on a specified plane.
    private func createRectangleSketch(
        in document: DocumentModel,
        planeName: String = "xy",
        minX: Double = 0,
        maxX: Double = 5,
        minY: Double = 0,
        maxY: Double = 10
    ) -> (feature: Feature, lines: [SketchEntity]) {
        let p1 = SIMD2<Double>(minX, minY)
        let p2 = SIMD2<Double>(maxX, minY)
        let p3 = SIMD2<Double>(maxX, maxY)
        let p4 = SIMD2<Double>(minX, maxY)

        let l1 = SketchEntity.line(start: p1, end: p2)
        let l2 = SketchEntity.line(start: p2, end: p3)
        let l3 = SketchEntity.line(start: p3, end: p4)
        let l4 = SketchEntity.line(start: p4, end: p1)

        let sketchFeature = document.addSketchFeature(planeName: planeName, entities: [l1, l2, l3, l4])
        return (sketchFeature, [l1, l2, l3, l4])
    }

    // MARK: - Definition of Done: 3. Volume Accuracy

    @Test func testRevolveCylinderVolumeFull360() async throws {
        let document = DocumentModel()
        let client = KernelClient(debounceDuration: .milliseconds(5))

        // Create 5 mm by 10 mm rectangle sketch on the XY plane
        let (sketch, lines) = createRectangleSketch(in: document, planeName: "xy", minX: 0, maxX: 5, minY: 0, maxY: 10)

        // Axis: the 10 mm long edge along the Y axis (from (0,10) to (0,0))
        let axisLine = lines[3]
        let axisRef = Reference.sketchEntity(featureId: sketch.id, entityId: axisLine.id)

        let revolveFeature = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .full,
            angle: 360.0,
            axisReference: axisRef
        )

        let solidId = try #require(revolveFeature.outputSolidId)
        await KernelRegeneration.regenerate(document: document, client: client)

        let res = await client.request(.tessellate(jobId: JobId("vol-test"), solidId: solidId))
        let payload = try #require(res.value)

        let analysis = SolidVerifier.analyzeMesh(payload)
        let measurements = try #require(analysis.measurements)

        // Volume = pi * r^2 * h = pi * 5^2 * 10 = 250 * pi ≈ 785.398 mm³
        let expectedVolume = 250.0 * Double.pi
        let volume = measurements.volume
        let tolerance = expectedVolume * 0.001 // 0.1% tolerance

        #expect(abs(volume - expectedVolume) <= tolerance)
        #expect(analysis.closed)
        #expect(analysis.positiveVolume)
    }

    // MARK: - Definition of Done: 1. Revolve Operation

    @Test func testRevolveFromSketchLine() async throws {
        let document = DocumentModel()
        let (sketch, lines) = createRectangleSketch(in: document, planeName: "xy", minX: 0, maxX: 10, minY: 0, maxY: 20)
        let axisRef = Reference.sketchEntity(featureId: sketch.id, entityId: lines[3].id)

        let feature = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .full,
            angle: 360.0,
            axisReference: axisRef
        )

        #expect(feature.outputSolidId != nil)
        guard case .revolve(let data) = feature.operation else {
            Issue.record("Expected .revolve feature operation")
            return
        }
        #expect(data.mode == .full)
        #expect(data.sketchFeatureId == sketch.id)
        #expect(data.axisReference == axisRef)
    }

    @Test func testRevolveFromDatumAxis() async throws {
        let document = DocumentModel()
        // Rectangle offset from origin
        let (sketch, _) = createRectangleSketch(in: document, planeName: "xy", minX: 5, maxX: 10, minY: 0, maxY: 10)
        let datumAxis = document.addDatumAxisFeature(data: DatumAxisFeatureData(mode: .preset, presetName: "Y"))
        let axisRef = Reference.feature(datumAxis.id)

        let feature = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .full,
            angle: 360.0,
            axisReference: axisRef
        )

        #expect(feature.outputSolidId != nil)
        guard case .revolve(let data) = feature.operation else {
            Issue.record("Expected .revolve feature operation")
            return
        }
        #expect(data.axisReference == axisRef)
        #expect(data.axisDirection == SIMD3<Float>(0, 1, 0))
    }

    @Test func testRevolveFromModelEdge() async throws {
        let document = DocumentModel()
        // Create an initial box solid from x=0..10, y=0..20, z=0..10
        let boxSolidId = ObjectId("box-1")
        _ = document.addObject(
            boxSolidId,
            def: .box(BoxParams(width: 10, depth: 20, height: 10))
        )
        guard let boxFeature = document.feature(for: boxSolidId) else {
            Issue.record("Missing box feature")
            return
        }

        // Create a sketch on the XY plane
        let (sketch, _) = createRectangleSketch(in: document, planeName: "xy", minX: 2, maxX: 6, minY: 0, maxY: 8)

        // Reference an edge of the box along Y axis
        let topRef = TopologicalReference(
            id: UUID(),
            sourceFeatureId: boxFeature.id,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:bottom-left")]
        )
        let axisRef = Reference.edge(topRef)

        // Revolve about that edge
        let feature = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .angle,
            angle: 180.0,
            axisReference: axisRef
        )

        #expect(feature.outputSolidId != nil)
    }

    // MARK: - Definition of Done: 2. Four Modes

    @Test func testRevolveModes() async throws {
        let document = DocumentModel()
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let (sketch, lines) = createRectangleSketch(in: document, planeName: "xy", minX: 0, maxX: 5, minY: 0, maxY: 10)
        let axisRef = Reference.sketchEntity(featureId: sketch.id, entityId: lines[3].id)
        let fullVolume = 250.0 * Double.pi

        // Angle Mode (90° = 25% volume)
        let fAngle = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .angle,
            angle: 90.0,
            axisReference: axisRef
        )
        let sAngle = try #require(fAngle.outputSolidId)
        await KernelRegeneration.regenerate(document: document, client: client)
        let resAngle = await client.request(.tessellate(jobId: JobId("angle-mode"), solidId: sAngle))
        let payloadAngle = try #require(resAngle.value)
        let analysisAngle = SolidVerifier.analyzeMesh(payloadAngle)
        let volAngle = try #require(analysisAngle.measurements?.volume)
        #expect(abs(volAngle - (fullVolume * 0.25)) < fullVolume * 0.05)
        #expect(analysisAngle.closed)

        // Symmetric Mode (180° = 50% volume)
        let fSym = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .symmetric,
            angle: 180.0,
            axisReference: axisRef
        )
        let sSym = try #require(fSym.outputSolidId)
        await KernelRegeneration.regenerate(document: document, client: client)
        let resSym = await client.request(.tessellate(jobId: JobId("sym-mode"), solidId: sSym))
        let payloadSym = try #require(resSym.value)
        let analysisSym = SolidVerifier.analyzeMesh(payloadSym)
        let volSym = try #require(analysisSym.measurements?.volume)
        #expect(abs(volSym - (fullVolume * 0.50)) < fullVolume * 0.05)
        #expect(analysisSym.closed)

        // Two-Direction Mode (45° + 45° = 25% volume)
        let fTwoDir = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .twoDirection,
            angle: 45.0,
            angle2: 45.0,
            axisReference: axisRef
        )
        let sTwoDir = try #require(fTwoDir.outputSolidId)
        await KernelRegeneration.regenerate(document: document, client: client)
        let resTwoDir = await client.request(.tessellate(jobId: JobId("twodir-mode"), solidId: sTwoDir))
        let payloadTwoDir = try #require(resTwoDir.value)
        let analysisTwoDir = SolidVerifier.analyzeMesh(payloadTwoDir)
        let volTwoDir = try #require(analysisTwoDir.measurements?.volume)
        #expect(abs(volTwoDir - (fullVolume * 0.25)) < fullVolume * 0.05)
        #expect(analysisTwoDir.closed)
    }

    // MARK: - Definition of Done: 5. Feature History & Undo

    @Test func testRevolveUndoRedo() throws {
        let document = DocumentModel()

        let (sketch, lines) = createRectangleSketch(in: document, planeName: "xy", minX: 0, maxX: 5, minY: 0, maxY: 10)
        let axisRef = Reference.sketchEntity(featureId: sketch.id, entityId: lines[3].id)

        document.undoManager = UndoManager()
        let initialCount = document.features.count
        let feature = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .full,
            angle: 360.0,
            axisReference: axisRef
        )

        #expect(document.features.count == initialCount + 1)
        #expect(document.objects.contains { $0.id == feature.outputSolidId })

        // Single undo removes revolve solid and feature
        document.undoManager?.undo()
        #expect(document.features.count == initialCount)
        #expect(!document.objects.contains { $0.id == feature.outputSolidId })

        // Redo restores it
        document.undoManager?.redo()
        #expect(document.features.count == initialCount + 1)
        #expect(document.objects.contains { $0.id == feature.outputSolidId })
    }

    // MARK: - Definition of Done: 6. Edge Cases

    @Test func testRevolveRejectsAxisCrossingProfile() {
        let document = DocumentModel()
        // Rectangle from x = -2 to x = 4 crosses x = 0
        let (sketch, _) = createRectangleSketch(in: document, planeName: "xy", minX: -2, maxX: 4, minY: 0, maxY: 10)
        let datumAxis = document.addDatumAxisFeature(data: DatumAxisFeatureData(mode: .preset, presetName: "Y"))
        let axisRef = Reference.feature(datumAxis.id)

        #expect(throws: Error.self) {
            try document.revolveSketch(
                sketchFeatureId: sketch.id,
                mode: .full,
                angle: 360.0,
                axisReference: axisRef
            )
        }

        do {
            try document.revolveSketch(
                sketchFeatureId: sketch.id,
                mode: .full,
                angle: 360.0,
                axisReference: axisRef
            )
            Issue.record("Expected error for axis crossing profile")
        } catch {
            let msg = error.localizedDescription
            #expect(msg.contains("Revolve axis crosses the sketch profile"))
        }
    }

    @Test func testRevolveAcceptsProfileEdgeOnAxis() throws {
        let document = DocumentModel()
        // Rectangle from x = 0 to x = 5 with long edge on x = 0 (Y axis)
        let (sketch, lines) = createRectangleSketch(in: document, planeName: "xy", minX: 0, maxX: 5, minY: 0, maxY: 10)
        let axisRef = Reference.sketchEntity(featureId: sketch.id, entityId: lines[3].id)

        let feature = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .full,
            angle: 360.0,
            axisReference: axisRef
        )
        #expect(feature.outputSolidId != nil)
    }

    @Test func testRevolveRejectsInvalidAngles() {
        let document = DocumentModel()
        let (sketch, lines) = createRectangleSketch(in: document, planeName: "xy", minX: 0, maxX: 5, minY: 0, maxY: 10)
        let axisRef = Reference.sketchEntity(featureId: sketch.id, entityId: lines[3].id)

        // Angle 0 degrees
        #expect(throws: Error.self) {
            try document.revolveSketch(
                sketchFeatureId: sketch.id,
                mode: .angle,
                angle: 0.0,
                axisReference: axisRef
            )
        }

        // Angle > 360 degrees
        #expect(throws: Error.self) {
            try document.revolveSketch(
                sketchFeatureId: sketch.id,
                mode: .angle,
                angle: 361.0,
                axisReference: axisRef
            )
        }

        // Two-Direction angle2 <= 0
        #expect(throws: Error.self) {
            try document.revolveSketch(
                sketchFeatureId: sketch.id,
                mode: .twoDirection,
                angle: 45.0,
                angle2: 0.0,
                axisReference: axisRef
            )
        }
    }

    @Test func testRevolveRejectsOpenProfile() {
        let document = DocumentModel()
        // Open sketch: two disconnected lines
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(5, 0))
        let l2 = SketchEntity.line(start: SIMD2(5, 0), end: SIMD2(5, 10))
        let openSketch = document.addSketchFeature(planeName: "xy", entities: [l1, l2])
        let axisRef = Reference.sketchEntity(featureId: openSketch.id, entityId: l1.id)

        #expect(throws: Error.self) {
            try document.revolveSketch(
                sketchFeatureId: openSketch.id,
                mode: .full,
                angle: 360.0,
                axisReference: axisRef
            )
        }
    }

    @Test func testRevolveRegenerationKeepsAxisReference() async throws {
        let document = DocumentModel()
        let client = KernelClient(debounceDuration: .milliseconds(5))

        let (sketch, lines) = createRectangleSketch(in: document, planeName: "xy", minX: 0, maxX: 5, minY: 0, maxY: 10)
        let axisRef = Reference.sketchEntity(featureId: sketch.id, entityId: lines[3].id)

        let revolveFeature = try document.revolveSketch(
            sketchFeatureId: sketch.id,
            mode: .full,
            angle: 360.0,
            axisReference: axisRef
        )

        // Modify rectangle: change maxX to 8
        let updatedLines = [
            SketchEntity.line(id: lines[0].id, start: SIMD2(0, 0), end: SIMD2(8, 0)),
            SketchEntity.line(id: lines[1].id, start: SIMD2(8, 0), end: SIMD2(8, 10)),
            SketchEntity.line(id: lines[2].id, start: SIMD2(8, 10), end: SIMD2(0, 10)),
            SketchEntity.line(id: lines[3].id, start: SIMD2(0, 10), end: SIMD2(0, 0))
        ]
        var updatedSketch = sketch
        updatedSketch.operation = .sketch(SketchFeatureData(planeName: "xy", entities: updatedLines))
        _ = document.updateFeature(updatedSketch)

        // Run regeneration
        await KernelRegeneration.regenerate(document: document, client: client)

        guard let regenerated = document.feature(for: revolveFeature.id),
              case .revolve(let revData) = regenerated.operation else {
            Issue.record("Revolve feature not found or not .revolve")
            return
        }

        // Verify axisReference is retained
        #expect(revData.axisReference == axisRef)
        // Verify profile updated to width 8
        let maxPtX = revData.profile?.points.map(\.x).max() ?? 0
        #expect(abs(maxPtX - 8.0) < 0.1)
    }
}
