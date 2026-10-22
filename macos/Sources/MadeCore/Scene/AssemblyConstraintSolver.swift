import Foundation
import simd

/// Pure-Swift 3D rigid-body assembly constraint and mate solver (ADR-D4, #164).
///
/// Implements Levenberg-Marquardt numerical optimization over continuous $SE(3)$ parameterizations,
/// numerical Jacobian rank and null space analysis for degrees of freedom (DOF), redundant mate detection,
/// and combinatorial conflict isolation.
public struct AssemblyConstraintSolver: Sendable {

    public static let convergenceTolerance: Double = 1e-4
    public static let maxIterations: Int = 60
    public static let regularizerWeight: Double = 1e-8

    // MARK: - Public API

    /// Solves the given 3D assembly constraint system, updating transforms of free component instances.
    public static func solve(system: AssemblyConstraintSystem) -> AssemblySolverResult {
        let activeConstraints = system.constraints.filter { !$0.isSuppressed }
        let freeInstances = system.instances.filter { !$0.isGrounded }
        let groundedInstances = system.instances.filter { $0.isGrounded }

        // Initial transforms dictionary
        var currentTransforms: [UUID: Transform] = [:]
        for inst in system.instances {
            currentTransforms[inst.id] = inst.transform
        }

        // If there are no free instances, just evaluate existing residuals
        if freeInstances.isEmpty {
            let residuals = evaluateResiduals(
                constraints: activeConstraints,
                currentTransforms: currentTransforms
            )
            let maxRes = residuals.map { abs($0) }.max() ?? 0.0
            var instDOF: [UUID: Int] = [:]
            for inst in groundedInstances {
                instDOF[inst.id] = 0
            }
            if maxRes < convergenceTolerance {
                return AssemblySolverResult(
                    status: .converged,
                    solvedTransforms: currentTransforms,
                    totalDOF: 0,
                    instanceDOF: instDOF
                )
            } else {
                return AssemblySolverResult(
                    status: .failedToConverge(reason: "Grounded assembly has unsatisfied constraints (max residual: \(maxRes))"),
                    solvedTransforms: currentTransforms,
                    totalDOF: 0,
                    instanceDOF: instDOF
                )
            }
        }

        // If there are no active constraints, each free body has 6 DOF
        if activeConstraints.isEmpty {
            let totalDOF = freeInstances.count * 6
            var instDOF: [UUID: Int] = [:]
            for inst in freeInstances {
                instDOF[inst.id] = 6
            }
            for inst in groundedInstances {
                instDOF[inst.id] = 0
            }
            return AssemblySolverResult(
                status: .converged,
                solvedTransforms: currentTransforms,
                totalDOF: totalDOF,
                instanceDOF: instDOF
            )
        }

        // Pack state vector X0 from free instance transforms
        let initialX = packParameters(instances: freeInstances)

        // Run numerical solve
        let outcome = solveInternal(
            freeInstances: freeInstances,
            groundedInstances: groundedInstances,
            constraints: activeConstraints,
            initialX: initialX
        )

        // Unpack final solved transforms
        var solvedTransforms = currentTransforms
        let solvedFreeTransforms = unpackTransforms(X: outcome.finalX, freeInstances: freeInstances)
        for (id, t) in solvedFreeTransforms {
            solvedTransforms[id] = t
        }

        // Compute DOF and Jacobian rank at the solved state
        let dofAnalysis = computeDOF(
            freeInstances: freeInstances,
            groundedInstances: groundedInstances,
            constraints: activeConstraints,
            solvedX: outcome.finalX,
            solvedTransforms: solvedTransforms
        )

        if outcome.converged {
            // Check for redundant constraints
            let redundant = findRedundantConstraints(
                freeInstances: freeInstances,
                groundedInstances: groundedInstances,
                constraints: activeConstraints,
                solvedX: outcome.finalX,
                solvedTransforms: solvedTransforms
            )

            if !redundant.isEmpty {
                return AssemblySolverResult(
                    status: .redundant(redundantConstraints: redundant),
                    solvedTransforms: solvedTransforms,
                    totalDOF: dofAnalysis.totalDOF,
                    instanceDOF: dofAnalysis.instanceDOF,
                    message: "Redundant constraints detected: \(redundant.map { $0.uuidString.prefix(8) }.joined(separator: ", "))"
                )
            }

            return AssemblySolverResult(
                status: .converged,
                solvedTransforms: solvedTransforms,
                totalDOF: dofAnalysis.totalDOF,
                instanceDOF: dofAnalysis.instanceDOF
            )
        } else {
            // Conflict isolation: find minimal conflicting constraint subset
            let conflicting = isolateConflictingConstraints(
                freeInstances: freeInstances,
                groundedInstances: groundedInstances,
                constraints: activeConstraints,
                initialX: initialX
            )

            if !conflicting.isEmpty {
                return AssemblySolverResult(
                    status: .overConstrained(conflictingConstraints: conflicting),
                    solvedTransforms: solvedTransforms,
                    totalDOF: dofAnalysis.totalDOF,
                    instanceDOF: dofAnalysis.instanceDOF,
                    message: "Over-constrained system: conflicting constraints \(conflicting.map { $0.uuidString.prefix(8) }.joined(separator: ", "))"
                )
            }

            return AssemblySolverResult(
                status: .failedToConverge(reason: "Non-linear assembly solver failed to converge within \(maxIterations) iterations (residual: \(String(format: "%.5f", outcome.maxResidual)))"),
                solvedTransforms: solvedTransforms,
                totalDOF: dofAnalysis.totalDOF,
                instanceDOF: dofAnalysis.instanceDOF
            )
        }
    }

