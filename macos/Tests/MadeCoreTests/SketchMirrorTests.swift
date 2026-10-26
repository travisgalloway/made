import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchMirrorTests {

    @Test func testLineMirrorAcrossAxisAndSymmetricConstraint() throws {
        // Mirror line along Y axis: (0, -10) to (0, 10)
        let mirrorLine = SketchEntity.line(
            start: SIMD2<Double>(0, -10),
            end: SIMD2<Double>(0, 10),
            isConstruction: true
        )

        let line = SketchEntity.line(
            start: SIMD2<Double>(5, 2),
            end: SIMD2<Double>(15, 8)
        )

        let result = try SketchMirror.makeMirror(entities: [line], mirrorLine: mirrorLine)

        #expect(result.entities.count == 1)
        #expect(result.constraints.count == 1)

        let mirroredLine = result.entities[0]
        let sPrime = try #require(mirroredLine.startPoint)
        let ePrime = try #require(mirroredLine.endPoint)

        #expect(abs(sPrime.x - (-5.0)) < 1e-4)
        #expect(abs(sPrime.y - 2.0) < 1e-4)
        #expect(abs(ePrime.x - (-15.0)) < 1e-4)
        #expect(abs(ePrime.y - 8.0) < 1e-4)

        let constraint = result.constraints[0]
        #expect(constraint.kind == .symmetric)
        #expect(constraint.entityIds == [line.id, mirroredLine.id])
        #expect(constraint.referenceEntityId == mirrorLine.id)
    }

    @Test func testArcMirrorChiralityReversal() throws {
        // Vertical mirror line along X = 0
        let mirrorLine = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(0, 20)
        )

        // Arc in quadrant 1, counter-clockwise (clockwise == false)
        let arc = SketchEntity.arc(
            start: SIMD2<Double>(10, 0),
            end: SIMD2<Double>(0, 10),
            center: SIMD2<Double>(0, 0),
            clockwise: false
        )

        let result = try SketchMirror.makeMirror(entities: [arc], mirrorLine: mirrorLine)

        #expect(result.entities.count == 1)
        let mirroredArc = result.entities[0]

        // Reflection across X=0 must invert chirality from false to true
        #expect(mirroredArc.isClockwise == true)

        let sPrime = try #require(mirroredArc.startPoint)
        let ePrime = try #require(mirroredArc.endPoint)

        #expect(abs(sPrime.x - (-10.0)) < 1e-4)
        #expect(abs(sPrime.y - 0.0) < 1e-4)
        #expect(abs(ePrime.x - 0.0) < 1e-4)
        #expect(abs(ePrime.y - 10.0) < 1e-4)
    }

    @Test func testCircleMirrorAcrossAxis() throws {
        // Mirror line along Y = 10 (horizontal line)
        let mirrorLine = SketchEntity.line(
            start: SIMD2<Double>(0, 10),
            end: SIMD2<Double>(30, 10)
        )

        let circle = SketchEntity.circle(
            center: SIMD2<Double>(15, 2),
            radius: 4.0
        )

        let result = try SketchMirror.makeMirror(entities: [circle], mirrorLine: mirrorLine)

        #expect(result.entities.count == 1)
        let mirrored = result.entities[0]

        let cPrime = try #require(mirrored.centerPoint)
        // Y reflects across Y=10: 10 + (10 - 2) = 18
        #expect(abs(cPrime.x - 15.0) < 1e-4)
        #expect(abs(cPrime.y - 18.0) < 1e-4)
        #expect(abs((mirrored.radius ?? 0) - 4.0) < 1e-4)
    }

    @Test func testPointOnAxisGeneratesCoincidentConstraint() throws {
        // Mirror line along X axis (Y = 0)
        let mirrorLine = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(50, 0)
        )

        // Line with start endpoint exactly on axis at (10, 0) and end at (20, 15)
        let line = SketchEntity.line(
            start: SIMD2<Double>(10, 0),
            end: SIMD2<Double>(20, 15)
        )

        let result = try SketchMirror.makeMirror(entities: [line], mirrorLine: mirrorLine)

        #expect(result.entities.count == 1)
        // 1 symmetric constraint + 1 coincident constraint with mirrorLine = 2 constraints
        #expect(result.constraints.count == 2)

        let coincident = result.constraints.first { $0.kind == .coincident }
        #expect(coincident != nil)
        #expect(coincident?.entityIds.contains(result.entities[0].id) == true)
        #expect(coincident?.entityIds.contains(mirrorLine.id) == true)
    }

    @Test func testDegenerateMirrorThrows() {
        let line = SketchEntity.line(start: .zero, end: SIMD2<Double>(10, 0))

        // Mirror axis with zero length
        let zeroLine = SketchEntity.line(start: .zero, end: .zero)
        #expect(throws: SketchError.self) {
            _ = try SketchMirror.makeMirror(entities: [line], mirrorLine: zeroLine)
        }

        // Mirror axis is not a line
        let circle = SketchEntity.circle(center: .zero, radius: 10)
        #expect(throws: SketchError.self) {
            _ = try SketchMirror.makeMirror(entities: [line], mirrorLine: circle)
        }

        // Empty entities list
        #expect(throws: SketchError.self) {
            _ = try SketchMirror.makeMirror(entities: [], mirrorLine: line)
        }
    }

    @Test func testEllipseMirrorReflection() throws {
        // Mirror line along Y axis (X = 0)
        let mirrorLine = SketchEntity.line(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(0, 100)
        )

        let ellipse = SketchEntity.ellipse(
            center: SIMD2<Double>(20, 30),
            radiusX: 15,
            radiusY: 8,
            rotation: .pi / 6.0
        )

        let result = try SketchMirror.makeMirror(entities: [ellipse], mirrorLine: mirrorLine)

        #expect(result.entities.count == 1)
        let mirrored = result.entities[0]

        let cPrime = try #require(mirrored.centerPoint)
        #expect(abs(cPrime.x - (-20.0)) < 1e-4)
        #expect(abs(cPrime.y - 30.0) < 1e-4)

        // Mirror axis angle is pi/2. Reflected angle = 2*(pi/2) - pi/6 = pi - pi/6 = 5*pi/6
        let expectedRot = .pi - (.pi / 6.0)
        #expect(abs((mirrored.rotationAngle ?? 0) - expectedRot) < 1e-4)
    }
}
