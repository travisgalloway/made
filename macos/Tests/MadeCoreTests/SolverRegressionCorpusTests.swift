import Testing
import Foundation
import simd
@testable import MadeCore

/// Benchmark fixture descriptor for the 2D constraint solver regression corpus (BL-CON-09, #200, ADR-D4).
public struct SolverCorpusFixture: Sendable, CustomStringConvertible {
    public enum Category: String, Sendable, CaseIterable {
        case orthogonal
        case curvilinear
        case concentric
        case symmetric
        case kinematicChain
        case conflict
        case redundant
        case degenerate
        case interactiveDrag
    }

    public enum ExpectedStatusKind: Sendable, Equatable {
        case converged
        case overConstrained
        case redundant
        case failedToConverge
    }

    public let id: String
    public let name: String
    public let category: Category
    public let expectedStatusKind: ExpectedStatusKind
    public let expectedSystemDOF: SketchDOFStatus
    public let buildSystem: @Sendable () -> (system: ConstraintSystem, labelMap: [String: UUID], dragTarget: DragTarget?)
    public let validate: @Sendable (SolverResult, [String: UUID]) throws -> Void

    public init(
        id: String,
        name: String,
        category: Category,
        expectedStatusKind: ExpectedStatusKind,
        expectedSystemDOF: SketchDOFStatus,
        buildSystem: @escaping @Sendable () -> (system: ConstraintSystem, labelMap: [String: UUID], dragTarget: DragTarget?),
        validate: @escaping @Sendable (SolverResult, [String: UUID]) throws -> Void
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.expectedStatusKind = expectedStatusKind
        self.expectedSystemDOF = expectedSystemDOF
        self.buildSystem = buildSystem
        self.validate = validate
    }

    public var description: String { "\(id): \(name)" }
}

/// Regression benchmark catalog containing 21 standard 2D constraint solver fixtures (BL-CON-09, #200).
public enum SolverRegressionCorpus {

    // MARK: - 1. Orthogonal Profiles

    /// CON-01-RIGHT-ANGLE: Fixed horizontal line + perpendicular vertical line sharing origin coincident corner.
    public static let con01RightAngle = SolverCorpusFixture(
        id: "CON-01-RIGHT-ANGLE",
        name: "Orthogonal Right Angle Corner",
        category: .orthogonal,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 1),
        buildSystem: {
            let base = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let vertical = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(2, 10))
            let cPerp = SketchConstraint(kind: .perpendicular, entityIds: [base.id, vertical.id])
            let cCoinc = SketchConstraint(kind: .coincident, entityIds: [base.id, vertical.id])
            let system = ConstraintSystem(
                entities: [base, vertical],
                constraints: [cPerp, cCoinc],
                fixedEntityIds: [base.id]
            )
            return (system, ["base": base.id, "vertical": vertical.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let vId = labels["vertical"],
                  let solvedV = result.solvedEntities.first(where: { $0.id == vId }),
                  let s = solvedV.startPoint, let e = solvedV.endPoint else {
                Issue.record("Missing solved vertical line")
                return
            }
            #expect(abs(s.x) < 1e-3 && abs(s.y) < 1e-3, "Start must remain at origin")
            let v = e - s
            #expect(abs(v.x) < 1e-3, "Vertical line x-delta must be 0")
            if let bId = labels["base"] {
                #expect(result.entityDOF[bId] == .fullyConstrained)
            }
            #expect(result.entityDOF[vId] == .underConstrained(dof: 1))
        }
    )

