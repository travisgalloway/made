import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct ConstraintSolverTests {

    @Test func testSlice1ParallelAndPerpendicular() {
        // Parallel lines test
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 8)) // Not parallel initially
        let parallelConstraint = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])

        let systemParallel = ConstraintSystem(
            entities: [lineA, lineB],
            constraints: [parallelConstraint],
            fixedEntityIds: [lineA.id]
        )
        let resultParallel = ConstraintSolver.solve(system: systemParallel)

        #expect(resultParallel.status.isConverged)
        if let solvedB = resultParallel.solvedEntities.first(where: { $0.id == lineB.id }),
           let s = solvedB.startPoint, let e = solvedB.endPoint {
            let v = e - s
            let slope = v.y / max(1e-6, abs(v.x))
            #expect(abs(slope) < 1e-3, "Line B should be horizontal/parallel to Line A")
        }

        // Perpendicular lines test
        let lineC = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineD = SketchEntity.line(start: SIMD2<Double>(5, 0), end: SIMD2<Double>(12, 10)) // Not perpendicular initially
        let perpConstraint = SketchConstraint(kind: .perpendicular, entityIds: [lineC.id, lineD.id])

        let systemPerp = ConstraintSystem(
            entities: [lineC, lineD],
            constraints: [perpConstraint],
            fixedEntityIds: [lineC.id]
        )
        let resultPerp = ConstraintSolver.solve(system: systemPerp)

        #expect(resultPerp.status.isConverged)
        if let solvedD = resultPerp.solvedEntities.first(where: { $0.id == lineD.id }),
           let s = solvedD.startPoint, let e = solvedD.endPoint {
            let v = e - s
            #expect(abs(v.x) < 1e-3, "Line D should be vertical (perpendicular to horizontal Line C)")
        }
    }

    @Test func testSlice2TangentAndConcentric() {
        // Line-circle tangency
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(20, 0))
        let circle = SketchEntity.circle(center: SIMD2<Double>(10, 15), radius: 10.0) // Distance is 15, radius 10
        let tangentConstraint = SketchConstraint(kind: .tangent, entityIds: [line.id, circle.id])

        let systemTangent = ConstraintSystem(
            entities: [line, circle],
            constraints: [tangentConstraint],
            fixedEntityIds: [line.id]
        )
        let resultTangent = ConstraintSolver.solve(system: systemTangent)

        #expect(resultTangent.status.isConverged)
        if let solvedCircle = resultTangent.solvedEntities.first(where: { $0.id == circle.id }),
           let center = solvedCircle.centerPoint, let r = solvedCircle.radius {
            #expect(abs(abs(center.y) - r) < 1e-3, "Circle should be tangent to Line at y=0")
        }

        // Concentric circles
        let circleA = SketchEntity.circle(center: SIMD2<Double>(5, 5), radius: 10.0)
        let circleB = SketchEntity.circle(center: SIMD2<Double>(12, 8), radius: 20.0)
        let concentricConstraint = SketchConstraint(kind: .concentric, entityIds: [circleA.id, circleB.id])

        let systemConcentric = ConstraintSystem(
            entities: [circleA, circleB],
            constraints: [concentricConstraint],
            fixedEntityIds: [circleA.id]
        )
        let resultConcentric = ConstraintSolver.solve(system: systemConcentric)

        #expect(resultConcentric.status.isConverged)
        if let solvedB = resultConcentric.solvedEntities.first(where: { $0.id == circleB.id }),
           let centerB = solvedB.centerPoint {
            #expect(abs(centerB.x - 5.0) < 1e-3)
            #expect(abs(centerB.y - 5.0) < 1e-3)
        }
    }

    @Test func testSlice3Symmetry() {
        // Axis line along Y axis (x = 0)
        let axis = SketchEntity.line(start: SIMD2<Double>(0, -50), end: SIMD2<Double>(0, 50))
        let lineA = SketchEntity.line(start: SIMD2<Double>(-10, 0), end: SIMD2<Double>(-10, 20))
        let lineB = SketchEntity.line(start: SIMD2<Double>(15, 2), end: SIMD2<Double>(12, 22)) // Asymmetric initially

        let symConstraint = SketchConstraint(
            kind: .symmetric,
            entityIds: [lineA.id, lineB.id],
            referenceEntityId: axis.id
        )

        let system = ConstraintSystem(
            entities: [axis, lineA, lineB],
            constraints: [symConstraint],
            fixedEntityIds: [axis.id, lineA.id]
        )
        let result = ConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        if let solvedB = result.solvedEntities.first(where: { $0.id == lineB.id }),
           let sB = solvedB.startPoint, let eB = solvedB.endPoint {
            // Line A is x = -10, y from 0 to 20 -> Line B should be x = +10, y from 0 to 20
            #expect(abs(sB.x - 10.0) < 1e-2)
            #expect(abs(eB.x - 10.0) < 1e-2)
            #expect(abs(abs(eB.y - sB.y) - 20.0) < 1e-2)
        }
    }

    @Test func testInteractiveDragWithMinimalMovement() {
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(0, 10))
        let perp = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])

        let system = ConstraintSystem(entities: [lineA, lineB], constraints: [perp])

        // Drag lineA endpoint from (10, 0) to (10, 10) (45 degree line)
        let drag = DragTarget(entityId: lineA.id, endpoint: .end, targetPosition: SIMD2<Double>(10, 10))
        let result = ConstraintSolver.solve(system: system, dragTarget: drag)

        #expect(result.status.isConverged)
        if let solvedA = result.solvedEntities.first(where: { $0.id == lineA.id }),
           let solvedB = result.solvedEntities.first(where: { $0.id == lineB.id }),
           let sA = solvedA.startPoint, let eA = solvedA.endPoint,
           let sB = solvedB.startPoint, let eB = solvedB.endPoint {
            let vA = eA - sA
            let vB = eB - sB
            let dot = vA.x * vB.x + vA.y * vB.y
            #expect(abs(dot) < 1e-2, "Lines must remain perpendicular after dragging")
        }
    }

    @Test func testConflictingConstraintsReportOverConstrained() {
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))

        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])

        let system = ConstraintSystem(entities: [lineA, lineB], constraints: [c1, c2])
        let result = ConstraintSolver.solve(system: system)

        switch result.status {
        case .overConstrained(let conflicting):
            #expect(conflicting.contains(c1.id))
            #expect(conflicting.contains(c2.id))
        default:
            Issue.record("Expected overConstrained status for parallel + perpendicular constraints, got \(result.status)")
        }
    }

    @Test func testConflictingParallelAndPerpendicularConstraints() {
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))

        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])

        let system = ConstraintSystem(entities: [lineA, lineB], constraints: [c1, c2])
        let dofStatus = ConstraintSolver.computeDOFStatus(system: system)

        if case .overConstrained = dofStatus {
            // Expected
        } else {
            Issue.record("Expected DOF status to be overConstrained, got \(dofStatus)")
        }
    }

    @Test func testRedundantParallelConstraints() {
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))

        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        let c2 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])

        let system = ConstraintSystem(entities: [lineA, lineB], constraints: [c1, c2])
        let result = ConstraintSolver.solve(system: system)

        switch result.status {
        case .redundant(let redundantIds):
            #expect(!redundantIds.isEmpty)
        default:
            Issue.record("Expected redundant status for duplicate parallel constraints, got \(result.status)")
        }
    }

    @Test func testDegenerateNonConvergence() {
        // Fixed circle at (0, 0) r=10 and fixed circle at (100, 0) r=10
        // Tangency is impossible when both are locked at distance 100
        let cA = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 10.0)
        let cB = SketchEntity.circle(center: SIMD2<Double>(100, 0), radius: 10.0)
        let tangent = SketchConstraint(kind: .tangent, entityIds: [cA.id, cB.id])

        let system = ConstraintSystem(
            entities: [cA, cB],
            constraints: [tangent],
            fixedEntityIds: [cA.id, cB.id]
        )
        let result = ConstraintSolver.solve(system: system)

        // Must not crash or produce NaNs
        #expect(!result.status.isConverged)
        for e in result.solvedEntities {
            if let c = e.centerPoint {
                #expect(!c.x.isNaN)
                #expect(!c.y.isNaN)
            }
        }
    }

    @Test func testDegreesOfFreedomCalculation() {
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let systemFree = ConstraintSystem(entities: [line], constraints: [])
        let dofFree = ConstraintSolver.computeDOFStatus(system: systemFree)
        #expect(dofFree == .underConstrained(dof: 4))

        let horizontal = SketchConstraint(kind: .horizontal, entityIds: [line.id])
        let systemH = ConstraintSystem(entities: [line], constraints: [horizontal])
        let dofH = ConstraintSolver.computeDOFStatus(system: systemH)
        #expect(dofH == .underConstrained(dof: 3))
    }

    @Test func testConstraintSolverActorOffMainThread() async {
        let actor = ConstraintSolverActor()
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 8))
        let parallelConstraint = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])

        let system = ConstraintSystem(
            entities: [lineA, lineB],
            constraints: [parallelConstraint],
            fixedEntityIds: [lineA.id]
        )
        let result = await actor.solve(system: system)
        #expect(result.status.isConverged)

        let status = await actor.computeDOFStatus(system: system)
        #expect(status != .inactive)
    }
}