    /// Evaluates total and per-instance degrees of freedom for an assembly constraint system.
    public static func computeSystemDOF(system: AssemblyConstraintSystem) -> (totalDOF: Int, instanceDOF: [UUID: Int]) {
        let activeConstraints = system.constraints.filter { !$0.isSuppressed }
        let freeInstances = system.instances.filter { !$0.isGrounded }
        let groundedInstances = system.instances.filter { $0.isGrounded }

        if freeInstances.isEmpty {
            var instDOF: [UUID: Int] = [:]
            for inst in groundedInstances { instDOF[inst.id] = 0 }
            return (totalDOF: 0, instanceDOF: instDOF)
        }

        var currentTransforms: [UUID: Transform] = [:]
        for inst in system.instances {
            currentTransforms[inst.id] = inst.transform
        }

        let X = packParameters(instances: freeInstances)
        let analysis = computeDOF(
            freeInstances: freeInstances,
            groundedInstances: groundedInstances,
            constraints: activeConstraints,
            solvedX: X,
            solvedTransforms: currentTransforms
        )
        return (totalDOF: analysis.totalDOF, instanceDOF: analysis.instanceDOF)
    }

    // MARK: - Internal Levenberg-Marquardt Solver

    private struct InternalSolveOutcome {
        var converged: Bool
        var finalX: [Double]
        var maxResidual: Double
    }