    /// CON-02-PARALLEL-PAIR: Fixed baseline horizontal line + floating parallel line (remaining DOF = 3).
    public static let con02ParallelPair = SolverCorpusFixture(
        id: "CON-02-PARALLEL-PAIR",
        name: "Parallel Line Pair",
        category: .orthogonal,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 3),
        buildSystem: {
            let base = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let floating = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 8))
            let cParallel = SketchConstraint(kind: .parallel, entityIds: [base.id, floating.id])
            let system = ConstraintSystem(
                entities: [base, floating],
                constraints: [cParallel],
                fixedEntityIds: [base.id]
            )
            return (system, ["base": base.id, "floating": floating.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let fId = labels["floating"],
                  let solvedF = result.solvedEntities.first(where: { $0.id == fId }),
                  let s = solvedF.startPoint, let e = solvedF.endPoint else {
                Issue.record("Missing solved floating line")
                return
            }
            let v = e - s
            let slope = v.y / max(1e-6, abs(v.x))
            #expect(abs(slope) < 1e-3, "Floating line slope residual must be < 1e-3")
            if let bId = labels["base"] {
                #expect(result.entityDOF[bId] == .fullyConstrained)
            }
            #expect(result.entityDOF[fId] == .underConstrained(dof: 3))
        }
    )

    /// CON-03-PERPENDICULAR-T-SECTION: Fixed horizontal flange + perpendicular stem anchored at midpoint via coincident constraint (DOF = 1).
    public static let con03PerpendicularTSection = SolverCorpusFixture(
        id: "CON-03-PERPENDICULAR-T-SECTION",
        name: "Perpendicular T-Section at Midpoint",
        category: .orthogonal,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 1),
        buildSystem: {
            let flangeLeft = SketchEntity.line(start: SIMD2<Double>(-10, 0), end: SIMD2<Double>(0, 0))
            let flangeRight = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let stem = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(3, 15))
            let cCoinc = SketchConstraint(kind: .coincident, entityIds: [flangeRight.id, stem.id])
            let cPerp = SketchConstraint(kind: .perpendicular, entityIds: [flangeRight.id, stem.id])
            let system = ConstraintSystem(
                entities: [flangeLeft, flangeRight, stem],
                constraints: [cCoinc, cPerp],
                fixedEntityIds: [flangeLeft.id, flangeRight.id]
            )
            return (system, ["flangeLeft": flangeLeft.id, "flangeRight": flangeRight.id, "stem": stem.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let sId = labels["stem"],
                  let solvedStem = result.solvedEntities.first(where: { $0.id == sId }),
                  let s = solvedStem.startPoint, let e = solvedStem.endPoint else {
                Issue.record("Missing solved stem line")
                return
            }
            #expect(abs(s.x) < 1e-3 && abs(s.y) < 1e-3, "Stem must anchor at flange midpoint (0,0)")
            let v = e - s
            #expect(abs(v.x) < 1e-3, "Stem must be perpendicular to horizontal flange")
            #expect(result.entityDOF[sId] == .underConstrained(dof: 1))
        }
    )

    /// CON-04-CONSTRAINED-RECTANGLE: 4 lines with parallel pairs, perpendicular corner, horizontal base, and fixed base line.
    public static let con04ConstrainedRectangle = SolverCorpusFixture(
        id: "CON-04-CONSTRAINED-RECTANGLE",
        name: "Constrained 4-Line Orthogonal Frame with Fixed Base",
        category: .orthogonal,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 8),
        buildSystem: {
            let base = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let top = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
            let left = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(0, 5))
            let right = SketchEntity.line(start: SIMD2<Double>(10, 0), end: SIMD2<Double>(10, 5))

            let c1 = SketchConstraint(kind: .parallel, entityIds: [base.id, top.id])
            let c2 = SketchConstraint(kind: .parallel, entityIds: [left.id, right.id])
            let c3 = SketchConstraint(kind: .perpendicular, entityIds: [base.id, left.id])
            let c4 = SketchConstraint(kind: .horizontal, entityIds: [base.id])

            let system = ConstraintSystem(
                entities: [base, top, left, right],
                constraints: [c1, c2, c3, c4],
                fixedEntityIds: [base.id]
            )
            return (system, ["base": base.id, "top": top.id, "left": left.id, "right": right.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            #expect(result.dof == 8)
            if let bId = labels["base"] {
                #expect(result.entityDOF[bId] == .fullyConstrained)
            }
            if let tId = labels["top"] {
                #expect(result.entityDOF[tId] == .underConstrained(dof: 3))
            }
            if let lId = labels["left"] {
                #expect(result.entityDOF[lId] == .underConstrained(dof: 3))
            }
            if let rId = labels["right"] {
                #expect(result.entityDOF[rId] == .underConstrained(dof: 3))
            }
        }
    )

    // MARK: - 2. Curvilinear & Tangency Topologies

    /// CON-05-LINE-CIRCLE-TANGENT: Fixed horizontal line + floating circle with tangent constraint.
    public static let con05LineCircleTangent = SolverCorpusFixture(
        id: "CON-05-LINE-CIRCLE-TANGENT",
        name: "Line-to-Circle Tangency",
        category: .curvilinear,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 2),
        buildSystem: {
            let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(20, 0))
            let circle = SketchEntity.circle(center: SIMD2<Double>(10, 15), radius: 10.0)
            let cTangent = SketchConstraint(kind: .tangent, entityIds: [line.id, circle.id])
            let system = ConstraintSystem(
                entities: [line, circle],
                constraints: [cTangent],
                fixedEntityIds: [line.id]
            )
            return (system, ["line": line.id, "circle": circle.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let cId = labels["circle"],
                  let solvedC = result.solvedEntities.first(where: { $0.id == cId }),
                  let center = solvedC.centerPoint, let r = solvedC.radius else {
                Issue.record("Missing solved circle")
                return
            }
            #expect(abs(abs(center.y) - r) < 1e-3, "Distance from center to line at y=0 must equal radius")
            #expect(result.entityDOF[cId] == .underConstrained(dof: 2))
        }
    )

    /// CON-06-CIRCLE-CIRCLE-EXTERNAL-TANGENT: Fixed circle A at origin (r=10) + floating circle B (r=15) with external tangency.
    public static let con06CircleCircleExternalTangent = SolverCorpusFixture(
        id: "CON-06-CIRCLE-CIRCLE-EXTERNAL-TANGENT",
        name: "External Circle-to-Circle Tangency",
        category: .curvilinear,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 2),
        buildSystem: {
            let circleA = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 10.0)
            let circleB = SketchEntity.circle(center: SIMD2<Double>(30, 0), radius: 15.0)
            let cTangent = SketchConstraint(kind: .tangent, entityIds: [circleA.id, circleB.id])
            let system = ConstraintSystem(
                entities: [circleA, circleB],
                constraints: [cTangent],
                fixedEntityIds: [circleA.id]
            )
            return (system, ["circleA": circleA.id, "circleB": circleB.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let aId = labels["circleA"], let bId = labels["circleB"],
                  let solvedA = result.solvedEntities.first(where: { $0.id == aId }),
                  let solvedB = result.solvedEntities.first(where: { $0.id == bId }),
                  let cA = solvedA.centerPoint, let rA = solvedA.radius,
                  let cB = solvedB.centerPoint, let rB = solvedB.radius else {
                Issue.record("Missing solved circles")
                return
            }
            let dist = hypot(cB.x - cA.x, cB.y - cA.y)
            #expect(abs(dist - (rA + rB)) < 1e-3, "Center distance must converge to sum of radii (rA + rB)")
            #expect(result.entityDOF[bId] == .underConstrained(dof: 2))
        }
    )

    /// CON-07-CIRCLE-CIRCLE-INTERNAL-TANGENT: Fixed circle A at origin (r=30) + floating circle B (r=10) with internal tangency.
    public static let con07CircleCircleInternalTangent = SolverCorpusFixture(
        id: "CON-07-CIRCLE-CIRCLE-INTERNAL-TANGENT",
        name: "Internal Circle-to-Circle Tangency",
        category: .curvilinear,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 2),
        buildSystem: {
            let circleA = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 30.0)
            let circleB = SketchEntity.circle(center: SIMD2<Double>(15, 0), radius: 10.0)
            let cTangent = SketchConstraint(kind: .tangent, entityIds: [circleA.id, circleB.id])
            let system = ConstraintSystem(
                entities: [circleA, circleB],
                constraints: [cTangent],
                fixedEntityIds: [circleA.id]
            )
            return (system, ["circleA": circleA.id, "circleB": circleB.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let aId = labels["circleA"], let bId = labels["circleB"],
                  let solvedA = result.solvedEntities.first(where: { $0.id == aId }),
                  let solvedB = result.solvedEntities.first(where: { $0.id == bId }),
                  let cA = solvedA.centerPoint, let rA = solvedA.radius,
                  let cB = solvedB.centerPoint, let rB = solvedB.radius else {
                Issue.record("Missing solved circles")
                return
            }
            let dist = hypot(cB.x - cA.x, cB.y - cA.y)
            #expect(abs(dist - abs(rA - rB)) < 1e-3, "Center distance must converge to difference of radii (|rA - rB|)")
            #expect(result.entityDOF[bId] == .underConstrained(dof: 2))
        }
    )

    // MARK: - 3. Concentric Systems

    /// CON-08-CONCENTRIC-BORE-SHAFT: Fixed outer circle at (15, 25) + floating inner circle with concentric constraint.
    public static let con08ConcentricBoreShaft = SolverCorpusFixture(
        id: "CON-08-CONCENTRIC-BORE-SHAFT",
        name: "Concentric Bore and Shaft",
        category: .concentric,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 1),
        buildSystem: {
            let outer = SketchEntity.circle(center: SIMD2<Double>(15, 25), radius: 20.0)
            let inner = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 8.0)
            let cConcentric = SketchConstraint(kind: .concentric, entityIds: [outer.id, inner.id])
            let system = ConstraintSystem(
                entities: [outer, inner],
                constraints: [cConcentric],
                fixedEntityIds: [outer.id]
            )
            return (system, ["outer": outer.id, "inner": inner.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let inId = labels["inner"],
                  let solvedInner = result.solvedEntities.first(where: { $0.id == inId }),
                  let center = solvedInner.centerPoint else {
                Issue.record("Missing solved inner circle")
                return
            }
            #expect(abs(center.x - 15.0) < 1e-3 && abs(center.y - 25.0) < 1e-3, "Inner center must match fixed outer center (15, 25)")
            #expect(result.entityDOF[inId] == .underConstrained(dof: 1))
        }
    )

    /// CON-09-CONCENTRIC-MULTI-CLUSTER: Fixed center circle + two floating concentric circles (remaining system DOF = 2).
    public static let con09ConcentricMultiCluster = SolverCorpusFixture(
        id: "CON-09-CONCENTRIC-MULTI-CLUSTER",
        name: "Multi-Circle Concentric Cluster",
        category: .concentric,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 2),
        buildSystem: {
            let hub = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 50.0)
            let ring1 = SketchEntity.circle(center: SIMD2<Double>(5, 5), radius: 30.0)
            let ring2 = SketchEntity.circle(center: SIMD2<Double>(-10, 8), radius: 15.0)
            let c1 = SketchConstraint(kind: .concentric, entityIds: [hub.id, ring1.id])
            let c2 = SketchConstraint(kind: .concentric, entityIds: [hub.id, ring2.id])
            let system = ConstraintSystem(
                entities: [hub, ring1, ring2],
                constraints: [c1, c2],
                fixedEntityIds: [hub.id]
            )
            return (system, ["hub": hub.id, "ring1": ring1.id, "ring2": ring2.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let r1Id = labels["ring1"], let r2Id = labels["ring2"],
                  let c1 = result.solvedEntities.first(where: { $0.id == r1Id })?.centerPoint,
                  let c2 = result.solvedEntities.first(where: { $0.id == r2Id })?.centerPoint else {
                Issue.record("Missing solved concentric rings")
                return
            }
            #expect(abs(c1.x) < 1e-3 && abs(c1.y) < 1e-3)
            #expect(abs(c2.x) < 1e-3 && abs(c2.y) < 1e-3)
            #expect(result.entityDOF[r1Id] == .underConstrained(dof: 1))
            #expect(result.entityDOF[r2Id] == .underConstrained(dof: 1))
        }
    )

    // MARK: - 4. Bilateral Symmetry Topologies

    /// CON-10-SYMMETRIC-LINE-PAIR: Fixed vertical axis line at x=0, fixed line A at x=-15, floating line B symmetric across axis.
    public static let con10SymmetricLinePair = SolverCorpusFixture(
        id: "CON-10-SYMMETRIC-LINE-PAIR",
        name: "Bilateral Symmetric Line Pair",
        category: .symmetric,
        expectedStatusKind: .converged,
        expectedSystemDOF: .fullyConstrained,
        buildSystem: {
            let axis = SketchEntity.line(start: SIMD2<Double>(0, -50), end: SIMD2<Double>(0, 50))
            let lineA = SketchEntity.line(start: SIMD2<Double>(-15, 0), end: SIMD2<Double>(-15, 30))
            let lineB = SketchEntity.line(start: SIMD2<Double>(10, 2), end: SIMD2<Double>(12, 32))
            let cSym = SketchConstraint(kind: .symmetric, entityIds: [lineA.id, lineB.id], referenceEntityId: axis.id)
            let system = ConstraintSystem(
                entities: [axis, lineA, lineB],
                constraints: [cSym],
                fixedEntityIds: [axis.id, lineA.id]
            )
            return (system, ["axis": axis.id, "lineA": lineA.id, "lineB": lineB.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let bId = labels["lineB"],
                  let solvedB = result.solvedEntities.first(where: { $0.id == bId }),
                  let s = solvedB.startPoint, let e = solvedB.endPoint else {
                Issue.record("Missing solved line B")
                return
            }
            #expect(abs(s.x - 15.0) < 1e-2, "Line B start must reflect to x=+15")
            #expect(abs(e.x - 15.0) < 1e-2, "Line B end must reflect to x=+15")
            #expect(abs(abs(e.y - s.y) - 30.0) < 1e-2, "Line B length must be preserved")
            #expect(result.entityDOF[bId] == .fullyConstrained)
        }
    )

    /// CON-11-SYMMETRIC-CIRCLE-PAIR: Fixed vertical axis line at x=0, fixed circle A at (-20, 10), floating circle B symmetric across axis.
    public static let con11SymmetricCirclePair = SolverCorpusFixture(
        id: "CON-11-SYMMETRIC-CIRCLE-PAIR",
        name: "Bilateral Symmetric Circle Pair",
        category: .symmetric,
        expectedStatusKind: .converged,
        expectedSystemDOF: .fullyConstrained,
        buildSystem: {
            let axis = SketchEntity.line(start: SIMD2<Double>(0, -50), end: SIMD2<Double>(0, 50))
            let circleA = SketchEntity.circle(center: SIMD2<Double>(-20, 10), radius: 8.0)
            let circleB = SketchEntity.circle(center: SIMD2<Double>(10, 0), radius: 12.0)
            let cSym = SketchConstraint(kind: .symmetric, entityIds: [circleA.id, circleB.id], referenceEntityId: axis.id)
            let system = ConstraintSystem(
                entities: [axis, circleA, circleB],
                constraints: [cSym],
                fixedEntityIds: [axis.id, circleA.id]
            )
            return (system, ["axis": axis.id, "circleA": circleA.id, "circleB": circleB.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let bId = labels["circleB"],
                  let solvedB = result.solvedEntities.first(where: { $0.id == bId }),
                  let center = solvedB.centerPoint, let r = solvedB.radius else {
                Issue.record("Missing solved circle B")
                return
            }
            #expect(abs(center.x - 20.0) < 1e-2 && abs(center.y - 10.0) < 1e-2, "Circle B center must reflect to (+20, 10)")
            #expect(abs(r - 8.0) < 1e-2, "Circle B radius must equal circle A radius")
            #expect(result.entityDOF[bId] == .fullyConstrained)
        }
    )

    // MARK: - 5. Kinematic Chains & DOF Propagation

    /// CON-12-CHAIN-DOF-PROPAGATION: 3-link open chain anchored at base line start, verifying sequential DOF reduction along the chain.
    public static let con12ChainDOFPropagation = SolverCorpusFixture(
        id: "CON-12-CHAIN-DOF-PROPAGATION",
        name: "Kinematic Chain Sequential DOF Propagation",
        category: .kinematicChain,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 2),
        buildSystem: {
            let link1 = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let link2 = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(0, 10))
            let link3 = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))

            let c1 = SketchConstraint(kind: .coincident, entityIds: [link1.id, link2.id])
            let c2 = SketchConstraint(kind: .perpendicular, entityIds: [link1.id, link2.id])
            let c3 = SketchConstraint(kind: .coincident, entityIds: [link1.id, link3.id])
            let c4 = SketchConstraint(kind: .parallel, entityIds: [link1.id, link3.id])

            let system = ConstraintSystem(
                entities: [link1, link2, link3],
                constraints: [c1, c2, c3, c4],
                fixedEntityIds: [link1.id]
            )
            return (system, ["link1": link1.id, "link2": link2.id, "link3": link3.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let l1Id = labels["link1"], let l2Id = labels["link2"], let l3Id = labels["link3"] else {
                Issue.record("Missing chain labels")
                return
            }
            #expect(result.entityDOF[l1Id] == .fullyConstrained)
            #expect(result.entityDOF[l2Id] == .underConstrained(dof: 1))
            #expect(result.entityDOF[l3Id] == .underConstrained(dof: 1))
            #expect(result.dof == 2)
        }
    )

    /// CON-13-FULLY-CONSTRAINED-ANCHORED-POINT: Line with fixed anchor and horizontal + vertical constraints resulting in fully constrained status.
    public static let con13FullyConstrainedAnchoredPoint = SolverCorpusFixture(
        id: "CON-13-FULLY-CONSTRAINED-ANCHORED-POINT",
        name: "Fully Constrained Anchored Point Line",
        category: .kinematicChain,
        expectedStatusKind: .converged,
        expectedSystemDOF: .fullyConstrained,
        buildSystem: {
            let anchor = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let pointLine = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(0, 0))
            let cCoinc = SketchConstraint(kind: .coincident, entityIds: [anchor.id, pointLine.id])
            let cH = SketchConstraint(kind: .horizontal, entityIds: [pointLine.id])
            let cV = SketchConstraint(kind: .vertical, entityIds: [pointLine.id])

            let system = ConstraintSystem(
                entities: [anchor, pointLine],
                constraints: [cCoinc, cH, cV],
                fixedEntityIds: [anchor.id]
            )
            return (system, ["anchor": anchor.id, "pointLine": pointLine.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            #expect(result.dof == 0)
            if let aId = labels["anchor"] {
                #expect(result.entityDOF[aId] == .fullyConstrained)
            }
            if let pId = labels["pointLine"] {
                #expect(result.entityDOF[pId] == .fullyConstrained)
            }
        }
    )

    // MARK: - 6. Over-Constrained & Conflict Diagnostics

    /// CON-14-CONFLICT-PARALLEL-PERPENDICULAR: Two lines constrained simultaneously parallel and perpendicular.
    public static let con14ConflictParallelPerpendicular = SolverCorpusFixture(
        id: "CON-14-CONFLICT-PARALLEL-PERPENDICULAR",
        name: "Conflicting Parallel and Perpendicular Constraints",
        category: .conflict,
        expectedStatusKind: .overConstrained,
        expectedSystemDOF: .overConstrained(dof: 7),
        buildSystem: {
            let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
            let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
            let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])
            let system = ConstraintSystem(
                entities: [lineA, lineB],
                constraints: [c1, c2]
            )
            return (system, ["lineA": lineA.id, "lineB": lineB.id, "c1": c1.id, "c2": c2.id], nil)
        },
        validate: { result, labels in
            switch result.status {
            case .overConstrained(let conflicting):
                if let c1Id = labels["c1"], let c2Id = labels["c2"] {
                    #expect(conflicting.contains(c1Id), "Must isolate parallel constraint ID")
                    #expect(conflicting.contains(c2Id), "Must isolate perpendicular constraint ID")
                }
            default:
                Issue.record("Expected overConstrained status, got \(result.status)")
            }
        }
    )

    /// CON-15-CONFLICT-HORIZONTAL-VERTICAL: Single line constrained simultaneously horizontal and perpendicular to horizontal datum.
    public static let con15ConflictHorizontalVertical = SolverCorpusFixture(
        id: "CON-15-CONFLICT-HORIZONTAL-VERTICAL",
        name: "Conflicting Horizontal and Vertical Constraints on Single Line",
        category: .conflict,
        expectedStatusKind: .overConstrained,
        expectedSystemDOF: .overConstrained(dof: 3),
        buildSystem: {
            let datum = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let line = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
            let c1 = SketchConstraint(kind: .horizontal, entityIds: [line.id])
            let c2 = SketchConstraint(kind: .perpendicular, entityIds: [datum.id, line.id])
            let system = ConstraintSystem(
                entities: [datum, line],
                constraints: [c1, c2],
                fixedEntityIds: [datum.id]
            )
            return (system, ["datum": datum.id, "line": line.id, "c1": c1.id, "c2": c2.id], nil)
        },
        validate: { result, labels in
            switch result.status {
            case .overConstrained(let conflicting):
                if let c1Id = labels["c1"], let c2Id = labels["c2"] {
                    #expect(conflicting.contains(c1Id))
                    #expect(conflicting.contains(c2Id))
                }
            default:
                Issue.record("Expected overConstrained status, got \(result.status)")
            }
        }
    )

    /// CON-16-CONFLICT-ISOLATION-INDEPENDENT-ENTITY: Over-constrained pair alongside an independent unconstrained circle.
    public static let con16ConflictIsolationIndependentEntity = SolverCorpusFixture(
        id: "CON-16-CONFLICT-ISOLATION-INDEPENDENT-ENTITY",
        name: "Conflict Isolation Preserves Independent Entity DOF",
        category: .conflict,
        expectedStatusKind: .overConstrained,
        expectedSystemDOF: .overConstrained(dof: 10),
        buildSystem: {
            let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
            let circle = SketchEntity.circle(center: SIMD2<Double>(50, 50), radius: 10.0)

            let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
            let c2 = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])

            let system = ConstraintSystem(
                entities: [lineA, lineB, circle],
                constraints: [c1, c2]
            )
            return (system, ["lineA": lineA.id, "lineB": lineB.id, "circle": circle.id], nil)
        },
        validate: { result, labels in
            guard let aId = labels["lineA"], let bId = labels["lineB"], let cId = labels["circle"] else {
                Issue.record("Missing labels")
                return
            }
            #expect(result.entityDOF[aId] == .overConstrained(dof: 0))
            #expect(result.entityDOF[bId] == .overConstrained(dof: 0))
            #expect(result.entityDOF[cId] == .underConstrained(dof: 3), "Independent circle must retain its 3 baseline degrees of freedom")
        }
    )

    // MARK: - 7. Redundant Constraint Diagnostics

    /// CON-17-REDUNDANT-PARALLEL: Line pair with duplicate parallel constraints.
    public static let con17RedundantParallel = SolverCorpusFixture(
        id: "CON-17-REDUNDANT-PARALLEL",
        name: "Redundant Duplicate Parallel Constraints",
        category: .redundant,
        expectedStatusKind: .redundant,
        expectedSystemDOF: .underConstrained(dof: 3),
        buildSystem: {
            let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 5))
            let c1 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
            let c2 = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
            let system = ConstraintSystem(
                entities: [lineA, lineB],
                constraints: [c1, c2],
                fixedEntityIds: [lineA.id]
            )
            return (system, ["lineA": lineA.id, "lineB": lineB.id], nil)
        },
        validate: { result, labels in
            switch result.status {
            case .redundant(let redundantIds):
                #expect(!redundantIds.isEmpty, "Must detect redundant duplicate constraint")
            default:
                Issue.record("Expected redundant status, got \(result.status)")
            }
            if let aId = labels["lineA"], let bId = labels["lineB"] {
                #expect(result.entityDOF[aId] == .fullyConstrained)
                #expect(result.entityDOF[bId] == .underConstrained(dof: 3))
            }
        }
    )

    /// CON-18-REDUNDANT-CONCENTRIC: Circle pair with duplicate concentric constraints.
    public static let con18RedundantConcentric = SolverCorpusFixture(
        id: "CON-18-REDUNDANT-CONCENTRIC",
        name: "Redundant Duplicate Concentric Constraints",
        category: .redundant,
        expectedStatusKind: .redundant,
        expectedSystemDOF: .underConstrained(dof: 1),
        buildSystem: {
            let circleA = SketchEntity.circle(center: SIMD2<Double>(5, 5), radius: 10.0)
            let circleB = SketchEntity.circle(center: SIMD2<Double>(12, 8), radius: 20.0)
            let c1 = SketchConstraint(kind: .concentric, entityIds: [circleA.id, circleB.id])
            let c2 = SketchConstraint(kind: .concentric, entityIds: [circleA.id, circleB.id])
            let system = ConstraintSystem(
                entities: [circleA, circleB],
                constraints: [c1, c2],
                fixedEntityIds: [circleA.id]
            )
            return (system, ["circleA": circleA.id, "circleB": circleB.id], nil)
        },
        validate: { result, labels in
            switch result.status {
            case .redundant(let redundantIds):
                #expect(!redundantIds.isEmpty, "Must detect redundant duplicate concentric constraint")
            default:
                Issue.record("Expected redundant status, got \(result.status)")
            }
            guard let bId = labels["circleB"],
                  let solvedB = result.solvedEntities.first(where: { $0.id == bId }),
                  let centerB = solvedB.centerPoint else {
                Issue.record("Missing solved circle B")
                return
            }
            #expect(abs(centerB.x - 5.0) < 1e-3 && abs(centerB.y - 5.0) < 1e-3)
            #expect(result.entityDOF[bId] == .underConstrained(dof: 1))
        }
    )

    // MARK: - 8. Degenerate Stability & Interactive Drag Perturbation

    /// CON-19-DEGENERATE-IMPOSSIBLE-TANGENCY: Fixed circles locked at distance 100 with radii 10 demanding tangency.
    public static let con19DegenerateImpossibleTangency = SolverCorpusFixture(
        id: "CON-19-DEGENERATE-IMPOSSIBLE-TANGENCY",
        name: "Degenerate Impossible Tangency Numerical Stability",
        category: .degenerate,
        expectedStatusKind: .failedToConverge,
        expectedSystemDOF: .overConstrained(dof: 0),
        buildSystem: {
            let circleA = SketchEntity.circle(center: SIMD2<Double>(0, 0), radius: 10.0)
            let circleB = SketchEntity.circle(center: SIMD2<Double>(100, 0), radius: 10.0)
            let cTangent = SketchConstraint(kind: .tangent, entityIds: [circleA.id, circleB.id])
            let system = ConstraintSystem(
                entities: [circleA, circleB],
                constraints: [cTangent],
                fixedEntityIds: [circleA.id, circleB.id]
            )
            return (system, ["circleA": circleA.id, "circleB": circleB.id], nil)
        },
        validate: { result, _ in
            #expect(!result.status.isConverged, "Impossible geometry must report non-convergence")
            for e in result.solvedEntities {
                if let c = e.centerPoint {
                    #expect(!c.x.isNaN && !c.y.isNaN, "Coordinates must not degrade to NaN")
                    #expect(!c.x.isInfinite && !c.y.isInfinite, "Coordinates must be finite")
                }
            }
        }
    )

    /// CON-20-INTERACTIVE-DRAG-PRESERVES-INVARIANTS: Perturbing endpoint of constrained perpendicular line via DragTarget preserving perpendicular invariant.
    public static let con20InteractiveDragPreservesInvariants = SolverCorpusFixture(
        id: "CON-20-INTERACTIVE-DRAG-PRESERVES-INVARIANTS",
        name: "Interactive Drag Preserves Geometric Invariants",
        category: .interactiveDrag,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 7),
        buildSystem: {
            let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let lineB = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(0, 10))
            let cPerp = SketchConstraint(kind: .perpendicular, entityIds: [lineA.id, lineB.id])
            let system = ConstraintSystem(
                entities: [lineA, lineB],
                constraints: [cPerp]
            )
            let drag = DragTarget(entityId: lineA.id, endpoint: .end, targetPosition: SIMD2<Double>(10, 10))
            return (system, ["lineA": lineA.id, "lineB": lineB.id], drag)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let aId = labels["lineA"], let bId = labels["lineB"],
                  let solvedA = result.solvedEntities.first(where: { $0.id == aId }),
                  let solvedB = result.solvedEntities.first(where: { $0.id == bId }),
                  let sA = solvedA.startPoint, let eA = solvedA.endPoint,
                  let sB = solvedB.startPoint, let eB = solvedB.endPoint else {
                Issue.record("Missing solved lines")
                return
            }
            let vA = eA - sA
            let vB = eB - sB
            let dot = vA.x * vB.x + vA.y * vB.y
            #expect(abs(dot) < 1e-2, "Lines must remain perpendicular after dragging")
        }
    )

    /// CON-21-ACTOR-CONCURRENT-SOLVING: Dispatching corpus fixtures through ConstraintSolverActor asynchronously off the main actor.
    public static let con21ActorConcurrentSolving = SolverCorpusFixture(
        id: "CON-21-ACTOR-CONCURRENT-SOLVING",
        name: "ConstraintSolverActor Concurrent Background Solving",
        category: .orthogonal,
        expectedStatusKind: .converged,
        expectedSystemDOF: .underConstrained(dof: 3),
        buildSystem: {
            let lineA = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(10, 0))
            let lineB = SketchEntity.line(start: SIMD2<Double>(0, 5), end: SIMD2<Double>(10, 8))
            let cParallel = SketchConstraint(kind: .parallel, entityIds: [lineA.id, lineB.id])
            let system = ConstraintSystem(
                entities: [lineA, lineB],
                constraints: [cParallel],
                fixedEntityIds: [lineA.id]
            )
            return (system, ["lineA": lineA.id, "lineB": lineB.id], nil)
        },
        validate: { result, labels in
            #expect(result.status.isConverged)
            guard let bId = labels["lineB"],
                  let solvedB = result.solvedEntities.first(where: { $0.id == bId }),
                  let s = solvedB.startPoint, let e = solvedB.endPoint else {
                Issue.record("Missing solved line B")
                return
            }
            let v = e - s
            let slope = v.y / max(1e-6, abs(v.x))
            #expect(abs(slope) < 1e-3, "Line B should be parallel to horizontal baseline")
            #expect(result.entityDOF[bId] == .underConstrained(dof: 3))
        }
    )

    // MARK: - Benchmark Catalog

    public static let allFixtures: [SolverCorpusFixture] = [
        con01RightAngle,
        con02ParallelPair,
        con03PerpendicularTSection,
        con04ConstrainedRectangle,
        con05LineCircleTangent,
        con06CircleCircleExternalTangent,
        con07CircleCircleInternalTangent,
        con08ConcentricBoreShaft,
        con09ConcentricMultiCluster,
        con10SymmetricLinePair,
        con11SymmetricCirclePair,
        con12ChainDOFPropagation,
        con13FullyConstrainedAnchoredPoint,
        con14ConflictParallelPerpendicular,
        con15ConflictHorizontalVertical,
        con16ConflictIsolationIndependentEntity,
        con17RedundantParallel,
        con18RedundantConcentric,
        con19DegenerateImpossibleTangency,
        con20InteractiveDragPreservesInvariants,
        con21ActorConcurrentSolving
    ]
}

