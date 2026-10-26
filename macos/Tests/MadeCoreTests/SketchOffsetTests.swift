import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchOffsetTests {

    @Test func testLineOffsetPerpendicularDistanceAndParallelConstraint() throws {
        let line = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(20, 0)
        )
        let result = try SketchOffset.makeOffset(entities: [line], distance: 5.0)

        #expect(result.entities.count == 1)
        #expect(result.constraints.count == 1)

        let offsetLine = result.entities[0]
        #expect(offsetLine.kind == "line")

        let sPrime = try #require(offsetLine.startPoint)
        let ePrime = try #require(offsetLine.endPoint)

        // Line along +X offsets leftward (+Y) for positive distance
        #expect(abs(sPrime.x - 0.0) < 1e-4)
        #expect(abs(sPrime.y - 5.0) < 1e-4)
        #expect(abs(ePrime.x - 20.0) < 1e-4)
        #expect(abs(ePrime.y - 5.0) < 1e-4)

        let constraint = result.constraints[0]
        #expect(constraint.kind == .parallel)
        #expect(constraint.entityIds == [line.id, offsetLine.id])
    }

    @Test func testCircleOffsetConcentricity() throws {
        let circle = SketchEntity.circle(
            center: SIMD2<Double>(10, 15),
            radius: 8.0
        )
        let result = try SketchOffset.makeOffset(entities: [circle], distance: 4.0)

        #expect(result.entities.count == 1)
        #expect(result.constraints.count == 1)

        let offsetCircle = result.entities[0]
        #expect(offsetCircle.kind == "circle")
        #expect(abs((offsetCircle.centerPoint?.x ?? 0) - 10.0) < 1e-4)
        #expect(abs((offsetCircle.centerPoint?.y ?? 0) - 15.0) < 1e-4)
        #expect(abs((offsetCircle.radius ?? 0) - 12.0) < 1e-4)

        let constraint = result.constraints[0]
        #expect(constraint.kind == .concentric)
        #expect(constraint.entityIds == [circle.id, offsetCircle.id])
    }

    @Test func testArcOffsetPreservesCenterAndAngles() throws {
        let center = SIMD2<Double>(0, 0)
        let start = SIMD2<Double>(10, 0)
        let end = SIMD2<Double>(0, 10)
        let arc = SketchEntity.arc(
            start: start,
            end: end,
            center: center,
            clockwise: false
        )
        let result = try SketchOffset.makeOffset(entities: [arc], distance: 2.0)

        #expect(result.entities.count == 1)
        #expect(result.constraints.count == 1)

        let offsetArc = result.entities[0]
        #expect(offsetArc.kind == "arc")
        #expect(offsetArc.isClockwise == false)
        #expect(abs((offsetArc.centerPoint?.x ?? 0) - 0.0) < 1e-4)
        #expect(abs((offsetArc.centerPoint?.y ?? 0) - 0.0) < 1e-4)

        let sPrime = try #require(offsetArc.startPoint)
        let ePrime = try #require(offsetArc.endPoint)
        #expect(abs(sPrime.x - 12.0) < 1e-4)
        #expect(abs(sPrime.y - 0.0) < 1e-4)
        #expect(abs(ePrime.x - 0.0) < 1e-4)
        #expect(abs(ePrime.y - 12.0) < 1e-4)

        let constraint = result.constraints[0]
        #expect(constraint.kind == .concentric)
        #expect(constraint.entityIds == [arc.id, offsetArc.id])
    }

    @Test func testConnectedChainCornerIntersection() throws {
        // Two connected perpendicular lines meeting at (20, 0)
        let line1 = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(20, 0)
        )
        let line2 = SketchEntity.line(
            start: SIMD2<Double>(20, 0),
            end: SIMD2<Double>(20, 30)
        )

        let result = try SketchOffset.makeOffset(entities: [line1, line2], distance: 5.0)

        #expect(result.entities.count == 2)
        // 2 parallel constraints + 1 corner coincident constraint = 3 constraints
        #expect(result.constraints.count == 3)

        let off1 = result.entities[0]
        let off2 = result.entities[1]

        let e1 = try #require(off1.endPoint)
        let s2 = try #require(off2.startPoint)

        // Corner at (20, 0): line 1 offsets to y=5, line 2 offsets to x=15
        // Intersection point must be exactly (15, 5)
        #expect(abs(e1.x - 15.0) < 1e-4)
        #expect(abs(e1.y - 5.0) < 1e-4)
        #expect(abs(s2.x - 15.0) < 1e-4)
        #expect(abs(s2.y - 5.0) < 1e-4)

        let coincidentConstraint = result.constraints.first { $0.kind == .coincident }
        #expect(coincidentConstraint != nil)
        #expect(coincidentConstraint?.entityIds.contains(off1.id) == true)
        #expect(coincidentConstraint?.entityIds.contains(off2.id) == true)
    }

    @Test func testClosedLoopOffset() throws {
        // 40x30 rectangle oriented counter-clockwise
        let l1 = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(40, 0))
        let l2 = SketchEntity.line(start: SIMD2<Double>(40, 0), end: SIMD2<Double>(40, 30))
        let l3 = SketchEntity.line(start: SIMD2<Double>(40, 30), end: SIMD2<Double>(0, 30))
        let l4 = SketchEntity.line(start: SIMD2<Double>(0, 30), end: SIMD2<Double>(0, 0))

        let result = try SketchOffset.makeOffset(entities: [l1, l2, l3, l4], distance: 5.0)

        #expect(result.entities.count == 4)
        // 4 parallel + 4 corner coincident = 8 constraints
        #expect(result.constraints.count == 8)

        let o1 = result.entities[0]
        let o2 = result.entities[1]
        let o3 = result.entities[2]
        let o4 = result.entities[3]

        // Inward offset of CCW rectangle by 5.0 produces 30x20 rectangle at (5, 5) to (35, 25)
        #expect(abs((o1.startPoint?.x ?? 0) - 5.0) < 1e-4)
        #expect(abs((o1.startPoint?.y ?? 0) - 5.0) < 1e-4)
        #expect(abs((o1.endPoint?.x ?? 0) - 35.0) < 1e-4)
        #expect(abs((o1.endPoint?.y ?? 0) - 5.0) < 1e-4)

        #expect(abs((o2.startPoint?.x ?? 0) - 35.0) < 1e-4)
        #expect(abs((o2.startPoint?.y ?? 0) - 5.0) < 1e-4)
        #expect(abs((o2.endPoint?.x ?? 0) - 35.0) < 1e-4)
        #expect(abs((o2.endPoint?.y ?? 0) - 25.0) < 1e-4)

        #expect(abs((o3.startPoint?.x ?? 0) - 35.0) < 1e-4)
        #expect(abs((o3.startPoint?.y ?? 0) - 25.0) < 1e-4)
        #expect(abs((o3.endPoint?.x ?? 0) - 5.0) < 1e-4)
        #expect(abs((o3.endPoint?.y ?? 0) - 25.0) < 1e-4)

        #expect(abs((o4.startPoint?.x ?? 0) - 5.0) < 1e-4)
        #expect(abs((o4.startPoint?.y ?? 0) - 25.0) < 1e-4)
        #expect(abs((o4.endPoint?.x ?? 0) - 5.0) < 1e-4)
        #expect(abs((o4.endPoint?.y ?? 0) - 5.0) < 1e-4)
    }

    @Test func testDegenerateOffsetThrows() {
        let line = SketchEntity.line(start: .zero, end: SIMD2<Double>(10, 0))

        // Empty entities
        #expect(throws: SketchError.self) {
            _ = try SketchOffset.makeOffset(entities: [], distance: 5.0)
        }

        // Zero distance
        #expect(throws: SketchError.self) {
            _ = try SketchOffset.makeOffset(entities: [line], distance: 0.0)
        }

        // Circle offset to negative or zero radius
        let circle = SketchEntity.circle(center: .zero, radius: 5.0)
        #expect(throws: SketchError.self) {
            _ = try SketchOffset.makeOffset(entities: [circle], distance: -6.0)
        }
    }
}