    private static func solveInternal(
        freeInstances: [ComponentInstance],
        groundedInstances: [ComponentInstance],
        constraints: [AssemblyConstraint],
        initialX: [Double]
    ) -> InternalSolveOutcome {
        let n = initialX.count
        var X = initialX
        var lambda = 1e-3
        var bestX = X
        var bestResidual = Double.greatestFiniteMagnitude

        let groundedMap = Dictionary(uniqueKeysWithValues: groundedInstances.map { ($0.id, $0.transform) })

        func transformsForState(_ state: [Double]) -> [UUID: Transform] {
            var dict = groundedMap
            let freeDict = unpackTransforms(X: state, freeInstances: freeInstances)
            for (k, v) in freeDict {
                dict[k] = v
            }
            return dict
        }

        func computeCost(residuals: [Double], currentX: [Double]) -> Double {
            var cost = 0.0
            for r in residuals {
                cost += r * r
            }
            for i in 0..<n {
                let diff = currentX[i] - initialX[i]
                cost += regularizerWeight * diff * diff
            }
            return cost
        }

        for _ in 0..<maxIterations {
            let currentTransforms = transformsForState(X)
            let residuals = evaluateResiduals(constraints: constraints, currentTransforms: currentTransforms)
            let maxRes = residuals.map { abs($0) }.max() ?? 0.0
            let currentCost = computeCost(residuals: residuals, currentX: X)

            if maxRes < bestResidual {
                bestResidual = maxRes
                bestX = X
            }

            if maxRes < convergenceTolerance {
                return InternalSolveOutcome(converged: true, finalX: X, maxResidual: maxRes)
            }

            // Numerical Jacobian J in R^{M x N}
            let J = evaluateJacobian(
                freeInstances: freeInstances,
                groundedMap: groundedMap,
                constraints: constraints,
                X: X,
                currentResiduals: residuals
            )
            let m = J.count
            guard m > 0 else {
                return InternalSolveOutcome(converged: true, finalX: X, maxResidual: 0.0)
            }

            // Normal equations: (J^T J + (lambda + regularizerWeight) I) * deltaX = -J^T F - regularizerWeight * (X - X0)
            var A = Array(repeating: Array(repeating: 0.0, count: n), count: n)
            var b = Array(repeating: 0.0, count: n)

            for i in 0..<n {
                for j in 0..<n {
                    var sum = 0.0
                    for k in 0..<m {
                        sum += J[k][i] * J[k][j]
                    }
                    A[i][j] = sum
                }
                A[i][i] += lambda + regularizerWeight

                var jtf = 0.0
                for k in 0..<m {
                    jtf += J[k][i] * residuals[k]
                }
                var rhs = -jtf
                rhs -= regularizerWeight * (X[i] - initialX[i])
                b[i] = rhs
            }

            // Solve linear system
            guard let deltaX = solveLinearSystem(A: A, b: b) else {
                lambda = min(1e8, lambda * 10.0)
                continue
            }

            // Candidate state
            var testX = X
            for i in 0..<n {
                testX[i] += deltaX[i]
            }

            let testTransforms = transformsForState(testX)
            let testResiduals = evaluateResiduals(constraints: constraints, currentTransforms: testTransforms)
            let testCost = computeCost(residuals: testResiduals, currentX: testX)
            let testMaxRes = testResiduals.map { abs($0) }.max() ?? 0.0

            if testCost < currentCost {
                X = testX
                lambda = max(1e-7, lambda / 10.0)
                if testMaxRes < convergenceTolerance {
                    return InternalSolveOutcome(converged: true, finalX: X, maxResidual: testMaxRes)
                }
            } else {
                lambda = min(1e8, lambda * 10.0)
            }
        }

        return InternalSolveOutcome(
            converged: bestResidual < convergenceTolerance,
            finalX: bestX,
            maxResidual: bestResidual
        )
    }

    // MARK: - Residual Evaluation

    /// Evaluates residuals for all active constraints given world transforms.
    public static func evaluateResiduals(
        constraints: [AssemblyConstraint],
        currentTransforms: [UUID: Transform]
    ) -> [Double] {
        var residuals: [Double] = []
        for c in constraints where !c.isSuppressed {
            residuals.append(contentsOf: evaluateSingleConstraint(c, currentTransforms: currentTransforms))
        }
        return residuals
    }