// MARK: - Test Suite

@Suite struct SolverRegressionCorpusTests {

    /// Parameterized table-driven execution across the full 21-fixture regression corpus (BL-CON-09, #200).
    @Test(arguments: SolverRegressionCorpus.allFixtures)
    func testParameterizedCorpusFixture(fixture: SolverCorpusFixture) throws {
        let (system, labels, dragTarget) = fixture.buildSystem()
        let result = ConstraintSolver.solve(system: system, dragTarget: dragTarget)

        switch fixture.expectedStatusKind {
        case .converged:
            #expect(result.status.isConverged, "Fixture \(fixture.id) expected converged status, got \(result.status)")
        case .overConstrained:
            if case .overConstrained = result.status {} else {
                Issue.record("Fixture \(fixture.id) expected overConstrained status, got \(result.status)")
            }
        case .redundant:
            if case .redundant = result.status {} else {
                Issue.record("Fixture \(fixture.id) expected redundant status, got \(result.status)")
            }
        case .failedToConverge:
            #expect(!result.status.isConverged, "Fixture \(fixture.id) expected failedToConverge status, got \(result.status)")
        }

        let computedDOF = ConstraintSolver.computeDOFStatus(system: system)
        #expect(computedDOF == fixture.expectedSystemDOF, "Fixture \(fixture.id) expected system DOF \(fixture.expectedSystemDOF), got \(computedDOF)")

        try fixture.validate(result, labels)
    }

