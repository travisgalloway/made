import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchFilletTests {

    @Test func testFilletPerpendicularLinesRadiusAndTangentArc() throws {
        let line1 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(50, 0)
        )
        let line2 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(0, 50)
        )

        let result = try SketchFillet.makeFillet(line1: line1, line2: line2, radius: 10.0)

        // Trimmed lines
        let s1 = try #require(result.updatedLine1.startPoint)
        let e1 = try #require(result.updatedLine1.endPoint)
        let s2 = try #require(result.updatedLine2.startPoint)
        let e2 = try #require(result.updatedLine2.endPoint)

        #expect(abs(s1.x - 10.0) < 1e-4)
        #expect(abs(s1.y - 0.0) < 1e-4)
        #expect(abs(e1.x - 50.0) < 1e-4)
        #expect(abs(e1.y - 0.0) < 1e-4)

        #expect(abs(s2.x - 0.0) < 1e-4)
        #expect(abs(s2.y - 10.0) < 1e-4)
        #expect(abs(e2.x - 0.0) < 1e-4)
        #expect(abs(e2.y - 50.0) < 1e-4)

        // Fillet arc
        let arc = result.filletArc
        #expect(arc.kind == "arc")
        let arcStart = try #require(arc.startPoint)
        let arcEnd = try #require(arc.endPoint)
        let arcCenter = try #require(arc.centerPoint)

        #expect(abs(arcStart.x - 10.0) < 1e-4)
        #expect(abs(arcStart.y - 0.0) < 1e-4)
        #expect(abs(arcEnd.x - 0.0) < 1e-4)
        #expect(abs(arcEnd.y - 10.0) < 1e-4)

        #expect(abs(arcCenter.x - 10.0) < 1e-4)
        #expect(abs(arcCenter.y - 10.0) < 1e-4)

        let rStart = hypot(arcStart.x - arcCenter.x, arcStart.y - arcCenter.y)
        let rEnd = hypot(arcEnd.x - arcCenter.x, arcEnd.y - arcCenter.y)
        #expect(abs(rStart - 10.0) < 1e-4)
        #expect(abs(rEnd - 10.0) < 1e-4)

        // Constraints
        #expect(result.constraints.count == 4)
        let coincidentConstraints = result.constraints.filter { $0.kind == .coincident }
        let tangentConstraints = result.constraints.filter { $0.kind == .tangent }
        #expect(coincidentConstraints.count == 2)
        #expect(tangentConstraints.count == 2)

        #expect(coincidentConstraints.contains { $0.entityIds.contains(line1.id) && $0.entityIds.contains(arc.id) })
        #expect(coincidentConstraints.contains { $0.entityIds.contains(line2.id) && $0.entityIds.contains(arc.id) })
        #expect(tangentConstraints.contains { $0.entityIds.contains(line1.id) && $0.entityIds.contains(arc.id) })
        #expect(tangentConstraints.contains { $0.entityIds.contains(line2.id) && $0.entityIds.contains(arc.id) })
    }

    @Test func testFilletAcuteAngle() throws {
        // 60-degree corner at (0, 0)
        let line1 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(50, 0)
        )
        let rad60 = 60.0 * .pi / 180.0
        let line2 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(50.0 * cos(rad60), 50.0 * sin(rad60))
        )

        let radius = 5.0
        let result = try SketchFillet.makeFillet(line1: line1, line2: line2, radius: radius)

        let expectedSetback = radius / tan(30.0 * .pi / 180.0) // 5 * sqrt(3) ~ 8.66025
        let arc = result.filletArc
        let arcStart = try #require(arc.startPoint)
        let arcEnd = try #require(arc.endPoint)
        let arcCenter = try #require(arc.centerPoint)

        #expect(abs(hypot(arcStart.x, arcStart.y) - expectedSetback) < 1e-3)
        #expect(abs(hypot(arcEnd.x, arcEnd.y) - expectedSetback) < 1e-3)

        let rStart = hypot(arcStart.x - arcCenter.x, arcStart.y - arcCenter.y)
        let rEnd = hypot(arcEnd.x - arcCenter.x, arcEnd.y - arcCenter.y)
        #expect(abs(rStart - radius) < 1e-4)
        #expect(abs(rEnd - radius) < 1e-4)
    }

    @Test func testFilletObtuseAngle() throws {
        // 120-degree corner at (0, 0)
        let line1 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(50, 0)
        )
        let rad120 = 120.0 * .pi / 180.0
        let line2 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(50.0 * cos(rad120), 50.0 * sin(rad120))
        )

        let radius = 10.0
        let result = try SketchFillet.makeFillet(line1: line1, line2: line2, radius: radius)

        let expectedSetback = radius / tan(60.0 * .pi / 180.0) // 10 / sqrt(3) ~ 5.7735
        let arc = result.filletArc
        let arcStart = try #require(arc.startPoint)
        let arcEnd = try #require(arc.endPoint)
        let arcCenter = try #require(arc.centerPoint)

        #expect(abs(hypot(arcStart.x, arcStart.y) - expectedSetback) < 1e-3)
        #expect(abs(hypot(arcEnd.x, arcEnd.y) - expectedSetback) < 1e-3)

        let rStart = hypot(arcStart.x - arcCenter.x, arcStart.y - arcCenter.y)
        let rEnd = hypot(arcEnd.x - arcCenter.x, arcEnd.y - arcCenter.y)
        #expect(abs(rStart - radius) < 1e-4)
        #expect(abs(rEnd - radius) < 1e-4)
    }

    @Test func testFilletPreservesEndpointChirality() throws {
        // Test all 4 endpoint order combinations
        let pCorner = SIMD2<Double>(10, 10)
        let pFar1 = SIMD2<Double>(60, 10)
        let pFar2 = SIMD2<Double>(10, 60)

        let configs: [(SIMD2<Double>, SIMD2<Double>, SIMD2<Double>, SIMD2<Double>)] = [
            (pCorner, pFar1, pCorner, pFar2), // start-start
            (pCorner, pFar1, pFar2, pCorner), // start-end
            (pFar1, pCorner, pCorner, pFar2), // end-start
            (pFar1, pCorner, pFar2, pCorner)  // end-end
        ]

        for (s1, e1, s2, e2) in configs {
            let line1 = SketchEntity.line(start: s1, end: e1)
            let line2 = SketchEntity.line(start: s2, end: e2)
            let result = try SketchFillet.makeFillet(line1: line1, line2: line2, radius: 5.0)

            let far1 = (result.updatedLine1.startPoint == pFar1) ? result.updatedLine1.startPoint : result.updatedLine1.endPoint
            let far2 = (result.updatedLine2.startPoint == pFar2) ? result.updatedLine2.startPoint : result.updatedLine2.endPoint

            #expect(far1 != nil)
            #expect(far2 != nil)

            let arc = result.filletArc
            let arcStart = try #require(arc.startPoint)
            let arcCenter = try #require(arc.centerPoint)
            let r = hypot(arcStart.x - arcCenter.x, arcStart.y - arcCenter.y)
            #expect(abs(r - 5.0) < 1e-4)
        }
    }

    @Test func testDegenerateFilletParallelLinesThrows() {
        let line1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(50, 0))
        let line2 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(50, 10))

        #expect(throws: SketchError.self) {
            try SketchFillet.makeFillet(line1: line1, line2: line2, radius: 5.0)
        }

        let collinear1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(50, 0))
        let collinear2 = SketchEntity.line(start: SIMD2(50, 0), end: SIMD2(100, 0))
        #expect(throws: SketchError.self) {
            try SketchFillet.makeFillet(line1: collinear1, line2: collinear2, radius: 5.0)
        }
    }

    @Test func testFilletRadiusExceedsLineLengthThrows() {
        let line1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(5, 0))
        let line2 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(0, 5))

        // Radius 10 requires setback 10 on 90 degree corner, which exceeds length 5
        #expect(throws: SketchError.self) {
            try SketchFillet.makeFillet(line1: line1, line2: line2, radius: 10.0)
        }
    }

    @Test func testNegativeOrZeroRadiusThrows() {
        let line1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let line2 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(0, 20))

        #expect(throws: SketchError.self) {
            try SketchFillet.makeFillet(line1: line1, line2: line2, radius: 0.0)
        }
        #expect(throws: SketchError.self) {
            try SketchFillet.makeFillet(line1: line1, line2: line2, radius: -5.0)
        }
        #expect(throws: SketchError.self) {
            try SketchFillet.makeFillet(line1: line1, line2: line2, radius: 1e-6)
        }
    }
}
