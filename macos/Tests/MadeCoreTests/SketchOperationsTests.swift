import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchOperationsTests {

    // MARK: - Line Trimming

    @Test func testLineTrimStartSegment() throws {
        // Line from (0,0) to (10,0) crossed by line from (3,-5) to (3,5)
        let mainLine = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let crossLine = SketchEntity.line(start: SIMD2(3, -5), end: SIMD2(3, 5))
        let entities = [mainLine, crossLine]

        // Click near (1, 0) should trim start segment [0, 3]
        let result = try SketchOperations.trim(entity: mainLine, at: SIMD2(1, 0), in: entities)
        guard case .updated(let updated) = result else {
            Issue.record("Expected .updated result")
            return
        }
        #expect(updated.id == mainLine.id)
        #expect(abs(updated.startPoint!.x - 3.0) < 1e-4)
        #expect(abs(updated.startPoint!.y - 0.0) < 1e-4)
        #expect(abs(updated.endPoint!.x - 10.0) < 1e-4)
    }

    @Test func testLineTrimEndSegment() throws {
        // Line from (0,0) to (10,0) crossed by line at x = 7
        let mainLine = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let crossLine = SketchEntity.line(start: SIMD2(7, -5), end: SIMD2(7, 5))
        let entities = [mainLine, crossLine]

        // Click near (9, 0) should trim end segment [7, 10]
        let result = try SketchOperations.trim(entity: mainLine, at: SIMD2(9, 0), in: entities)
        guard case .updated(let updated) = result else {
            Issue.record("Expected .updated result")
            return
        }
        #expect(updated.id == mainLine.id)
        #expect(abs(updated.startPoint!.x - 0.0) < 1e-4)
        #expect(abs(updated.endPoint!.x - 7.0) < 1e-4)
    }

    @Test func testLineTrimMiddleSegmentDivided() throws {
        // Line from (0,0) to (10,0) crossed by lines at x = 3 and x = 7
        let mainLine = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let cross1 = SketchEntity.line(start: SIMD2(3, -5), end: SIMD2(3, 5))
        let cross2 = SketchEntity.line(start: SIMD2(7, -5), end: SIMD2(7, 5))
        let entities = [mainLine, cross1, cross2]

        // Click near (5, 0) should trim interior interval [3, 7]
        let result = try SketchOperations.trim(entity: mainLine, at: SIMD2(5, 0), in: entities)
        guard case .divided(let part1, let part2) = result else {
            Issue.record("Expected .divided result")
            return
        }
        #expect(part1.id == mainLine.id)
        #expect(abs(part1.startPoint!.x - 0.0) < 1e-4)
        #expect(abs(part1.endPoint!.x - 3.0) < 1e-4)

        #expect(part2.id != mainLine.id)
        #expect(abs(part2.startPoint!.x - 7.0) < 1e-4)
        #expect(abs(part2.endPoint!.x - 10.0) < 1e-4)
    }

    @Test func testLineTrimZeroIntersectionsDeletes() throws {
        // Standalone isolated line with no intersections
        let mainLine = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let otherLine = SketchEntity.line(start: SIMD2(0, 5), end: SIMD2(10, 5)) // parallel, no intersection
        let entities = [mainLine, otherLine]

        let result = try SketchOperations.trim(entity: mainLine, at: SIMD2(5, 0), in: entities)
        guard case .deleted(let id) = result else {
            Issue.record("Expected .deleted result")
            return
        }
        #expect(id == mainLine.id)
    }

    // MARK: - Arc Trimming

    @Test func testArcTrimStartSegment() throws {
        // Semicircle arc centered at (0,0), radius 5, from (5,0) CCW to (-5,0)
        let arc = SketchEntity.arc(start: SIMD2(5, 0), end: SIMD2(-5, 0), center: SIMD2(0, 0), clockwise: false)
        // Crossed by line along Y-axis from (0, -1) to (0, 6) intersecting at (0, 5)
        let cross = SketchEntity.line(start: SIMD2(0, -1), end: SIMD2(0, 6))
        let entities = [arc, cross]

        // Click at angle pi/4 (approx (3.5, 3.5)) trims start segment [0, pi/2]
        let result = try SketchOperations.trim(entity: arc, at: SIMD2(3.5, 3.5), in: entities)
        guard case .updated(let updated) = result else {
            Issue.record("Expected .updated result")
            return
        }
        #expect(updated.id == arc.id)
        #expect(abs(updated.startPoint!.x - 0.0) < 1e-3)
        #expect(abs(updated.startPoint!.y - 5.0) < 1e-3)
        #expect(abs(updated.endPoint!.x - (-5.0)) < 1e-3)
    }

    @Test func testArcTrimEndSegment() throws {
        // Semicircle arc centered at (0,0), radius 5, from (5,0) CCW to (-5,0)
        let arc = SketchEntity.arc(start: SIMD2(5, 0), end: SIMD2(-5, 0), center: SIMD2(0, 0), clockwise: false)
        // Crossed by line at (0, 5)
        let cross = SketchEntity.line(start: SIMD2(0, -1), end: SIMD2(0, 6))
        let entities = [arc, cross]

        // Click at angle 3pi/4 (approx (-3.5, 3.5)) trims end segment [pi/2, pi]
        let result = try SketchOperations.trim(entity: arc, at: SIMD2(-3.5, 3.5), in: entities)
        guard case .updated(let updated) = result else {
            Issue.record("Expected .updated result")
            return
        }
        #expect(updated.id == arc.id)
        #expect(abs(updated.startPoint!.x - 5.0) < 1e-3)
        #expect(abs(updated.endPoint!.x - 0.0) < 1e-3)
        #expect(abs(updated.endPoint!.y - 5.0) < 1e-3)
    }

    @Test func testArcTrimMiddleSegmentDivided() throws {
        // Three-quarter arc from (5,0) CCW through (0,5), (-5,0) to (0,-5)
        let arc = SketchEntity.arc(start: SIMD2(5, 0), end: SIMD2(0, -5), center: SIMD2(0, 0), clockwise: false)
        let cross1 = SketchEntity.line(start: SIMD2(0, -1), end: SIMD2(0, 6)) // intersects at (0,5)
        let cross2 = SketchEntity.line(start: SIMD2(-6, 0), end: SIMD2(1, 0)) // intersects at (-5,0)
        let entities = [arc, cross1, cross2]

        // Click in middle quadrant between (0,5) and (-5,0)
        let result = try SketchOperations.trim(entity: arc, at: SIMD2(-3.5, 3.5), in: entities)
        guard case .divided(let part1, let part2) = result else {
            Issue.record("Expected .divided result")
            return
        }
        #expect(part1.id == arc.id)
        #expect(abs(part1.endPoint!.x - 0.0) < 1e-3)
        #expect(abs(part1.endPoint!.y - 5.0) < 1e-3)

        #expect(part2.id != arc.id)
        #expect(abs(part2.startPoint!.x - (-5.0)) < 1e-3)
        #expect(abs(part2.endPoint!.x - 0.0) < 1e-3)
        #expect(abs(part2.endPoint!.y - (-5.0)) < 1e-3)
    }

    // MARK: - Circle Trimming

    @Test func testCircleTrimWithTwoIntersectionsBecomesArc() throws {
        // Circle centered at (0,0), radius 5
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 5)
        // Bisected by line along X axis from (-6, 0) to (6, 0), intersecting at (-5,0) and (5,0)
        let diamLine = SketchEntity.line(start: SIMD2(-6, 0), end: SIMD2(6, 0))
        let entities = [circle, diamLine]

        // Click top half near (0, 5)
        let result = try SketchOperations.trim(entity: circle, at: SIMD2(0, 5), in: entities)
        guard case .updated(let remaining) = result else {
            Issue.record("Expected .updated result")
            return
        }
        #expect(remaining.id == circle.id)
        #expect(remaining.kind == "arc")
        // Trimmed top half [0, pi], remaining is bottom half from (-5, 0) through (0, -5) to (5, 0)
        #expect(abs(remaining.centerPoint!.x - 0.0) < 1e-4)
        #expect(abs(remaining.centerPoint!.y - 0.0) < 1e-4)
        #expect(abs(remaining.radius! - 5.0) < 1e-4)
        #expect(abs(remaining.startPoint!.x - (-5.0)) < 1e-3)
        #expect(abs(remaining.endPoint!.x - 5.0) < 1e-3)
    }

    @Test func testCircleTrimZeroOrOneIntersectionDeletes() throws {
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 5)
        let farLine = SketchEntity.line(start: SIMD2(10, 0), end: SIMD2(20, 0))
        let entities = [circle, farLine]

        let result = try SketchOperations.trim(entity: circle, at: SIMD2(5, 0), in: entities)
        guard case .deleted(let id) = result else {
            Issue.record("Expected .deleted result")
            return
        }
        #expect(id == circle.id)
    }

    // MARK: - Drag Trim ("Power Trim")

    @Test func testDragTrimCrossings() throws {
        // Three vertical parallel lines at x = 2, 4, 6
        let l1 = SketchEntity.line(start: SIMD2(2, 0), end: SIMD2(2, 10))
        let l2 = SketchEntity.line(start: SIMD2(4, 0), end: SIMD2(4, 10))
        let l3 = SketchEntity.line(start: SIMD2(6, 0), end: SIMD2(6, 10))
        // Crossing horizontal boundary at y = 5
        let bound = SketchEntity.line(start: SIMD2(0, 5), end: SIMD2(8, 5))
        var entities = [l1, l2, l3, bound]

        // Drag stroke crossing top half of l1 and l2 at y = 8
        let strokePath = [SIMD2(1.0, 8.0), SIMD2(5.0, 8.0)]
        let results = SketchOperations.trimAlongPath(path: strokePath, in: &entities)

        #expect(results.count == 2)
        // Top half trimmed on both l1 and l2 (end updated from 10 to 5)
        let updatedL1 = entities.first(where: { $0.id == l1.id })!
        #expect(abs(updatedL1.endPoint!.y - 5.0) < 1e-4)
        let updatedL2 = entities.first(where: { $0.id == l2.id })!
        #expect(abs(updatedL2.endPoint!.y - 5.0) < 1e-4)

        // l3 was not crossed by stroke, remains intact
        let intactL3 = entities.first(where: { $0.id == l3.id })!
        #expect(abs(intactL3.endPoint!.y - 10.0) < 1e-4)
    }

    // MARK: - Extend Operations

    @Test func testLineExtendEndToBoundary() throws {
        // Line from (0,0) to (5,0)
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(5, 0))
        // Vertical boundary line at x = 12
        let boundary = SketchEntity.line(start: SIMD2(12, -10), end: SIMD2(12, 10))
        let entities = [line, boundary]

        let extended = try SketchOperations.extend(entity: line, targetEnd: .end, in: entities)
        #expect(extended.id == line.id)
        #expect(abs(extended.startPoint!.x - 0.0) < 1e-4)
        #expect(abs(extended.endPoint!.x - 12.0) < 1e-4)
        #expect(abs(extended.endPoint!.y - 0.0) < 1e-4)
    }

    @Test func testLineExtendStartToBoundary() throws {
        // Line from (5,0) to (10,0)
        let line = SketchEntity.line(start: SIMD2(5, 0), end: SIMD2(10, 0))
        // Vertical boundary line at x = -4
        let boundary = SketchEntity.line(start: SIMD2(-4, -10), end: SIMD2(-4, 10))
        let entities = [line, boundary]

        let extended = try SketchOperations.extend(entity: line, targetEnd: .start, in: entities)
        #expect(extended.id == line.id)
        #expect(abs(extended.startPoint!.x - (-4.0)) < 1e-4)
        #expect(abs(extended.startPoint!.y - 0.0) < 1e-4)
        #expect(abs(extended.endPoint!.x - 10.0) < 1e-4)
    }

    @Test func testLineExtendNoIntersectionThrows() throws {
        // Line pointing away from or parallel to other geometry
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(5, 0))
        let parallelLine = SketchEntity.line(start: SIMD2(0, 2), end: SIMD2(5, 2))
        let entities = [line, parallelLine]

        #expect(throws: SketchError.noIntersection("No intersecting boundary found to extend line")) {
            _ = try SketchOperations.extend(entity: line, targetEnd: .end, in: entities)
        }
    }

    @Test func testArcExtendToBoundary() throws {
        // Quarter-arc from (5,0) to (0,5), centered at (0,0), radius 5
        let arc = SketchEntity.arc(start: SIMD2(5, 0), end: SIMD2(0, 5), center: SIMD2(0, 0), clockwise: false)
        // Horizontal boundary line at y = 0 from (-10,0) to (-1,0) - crosses arc circle at (-5,0)
        let boundary = SketchEntity.line(start: SIMD2(-10, 0), end: SIMD2(-1, 0))
        let entities = [arc, boundary]

        let extended = try SketchOperations.extend(entity: arc, targetEnd: .end, in: entities)
        #expect(extended.id == arc.id)
        #expect(abs(extended.startPoint!.x - 5.0) < 1e-3)
        #expect(abs(extended.endPoint!.x - (-5.0)) < 1e-3)
        #expect(abs(extended.endPoint!.y - 0.0) < 1e-3)
    }

    @Test func testCircleExtendThrowsInvalidEntity() throws {
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 5)
        #expect(throws: SketchError.invalidEntity("Circle entities cannot be extended")) {
            _ = try SketchOperations.extend(entity: circle, targetEnd: .end, in: [circle])
        }
    }

    // MARK: - Split Operations

    @Test func testLineSplitAtInteriorPoint() throws {
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let splitPt = SIMD2(4.0, 0.0)

        let (part1, part2) = try SketchOperations.split(entity: line, at: splitPt)
        #expect(part1.id == line.id)
        #expect(abs(part1.startPoint!.x - 0.0) < 1e-4)
        #expect(abs(part1.endPoint!.x - 4.0) < 1e-4)

        #expect(part2.id != line.id)
        #expect(abs(part2.startPoint!.x - 4.0) < 1e-4)
        #expect(abs(part2.endPoint!.x - 10.0) < 1e-4)
    }

    @Test func testLineSplitOffEntityThrows() throws {
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let offPt = SIMD2(4.0, 5.0)

        #expect(throws: SketchError.pointNotOnEntity(entityId: line.id)) {
            _ = try SketchOperations.split(entity: line, at: offPt)
        }
    }

    @Test func testLineSplitAtEndpointThrows() throws {
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let endpoint = SIMD2(0.0, 0.0)

        #expect(throws: SketchError.invalidEntity("Split point cannot be at or beyond endpoints")) {
            _ = try SketchOperations.split(entity: line, at: endpoint)
        }
    }

    @Test func testArcSplitAtInteriorPoint() throws {
        // Semicircle arc from (5,0) to (-5,0), center (0,0), radius 5
        let arc = SketchEntity.arc(start: SIMD2(5, 0), end: SIMD2(-5, 0), center: SIMD2(0, 0), clockwise: false)
        let splitPt = SIMD2(0.0, 5.0)

        let (part1, part2) = try SketchOperations.split(entity: arc, at: splitPt)
        #expect(part1.id == arc.id)
        #expect(abs(part1.startPoint!.x - 5.0) < 1e-3)
        #expect(abs(part1.endPoint!.y - 5.0) < 1e-3)

        #expect(part2.id != arc.id)
        #expect(abs(part2.startPoint!.y - 5.0) < 1e-3)
        #expect(abs(part2.endPoint!.x - (-5.0)) < 1e-3)
    }

    @Test func testCircleSplitIntoTwoSemicircles() throws {
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 5)
        let splitPt = SIMD2(0.0, 5.0)

        let (arc1, arc2) = try SketchOperations.split(entity: circle, at: splitPt)
        #expect(arc1.id == circle.id)
        #expect(arc1.kind == "arc")
        #expect(abs(arc1.startPoint!.x - 0.0) < 1e-3)
        #expect(abs(arc1.startPoint!.y - 5.0) < 1e-3)
        #expect(abs(arc1.endPoint!.x - 0.0) < 1e-3)
        #expect(abs(arc1.endPoint!.y - (-5.0)) < 1e-3) // antipode

        #expect(arc2.id != circle.id)
        #expect(arc2.kind == "arc")
        #expect(abs(arc2.startPoint!.x - 0.0) < 1e-3)
        #expect(abs(arc2.startPoint!.y - (-5.0)) < 1e-3)
        #expect(abs(arc2.endPoint!.x - 0.0) < 1e-3)
        #expect(abs(arc2.endPoint!.y - 5.0) < 1e-3)
    }

    // MARK: - Hit Testing

    @Test func testHitTestEntity() throws {
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0))
        let circle = SketchEntity.circle(center: SIMD2(20, 20), radius: 5)
        let entities = [line, circle]

        let hitLine = SketchOperations.hitTestEntity(at: SIMD2(5, 0.1), in: entities, maxDistance: 0.5)
        #expect(hitLine?.id == line.id)

        let hitCircle = SketchOperations.hitTestEntity(at: SIMD2(25.1, 20), in: entities, maxDistance: 0.5)
        #expect(hitCircle?.id == circle.id)

        let miss = SketchOperations.hitTestEntity(at: SIMD2(100, 100), in: entities, maxDistance: 0.5)
        #expect(miss == nil)
    }
}
