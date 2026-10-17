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

        let entityDOF = await actor.computeEntityDOF(system: system)
        #expect(entityDOF[lineA.id] == .fullyConstrained)
        #expect(entityDOF[lineB.id] == .underConstrained(dof: 3))
    }

    @Test func testComputeNullSpaceBasis() {
        // Under-determined matrix: 1 row, 3 columns (x + 2y + 3z = 0)
        let A_under = [[1.0, 2.0, 3.0]]
        let V_under = ConstraintSolver.computeNullSpaceBasis(A_under)
        #expect(V_under.count == 3)
        #expect(V_under[0].count == 2)
        #expect(ConstraintSolver.computeRank(V_under) == 2)

        // Verify A * v == 0 for all basis vectors
        for col in 0..<2 {
            let v = [V_under[0][col], V_under[1][col], V_under[2][col]]
            let dot = A_under[0][0] * v[0] + A_under[0][1] * v[1] + A_under[0][2] * v[2]
            #expect(abs(dot) < 1e-6)
        }

        // Full rank matrix: 2 rows, 2 columns (x = 0, y = 0 -> only trivial solution)
        let A_full = [
            [1.0, 0.0],
            [0.0, 1.0]
        ]
        let V_full = ConstraintSolver.computeNullSpaceBasis(A_full)
        #expect(V_full.count == 2)
        #expect(V_full[0].isEmpty)
        #expect(ConstraintSolver.computeRank(V_full) == 0)

        // Redundant matrix: 2 rows, 3 columns with row 2 = 2 * row 1
        let A_redundant = [
            [1.0, 0.0, -1.0],
            [2.0, 0.0, -2.0]
        ]
        let V_redundant = ConstraintSolver.computeNullSpaceBasis(A_redundant)
        #expect(V_redundant.count == 3)
        #expect(V_redundant[0].count == 2)
        #expect(ConstraintSolver.computeRank(V_redundant) == 2)

        // Empty matrix
        let V_empty = ConstraintSolver.computeNullSpaceBasis([])
        #expect(V_empty.isEmpty)
    }

    @Test func testBaselineEntityDOF() {
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let circle = SketchEntity.circle(center: SIMD2<Double>(5, 5), radius: 10)
        let arc = SketchEntity.arc(
            start: SIMD2<Double>(0, 0),
            end: SIMD2<Double>(10, 0),
            center: SIMD2<Double>(5, 0)
        )

        let system = ConstraintSystem(entities: [line, circle, arc], constraints: [])
        let entityDOF = ConstraintSolver.computeEntityDOF(system: system)

        #expect(entityDOF[line.id] == .underConstrained(dof: 4))
        #expect(entityDOF[circle.id] == .underConstrained(dof: 3))
        #expect(entityDOF[arc.id] == .underConstrained(dof: 5))

        // Empty system
        let emptySystem = ConstraintSystem(entities: [], constraints: [])
        #expect(ConstraintSolver.computeEntityDOF(system: emptySystem).isEmpty)
    }

    @Test func testRemainingDOFReductionWithGeometricConstraints() {
        // Free line: 4 DOF
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let sysFree = ConstraintSystem(entities: [line], constraints: [])
        #expect(ConstraintSolver.computeEntityDOF(system: sysFree)[line.id] == .underConstrained(dof: 4))

        // Horizontal constraint reduces line to 3 DOF
        let horizontal = SketchConstraint(kind: .horizontal, entityIds: [line.id])
        let sysH = ConstraintSystem(entities: [line], constraints: [horizontal])
        #expect(ConstraintSolver.computeEntityDOF(system: sysH)[line.id] == .underConstrained(dof: 3))

        // Vertical constraint reduces line to 3 DOF
        let lineV = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(0, 10))
        let vertical = SketchConstraint(kind: .vertical, entityIds: [lineV.id])
        let sysV = ConstraintSystem(entities: [lineV], constraints: [vertical])
        #expect(ConstraintSolver.computeEntityDOF(system: sysV)[lineV.id] == .underConstrained(dof: 3))

        // Line anchored to a fixed line via coincident constraint reduces free line to 2 DOF
        let anchor = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let freeLine = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 10))
        let coincident = SketchConstraint(kind: .coincident, entityIds: [anchor.id, freeLine.id])
        let sysCoincident = ConstraintSystem(
            entities: [anchor, freeLine],
            constraints: [coincident],
            fixedEntityIds: [anchor.id]
        )
        let dofCoincident = ConstraintSolver.computeEntityDOF(system: sysCoincident)
        #expect(dofCoincident[anchor.id] == .fullyConstrained)
        #expect(dofCoincident[freeLine.id] == .underConstrained(dof: 2))

        // Anchored coincident line + horizontal constraint reduces to 1 DOF
        let horizCoincident = SketchConstraint(kind: .horizontal, entityIds: [freeLine.id])
        let sysCoincidentH = ConstraintSystem(
            entities: [anchor, freeLine],
            constraints: [coincident, horizCoincident],
            fixedEntityIds: [anchor.id]
        )
        let dofCoincidentH = ConstraintSolver.computeEntityDOF(system: sysCoincidentH)
        #expect(dofCoincidentH[freeLine.id] == .underConstrained(dof: 1))
    }

    @Test func testFixedEntitiesAndAnchoredProjections() {
        let fixedLine = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let movingLine = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let parallel = SketchConstraint(kind: .parallel, entityIds: [fixedLine.id, movingLine.id])

        let system = ConstraintSystem(
            entities: [fixedLine, movingLine],
            constraints: [parallel],
            fixedEntityIds: [fixedLine.id]
        )
        let result = ConstraintSolver.solve(system: system)
        #expect(result.status.isConverged)
        #expect(result.entityDOF[fixedLine.id] == .fullyConstrained)
        #expect(result.entityDOF[movingLine.id] == .underConstrained(dof: 3))

        // Concentric circles: fixed anchor circle locks center of moving circle, leaving 1 DOF (radius)
        let fixedCircle = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 10.0)
        let movingCircle = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 20.0)
        let concentric = SketchConstraint(kind: .concentric, entityIds: [fixedCircle.id, movingCircle.id])

        let sysCircle = ConstraintSystem(
            entities: [fixedCircle, movingCircle],
            constraints: [concentric],
            fixedEntityIds: [fixedCircle.id]
        )
        let resCircle = ConstraintSolver.solve(system: sysCircle)
        #expect(resCircle.status.isConverged)
        #expect(resCircle.entityDOF[fixedCircle.id] == .fullyConstrained)
        #expect(resCircle.entityDOF[movingCircle.id] == .underConstrained(dof: 1))
    }

    @Test func testFullyConstrainedSymmetricEntity() {
        // Line A fixed, Axis line fixed, Line B constrained symmetric to Line A
        let axis = SketchEntity.line(start: SIMD2<Double>(0, -50), end: SIMD2<Double>(0, 50))
        let lineA = SketchEntity.line(start: SIMD2<Double>(-10, 0), end: SIMD2<Double>(-10, 20))
        let lineB = SketchEntity.line(start: SIMD2<Double>(10, 0), end: SIMD2<Double>(10, 20))

        let sym = SketchConstraint(
            kind: .symmetric,
            entityIds: [lineA.id, lineB.id],
            referenceEntityId: axis.id
        )

        let system = ConstraintSystem(
            entities: [axis, lineA, lineB],
            constraints: [sym],
            fixedEntityIds: [axis.id, lineA.id]
        )
        let result = ConstraintSolver.solve(system: system)
        #expect(result.status.isConverged)
        #expect(result.entityDOF[axis.id] == .fullyConstrained)
        #expect(result.entityDOF[lineA.id] == .fullyConstrained)
        #expect(result.entityDOF[lineB.id] == .fullyConstrained)
    }

    @Test func testOverConstrainedConflictIsolationWithIndependentEntity() {
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
        let lineC = SketchEntity.line(start: SIMD2<Double>(0, 20), end: SIMD2<Double>(10, 20)) // Independent entity

        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])
        let c3 = SketchConstraint(kind: .horizontal, entityIds: [lineC.id])

        let system = ConstraintSystem(entities: [lineA, lineB, lineC], constraints: [c1, c2, c3])
        let result = ConstraintSolver.solve(system: system)

        // Lines A and B conflict and must report over-constrained
        #expect(result.entityDOF[lineA.id] == .overConstrained(dof: 0))
        #expect(result.entityDOF[lineB.id] == .overConstrained(dof: 0))

        // Independent line C must report its valid under-constrained DOF (3)
        #expect(result.entityDOF[lineC.id] == .underConstrained(dof: 3))
    }

    @Test func testRedundantConstraintsPreserveEntityDOF() {
        let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
        let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))

        let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
        let c2 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])

        let system = ConstraintSystem(
            entities: [lineA, lineB],
            constraints: [c1, c2],
            fixedEntityIds: [lineA.id]
        )
        let result = ConstraintSolver.solve(system: system)

        switch result.status {
        case .redundant(let redundantIds):
            #expect(!redundantIds.isEmpty)
        default:
            Issue.record("Expected redundant status")
        }

        #expect(result.entityDOF[lineA.id] == .fullyConstrained)
        #expect(result.entityDOF[lineB.id] == .underConstrained(dof: 3))
    }
}