    private static func evaluateSingleConstraint(
        _ constraint: AssemblyConstraint,
        currentTransforms: [UUID: Transform]
    ) -> [Double] {
        let f1World = worldFeature(constraint.firstFeature, currentTransforms: currentTransforms)
        let f2World = worldFeature(constraint.secondFeature, currentTransforms: currentTransforms)

        let P1 = SIMD3<Double>(Double(f1World.origin.x), Double(f1World.origin.y), Double(f1World.origin.z))
        let P2 = SIMD3<Double>(Double(f2World.origin.x), Double(f2World.origin.y), Double(f2World.origin.z))
        let A1 = SIMD3<Double>(Double(f1World.primaryAxis.x), Double(f1World.primaryAxis.y), Double(f1World.primaryAxis.z))
        let A2 = SIMD3<Double>(Double(f2World.primaryAxis.x), Double(f2World.primaryAxis.y), Double(f2World.primaryAxis.z))
        let B1 = SIMD3<Double>(Double(f1World.secondaryAxis.x), Double(f1World.secondaryAxis.y), Double(f1World.secondaryAxis.z))
        let B2 = SIMD3<Double>(Double(f2World.secondaryAxis.x), Double(f2World.secondaryAxis.y), Double(f2World.secondaryAxis.z))

        switch constraint.kind {
        case .coincident:
            // Aligns two feature origins to coincide (3 translation constraints)
            return [P1.x - P2.x, P1.y - P2.y, P1.z - P2.z]

        case .concentric:
            // Collinear axes: 2 angular constraints for parallel axes + 2 lateral position constraints
            let u1 = perpendicularVector(primary: A1, hint: B1)
            let v1 = simd_cross(A1, u1)
            let D = P2 - P1

            let rAngle1 = simd_dot(A2, u1)
            let rAngle2 = simd_dot(A2, v1)
            let rPos1 = simd_dot(D, u1)
            let rPos2 = simd_dot(D, v1)
            return [rAngle1, rAngle2, rPos1, rPos2]

        case .distance:
            let d = constraint.value ?? 0.0
            if constraint.secondFeature.hasExplicitAxis || constraint.firstFeature.hasExplicitAxis {
                let axis = constraint.secondFeature.hasExplicitAxis ? A2 : A1
                return [simd_dot(P1 - P2, axis) - d]
            } else {
                let dist = simd_length(P1 - P2)
                return [dist - d]
            }

        case .parallel:
            // Aligns two orientation axes to be parallel (2 angular constraints)
            let u1 = perpendicularVector(primary: A1, hint: B1)
            let v1 = simd_cross(A1, u1)
            return [simd_dot(A2, u1), simd_dot(A2, v1)]

        case .perpendicular:
            // Two axes perpendicular: dot product is 0 (1 constraint)
            return [simd_dot(A1, A2)]

        case .angle:
            // Angle theta between axes: dot product is cos(theta) (1 constraint)
            let theta = constraint.value ?? 0.0
            return [simd_dot(A1, A2) - cos(theta)]

        case .tangent:
            let d = constraint.value ?? 0.0
            if constraint.firstFeature.hasExplicitAxis && constraint.secondFeature.hasExplicitAxis {
                // Cylinder-to-plane: cylinder axis A1 is perpendicular to plane normal A2
                // Distance from cylinder origin P1 to plane (P2, A2) equals offset d
                let rPos = simd_dot(P1 - P2, A2) - d
                let rPerp = simd_dot(A1, A2)
                return [rPos, rPerp]
            } else if constraint.secondFeature.hasExplicitAxis {
                // Point/sphere to plane (feature 2 has normal A2)
                let rPos = simd_dot(P1 - P2, A2) - d
                return [rPos]
            } else if constraint.firstFeature.hasExplicitAxis {
                // Plane (feature 1 has normal A1) to point/sphere
                let rPos = simd_dot(P2 - P1, A1) - d
                return [rPos]
            } else {
                // Sphere-to-sphere / distance
                let dist = simd_length(P1 - P2)
                return [dist - d]
            }

        case .fastened:
            // Rigidly locks translation and orientation (6 DOF: 3 translation, 3 rotation)
            let posDiff = P1 - P2
            let C1 = simd_cross(A1, B1)
            let C2 = simd_cross(A2, B2)
            // Orientation error rotation vector (isotropic, rank 3 at alignment)
            let rotErr = 0.5 * (simd_cross(A1, A2) + simd_cross(B1, B2) + simd_cross(C1, C2))
            // Orientation alignment penalties to prevent 180-degree spurious local roots
            let alignA = 1.0 - simd_dot(A1, A2)
            let alignB = 1.0 - simd_dot(B1, B2)
            return [posDiff.x, posDiff.y, posDiff.z, rotErr.x, rotErr.y, rotErr.z, alignA, alignB]

        case .revolute:
            // Rotational joint: 1 rotational DOF free around A1, 5 constrained (3 translation, 2 rotation)
            let posDiff = P1 - P2
            let u1 = perpendicularVector(primary: A1, hint: B1)
            let v1 = simd_cross(A1, u1)
            let rAng1 = simd_dot(A2, u1)
            let rAng2 = simd_dot(A2, v1)
            let alignA = 1.0 - simd_dot(A1, A2)
            return [posDiff.x, posDiff.y, posDiff.z, rAng1, rAng2, alignA]

        case .slider:
            // Prismatic joint: 1 translational DOF free along A1, 5 constrained (2 translation, 3 rotation)
            let D = P1 - P2
            let u1 = perpendicularVector(primary: A1, hint: B1)
            let v1 = simd_cross(A1, u1)
            let rPos1 = simd_dot(D, u1)
            let rPos2 = simd_dot(D, v1)

            let C1 = simd_cross(A1, B1)
            let C2 = simd_cross(A2, B2)
            let rotErr = 0.5 * (simd_cross(A1, A2) + simd_cross(B1, B2) + simd_cross(C1, C2))
            let alignA = 1.0 - simd_dot(A1, A2)
            let alignB = 1.0 - simd_dot(B1, B2)
            return [rPos1, rPos2, rotErr.x, rotErr.y, rotErr.z, alignA, alignB]

        case .cylindrical:
            // 2 DOFs free: 1 axial translation + 1 axial rotation along A1, 4 constrained (2 translation, 2 rotation)
            let D = P2 - P1
            let u1 = perpendicularVector(primary: A1, hint: B1)
            let v1 = simd_cross(A1, u1)
            let rAng1 = simd_dot(A2, u1)
            let rAng2 = simd_dot(A2, v1)
            let alignA = 1.0 - simd_dot(A1, A2)
            let rPos1 = simd_dot(D, u1)
            let rPos2 = simd_dot(D, v1)
            return [rAng1, rAng2, alignA, rPos1, rPos2]

        case .pinSlot:
            // 2 DOFs free: 1 translation along slot B1 + 1 rotation around pin axis A1, 4 constrained
            let u1 = perpendicularVector(primary: A1, hint: B1)
            let v1 = simd_cross(A1, u1)
            let rAng1 = simd_dot(A2, u1)
            let rAng2 = simd_dot(A2, v1)
            let alignA = 1.0 - simd_dot(A1, A2)

            let D = P2 - P1
            // Normal displacement out of slot plane (along A1)
            let rPosNorm = simd_dot(D, A1)
            // Transverse displacement across slot width (along v1)
            let rPosTrans = simd_dot(D, v1)
            return [rAng1, rAng2, alignA, rPosNorm, rPosTrans]

        case .planar:
            // 3 DOFs free: 2 planar translations in u1, v1 + 1 rotation around normal A1, 3 constrained
            let u1 = perpendicularVector(primary: A1, hint: B1)
            let v1 = simd_cross(A1, u1)
            let rAng1 = simd_dot(A2, u1)
            let rAng2 = simd_dot(A2, v1)
            let alignA = 1.0 - simd_dot(A1, A2)
            let d = constraint.value ?? 0.0
            let rPos = simd_dot(P2 - P1, A1) - d
            return [rAng1, rAng2, alignA, rPos]

        case .ball:
            // Spherical joint: 3 translation constrained, 3 rotation free
            let posDiff = P1 - P2
            return [posDiff.x, posDiff.y, posDiff.z]
        }
    }

