import Testing
import Foundation
import CoreGraphics
import simd
@testable import MadeCore

@Suite struct MarqueeSelectionTests {
    @Test func testPolygonContains() {
        // Simple triangle: (0, 0), (10, 0), (5, 10)
        let triangle: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(10, 0),
            SIMD2<Float>(5, 10)
        ]

        // Inside
        #expect(polygonContains(point: SIMD2<Float>(5, 3), polygon: triangle))
        // Outside
        #expect(!polygonContains(point: SIMD2<Float>(0, 10), polygon: triangle))
        #expect(!polygonContains(point: SIMD2<Float>(5, -2), polygon: triangle))
        #expect(!polygonContains(point: SIMD2<Float>(12, 5), polygon: triangle))

        // Less than 3 points
        #expect(!polygonContains(point: SIMD2<Float>(5, 3), polygon: [SIMD2<Float>(0, 0), SIMD2<Float>(10, 0)]))
    }

    @Test func testSegmentsIntersect() {
        // Crossing segments
        let p1 = SIMD2<Float>(0, 0)
        let p2 = SIMD2<Float>(10, 10)
        let p3 = SIMD2<Float>(0, 10)
        let p4 = SIMD2<Float>(10, 0)
        #expect(segmentsIntersect(p1: p1, p2: p2, p3: p3, p4: p4))

        // Parallel non-intersecting
        let q1 = SIMD2<Float>(0, 0)
        let q2 = SIMD2<Float>(10, 0)
        let q3 = SIMD2<Float>(0, 5)
        let q4 = SIMD2<Float>(10, 5)
        #expect(!segmentsIntersect(p1: q1, p2: q2, p3: q3, p4: q4))

        // Disjoint non-parallel
        let r1 = SIMD2<Float>(0, 0)
        let r2 = SIMD2<Float>(5, 5)
        let r3 = SIMD2<Float>(10, 10)
        let r4 = SIMD2<Float>(15, 15)
        #expect(!segmentsIntersect(p1: r1, p2: r2, p3: r3, p4: r4))

        // Touching endpoint
        let s1 = SIMD2<Float>(0, 0)
        let s2 = SIMD2<Float>(10, 0)
        let s3 = SIMD2<Float>(5, 0)
        let s4 = SIMD2<Float>(5, 5)
        #expect(segmentsIntersect(p1: s1, p2: s2, p3: s3, p4: s4))
    }

    @Test func testPointInTriangle() {
        let a = SIMD2<Float>(0, 0)
        let b = SIMD2<Float>(10, 0)
        let c = SIMD2<Float>(5, 10)

        // Inside
        #expect(pointInTriangle(p: SIMD2<Float>(5, 3), a: a, b: b, c: c))
        // Outside
        #expect(!pointInTriangle(p: SIMD2<Float>(5, 12), a: a, b: b, c: c))
        #expect(!pointInTriangle(p: SIMD2<Float>(-1, 1), a: a, b: b, c: c))

        // Opposite winding (CW)
        #expect(pointInTriangle(p: SIMD2<Float>(5, 3), a: a, b: c, c: b))
    }

    private func makeCameraSetup() -> (simd_float4x4, CGSize) {
        let viewportSize = CGSize(width: 800, height: 600)
        let aspect: Float = 800.0 / 600.0
        let view = Orientation.makeLookAt(
            eye: SIMD3<Float>(0, -100, 0),
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 0, 1)
        )
        let proj = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
        return (proj * view, viewportSize)
    }

    @Test func testBoxWindowVsCrossingSelection() {
        let (vp, size) = makeCameraSetup()
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        // Projected center of the box is at screen center: (400, 300)
        // Projected extents of this 20x20x20 box roughly span ~ (350..450, 250..350)

        // 1. Fully enclosing marquee (300, 200) to (500, 400)
        let fullWindowMarquee = MarqueeState(
            shape: .box,
            mode: .window,
            startPoint: CGPoint(x: 300, y: 200),
            currentPoint: CGPoint(x: 500, y: 400)
        )
        let fullWindowResult = evaluateMarqueeSelection(
            marquee: fullWindowMarquee,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(fullWindowResult.contains(SolidId("box-1")))

        let fullCrossingMarquee = MarqueeState(
            shape: .box,
            mode: .crossing,
            startPoint: CGPoint(x: 500, y: 400),
            currentPoint: CGPoint(x: 300, y: 200)
        )
        let fullCrossingResult = evaluateMarqueeSelection(
            marquee: fullCrossingMarquee,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(fullCrossingResult.contains(SolidId("box-1")))

        // 2. Partial marquee: overlapping the right edge of the box (e.g. 400 to 600, 200 to 400)
        // Crosses the object, but does not fully enclose it.
        let partialWindowMarquee = MarqueeState(
            shape: .box,
            mode: .window,
            startPoint: CGPoint(x: 400, y: 200),
            currentPoint: CGPoint(x: 600, y: 400)
        )
        let partialWindowResult = evaluateMarqueeSelection(
            marquee: partialWindowMarquee,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(partialWindowResult.isEmpty, "Window selection must reject partially enclosed mesh")

        let partialCrossingMarquee = MarqueeState(
            shape: .box,
            mode: .crossing,
            startPoint: CGPoint(x: 600, y: 400),
            currentPoint: CGPoint(x: 400, y: 200)
        )
        let partialCrossingResult = evaluateMarqueeSelection(
            marquee: partialCrossingMarquee,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(partialCrossingResult.contains(SolidId("box-1")), "Crossing selection must include partially enclosed mesh")

        // 3. Completely outside marquee (10 to 50, 10 to 50)
        let outsideCrossingMarquee = MarqueeState(
            shape: .box,
            mode: .crossing,
            startPoint: CGPoint(x: 50, y: 50),
            currentPoint: CGPoint(x: 10, y: 10)
        )
        let outsideResult = evaluateMarqueeSelection(
            marquee: outsideCrossingMarquee,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(outsideResult.isEmpty)
    }

    @Test func testLassoWindowVsCrossingSelection() {
        let (vp, size) = makeCameraSetup()
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        // 1. Enclosing polygon around center (400, 300)
        let enclosingPolygon: [CGPoint] = [
            CGPoint(x: 250, y: 150),
            CGPoint(x: 550, y: 150),
            CGPoint(x: 550, y: 450),
            CGPoint(x: 250, y: 450)
        ]
        let lassoWindow = MarqueeState(
            shape: .lasso,
            mode: .window,
            startPoint: enclosingPolygon[0],
            currentPoint: enclosingPolygon[2],
            points: enclosingPolygon
        )
        let lassoWindowResult = evaluateMarqueeSelection(
            marquee: lassoWindow,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(lassoWindowResult.contains(SolidId("box-1")))

        // 2. Partial polygon intersecting center
        let partialPolygon: [CGPoint] = [
            CGPoint(x: 400, y: 200),
            CGPoint(x: 600, y: 200),
            CGPoint(x: 600, y: 400),
            CGPoint(x: 400, y: 400)
        ]
        let lassoPartialWindow = MarqueeState(
            shape: .lasso,
            mode: .window,
            startPoint: partialPolygon[0],
            currentPoint: partialPolygon[2],
            points: partialPolygon
        )
        let lassoPartialWindowResult = evaluateMarqueeSelection(
            marquee: lassoPartialWindow,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(lassoPartialWindowResult.isEmpty)

        let lassoPartialCrossing = MarqueeState(
            shape: .lasso,
            mode: .crossing,
            startPoint: partialPolygon[0],
            currentPoint: partialPolygon[2],
            points: partialPolygon
        )
        let lassoPartialCrossingResult = evaluateMarqueeSelection(
            marquee: lassoPartialCrossing,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(lassoPartialCrossingResult.contains(SolidId("box-1")))
    }

    @Test func testSelectionFilterGatesMarquee() {
        let (vp, size) = makeCameraSetup()
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: payload)

        let marquee = MarqueeState(
            shape: .box,
            mode: .window,
            startPoint: CGPoint(x: 300, y: 200),
            currentPoint: CGPoint(x: 500, y: 400)
        )

        // Filter excluding bodies
        let filterFacesOnly = SelectionFilter.faces
        let filteredResult = evaluateMarqueeSelection(
            marquee: marquee,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp,
            filter: filterFacesOnly
        )
        #expect(filteredResult.isEmpty, "Selection filter without .bodies must reject marquee selection")
    }

    @Test func testCameraNearPlaneRejection() {
        let (vp, size) = makeCameraSetup()
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        // Camera is at (0, -100, 0) looking at (0, 0, 0).
        // Place mesh behind camera at (0, -200, 0)
        let mesh = CandidateMesh(
            id: SolidId("box-behind"),
            payload: payload,
            transform: Transform(position: SIMD3<Float>(0, -200, 0))
        )

        let marquee = MarqueeState(
            shape: .box,
            mode: .crossing,
            startPoint: CGPoint(x: 0, y: 0),
            currentPoint: CGPoint(x: 800, y: 600)
        )
        let result = evaluateMarqueeSelection(
            marquee: marquee,
            candidateMeshes: [mesh],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(result.isEmpty, "Mesh behind near plane must be rejected")
    }

    @Test func testEmptySceneEvaluation() {
        let (vp, size) = makeCameraSetup()
        let marquee = MarqueeState(
            shape: .box,
            mode: .crossing,
            startPoint: CGPoint(x: 100, y: 100),
            currentPoint: CGPoint(x: 200, y: 200)
        )
        let result = evaluateMarqueeSelection(
            marquee: marquee,
            candidateMeshes: [],
            viewportSize: size,
            viewProjectionMatrix: vp
        )
        #expect(result.isEmpty)
    }
}
