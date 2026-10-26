import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchPatternTests {

    @Test func testLinearPattern1D() throws {
        let line = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(10, 0)
        )

        // 3 instances along X with 25.0 mm spacing produces 2 copies
        let result = try SketchPattern.makeLinearPattern(
            entities: [line],
            direction1: SIMD2<Double>(1, 0),
            spacing1: 25.0,
            count1: 3
        )

        #expect(result.entities.count == 2)
        // Each copy line gets 1 parallel constraint + 1 equal constraint = 2 constraints per copy
        #expect(result.constraints.count == 4)

        let copy1 = result.entities[0]
        let copy2 = result.entities[1]

        #expect(abs((copy1.startPoint?.x ?? 0) - 25.0) < 1e-4)
        #expect(abs((copy1.endPoint?.x ?? 0) - 35.0) < 1e-4)

        #expect(abs((copy2.startPoint?.x ?? 0) - 50.0) < 1e-4)
        #expect(abs((copy2.endPoint?.x ?? 0) - 60.0) < 1e-4)

        let parallelConstraints = result.constraints.filter { $0.kind == .parallel }
        let equalConstraints = result.constraints.filter { $0.kind == .equal }
        #expect(parallelConstraints.count == 2)
        #expect(equalConstraints.count == 2)
    }

    @Test func testLinearPattern2D() throws {
        let circle = SketchEntity.circle(
            center: SIMD2<Double>(0, 0),
            radius: 5.0
        )

        // 3 instances along X (spacing 20), 2 instances along Y (spacing 15) -> total 3*2 = 6, 5 new copies
        let result = try SketchPattern.makeLinearPattern(
            entities: [circle],
            direction1: SIMD2<Double>(1, 0),
            spacing1: 20.0,
            count1: 3,
            direction2: SIMD2<Double>(0, 1),
            spacing2: 15.0,
            count2: 2
        )

        #expect(result.entities.count == 5)
        #expect(result.constraints.count == 5)

        for copy in result.entities {
            #expect(abs((copy.radius ?? 0) - 5.0) < 1e-4)
        }

        let equalConstraints = result.constraints.filter { $0.kind == .equal }
        #expect(equalConstraints.count == 5)
    }

    @Test func testCircularPatternEqualSpacing360() throws {
        let circle = SketchEntity.circle(
            center: SIMD2<Double>(20, 0),
            radius: 3.0
        )

        // 4 instances equally spaced over 360 degrees (2*pi) around center (0, 0)
        // Produces 3 copies at 90°, 180°, 270°
        let result = try SketchPattern.makeCircularPattern(
            entities: [circle],
            center: .zero,
            count: 4,
            totalAngle: 2.0 * .pi,
            equalSpacing: true
        )

        #expect(result.entities.count == 3)
        #expect(result.constraints.count == 3)

        let c1 = try #require(result.entities[0].centerPoint)
        let c2 = try #require(result.entities[1].centerPoint)
        let c3 = try #require(result.entities[2].centerPoint)

        // 90 degrees -> (0, 20)
        #expect(abs(c1.x - 0.0) < 1e-4)
        #expect(abs(c1.y - 20.0) < 1e-4)

        // 180 degrees -> (-20, 0)
        #expect(abs(c2.x - (-20.0)) < 1e-4)
        #expect(abs(c2.y - 0.0) < 1e-4)

        // 270 degrees -> (0, -20)
        #expect(abs(c3.x - 0.0) < 1e-4)
        #expect(abs(c3.y - (-20.0)) < 1e-4)
    }

    @Test func testCircularPatternPartialAngle() throws {
        let line = SketchEntity.line(
            start: SIMD2<Double>(10, 0),
            end: SIMD2<Double>(20, 0)
        )

        // 3 instances over 180 degrees (pi) -> step angle = pi / 2 = 90 degrees
        let result = try SketchPattern.makeCircularPattern(
            entities: [line],
            center: .zero,
            count: 3,
            totalAngle: .pi,
            equalSpacing: true
        )

        #expect(result.entities.count == 2)
        #expect(result.constraints.count == 2)

        let l1 = result.entities[0]
        let l2 = result.entities[1]

        // 90 degrees
        #expect(abs((l1.startPoint?.x ?? 0) - 0.0) < 1e-4)
        #expect(abs((l1.startPoint?.y ?? 0) - 10.0) < 1e-4)
        #expect(abs((l1.endPoint?.x ?? 0) - 0.0) < 1e-4)
        #expect(abs((l1.endPoint?.y ?? 0) - 20.0) < 1e-4)

        // 180 degrees
        #expect(abs((l2.startPoint?.x ?? 0) - (-10.0)) < 1e-4)
        #expect(abs((l2.startPoint?.y ?? 0) - 0.0) < 1e-4)
        #expect(abs((l2.endPoint?.x ?? 0) - (-20.0)) < 1e-4)
        #expect(abs((l2.endPoint?.y ?? 0) - 0.0) < 1e-4)
    }

    @Test func testPatternPreservesInternalCoincidence() throws {
        // Two connected lines forming an L-joint at (10, 0)
        let l1 = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let l2 = SketchEntity.line(start: SIMD2<Double>(10, 0), end: SIMD2<Double>(10, 10))

        let result = try SketchPattern.makeLinearPattern(
            entities: [l1, l2],
            direction1: SIMD2<Double>(0, 1),
            spacing1: 20.0,
            count1: 2
        )

        #expect(result.entities.count == 2)
        // 2 parallel + 2 equal + 1 internal coincident = 5 constraints
        #expect(result.constraints.count == 5)

        let coincidentConstraints = result.constraints.filter { $0.kind == .coincident }
        #expect(coincidentConstraints.count == 1)

        let joint = coincidentConstraints[0]
        let copy1 = result.entities[0]
        let copy2 = result.entities[1]
        #expect(joint.entityIds.contains(copy1.id))
        #expect(joint.entityIds.contains(copy2.id))
    }

    @Test func testDegeneratePatternThrows() {
        let line = SketchEntity.line(start: .zero, end: SIMD2<Double>(10, 0))

        // Count < 1
        #expect(throws: SketchError.self) {
            _ = try SketchPattern.makeLinearPattern(
                entities: [line],
                direction1: SIMD2<Double>(1, 0),
                spacing1: 10,
                count1: 0
            )
        }

        // Circular pattern count < 2
        #expect(throws: SketchError.self) {
            _ = try SketchPattern.makeCircularPattern(
                entities: [line],
                center: .zero,
                count: 1
            )
        }

        // Zero spacing with count > 1
        #expect(throws: SketchError.self) {
            _ = try SketchPattern.makeLinearPattern(
                entities: [line],
                direction1: SIMD2<Double>(1, 0),
                spacing1: 0,
                count1: 3
            )
        }
    }
}