    private struct WorldFeatureFrame {
        var origin: SIMD3<Float>
        var primaryAxis: SIMD3<Float>
        var secondaryAxis: SIMD3<Float>
    }

    private static func safeNormalize(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let len = simd_length(v)
        return len > 1e-6 ? v / len : fallback
    }

    private static func worldFeature(
        _ feature: AssemblyFeature,
        currentTransforms: [UUID: Transform]
    ) -> WorldFeatureFrame {
        guard let id = feature.componentInstanceId, let transform = currentTransforms[id] else {
            return WorldFeatureFrame(
                origin: feature.localOrigin,
                primaryAxis: safeNormalize(feature.localAxis, fallback: SIMD3<Float>(0, 0, 1)),
                secondaryAxis: safeNormalize(feature.localSecondaryAxis, fallback: SIMD3<Float>(1, 0, 0))
            )
        }
        let worldOrigin = transform.transformPoint(feature.localOrigin)
        let worldAxis = safeNormalize(transform.rotation.act(feature.localAxis), fallback: SIMD3<Float>(0, 0, 1))
        let worldSec = safeNormalize(transform.rotation.act(feature.localSecondaryAxis), fallback: SIMD3<Float>(1, 0, 0))
        return WorldFeatureFrame(
            origin: worldOrigin,
            primaryAxis: worldAxis,
            secondaryAxis: worldSec
        )
    }

    private static func perpendicularVector(primary: SIMD3<Double>, hint: SIMD3<Double>) -> SIMD3<Double> {
        let pLen = simd_length(primary)
        let pNorm = pLen > 1e-6 ? primary / pLen : SIMD3<Double>(0, 0, 1)
        let proj = hint - simd_dot(hint, pNorm) * pNorm
        let len = simd_length(proj)
        if len > 1e-4 {
            return proj / len
        }
        if abs(pNorm.x) < 0.9 {
            return simd_normalize(simd_cross(pNorm, SIMD3<Double>(1, 0, 0)))
        } else {
            return simd_normalize(simd_cross(pNorm, SIMD3<Double>(0, 1, 0)))
        }
    }

