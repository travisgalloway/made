import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchRectangleTests {

    // MARK: - Mathematical Engine Generation

    @Test func testCornerRectangleGeneratesLinesAndConstraints() throws {
        let c1 = SIMD2<Double>(10, 20)
        let c2 = SIMD2<Double>(60, 50)
        let result = try SketchRectangle.makeCornerRectangle(corner1: c1, corner2: c2)

        #expect(result.entities.count == 4)
        #expect(result.corners.count == 4)
        #expect(result.constraints.count == 8)

        // All entities are perimeter lines (not construction)
        for entity in result.entities {
            #expect(entity.kind == "line")
            #expect(!entity.isConstruction)
        }

        // Ordered corners
        #expect(result.corners[0] == SIMD2<Double>(10, 20))
        #expect(result.corners[1] == SIMD2<Double>(60, 20))
        #expect(result.corners[2] == SIMD2<Double>(60, 50))
        #expect(result.corners[3] == SIMD2<Double>(10, 50))

        // Constraints: 4 coincident, 2 horizontal, 2 vertical
        let coincidents = result.constraints.filter { $0.kind == .coincident }
        let horizontals = result.constraints.filter { $0.kind == .horizontal }
        let verticals = result.constraints.filter { $0.kind == .vertical }

        #expect(coincidents.count == 4)
        #expect(horizontals.count == 2)
        #expect(verticals.count == 2)

        // Verify perimeter lines form continuous closed chain
        let l0 = result.entities[0]
        let l1 = result.entities[1]
        let l2 = result.entities[2]
        let l3 = result.entities[3]

        #expect(l0.startPoint == result.corners[0])
        #expect(l0.endPoint == result.corners[1])
        #expect(l1.startPoint == result.corners[1])
        #expect(l1.endPoint == result.corners[2])
        #expect(l2.startPoint == result.corners[2])
        #expect(l2.endPoint == result.corners[3])
        #expect(l3.startPoint == result.corners[3])
        #expect(l3.endPoint == result.corners[0])
    }

    @Test func testCenterRectangleGeneratesLinesAndConstructionDiagonals() throws {
        let center = SIMD2<Double>(10, 20)
        let corner = SIMD2<Double>(30, 35)
        let result = try SketchRectangle.makeCenterRectangle(center: center, corner: corner)

        #expect(result.entities.count == 6) // 4 perimeter + 2 diagonals
        #expect(result.corners.count == 4)
        #expect(result.constraints.count == 12)

        let perimeter = result.entities.filter { !$0.isConstruction }
        let diagonals = result.entities.filter { $0.isConstruction }

        #expect(perimeter.count == 4)
        #expect(diagonals.count == 2)

        // Opposite corner p0 = 2*center - corner = 2*(10, 20) - (30, 35) = (-10, 5)
        #expect(result.corners[0] == SIMD2<Double>(-10, 5))
        #expect(result.corners[1] == SIMD2<Double>(30, 5))
        #expect(result.corners[2] == SIMD2<Double>(30, 35))
        #expect(result.corners[3] == SIMD2<Double>(-10, 35))

        // Diagonal lines connect opposing corners
        let d1 = diagonals[0]
        let d2 = diagonals[1]
        #expect(d1.startPoint == result.corners[0] && d1.endPoint == result.corners[2])
        #expect(d2.startPoint == result.corners[1] && d2.endPoint == result.corners[3])

        // Constraints: 8 coincident (4 perimeter + 4 diagonal), 2 horizontal, 2 vertical
        let coincidents = result.constraints.filter { $0.kind == .coincident }
        let horizontals = result.constraints.filter { $0.kind == .horizontal }
        let verticals = result.constraints.filter { $0.kind == .vertical }

        #expect(coincidents.count == 8)
        #expect(horizontals.count == 2)
        #expect(verticals.count == 2)
    }

    @Test func testThreePointRectangleArbitraryAngleAndConstraints() throws {
        let p1 = SIMD2<Double>(0, 0)
        let p2 = SIMD2<Double>(30, 40) // length 50, at ~53.13 degrees
        let p3 = SIMD2<Double>(-10, 10)
        let result = try SketchRectangle.makeThreePointRectangle(point1: p1, point2: p2, point3: p3)

        #expect(result.entities.count == 4)
        #expect(result.corners.count == 4)

        // Constraints: 4 coincident, 2 parallel, 1 perpendicular (no horizontal/vertical lock)
        let coincidents = result.constraints.filter { $0.kind == .coincident }
        let parallels = result.constraints.filter { $0.kind == .parallel }
        let perpendiculars = result.constraints.filter { $0.kind == .perpendicular }
        let horizontals = result.constraints.filter { $0.kind == .horizontal }
        let verticals = result.constraints.filter { $0.kind == .vertical }

        #expect(coincidents.count == 4)
        #expect(parallels.count == 2)
        #expect(perpendiculars.count == 1)
        #expect(horizontals.isEmpty)
        #expect(verticals.isEmpty)

        // Verify orthogonality: (p1 - p0) dot (p2 - p1) == 0
        let v01 = result.corners[1] - result.corners[0]
        let v12 = result.corners[2] - result.corners[1]
        let dot = simd_dot(v01, v12)
        #expect(abs(dot) < 1e-6)
    }

    // MARK: - Degeneracy Handling

    @Test func testDegenerateCornerRectangleThrows() {
        // Coincident points
        #expect(throws: SketchError.self) {
            try SketchRectangle.makeCornerRectangle(corner1: SIMD2(10, 10), corner2: SIMD2(10, 10))
        }

        // Zero width
        #expect(throws: SketchError.self) {
            try SketchRectangle.makeCornerRectangle(corner1: SIMD2(10, 10), corner2: SIMD2(10, 30))
        }

        // Zero height
        #expect(throws: SketchError.self) {
            try SketchRectangle.makeCornerRectangle(corner1: SIMD2(10, 10), corner2: SIMD2(40, 10))
        }
    }

    @Test func testDegenerateCenterRectangleThrows() {
        // Center equal to corner
        #expect(throws: SketchError.self) {
            try SketchRectangle.makeCenterRectangle(center: SIMD2(10, 10), corner: SIMD2(10, 10))
        }

        // Zero half-width
        #expect(throws: SketchError.self) {
            try SketchRectangle.makeCenterRectangle(center: SIMD2(10, 10), corner: SIMD2(10, 30))
        }

        // Zero half-height
        #expect(throws: SketchError.self) {
            try SketchRectangle.makeCenterRectangle(center: SIMD2(10, 10), corner: SIMD2(40, 10))
        }
    }

    @Test func testDegenerateThreePointCollinearThrows() {
        // Base edge length zero
        #expect(throws: SketchError.self) {
            try SketchRectangle.makeThreePointRectangle(point1: SIMD2(0, 0), point2: SIMD2(0, 0), point3: SIMD2(10, 10))
        }

        // Collinear three points (height is zero)
        #expect(throws: SketchError.self) {
            try SketchRectangle.makeThreePointRectangle(point1: SIMD2(0, 0), point2: SIMD2(10, 0), point3: SIMD2(20, 0))
        }
    }

    // MARK: - Constraint Solver DOF & Convergence

    @Test func testConstraintSolverConvergesOnRectangleWithDOF4() throws {
        let rect = try SketchRectangle.makeCornerRectangle(corner1: SIMD2(0, 0), corner2: SIMD2(40, 30))
        let system = ConstraintSystem(entities: rect.entities, constraints: rect.constraints)

        let status = ConstraintSolver.computeDOFStatus(system: system)
        #expect(status == .underConstrained(dof: 4))

        let result = ConstraintSolver.solve(system: system)
        if case .converged = result.status {
            #expect(result.dof == 4)
        } else {
            Issue.record("Expected solver to converge on corner rectangle, got \(result.status)")
        }
    }

    @Test func testConstraintSolverConvergesOnThreePointRectangleWithDOF5() throws {
        let rect = try SketchRectangle.makeThreePointRectangle(
            point1: SIMD2(0, 0),
            point2: SIMD2(40, 0),
            point3: SIMD2(40, 30)
        )
        let system = ConstraintSystem(entities: rect.entities, constraints: rect.constraints)

        let status = ConstraintSolver.computeDOFStatus(system: system)
        #expect(status == .underConstrained(dof: 5))

        let result = ConstraintSolver.solve(system: system)
        if case .converged = result.status {
            #expect(result.dof == 5)
        } else {
            Issue.record("Expected solver to converge on three-point rectangle, got \(result.status)")
        }
    }

    // MARK: - Profile & Region Discretization

    @Test func testRectangleDiscretizesIntoValidProfile() throws {
        let rect = try SketchRectangle.makeCornerRectangle(corner1: SIMD2(0, 0), corner2: SIMD2(40, 30))
        let profile = try SketchProfileBuilder.build(from: rect.entities)
        #expect(profile.points.count == 4)
    }

    @Test func testConstructionDiagonalsExcludedFromExtrusion() throws {
        let centerRect = try SketchRectangle.makeCenterRectangle(center: SIMD2(0, 0), corner: SIMD2(20, 15))
        #expect(centerRect.entities.count == 6)

        // SketchProfileBuilder ignores construction entities and extracts 4 perimeter vertices
        let profile = try SketchProfileBuilder.build(from: centerRect.entities)
        #expect(profile.points.count == 4)

        // SketchRegionDetector also ignores construction diagonals and detects exactly 1 closed region
        let regions = try SketchRegionDetector.detectRegions(from: centerRect.entities)
        #expect(regions.count == 1)
    }
}
