import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchChamferTests {

    @Test func testChamferEqualDistance() throws {
        let line1 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(50, 0)
        )
        let line2 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(0, 50)
        )

        let result = try SketchChamfer.makeChamfer(line1: line1, line2: line2, distance1: 10.0)

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

        // Bevel line
        let bevel = result.chamferLine
        #expect(bevel.kind == "line")
        let bStart = try #require(bevel.startPoint)
        let bEnd = try #require(bevel.endPoint)

        #expect(abs(bStart.x - 10.0) < 1e-4)
        #expect(abs(bStart.y - 0.0) < 1e-4)
        #expect(abs(bEnd.x - 0.0) < 1e-4)
        #expect(abs(bEnd.y - 10.0) < 1e-4)

        let bevelLen = hypot(bEnd.x - bStart.x, bEnd.y - bStart.y)
        #expect(abs(bevelLen - (10.0 * sqrt(2.0))) < 1e-4)

        // Constraints
        #expect(result.constraints.count == 2)
        let coincidentConstraints = result.constraints.filter { $0.kind == .coincident }
        #expect(coincidentConstraints.count == 2)
        #expect(coincidentConstraints.contains { $0.entityIds.contains(line1.id) && $0.entityIds.contains(bevel.id) })
        #expect(coincidentConstraints.contains { $0.entityIds.contains(line2.id) && $0.entityIds.contains(bevel.id) })
    }

    @Test func testChamferTwoDistances() throws {
        let line1 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(50, 0)
        )
        let line2 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(0, 50)
        )

        let result = try SketchChamfer.makeChamfer(
            line1: line1,
            line2: line2,
            distance1: 8.0,
            distance2: 15.0
        )

        let s1 = try #require(result.updatedLine1.startPoint)
        let s2 = try #require(result.updatedLine2.startPoint)

        #expect(abs(s1.x - 8.0) < 1e-4)
        #expect(abs(s1.y - 0.0) < 1e-4)

        #expect(abs(s2.x - 0.0) < 1e-4)
        #expect(abs(s2.y - 15.0) < 1e-4)

        let bevel = result.chamferLine
        let bStart = try #require(bevel.startPoint)
        let bEnd = try #require(bevel.endPoint)

        #expect(abs(bStart.x - 8.0) < 1e-4)
        #expect(abs(bStart.y - 0.0) < 1e-4)
        #expect(abs(bEnd.x - 0.0) < 1e-4)
        #expect(abs(bEnd.y - 15.0) < 1e-4)
    }

    @Test func testChamferDistanceAndAngle() throws {
        let line1 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(50, 0)
        )
        let line2 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(0, 50)
        )

        // 30 degree angle: distance2 = distance1 * tan(30 deg) = 10 * (1 / sqrt(3)) ~ 5.7735
        let result = try SketchChamfer.makeChamfer(
            line1: line1,
            line2: line2,
            distance1: 10.0,
            angle: 30.0
        )

        let expectedD2 = 10.0 * tan(30.0 * .pi / 180.0)
        let bevel = result.chamferLine
        let bStart = try #require(bevel.startPoint)
        let bEnd = try #require(bevel.endPoint)

        #expect(abs(bStart.x - 10.0) < 1e-4)
        #expect(abs(bStart.y - 0.0) < 1e-4)
        #expect(abs(bEnd.x - 0.0) < 1e-4)
        #expect(abs(bEnd.y - expectedD2) < 1e-4)
    }

    @Test func testDegenerateChamferParallelLinesThrows() {
        let line1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(50, 0))
        let line2 = SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(50, 10))

        #expect(throws: SketchError.self) {
            try SketchChamfer.makeChamfer(line1: line1, line2: line2, distance1: 5.0)
        }

        let collinear1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(50, 0))
        let collinear2 = SketchEntity.line(start: SIMD2(50, 0), end: SIMD2(100, 0))
        #expect(throws: SketchError.self) {
            try SketchChamfer.makeChamfer(line1: collinear1, line2: collinear2, distance1: 5.0)
        }
    }

    @Test func testChamferDistanceExceedsLineLengthThrows() {
        let line1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let line2 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(0, 10))

        #expect(throws: SketchError.self) {
            try SketchChamfer.makeChamfer(line1: line1, line2: line2, distance1: 15.0)
        }
        #expect(throws: SketchError.self) {
            try SketchChamfer.makeChamfer(line1: line1, line2: line2, distance1: 5.0, distance2: 12.0)
        }
    }

    @Test func testNegativeOrZeroDistanceThrows() {
        let line1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0))
        let line2 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(0, 20))

        #expect(throws: SketchError.self) {
            try SketchChamfer.makeChamfer(line1: line1, line2: line2, distance1: 0.0)
        }
        #expect(throws: SketchError.self) {
            try SketchChamfer.makeChamfer(line1: line1, line2: line2, distance1: -5.0)
        }
        #expect(throws: SketchError.self) {
            try SketchChamfer.makeChamfer(line1: line1, line2: line2, distance1: 10.0, distance2: -2.0)
        }
        #expect(throws: SketchError.self) {
            try SketchChamfer.makeChamfer(line1: line1, line2: line2, distance1: 10.0, angle: 95.0)
        }
    }
}