    // MARK: - Numerical Jacobian

    private static func evaluateJacobian(
        freeInstances: [ComponentInstance],
        groundedMap: [UUID: Transform],
        constraints: [AssemblyConstraint],
        X: [Double],
        currentResiduals: [Double]
    ) -> [[Double]] {
        let m = currentResiduals.count
        let n = X.count
        guard m > 0 && n > 0 else { return [] }

        var J = Array(repeating: Array(repeating: 0.0, count: n), count: m)

        func transformsForState(_ state: [Double]) -> [UUID: Transform] {
            var dict = groundedMap
            let freeDict = unpackTransforms(X: state, freeInstances: freeInstances)
            for (k, v) in freeDict {
                dict[k] = v
            }
            return dict
        }

        for j in 0..<n {
            let isPos = (j % 6) < 3
            let eps = isPos ? max(1e-3, abs(X[j]) * 1e-4) : 1e-3

            var xPlus = X
            var xMinus = X
            xPlus[j] += eps
            xMinus[j] -= eps

            let tPlus = transformsForState(xPlus)
            let tMinus = transformsForState(xMinus)

            let fPlus = evaluateResiduals(constraints: constraints, currentTransforms: tPlus)
            let fMinus = evaluateResiduals(constraints: constraints, currentTransforms: tMinus)

            let denom = 2.0 * eps
            for i in 0..<m {
                J[i][j] = (fPlus[i] - fMinus[i]) / denom
            }
        }

        return J
    }

    // MARK: - Degrees of Freedom Analysis

    private struct DOFResult {
        var totalDOF: Int
        var instanceDOF: [UUID: Int]
        var rank: Int
    }

    private static func computeDOF(
        freeInstances: [ComponentInstance],
        groundedInstances: [ComponentInstance],
        constraints: [AssemblyConstraint],
        solvedX: [Double],
        solvedTransforms: [UUID: Transform]
    ) -> DOFResult {
        let baselineDOF = freeInstances.count * 6
        var instDOF: [UUID: Int] = [:]
        for inst in groundedInstances {
            instDOF[inst.id] = 0
        }

        guard !freeInstances.isEmpty else {
            return DOFResult(totalDOF: 0, instanceDOF: instDOF, rank: 0)
        }

        guard !constraints.isEmpty else {
            for inst in freeInstances {
                instDOF[inst.id] = 6
            }
            return DOFResult(totalDOF: baselineDOF, instanceDOF: instDOF, rank: 0)
        }

        let groundedMap = Dictionary(uniqueKeysWithValues: groundedInstances.map { ($0.id, $0.transform) })
        let residuals = evaluateResiduals(constraints: constraints, currentTransforms: solvedTransforms)
        let J = evaluateJacobian(
            freeInstances: freeInstances,
            groundedMap: groundedMap,
            constraints: constraints,
            X: solvedX,
            currentResiduals: residuals
        )

        let rank = computeRank(J, tolerance: convergenceTolerance)
        let totalRemainingDOF = max(0, baselineDOF - rank)

        // Compute null space basis V in R^{n x k} where k = totalRemainingDOF
        let V = computeNullSpaceBasis(J, tolerance: convergenceTolerance)

        for (idx, inst) in freeInstances.enumerated() {
            let startRow = idx * 6
            let endRow = startRow + 6
            if startRow < V.count && endRow <= V.count {
                let Ve = Array(V[startRow..<endRow])
                let rankVe = computeRank(Ve, tolerance: convergenceTolerance)
                instDOF[inst.id] = min(6, rankVe)
            } else {
                instDOF[inst.id] = 0
            }
        }

        return DOFResult(totalDOF: totalRemainingDOF, instanceDOF: instDOF, rank: rank)
    }

    // MARK: - Redundancy & Conflict Diagnostics