    // MARK: - Named Categorical Benchmark Suites

    @Test func testOrthogonalCorpus() throws {
        let fixtures = [
            SolverRegressionCorpus.con01RightAngle,
            SolverRegressionCorpus.con02ParallelPair,
            SolverRegressionCorpus.con03PerpendicularTSection,
            SolverRegressionCorpus.con04ConstrainedRectangle
        ]
        for fixture in fixtures {
            try runFixture(fixture)
        }
    }

    @Test func testCurvilinearTangencyCorpus() throws {
        let fixtures = [
            SolverRegressionCorpus.con05LineCircleTangent,
            SolverRegressionCorpus.con06CircleCircleExternalTangent,
            SolverRegressionCorpus.con07CircleCircleInternalTangent
        ]
        for fixture in fixtures {
            try runFixture(fixture)
        }
    }

    @Test func testConcentricCorpus() throws {
        let fixtures = [
            SolverRegressionCorpus.con08ConcentricBoreShaft,
            SolverRegressionCorpus.con09ConcentricMultiCluster
        ]
        for fixture in fixtures {
            try runFixture(fixture)
        }
    }

    @Test func testBilateralSymmetryCorpus() throws {
        let fixtures = [
            SolverRegressionCorpus.con10SymmetricLinePair,
            SolverRegressionCorpus.con11SymmetricCirclePair
        ]
        for fixture in fixtures {
            try runFixture(fixture)
        }
    }

