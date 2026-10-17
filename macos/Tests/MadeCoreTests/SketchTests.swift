import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchTests {

    @Test func testSketchEntityFactoriesAndAccessors() {
        // Line
        var line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 20))
        #expect(line.kind == "line")
        #expect(line.startPoint == SIMD2(0, 0))
        #expect(line.endPoint == SIMD2(10, 20))
        #expect(line.centerPoint == nil)

        line.startPoint = SIMD2(5, 5)
        #expect(line.startPoint == SIMD2(5, 5))
        line.endPoint = SIMD2(15, 25)
        #expect(line.endPoint == SIMD2(15, 25))

        // Arc
        var arc = SketchEntity.arc(
            start: SIMD2(10, 0),
            end: SIMD2(0, 10),
            center: SIMD2(0, 0),
            clockwise: false
        )
        #expect(arc.kind == "arc")
        #expect(arc.startPoint == SIMD2(10, 0))
        #expect(arc.endPoint == SIMD2(0, 10))
        #expect(arc.centerPoint == SIMD2(0, 0))
        #expect(arc.isClockwise == false)
        #expect(arc.radius == 10.0)

        arc.isClockwise = true
        #expect(arc.isClockwise == true)
        arc.centerPoint = SIMD2(1, 1)
        #expect(arc.centerPoint == SIMD2(1, 1))

        // Circle
        var circle = SketchEntity.circle(center: SIMD2(2, 3), radius: 15.0)
        #expect(circle.kind == "circle")
        #expect(circle.centerPoint == SIMD2(2, 3))
        #expect(circle.radius == 15.0)

        circle.centerPoint = SIMD2(4, 5)
        #expect(circle.centerPoint == SIMD2(4, 5))
        circle.radius = 20.0
        #expect(circle.radius == 20.0)
    }

    @Test func testZeroLengthLineRejection() {
        let line = SketchEntity.line(start: SIMD2(10, 10), end: SIMD2(10, 10))
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.build(from: [line])
        }
    }

    @Test func testDegenerateArcRejection() {
        // Coincident start and end
        let arc1 = SketchEntity.arc(
            start: SIMD2(5, 5),
            end: SIMD2(5, 5),
            center: SIMD2(0, 0)
        )
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.build(from: [arc1])
        }

        // Zero radius
        let arc2 = SketchEntity.arc(
            start: SIMD2(0, 0),
            end: SIMD2(0.000001, 0),
            center: SIMD2(0, 0)
        )
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.build(from: [arc2])
        }
    }

    @Test func testEmptySketchRejection() {
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.build(from: [])
        }
    }

    @Test func testOpenProfileDetection() {
        // Two lines with a gap
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let l2 = SketchEntity.line(start: SIMD2(10, 0), end: SIMD2(10, 10))
        // Does not close back to (0, 0)
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.build(from: [l1, l2])
        }
    }

    @Test func testSingleCircleDiscretization() throws {
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 10.0)
        let profile = try SketchProfileBuilder.build(from: [circle])
        #expect(profile.plane == .xy)
        #expect(profile.points.count == 32)

        for pt in profile.points {
            let r = hypot(pt.x, pt.y)
            #expect(abs(r - 10.0) < 1e-4)
        }
    }

    @Test func testClosedRectangleDiscretization() throws {
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let l2 = SketchEntity.line(start: SIMD2(20, 0), end: SIMD2(20, 10))
        let l3 = SketchEntity.line(start: SIMD2(20, 10), end: SIMD2(0, 10))
        let l4 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(0, 0))

        let profile = try SketchProfileBuilder.build(from: [l1, l2, l3, l4])
        #expect(profile.plane == .xy)
        #expect(profile.points.count == 4)
    }

    @Test func testMixedLineAndArcClosedProfile() throws {
        // Slot shape: two lines and two half circles
        let arc1 = SketchEntity.arc(
            start: SIMD2(0, 10),
            end: SIMD2(0, -10),
            center: SIMD2(0, 0),
            clockwise: false
        )
        let line1 = SketchEntity.line(start: SIMD2(0, -10), end: SIMD2(20, -10))
        let arc2 = SketchEntity.arc(
            start: SIMD2(20, -10),
            end: SIMD2(20, 10),
            center: SIMD2(20, 0),
            clockwise: false
        )
        let line2 = SketchEntity.line(start: SIMD2(20, 10), end: SIMD2(0, 10))

        let profile = try SketchProfileBuilder.build(from: [arc1, line1, arc2, line2])
        #expect(profile.plane == .xy)
        #expect(profile.points.count > 10)
    }

    @Test func testExtrudeShapeNodeEvaluation() async throws {
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 10.0)
        let profile = try SketchProfileBuilder.build(from: [circle])

        let kernel = KernelClient(engine: LocalKernelEngine(), debounceDuration: .milliseconds(5))
        let shape = ShapeNode.extrude(profile: profile, distance: 20.0, centered: false)
        let result = await kernel.request(.evaluateShape(jobId: JobId("extrude-1"), solidId: SolidId("s-extrude"), shape: shape))
        let payload = try #require(result.value)

        #expect(payload.triangleCount > 0)
        #expect(payload.positions.count > 0)
    }

    @MainActor
    @Test func testDocumentModelSketchAndExtrude() throws {
        let doc = DocumentModel()
        let initialFeatureCount = doc.features.count

        // Add sketch feature
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let l2 = SketchEntity.line(start: SIMD2(20, 0), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(0, 20))
        let l4 = SketchEntity.line(start: SIMD2(0, 20), end: SIMD2(0, 0))

        let sketchFeat = doc.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        #expect(doc.features.count == initialFeatureCount + 1)
        #expect(sketchFeat.name.contains("Sketch"))

        // Extrude sketch
        let extrudeFeat = try doc.extrudeSketch(sketchFeatureId: sketchFeat.id, distance: 30.0, isSymmetric: false)
        #expect(doc.features.count == initialFeatureCount + 2)
        guard let solidId = extrudeFeat.outputSolidId else {
            Issue.record("Expected outputSolidId on extrude feature")
            return
        }

        let sceneObj = try #require(doc.objects.first(where: { $0.id == solidId }))
        if case .extrude(let params) = sceneObj.def {
            #expect(params.distance == 30.0)
            #expect(params.sketchFeatureId == sketchFeat.id)
            #expect(params.profile.points.count == 4)
        } else {
            Issue.record("Expected .extrude def on scene object")
        }

        // Test Undo & Redo
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let lNew = SketchEntity.line(start: SIMD2(100, 100), end: SIMD2(120, 100))
        _ = doc.addSketchEntity(to: sketchFeat.id, entity: lNew)
        guard case .sketch(let dataAfterAdd) = doc.feature(for: sketchFeat.id)?.operation else {
            Issue.record("Expected sketch feature")
            return
        }
        #expect(dataAfterAdd.entities.count == 5)

        undoManager.undo()
        guard case .sketch(let dataAfterUndo) = doc.feature(for: sketchFeat.id)?.operation else {
            Issue.record("Expected sketch feature")
            return
        }
        #expect(dataAfterUndo.entities.count == 4)

        undoManager.redo()
        guard case .sketch(let dataAfterRedo) = doc.feature(for: sketchFeat.id)?.operation else {
            Issue.record("Expected sketch feature")
            return
        }
        #expect(dataAfterRedo.entities.count == 5)
    }

    @MainActor
    @Test func testDocumentDataRoundTrip() throws {
        let doc = DocumentModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let l2 = SketchEntity.line(start: SIMD2(10, 0), end: SIMD2(10, 10))
        let l3 = SketchEntity.line(start: SIMD2(10, 10), end: SIMD2(0, 10))
        let l4 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(0, 0))
        let sketchFeat = doc.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        _ = try doc.extrudeSketch(sketchFeatureId: sketchFeat.id, distance: 15.0)

        let encoded = try DocumentModelCoder.encode(document: doc)
        let decoded = try DocumentModelCoder.decode(from: encoded)

        guard let features = decoded.features else {
            Issue.record("Expected features in decoded DocumentData")
            return
        }
        #expect(features.count == doc.features.count)

        let sketchFeatureData = features.first { $0.id == sketchFeat.id }
        guard let sketchFeatureData, case .sketch(let sketchData) = sketchFeatureData.operation else {
            Issue.record("Expected sketch feature after decode")
            return
        }
        #expect(sketchData.entities.count == 4)

        let targetDoc = DocumentModel(features: [])
        try DocumentModelCoder.decode(into: targetDoc, from: encoded)
        #expect(targetDoc.features.count == doc.features.count)
        #expect(targetDoc.objects.count == doc.objects.count)

        let extrudeObj = targetDoc.objects.first(where: {
            if case .extrude = $0.def { return true }
            return false
        })
        #expect(extrudeObj != nil)
    }

    @MainActor
    @Test func testIncrementalRegeneration() async throws {
        let doc = DocumentModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let l2 = SketchEntity.line(start: SIMD2(10, 0), end: SIMD2(10, 10))
        let l3 = SketchEntity.line(start: SIMD2(10, 10), end: SIMD2(0, 10))
        let l4 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(0, 0))
        let sketchFeat = doc.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        let extrudeFeat = try doc.extrudeSketch(sketchFeatureId: sketchFeat.id, distance: 10.0)

        let kernel = KernelClient(engine: LocalKernelEngine(), debounceDuration: .milliseconds(5))

        // Initial regeneration
        await KernelRegeneration.regenerate(features: doc.activeFeatures, in: doc, client: kernel)
        let initialExtrude = doc.feature(for: extrudeFeat.id)
        #expect(initialExtrude?.errorState == nil)

        // Modify sketch entity: stretch rectangle from width 10 to 50
        var modifiedL1 = l1
        modifiedL1.endPoint = SIMD2(50, 0)
        var modifiedL2 = l2
        modifiedL2.startPoint = SIMD2(50, 0)
        modifiedL2.endPoint = SIMD2(50, 10)
        var modifiedL3 = l3
        modifiedL3.startPoint = SIMD2(50, 10)

        _ = doc.updateSketchEntity(in: sketchFeat.id, entity: modifiedL1)
        _ = doc.updateSketchEntity(in: sketchFeat.id, entity: modifiedL2)
        _ = doc.updateSketchEntity(in: sketchFeat.id, entity: modifiedL3)

        // Regenerate after sketch edit
        await KernelRegeneration.regenerate(features: doc.activeFeatures, in: doc, client: kernel)

        // Check updated extrude profile
        let updatedExtrude = doc.feature(for: extrudeFeat.id)
        if case .extrude(let extrudeData) = updatedExtrude?.operation {
            #expect(extrudeData.profile?.points.contains(SIMD2(50, 0)) == true)
        } else {
            Issue.record("Expected extrude feature with updated profile")
        }

        // Now break the sketch (make profile open by moving endpoint away)
        var brokenL1 = modifiedL1
        brokenL1.endPoint = SIMD2(100, 100) // leaves gap with l2 at (50, 0)
        _ = doc.updateSketchEntity(in: sketchFeat.id, entity: brokenL1)

        await KernelRegeneration.regenerate(features: doc.activeFeatures, in: doc, client: kernel)
        let brokenExtrude = doc.feature(for: extrudeFeat.id)
        #expect(brokenExtrude?.errorState != nil)
        #expect(brokenExtrude?.errorState?.code == "sketch-error")
    }
}