    private static func findRedundantConstraints(
        freeInstances: [ComponentInstance],
        groundedInstances: [ComponentInstance],
        constraints: [AssemblyConstraint],
        solvedX: [Double],
        solvedTransforms: [UUID: Transform]
    ) -> [UUID] {
        guard constraints.count > 1 else { return [] }
        let groundedMap = Dictionary(uniqueKeysWithValues: groundedInstances.map { ($0.id, $0.transform) })
        let fullResiduals = evaluateResiduals(constraints: constraints, currentTransforms: solvedTransforms)
        let fullJ = evaluateJacobian(
            freeInstances: freeInstances,
            groundedMap: groundedMap,
            constraints: constraints,
            X: solvedX,
            currentResiduals: fullResiduals
        )
        let baseRank = computeRank(fullJ, tolerance: convergenceTolerance)
        guard fullJ.count > baseRank else { return [] }

        var redundant: [UUID] = []
        for i in 0..<constraints.count {
            var subset = constraints
            let candidate = subset.remove(at: i)
            let subResiduals = evaluateResiduals(constraints: subset, currentTransforms: solvedTransforms)
            let subJ = evaluateJacobian(
                freeInstances: freeInstances,
                groundedMap: groundedMap,
                constraints: subset,
                X: solvedX,
                currentResiduals: subResiduals
            )
            let subRank = computeRank(subJ, tolerance: convergenceTolerance)
            if subRank == baseRank {
                redundant.append(candidate.id)
            }
        }
        return redundant
    }

    private static func isolateConflictingConstraints(
        freeInstances: [ComponentInstance],
        groundedInstances: [ComponentInstance],
        constraints: [AssemblyConstraint],
        initialX: [Double]
    ) -> [UUID] {
        guard constraints.count > 1 else { return [] }
        var conflicting: [UUID] = []

        for i in 0..<constraints.count {
            var subset = constraints
            let excluded = subset.remove(at: i)
            let outcome = solveInternal(
                freeInstances: freeInstances,
                groundedInstances: groundedInstances,
                constraints: subset,
                initialX: initialX
            )
            if outcome.converged {
                conflicting.append(excluded.id)
            }
        }

        if conflicting.count == 1, let firstId = conflicting.first, let firstConstraint = constraints.first(where: { $0.id == firstId }) {
            let entity1 = firstConstraint.firstFeature.componentInstanceId
            let entity2 = firstConstraint.secondFeature.componentInstanceId
            for other in constraints where other.id != firstId {
                let other1 = other.firstFeature.componentInstanceId
                let other2 = other.secondFeature.componentInstanceId
                if (other1 != nil && (other1 == entity1 || other1 == entity2)) ||
                   (other2 != nil && (other2 == entity1 || other2 == entity2)) {
                    conflicting.append(other.id)
                }
            }
        }

        return conflicting
    }

    // MARK: - Parameter Packing and Unpacking

    private static func packParameters(instances: [ComponentInstance]) -> [Double] {
        var X: [Double] = []
        X.reserveCapacity(instances.count * 6)
        let degToRad = Float.pi / 180.0

        for inst in instances {
            let pos = inst.transform.position
            let eulerDeg = inst.transform.rotation.eulerAnglesDegrees
            X.append(Double(pos.x))
            X.append(Double(pos.y))
            X.append(Double(pos.z))
            X.append(Double(eulerDeg.x * degToRad))
            X.append(Double(eulerDeg.y * degToRad))
            X.append(Double(eulerDeg.z * degToRad))
        }
        return X
    }

    private static func unpackTransforms(X: [Double], freeInstances: [ComponentInstance]) -> [UUID: Transform] {
        var dict: [UUID: Transform] = [:]
        for (i, inst) in freeInstances.enumerated() {
            let base = i * 6
            let px = Float(X[base + 0])
            let py = Float(X[base + 1])
            let pz = Float(X[base + 2])
            let rx = Float(X[base + 3])
            let ry = Float(X[base + 4])
            let rz = Float(X[base + 5])

            let qx = simd_quatf(angle: rx, axis: SIMD3<Float>(1, 0, 0))
            let qy = simd_quatf(angle: ry, axis: SIMD3<Float>(0, 1, 0))
            let qz = simd_quatf(angle: rz, axis: SIMD3<Float>(0, 0, 1))
            let rot = simd_normalize(qz * qy * qx)

            dict[inst.id] = Transform(
                position: SIMD3<Float>(px, py, pz),
                rotation: rot,
                scale: inst.transform.scale
            )
        }
        return dict
    }

    // MARK: - Linear Algebra Utilities

