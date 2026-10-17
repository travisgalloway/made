import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct ConstraintInferenceTests {

    @Test func testParallelInferenceWithinTolerance() {
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(100, 0))
        // Line B at angle ~2 degrees (< 5 degree tolerance)
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 20), end: SIMD2<Double>(100, 23))

        let candidates = ConstraintInference.inferConstraints(between: lineA, and: lineB)
        #expect(candidates.contains(where: { $0.kind == .parallel }))
    }

    @Test func testPerpendicularInferenceWithinTolerance() {
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(100, 0))
        // Line B at angle ~88 degrees (within 5 degrees of 90)
        let lineB = SketchEntity.line(start: SIMD2<Double>(50, 0), end: SIMD2<Double>(52, 100))

        let candidates = ConstraintInference.inferConstraints(between: lineA, and: lineB)
        #expect(candidates.contains(where: { $0.kind == .perpendicular }))
    }

    @Test func testTangencyInference() {
        // Line at y=0, Circle at (20, 10.4) with r=10.0 (distance 10.4 is within 1.0mm tolerance of r=10)
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(100, 0))
        let circle = SketchEntity.circle(center: SIMD2<Double>(20, 10.4), radius: 10.0)

        let candidates = ConstraintInference.inferConstraints(between: line, and: circle)
        #expect(candidates.contains(where: { $0.kind == .tangent }))

        // Circle-circle tangency
        let c1 = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 10.0)
        let c2 = SketchEntity.circle(center: SIMD2<Double>(20.5, 0), radius: 10.0) // Distance 20.5 ~ 20.0 (r1+r2)
        let circleCandidates = ConstraintInference.inferConstraints(between: c1, and: c2)
        #expect(circleCandidates.contains(where: { $0.kind == .tangent }))
    }

    @Test func testConcentricInference() {
        let c1 = SketchEntity.circle(center: SIMD2<Double>(10, 10), radius: 5.0)
        let c2 = SketchEntity.circle(center: SIMD2<Double>(10.3, 10.2), radius: 15.0) // Offset ~0.36mm <= 1.0mm

        let candidates = ConstraintInference.inferConstraints(between: c1, and: c2)
        #expect(candidates.contains(where: { $0.kind == .concentric }))
    }

    @Test func testSymmetryInference() {
        let axis = SketchEntity.line(start: SIMD2<Double>(0, -50), end: SIMD2<Double>(0, 50))
        let lineA = SketchEntity.line(start: SIMD2<Double>(-20, 10), end: SIMD2<Double>(-20, 40))
        let lineB = SketchEntity.line(start: SIMD2<Double>(20.2, 10.1), end: SIMD2<Double>(19.8, 39.9))

        let candidates = ConstraintInference.inferConstraints(between: lineA, and: lineB, referenceEntity: axis)
        #expect(candidates.contains(where: { $0.kind == .symmetric }))
    }

    @Test func testNegativeInferenceRejectsNonConformingAnglesAndDistances() {
        // Two lines at 45 degrees
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(100, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(100, 100))

        let candidates = ConstraintInference.inferConstraints(between: lineA, and: lineB)
        #expect(!candidates.contains(where: { $0.kind == .parallel }))
        #expect(!candidates.contains(where: { $0.kind == .perpendicular }))

        // Circle far from line
        let circle = SketchEntity.circle(center: SIMD2<Double>(50, 50), radius: 10.0)
        let tangentCandidates = ConstraintInference.inferConstraints(between: lineA, and: circle)
        #expect(!tangentCandidates.contains(where: { $0.kind == .tangent }))
    }

    @Test func testBatchCandidateInferenceDeduplication() {
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 10), end: SIMD2<Double>(10, 10))

        let existing = [SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])]
        let candidates = ConstraintInference.inferCandidates(for: [lineA, lineB], existingConstraints: existing)

        // Existing constraint must be filtered out
        #expect(candidates.isEmpty)
    }
}