    @Test func testKinematicChainDOFCorpus() throws {
        let fixtures = [
            SolverRegressionCorpus.con12ChainDOFPropagation,
            SolverRegressionCorpus.con13FullyConstrainedAnchoredPoint
        ]
        for fixture in fixtures {
            try runFixture(fixture)
        }
    }

    @Test func testConflictAndOverConstrainedCorpus() throws {
        let fixtures = [
            SolverRegressionCorpus.con14ConflictParallelPerpendicular,
            SolverRegressionCorpus.con15ConflictHorizontalVertical,
            SolverRegressionCorpus.con16ConflictIsolationIndependentEntity
        ]
        for fixture in fixtures {
            try runFixture(fixture)
        }
    }

    @Test func testRedundantConstraintCorpus() throws {
        let fixtures = [
            SolverRegressionCorpus.con17RedundantParallel,
            SolverRegressionCorpus.con18RedundantConcentric
        ]
        for fixture in fixtures {
            try runFixture(fixture)
        }
    }

    @Test func testDegenerateStabilityCorpus() throws {
        try runFixture(SolverRegressionCorpus.con19DegenerateImpossibleTangency)
    }

    @Test func testInteractiveDragCorpus() throws {
        try runFixture(SolverRegressionCorpus.con20InteractiveDragPreservesInvariants)
    }

    @Test func testActorConcurrentCorpus() async throws {
        let fixture = SolverRegressionCorpus.con21ActorConcurrentSolving
        let (system, labels, dragTarget) = fixture.buildSystem()
        let actor = ConstraintSolverActor()

        let result = await actor.solve(system: system, dragTarget: dragTarget)
        #expect(result.status.isConverged)

        let status = await actor.computeDOFStatus(system: system)
        #expect(status == fixture.expectedSystemDOF)

        let entityDOF = await actor.computeEntityDOF(system: system)
        if let bId = labels["lineB"] {
            #expect(entityDOF[bId] == .underConstrained(dof: 3))
        }

        try fixture.validate(result, labels)
    }

    private func runFixture(_ fixture: SolverCorpusFixture) throws {
        let (system, labels, dragTarget) = fixture.buildSystem()
        let result = ConstraintSolver.solve(system: system, dragTarget: dragTarget)
        let computedDOF = ConstraintSolver.computeDOFStatus(system: system)
        #expect(computedDOF == fixture.expectedSystemDOF, "\(fixture.id): expected \(fixture.expectedSystemDOF), got \(computedDOF)")
        try fixture.validate(result, labels)
    }
}