    /// Solves linear system $A x = b$ via Gaussian elimination with partial pivoting.
    public static func solveLinearSystem(A: [[Double]], b: [Double]) -> [Double]? {
        let n = b.count
        guard n > 0, A.count == n, A[0].count == n else { return nil }
        var mat = A
        var rhs = b

        for i in 0..<n {
            var pivotRow = i
            var maxVal = abs(mat[i][i])
            for r in (i + 1)..<n {
                let val = abs(mat[r][i])
                if val > maxVal {
                    maxVal = val
                    pivotRow = r
                }
            }
            guard maxVal > 1e-12 else { return nil }
            if pivotRow != i {
                mat.swapAt(i, pivotRow)
                rhs.swapAt(i, pivotRow)
            }
            let pivot = mat[i][i]
            for r in (i + 1)..<n {
                let factor = mat[r][i] / pivot
                for c in i..<n {
                    mat[r][c] -= factor * mat[i][c]
                }
                rhs[r] -= factor * rhs[i]
            }
        }

        var x = Array(repeating: 0.0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = rhs[i]
            for c in (i + 1)..<n {
                sum -= mat[i][c] * x[c]
            }
            x[i] = sum / mat[i][i]
        }
        return x
    }

    /// Computes the rank of a matrix using Gaussian elimination with row echelon reduction.
    public static func computeRank(_ matrix: [[Double]], tolerance: Double = 1e-4) -> Int {
        guard !matrix.isEmpty && !matrix[0].isEmpty else { return 0 }
        let m = matrix.count
        let n = matrix[0].count
        var mat = matrix
        var rank = 0

        for col in 0..<n {
            var pivotRow = -1
            var maxVal = tolerance
            for r in rank..<m {
                let val = abs(mat[r][col])
                if val > maxVal {
                    maxVal = val
                    pivotRow = r
                }
            }
            if pivotRow != -1 {
                mat.swapAt(rank, pivotRow)
                let pivot = mat[rank][col]
                for r in 0..<m {
                    if r != rank {
                        let factor = mat[r][col] / pivot
                        for c in col..<n {
                            mat[r][c] -= factor * mat[rank][c]
                        }
                    }
                }
                rank += 1
                if rank == m { break }
            }
        }
        return rank
    }

    /// Computes an exact basis of the null space (kernel) of a matrix via Gauss-Jordan elimination to RREF.
    /// Returns a basis matrix $V$ in $\mathbb{R}^{n \times k}$ whose columns span $\ker(matrix)$.
    public static func computeNullSpaceBasis(_ matrix: [[Double]], tolerance: Double = 1e-4) -> [[Double]] {
        guard !matrix.isEmpty && !matrix[0].isEmpty else { return [] }
        let m = matrix.count
        let n = matrix[0].count
        var mat = matrix

        var pivotCols: [Int] = []
        var lead = 0

        for col in 0..<n {
            var pivotRow = -1
            var maxVal = tolerance
            for r in lead..<m {
                let val = abs(mat[r][col])
                if val > maxVal {
                    maxVal = val
                    pivotRow = r
                }
            }

            if pivotRow != -1 {
                mat.swapAt(lead, pivotRow)
                let pivot = mat[lead][col]
                for c in 0..<n {
                    mat[lead][c] /= pivot
                }
                for r in 0..<m {
                    if r != lead {
                        let factor = mat[r][col]
                        if abs(factor) > 1e-12 {
                            for c in 0..<n {
                                mat[r][c] -= factor * mat[lead][c]
                            }
                        }
                    }
                }
                pivotCols.append(col)
                lead += 1
                if lead == m { break }
            }
        }

        let pivotSet = Set(pivotCols)
        var freeCols: [Int] = []
        for c in 0..<n {
            if !pivotSet.contains(c) {
                freeCols.append(c)
            }
        }

        let k = freeCols.count
        guard k > 0 else {
            return Array(repeating: [Double](), count: n)
        }

        var V = Array(repeating: Array(repeating: 0.0, count: k), count: n)
        for (colIdx, f) in freeCols.enumerated() {
            V[f][colIdx] = 1.0
            for (rowIdx, c) in pivotCols.enumerated() {
                let coeff = mat[rowIdx][f]
                V[c][colIdx] = abs(coeff) < 1e-10 ? 0.0 : -coeff
            }
        }

        return V
    }
}
