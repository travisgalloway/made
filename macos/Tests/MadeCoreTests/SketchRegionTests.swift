import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchRegionTests {

    // MARK: - 1. Closed loops and their intersections compute regions

    @Test func testSingleLoopRegionDetection() throws {
        // 1. Single rectangle
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let l2 = SketchEntity.line(start: SIMD2(20, 0), end: SIMD2(20, 10))
        let l3 = SketchEntity.line(start: SIMD2(20, 10), end: SIMD2(0, 10))
        let l4 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(0, 0))

        let rectRegions = try SketchRegionDetector.detectRegions(from: [l1, l2, l3, l4])
        #expect(rectRegions.count == 1)
        let rect = rectRegions[0]
        #expect(rect.outerLoop.count == 4)
        #expect(rect.innerLoops.isEmpty)
        #expect(abs(rect.area - 200.0) < 1e-2)

        // 2. Single circle
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 10.0)
        let circleRegions = try SketchRegionDetector.detectRegions(from: [circle])
        #expect(circleRegions.count == 1)
        let cRegion = circleRegions[0]
        #expect(cRegion.outerLoop.count == 32)
        #expect(cRegion.innerLoops.isEmpty)
        #expect(abs(cRegion.area - Float.pi * 100.0) < 2.0)

        // 3. Slot shape (two arcs, two lines)
        let arc1 = SketchEntity.arc(start: SIMD2(0, 10), end: SIMD2(0, -10), center: SIMD2(0, 0), clockwise: false)
        let line1 = SketchEntity.line(start: SIMD2(0, -10), end: SIMD2(20, -10))
        let arc2 = SketchEntity.arc(start: SIMD2(20, -10), end: SIMD2(20, 10), center: SIMD2(20, 0), clockwise: false)
        let line2 = SketchEntity.line(start: SIMD2(20, 10), end: SIMD2(0, 10))

        let slotRegions = try SketchRegionDetector.detectRegions(from: [arc1, line1, arc2, line2])
        #expect(slotRegions.count == 1)
        #expect(slotRegions[0].innerLoops.isEmpty)
        #expect(slotRegions[0].area > 100.0)
    }

    @Test func testIntersectingLoopsRegionDecomposition() throws {
        // Rectangle [-10, 10] x [-10, 10] bisected by a vertical division line at x = 0
        let l1 = SketchEntity.line(start: SIMD2(-10, -10), end: SIMD2(10, -10))
        let l2 = SketchEntity.line(start: SIMD2(10, -10), end: SIMD2(10, 10))
        let l3 = SketchEntity.line(start: SIMD2(10, 10), end: SIMD2(-10, 10))
        let l4 = SketchEntity.line(start: SIMD2(-10, 10), end: SIMD2(-10, -10))
        let divider = SketchEntity.line(start: SIMD2(0, -10), end: SIMD2(0, 10))

        let regions = try SketchRegionDetector.detectRegions(from: [l1, l2, l3, l4, divider])
        #expect(regions.count == 2)
        let totalArea = regions.reduce(Float(0)) { $0 + $1.area }
        #expect(abs(totalArea - 400.0) < 1.0)
        for r in regions {
            #expect(abs(r.area - 200.0) < 1.0)
            #expect(r.innerLoops.isEmpty)
        }

        // Two overlapping circles: center (-4, 0), R = 8 and center (4, 0), R = 8
        let c1 = SketchEntity.circle(center: SIMD2(-4, 0), radius: 8.0)
        let c2 = SketchEntity.circle(center: SIMD2(4, 0), radius: 8.0)
        let circleIntersections = try SketchRegionDetector.detectRegions(from: [c1, c2])
        #expect(circleIntersections.count == 3)
        for r in circleIntersections {
            #expect(r.area > 0)
            #expect(r.innerLoops.isEmpty)
        }
    }

    // MARK: - 2. Nested loops become holes

    @Test func testNestedLoopBecomesHole() throws {
        // Outer rectangle [-20, 20] x [-20, 20], inner circle at (0, 0), radius 5
        let l1 = SketchEntity.line(start: SIMD2(-20, -20), end: SIMD2(20, -20))
        let l2 = SketchEntity.line(start: SIMD2(20, -20), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(-20, 20))
        let l4 = SketchEntity.line(start: SIMD2(-20, 20), end: SIMD2(-20, -20))
        let hole = SketchEntity.circle(center: SIMD2(0, 0), radius: 5.0)

        let regions = try SketchRegionDetector.detectRegions(from: [l1, l2, l3, l4, hole])
        #expect(regions.count == 2)

        // The outer region (largest area) should have 1 hole
        let outer = regions[0]
        #expect(outer.innerLoops.count == 1)
        let expectedHoleArea = Float.pi * 25.0
        let expectedOuterArea = 1600.0 - expectedHoleArea
        #expect(abs(outer.area - expectedOuterArea) < 2.0)

        // The inner region should be solid with 0 holes
        let inner = regions[1]
        #expect(inner.innerLoops.isEmpty)
        #expect(abs(inner.area - expectedHoleArea) < 2.0)
    }

    @Test func testAnnulusAndMultiHoleRegions() throws {
        // Annulus: Concentric circles with R = 20 and R = 10
        let cOuter = SketchEntity.circle(center: SIMD2(0, 0), radius: 20.0)
        let cInner = SketchEntity.circle(center: SIMD2(0, 0), radius: 10.0)

        let annulusRegions = try SketchRegionDetector.detectRegions(from: [cOuter, cInner])
        #expect(annulusRegions.count == 2)

        let outerAnnulus = annulusRegions[0]
        #expect(outerAnnulus.innerLoops.count == 1)
        let expectedAnnulusArea = Float.pi * (400.0 - 100.0)
        #expect(abs(outerAnnulus.area - expectedAnnulusArea) < 3.0)

        let innerCircle = annulusRegions[1]
        #expect(innerCircle.innerLoops.isEmpty)
        #expect(abs(innerCircle.area - Float.pi * 100.0) < 2.0)

        // Multi-hole plate: Rectangle [-30, 30] x [-20, 20] with 2 circular holes
        let pl1 = SketchEntity.line(start: SIMD2(-30, -20), end: SIMD2(30, -20))
        let pl2 = SketchEntity.line(start: SIMD2(30, -20), end: SIMD2(30, 20))
        let pl3 = SketchEntity.line(start: SIMD2(30, 20), end: SIMD2(-30, 20))
        let pl4 = SketchEntity.line(start: SIMD2(-30, 20), end: SIMD2(-30, -20))
        let h1 = SketchEntity.circle(center: SIMD2(-15, 0), radius: 5.0)
        let h2 = SketchEntity.circle(center: SIMD2(15, 0), radius: 5.0)

        let plateRegions = try SketchRegionDetector.detectRegions(from: [pl1, pl2, pl3, pl4, h1, h2])
        #expect(plateRegions.count == 3)

        let plate = plateRegions[0]
        #expect(plate.innerLoops.count == 2)
        let expectedPlateArea = 2400.0 - 2.0 * (Float.pi * 25.0)
        #expect(abs(plate.area - expectedPlateArea) < 3.0)
    }

    @Test func testConcentricNestingHoleHierarchy() throws {
        // Bullseye: 3 concentric circles: R = 30, R = 20, R = 10
        let c1 = SketchEntity.circle(center: SIMD2(0, 0), radius: 30.0)
        let c2 = SketchEntity.circle(center: SIMD2(0, 0), radius: 20.0)
        let c3 = SketchEntity.circle(center: SIMD2(0, 0), radius: 10.0)

        let regions = try SketchRegionDetector.detectRegions(from: [c1, c2, c3])
        #expect(regions.count == 3)

        // Region 1 (outermost band): outer = C1, hole = C2
        let r1 = regions[0]
        #expect(r1.innerLoops.count == 1)
        let exp1 = Float.pi * (900.0 - 400.0)
        #expect(abs(r1.area - exp1) < 4.0)

        // Region 2 (middle band): outer = C2, hole = C3
        let r2 = regions[1]
        #expect(r2.innerLoops.count == 1)
        let exp2 = Float.pi * (400.0 - 100.0)
        #expect(abs(r2.area - exp2) < 3.0)

        // Region 3 (central disk): outer = C3, no holes
        let r3 = regions[2]
        #expect(r3.innerLoops.isEmpty)
        let exp3 = Float.pi * 100.0
        #expect(abs(r3.area - exp3) < 2.0)
    }

    @Test func testExtrudeRegionWithHoles() async throws {
        // Extrude plate with hole via ShapeEvaluator and KernelClient
        let l1 = SketchEntity.line(start: SIMD2(-20, -20), end: SIMD2(20, -20))
        let l2 = SketchEntity.line(start: SIMD2(20, -20), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(-20, 20))
        let l4 = SketchEntity.line(start: SIMD2(-20, 20), end: SIMD2(-20, -20))
        let hole = SketchEntity.circle(center: SIMD2(0, 0), radius: 6.0)

        let regions = try SketchRegionDetector.detectRegions(from: [l1, l2, l3, l4, hole])
        let regionWithHole = try #require(regions.first(where: { !$0.innerLoops.isEmpty }))
        let profile = regionWithHole.toProfile(plane: .xy)
        #expect(profile.holes.count == 1)

        let shape = ShapeNode.extrude(profile: profile, distance: 10.0, centered: false)
        let kernel = KernelClient(engine: LocalKernelEngine(), debounceDuration: .milliseconds(5))
        let result = await kernel.request(.evaluateShape(
            jobId: JobId("extrude-hole-\(UUID().uuidString)"),
            solidId: SolidId("s-hole"),
            shape: shape
        ))
        let payload = try #require(result.value)
        #expect(payload.triangleCount > 0)
        #expect(payload.positions.count > 0)
    }

    // MARK: - 3. Hover highlights a region for extrude selection

    @Test func testPointInRegionContainment() throws {
        // Region: [-20, 20] x [-20, 20] with hole at (0,0), radius 10
        let l1 = SketchEntity.line(start: SIMD2(-20, -20), end: SIMD2(20, -20))
        let l2 = SketchEntity.line(start: SIMD2(20, -20), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(-20, 20))
        let l4 = SketchEntity.line(start: SIMD2(-20, 20), end: SIMD2(-20, -20))
        let hole = SketchEntity.circle(center: SIMD2(0, 0), radius: 10.0)

        let regions = try SketchRegionDetector.detectRegions(from: [l1, l2, l3, l4, hole])
        let regionWithHole = try #require(regions.first(where: { !$0.innerLoops.isEmpty }))

        // Point in solid portion between hole and outer boundary
        #expect(regionWithHole.contains(point: SIMD2(15, 15)) == true)
        #expect(regionWithHole.contains(point: SIMD2(-15, -15)) == true)

        // Point inside the hole must be rejected
        #expect(regionWithHole.contains(point: SIMD2(0, 0)) == false)
        #expect(regionWithHole.contains(point: SIMD2(5, 5)) == false)

        // Point outside the outer boundary must be rejected
        #expect(regionWithHole.contains(point: SIMD2(25, 25)) == false)
        #expect(regionWithHole.contains(point: SIMD2(-30, 0)) == false)

        // Point on boundary is accepted
        #expect(regionWithHole.contains(point: SIMD2(-20, 0)) == true)
    }

    // MARK: - 4. Timeline regeneration & stability

    @MainActor
    @Test func testDownstreamExtrudeRegenerationOnSketchEdit() async throws {
        let doc = DocumentModel()

        // 1. Add sketch with rectangle and hole
        let l1 = SketchEntity.line(start: SIMD2(-20, -20), end: SIMD2(20, -20))
        let l2 = SketchEntity.line(start: SIMD2(20, -20), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(-20, 20))
        let l4 = SketchEntity.line(start: SIMD2(-20, 20), end: SIMD2(-20, -20))
        var hole = SketchEntity.circle(center: SIMD2(0, 0), radius: 5.0)

        let sketchFeature = doc.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4, hole])

        // 2. Extrude the sketch
        let extrudeFeature = try doc.extrudeSketch(sketchFeatureId: sketchFeature.id, distance: 15.0)
        guard case .extrude(let initialData) = extrudeFeature.operation else {
            Issue.record("Expected extrude operation")
            return
        }
        #expect(initialData.profile?.holes.count == 1)

        // 3. Edit sketch entity: enlarge hole radius from 5 to 10
        hole.radius = 10.0
        _ = doc.updateSketchEntities(in: sketchFeature.id, entities: [l1, l2, l3, l4, hole])

        // 4. Regenerate timeline
        let kernel = KernelClient(engine: LocalKernelEngine(), debounceDuration: .milliseconds(5))
        await KernelRegeneration.regenerateIncremental(from: sketchFeature.id, in: doc, client: kernel)

        // 5. Verify downstream extrude feature's profile is updated
        let updatedExtrude = try #require(doc.feature(for: extrudeFeature.id))
        guard case .extrude(let updatedData) = updatedExtrude.operation else {
            Issue.record("Expected extrude operation after regeneration")
            return
        }
        let updatedProfile = try #require(updatedData.profile)
        #expect(updatedProfile.holes.count == 1)
        // Hole points should now be ~10 units from origin
        let firstHolePt = updatedProfile.holes[0][0]
        let r = hypot(firstHolePt.x, firstHolePt.y)
        #expect(abs(r - 10.0) < 1e-3)
    }

    @MainActor
    @Test func testRegionExtrudeUndoRedo() throws {
        let doc = DocumentModel()
        doc.undoManager = UndoManager()

        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 10.0)
        let sketch = doc.addSketchFeature(planeName: "xy", entities: [circle])

        let ext = try doc.extrudeSketch(sketchFeatureId: sketch.id, distance: 25.0)
        #expect(doc.features.contains(where: { $0.id == ext.id }))

        doc.undoManager?.undo()
        #expect(!doc.features.contains(where: { $0.id == ext.id }))

        doc.undoManager?.redo()
        #expect(doc.features.contains(where: { $0.id == ext.id }))
    }

    // MARK: - 5. Edge cases handled

    @Test func testTangentTouchingLoopsAndSnapping() throws {
        // Two circles tangent at (0, 0): Center (-10, 0), R=10 and Center (10, 0), R=10
        let c1 = SketchEntity.circle(center: SIMD2(-10, 0), radius: 10.0)
        let c2 = SketchEntity.circle(center: SIMD2(10, 0), radius: 10.0)

        let regions = try SketchRegionDetector.detectRegions(from: [c1, c2])
        #expect(regions.count == 2)
        for r in regions {
            #expect(r.area > 0)
            #expect(r.innerLoops.isEmpty)
        }
    }

    @Test func testDisjointNonNestedLoops() throws {
        // Two separated rectangles with no containment
        let r1_l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let r1_l2 = SketchEntity.line(start: SIMD2(10, 0), end: SIMD2(10, 10))
        let r1_l3 = SketchEntity.line(start: SIMD2(10, 10), end: SIMD2(0, 10))
        let r1_l4 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(0, 0))

        let r2_l1 = SketchEntity.line(start: SIMD2(30, 0), end: SIMD2(40, 0))
        let r2_l2 = SketchEntity.line(start: SIMD2(40, 0), end: SIMD2(40, 10))
        let r2_l3 = SketchEntity.line(start: SIMD2(40, 10), end: SIMD2(30, 10))
        let r2_l4 = SketchEntity.line(start: SIMD2(30, 10), end: SIMD2(30, 0))

        let regions = try SketchRegionDetector.detectRegions(from: [r1_l1, r1_l2, r1_l3, r1_l4, r2_l1, r2_l2, r2_l3, r2_l4])
        #expect(regions.count == 2)
        for r in regions {
            #expect(abs(r.area - 100.0) < 1e-2)
            #expect(r.innerLoops.isEmpty)
        }
    }

    @Test func testDanglingOpenSegmentsIgnored() throws {
        // Closed rectangle [0, 10] x [0, 10] with an antenna/dangling line extending to (25, 25)
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let l2 = SketchEntity.line(start: SIMD2(10, 0), end: SIMD2(10, 10))
        let l3 = SketchEntity.line(start: SIMD2(10, 10), end: SIMD2(0, 10))
        let l4 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(0, 0))
        let antenna = SketchEntity.line(start: SIMD2(10, 10), end: SIMD2(25, 25))

        let regions = try SketchRegionDetector.detectRegions(from: [l1, l2, l3, l4, antenna])
        #expect(regions.count == 1)
        #expect(abs(regions[0].area - 100.0) < 1e-2)
    }

    // MARK: - Construction Geometry Tests

    @Test func testConstructionEntitiesExcludedFromRegionDetection() throws {
        // Rectangle [-10, 10] x [-10, 10] with a bisecting centerline at x = 0 marked as construction
        let l1 = SketchEntity.line(start: SIMD2(-10, -10), end: SIMD2(10, -10))
        let l2 = SketchEntity.line(start: SIMD2(10, -10), end: SIMD2(10, 10))
        let l3 = SketchEntity.line(start: SIMD2(10, 10), end: SIMD2(-10, 10))
        let l4 = SketchEntity.line(start: SIMD2(-10, 10), end: SIMD2(-10, -10))
        let divider = SketchEntity.line(start: SIMD2(0, -10), end: SIMD2(0, 10), isConstruction: true)

        let regions = try SketchRegionDetector.detectRegions(from: [l1, l2, l3, l4, divider])
        // Since divider is construction, it does not partition the face into 2 sub-regions
        #expect(regions.count == 1)
        #expect(abs(regions[0].area - 400.0) < 1.0)
        #expect(regions[0].innerLoops.isEmpty)
    }

    @Test func testConstructionCircleIgnoredInRegionHoles() throws {
        // Outer rectangle [-20, 20] x [-20, 20] containing a construction circle
        let l1 = SketchEntity.line(start: SIMD2(-20, -20), end: SIMD2(20, -20))
        let l2 = SketchEntity.line(start: SIMD2(20, -20), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(-20, 20))
        let l4 = SketchEntity.line(start: SIMD2(-20, 20), end: SIMD2(-20, -20))
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 5.0, isConstruction: true)

        let regions = try SketchRegionDetector.detectRegions(from: [l1, l2, l3, l4, circle])
        #expect(regions.count == 1)
        // Construction circle does not create an inner hole
        #expect(regions[0].innerLoops.isEmpty)
        #expect(abs(regions[0].area - 1600.0) < 1.0)
    }
}
