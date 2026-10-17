import Foundation
import simd

/// Status of constraint solving and diagnostic analysis (ADR-D4, #37).
public enum SolverStatus: Sendable, Codable, Equatable {
    case converged
    case overConstrained(conflictingConstraints: [UUID])
    case redundant(redundantConstraints: [UUID])
    case failedToConverge(reason: String)

    public var isConverged: Bool {
        switch self {
        case .converged, .redundant:
            return true
        case .overConstrained, .failedToConverge:
            return false
        }
    }
}

/// Result envelope returned by the 2D geometric constraint solver (ADR-D4, #37, #196).
public struct SolverResult: Sendable, Codable, Equatable {
    public var status: SolverStatus
    public var solvedEntities: [SketchEntity]
    public var dof: Int
    public var message: String?
    public var entityDOF: [UUID: SketchDOFStatus]

    public init(
        status: SolverStatus,
        solvedEntities: [SketchEntity],
        dof: Int,
        message: String? = nil,
        entityDOF: [UUID: SketchDOFStatus] = [:]
    ) {
        self.status = status
        self.solvedEntities = solvedEntities
        self.dof = dof
        self.message = message
        self.entityDOF = entityDOF
    }
}

/// Pure-Swift 2D geometric constraint solver with Levenberg-Marquardt optimization,
/// Jacobian rank analysis, degrees-of-freedom calculation, and conflict diagnosis (ADR-D4, #37).
public struct ConstraintSolver: Sendable {

    public static let convergenceTolerance: Double = 1e-4
    public static let maxIterations: Int = 60

    /// Solves the given constraint system with an optional interactive drag target.
    public static func solve(system: ConstraintSystem, dragTarget: DragTarget? = nil) -> SolverResult {
        guard !system.entities.isEmpty else {
            return SolverResult(status: .converged, solvedEntities: [], dof: 0, entityDOF: [:])
        }

        let dofBaseline = calculateEntityDOF(entities: system.entities, fixedIds: system.fixedEntityIds)

        // If no constraints, just apply drag target if any and return
        if system.constraints.isEmpty {
            let entityDOF = baselineEntityDOF(entities: system.entities, fixedIds: system.fixedEntityIds)
            if let drag = dragTarget {
                var updated = system.entities
                if let idx = updated.firstIndex(where: { $0.id == drag.entityId }) {
                    applyDragToEntity(&updated[idx], drag: drag)
                }
                return SolverResult(status: .converged, solvedEntities: updated, dof: dofBaseline, entityDOF: entityDOF)
            }
            return SolverResult(status: .converged, solvedEntities: system.entities, dof: dofBaseline, entityDOF: entityDOF)
        }

        // Check for redundant constraints before or during solving
        let activeConstraints = system.constraints.filter { !$0.isDriven }
        let initialX = system.packParameters()
        let paramRanges = system.parameterRanges()

        // Solve the numerical system
        let solveOutcome = solveInternal(
            system: system,
            constraints: activeConstraints,
            dragTarget: dragTarget,
            initialX: initialX,
            paramRanges: paramRanges
        )

        let rank = computeSystemRank(system: system, constraints: activeConstraints, X: solveOutcome.finalX)
        let remainingDOF = max(0, dofBaseline - rank)

        if solveOutcome.converged {
            // Check for redundant constraints (constraints whose gradient is linearly dependent)
            let redundant = findRedundantConstraints(
                system: system,
                constraints: activeConstraints,
                solvedX: solveOutcome.finalX
            )

            let finalEntities = system.unpackParameters(solveOutcome.finalX)
            let entityDOF = evaluateEntityDOF(
                system: system,
                activeConstraints: activeConstraints,
                solvedX: solveOutcome.finalX,
                conflictingConstraintIds: [],
                isConverged: true
            )
            if !redundant.isEmpty {
                return SolverResult(
                    status: .redundant(redundantConstraints: redundant),
                    solvedEntities: finalEntities,
                    dof: remainingDOF,
                    message: "Redundant constraints detected: \(redundant.map { $0.uuidString.prefix(8) }.joined(separator: ", "))",
                    entityDOF: entityDOF
                )
            }

            return SolverResult(
                status: .converged,
                solvedEntities: finalEntities,
                dof: remainingDOF,
                entityDOF: entityDOF
            )
        } else {
            // The system did not converge. Perform conflict isolation.
            let conflicting = isolateConflictingConstraints(
                system: system,
                constraints: activeConstraints,
                dragTarget: dragTarget,
                initialX: initialX,
                paramRanges: paramRanges
            )

            let finalEntities = system.unpackParameters(solveOutcome.finalX)
            let entityDOF = evaluateEntityDOF(
                system: system,
                activeConstraints: activeConstraints,
                solvedX: solveOutcome.finalX,
                conflictingConstraintIds: conflicting,
                isConverged: false
            )
            if !conflicting.isEmpty {
                return SolverResult(
                    status: .overConstrained(conflictingConstraints: conflicting),
                    solvedEntities: finalEntities,
                    dof: remainingDOF,
                    message: "Over-constrained system: conflicting constraints \(conflicting.map { $0.uuidString.prefix(8) }.joined(separator: ", "))",
                    entityDOF: entityDOF
                )
            } else {
                return SolverResult(
                    status: .failedToConverge(reason: "Non-linear solver failed to converge within \(maxIterations) iterations (residual: \(String(format: "%.5f", solveOutcome.maxResidual)))"),
                    solvedEntities: finalEntities,
                    dof: remainingDOF,
                    message: "Solver failed to converge to a valid geometric solution",
                    entityDOF: entityDOF
                )
            }
        }
    }

    /// Evaluates the degree of freedom status of a sketch.
    public static func computeDOFStatus(system: ConstraintSystem) -> SketchDOFStatus {
        guard !system.entities.isEmpty else { return .inactive }
        let result = solve(system: system)
        switch result.status {
        case .converged, .redundant:
            if result.dof == 0 {
                return .fullyConstrained
            } else {
                return .underConstrained(dof: result.dof)
            }
        case .overConstrained:
            return .overConstrained(dof: result.dof)
        case .failedToConverge:
            return .overConstrained(dof: result.dof)
        }
    }

    /// Computes the degree of freedom status for each entity in the constraint system (BL-CON-05, #196).
    public static func computeEntityDOF(system: ConstraintSystem) -> [UUID: SketchDOFStatus] {
        guard !system.entities.isEmpty else { return [:] }
        if system.constraints.isEmpty {
            return baselineEntityDOF(entities: system.entities, fixedIds: system.fixedEntityIds)
        }

        let activeConstraints = system.constraints.filter { !$0.isDriven }
        let initialX = system.packParameters()
        let paramRanges = system.parameterRanges()

        let solveOutcome = solveInternal(
            system: system,
            constraints: activeConstraints,
            dragTarget: nil,
            initialX: initialX,
            paramRanges: paramRanges
        )

        let conflicting: [UUID]
        if !solveOutcome.converged {
            conflicting = isolateConflictingConstraints(
                system: system,
                constraints: activeConstraints,
                dragTarget: nil,
                initialX: initialX,
                paramRanges: paramRanges
            )
        } else {
            conflicting = []
        }

        return evaluateEntityDOF(
            system: system,
            activeConstraints: activeConstraints,
            solvedX: solveOutcome.finalX,
            conflictingConstraintIds: conflicting,
            isConverged: solveOutcome.converged
        )
    }

    // MARK: - Internal Solver

    private struct InternalSolveOutcome {
        var converged: Bool
        var finalX: [Double]
        var maxResidual: Double
    }

    private static func solveInternal(
        system: ConstraintSystem,
        constraints: [SketchConstraint],
        dragTarget: DragTarget?,
        initialX: [Double],
        paramRanges: [ConstraintSystem.EntityParamRange]
    ) -> InternalSolveOutcome {
        var X = initialX
        let n = X.count
        guard n > 0 else {
            return InternalSolveOutcome(converged: true, finalX: X, maxResidual: 0.0)
        }

        var fixedIndices = Set<Int>()
        for fixedId in system.fixedEntityIds {
            if let range = paramRanges.first(where: { $0.entityId == fixedId }) {
                for i in range.startIndex..<(range.startIndex + range.count) {
                    fixedIndices.insert(i)
                }
            }
        }

        if let drag = dragTarget, let range = paramRanges.first(where: { $0.entityId == drag.entityId }) {
            switch range.kind {
            case "line":
                if drag.endpoint == .start {
                    X[range.startIndex] = drag.targetPosition.x
                    X[range.startIndex + 1] = drag.targetPosition.y
                    fixedIndices.insert(range.startIndex)
                    fixedIndices.insert(range.startIndex + 1)
                } else {
                    X[range.startIndex + 2] = drag.targetPosition.x
                    X[range.startIndex + 3] = drag.targetPosition.y
                    fixedIndices.insert(range.startIndex + 2)
                    fixedIndices.insert(range.startIndex + 3)
                }
            case "circle", "arc":
                X[range.startIndex] = drag.targetPosition.x
                X[range.startIndex + 1] = drag.targetPosition.y
                fixedIndices.insert(range.startIndex)
                fixedIndices.insert(range.startIndex + 1)
            default:
                break
            }
        }

        var lambda = 1e-3
        var bestX = X
        var bestResidual = Double.greatestFiniteMagnitude

        for _ in 0..<maxIterations {
            let entities = system.unpackParameters(X)
            let residuals = evaluateResiduals(entities: entities, constraints: constraints)
            let maxRes = residuals.map { abs($0) }.max() ?? 0.0
            let currentNorm = residuals.reduce(0.0) { $0 + $1 * $1 }

            if maxRes < bestResidual {
                bestResidual = maxRes
                bestX = X
            }

            if maxRes < convergenceTolerance {
                return InternalSolveOutcome(converged: true, finalX: X, maxResidual: maxRes)
            }

            // Numerical Jacobian
            let J = evaluateJacobian(system: system, constraints: constraints, X: X, currentF: residuals)
            let m = J.count

            // Normal equations: (J^T J + lambda * I) * deltaX = -J^T F
            var A = Array(repeating: Array(repeating: 0.0, count: n), count: n)
            var b = Array(repeating: 0.0, count: n)

            // J^T J
            for i in 0..<n {
                guard !fixedIndices.contains(i) else {
                    A[i][i] = 1.0
                    b[i] = 0.0
                    continue
                }
                for j in 0..<n {
                    guard !fixedIndices.contains(j) else { continue }
                    var sum = 0.0
                    for k in 0..<m {
                        sum += J[k][i] * J[k][j]
                    }
                    A[i][j] = sum
                }
                A[i][i] += lambda

                var jtf = 0.0
                for k in 0..<m {
                    jtf += J[k][i] * residuals[k]
                }
                b[i] = -jtf
            }

            // Solve A * deltaX = b
            guard let deltaX = solveLinearSystem(A: A, b: b) else {
                lambda *= 10.0
                continue
            }

            // Candidate step
            var testX = X
            for i in 0..<n {
                if !fixedIndices.contains(i) {
                    testX[i] += deltaX[i]
                }
            }

            let testEntities = system.unpackParameters(testX)
            let testResiduals = evaluateResiduals(entities: testEntities, constraints: constraints)
            let testNorm = testResiduals.reduce(0.0) { $0 + $1 * $1 }

            if testNorm < currentNorm {
                X = testX
                lambda = max(1e-7, lambda / 10.0)
            } else {
                lambda = min(1e8, lambda * 10.0)
            }
        }

        return InternalSolveOutcome(converged: bestResidual < convergenceTolerance, finalX: bestX, maxResidual: bestResidual)
    }

    // MARK: - Residual Evaluation

    private static func evaluateResiduals(entities: [SketchEntity], constraints: [SketchConstraint]) -> [Double] {
        let entityMap = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        var residuals: [Double] = []

        for c in constraints {
            residuals.append(contentsOf: evaluateSingleConstraint(c, entityMap: entityMap))
        }
        return residuals
    }

    private static func evaluateSingleConstraint(_ constraint: SketchConstraint, entityMap: [UUID: SketchEntity]) -> [Double] {
        guard let firstId = constraint.entityIds.first, let entityA = entityMap[firstId] else {
            return [0.0]
        }
        let entityB = constraint.entityIds.count > 1 ? entityMap[constraint.entityIds[1]] : nil

        switch constraint.kind {
        case .parallel:
            guard let lineA = entityA.asLine(), let lineB = entityB?.asLine() else { return [0.0] }
            let vA = lineA.end - lineA.start
            let vB = lineB.end - lineB.start
            let lenA = max(1e-6, hypot(vA.x, vA.y))
            let lenB = max(1e-6, hypot(vB.x, vB.y))
            let uA = vA / lenA
            let uB = vB / lenB
            // Normalized cross product = 0
            return [uA.x * uB.y - uA.y * uB.x]

        case .perpendicular:
            guard let lineA = entityA.asLine(), let lineB = entityB?.asLine() else { return [0.0] }
            let vA = lineA.end - lineA.start
            let vB = lineB.end - lineB.start
            let lenA = max(1e-6, hypot(vA.x, vA.y))
            let lenB = max(1e-6, hypot(vB.x, vB.y))
            let uA = vA / lenA
            let uB = vB / lenB
            // Normalized dot product = 0
            return [uA.x * uB.x + uA.y * uB.y]

        case .tangent:
            if let line = entityA.asLine(), let circle = entityB?.asCircle() {
                return [pointToLineDistanceResidual(point: circle.center, line: line, targetDistance: circle.radius)]
            } else if let circle = entityA.asCircle(), let line = entityB?.asLine() {
                return [pointToLineDistanceResidual(point: circle.center, line: line, targetDistance: circle.radius)]
            } else if let cA = entityA.asCircle(), let cB = entityB?.asCircle() {
                let dist = hypot(cA.center.x - cB.center.x, cA.center.y - cB.center.y)
                let dExt = cA.radius + cB.radius
                let dInt = abs(cA.radius - cB.radius)
                let target = abs(dist - dExt) <= abs(dist - dInt) ? dExt : dInt
                return [dist - target]
            }
            return [0.0]

        case .concentric:
            guard let cA = entityA.centerPoint, let cB = entityB?.centerPoint else { return [0.0, 0.0] }
            return [cA.x - cB.x, cA.y - cB.y]

        case .symmetric:
            // Axis line is referenceEntityId or second/third entity
            let axisLine: (start: SIMD2<Double>, end: SIMD2<Double>)?
            if let refId = constraint.referenceEntityId, let ref = entityMap[refId]?.asLine() {
                axisLine = ref
            } else if constraint.entityIds.count >= 3, let ref = entityMap[constraint.entityIds[2]]?.asLine() {
                axisLine = ref
            } else {
                axisLine = nil
            }
            guard let axis = axisLine else { return [0.0] }

            let vAxis = axis.end - axis.start
            let lenAxis = max(1e-6, hypot(vAxis.x, vAxis.y))
            let uAxis = vAxis / lenAxis
            let nAxis = SIMD2<Double>(-uAxis.y, uAxis.x)

            if let lA = entityA.asLine(), let lB = entityB?.asLine() {
                // Determine point pairing (start-to-start or start-to-end)
                let errPair1 = symmetryError(pA: lA.start, pB: lB.start, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis)
                             + symmetryError(pA: lA.end, pB: lB.end, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis)
                let errPair2 = symmetryError(pA: lA.start, pB: lB.end, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis)
                             + symmetryError(pA: lA.end, pB: lB.start, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis)

                let pBStart = errPair1 <= errPair2 ? lB.start : lB.end
                let pBEnd = errPair1 <= errPair2 ? lB.end : lB.start

                let r1 = pointSymmetryResiduals(pA: lA.start, pB: pBStart, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis)
                let r2 = pointSymmetryResiduals(pA: lA.end, pB: pBEnd, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis)
                return [r1.0, r1.1, r2.0, r2.1]
            } else if let cA = entityA.asCircle(), let cB = entityB?.asCircle() {
                let r = pointSymmetryResiduals(pA: cA.center, pB: cB.center, axisStart: axis.start, uAxis: uAxis, nAxis: nAxis)
                return [r.0, r.1, cA.radius - cB.radius]
            }
            return [0.0]

        case .coincident:
            let pA = entityA.startPoint ?? entityA.centerPoint ?? .zero
            let pB = entityB?.startPoint ?? entityB?.centerPoint ?? .zero
            return [pA.x - pB.x, pA.y - pB.y]

        case .horizontal:
            guard let line = entityA.asLine() else { return [0.0] }
            return [line.end.y - line.start.y]

        case .vertical:
            guard let line = entityA.asLine() else { return [0.0] }
            return [line.end.x - line.start.x]
        }
    }

    private static func pointToLineDistanceResidual(point: SIMD2<Double>, line: (start: SIMD2<Double>, end: SIMD2<Double>), targetDistance: Double) -> Double {
        let v = line.end - line.start
        let len = max(1e-6, hypot(v.x, v.y))
        let cross = (line.end.x - line.start.x) * (point.y - line.start.y) - (line.end.y - line.start.y) * (point.x - line.start.x)
        let dist = abs(cross) / len
        return dist - targetDistance
    }

    private static func pointSymmetryResiduals(pA: SIMD2<Double>, pB: SIMD2<Double>, axisStart: SIMD2<Double>, uAxis: SIMD2<Double>, nAxis: SIMD2<Double>) -> (Double, Double) {
        let mid = (pA + pB) * 0.5
        // Midpoint on axis line
        let resMid = (mid.x - axisStart.x) * nAxis.x + (mid.y - axisStart.y) * nAxis.y
        // Difference vector perpendicular to axis (dot product with axis direction is zero)
        let resPerp = (pB.x - pA.x) * uAxis.x + (pB.y - pA.y) * uAxis.y
        return (resMid, resPerp)
    }

    private static func symmetryError(pA: SIMD2<Double>, pB: SIMD2<Double>, axisStart: SIMD2<Double>, uAxis: SIMD2<Double>, nAxis: SIMD2<Double>) -> Double {
        let (r1, r2) = pointSymmetryResiduals(pA: pA, pB: pB, axisStart: axisStart, uAxis: uAxis, nAxis: nAxis)
        return r1 * r1 + r2 * r2
    }

    // MARK: - Jacobian & Linear Algebra

    private static func evaluateJacobian(
        system: ConstraintSystem,
        constraints: [SketchConstraint],
        X: [Double],
        currentF: [Double]
    ) -> [[Double]] {
        let m = currentF.count
        let n = X.count
        guard m > 0 && n > 0 else { return [] }

        var J = Array(repeating: Array(repeating: 0.0, count: n), count: m)
        let h = 1e-6

        for j in 0..<n {
            var xPlus = X
            xPlus[j] += h
            let ePlus = system.unpackParameters(xPlus)
            let fPlus = evaluateResiduals(entities: ePlus, constraints: constraints)

            var xMinus = X
            xMinus[j] -= h
            let eMinus = system.unpackParameters(xMinus)
            let fMinus = evaluateResiduals(entities: eMinus, constraints: constraints)

            for i in 0..<m {
                J[i][j] = (fPlus[i] - fMinus[i]) / (2.0 * h)
            }
        }
        return J
    }

    private static func solveLinearSystem(A: [[Double]], b: [Double]) -> [Double]? {
        let n = b.count
        guard n > 0 else { return [] }
        var mat = A
        var rhs = b

        for i in 0..<n {
            var maxRow = i
            var maxVal = abs(mat[i][i])
            for r in (i + 1)..<n {
                let v = abs(mat[r][i])
                if v > maxVal {
                    maxVal = v
                    maxRow = r
                }
            }
            if maxVal < 1e-12 {
                return nil
            }
            if maxRow != i {
                mat.swapAt(i, maxRow)
                rhs.swapAt(i, maxRow)
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

    /// Computes an exact basis of the null space (kernel) of a matrix via Gauss-Jordan elimination to RREF (BL-CON-05, #196).
    /// Returns a basis matrix V in R^{n x k} whose columns span ker(matrix).
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

    private static func computeSystemRank(system: ConstraintSystem, constraints: [SketchConstraint], X: [Double]) -> Int {
        let entities = system.unpackParameters(X)
        let F = evaluateResiduals(entities: entities, constraints: constraints)
        guard !F.isEmpty else { return 0 }
        let J = evaluateJacobian(system: system, constraints: constraints, X: X, currentF: F)
        return computeRank(J)
    }

    private static func baselineDOF(for entity: SketchEntity) -> Int {
        switch entity.kind {
        case "line":
            return 4
        case "circle":
            return 3
        case "arc":
            return 5
        default:
            return 0
        }
    }

    private static func calculateEntityDOF(entities: [SketchEntity], fixedIds: Set<UUID>) -> Int {
        var total = 0
        for e in entities where !fixedIds.contains(e.id) {
            total += baselineDOF(for: e)
        }
        return total
    }

    private static func baselineEntityDOF(entities: [SketchEntity], fixedIds: Set<UUID>) -> [UUID: SketchDOFStatus] {
        var statuses: [UUID: SketchDOFStatus] = [:]
        for entity in entities {
            if fixedIds.contains(entity.id) {
                statuses[entity.id] = .fullyConstrained
            } else {
                let base = baselineDOF(for: entity)
                statuses[entity.id] = base == 0 ? .fullyConstrained : .underConstrained(dof: base)
            }
        }
        return statuses
    }

    private static func evaluateEntityDOF(
        system: ConstraintSystem,
        activeConstraints: [SketchConstraint],
        solvedX: [Double],
        conflictingConstraintIds: [UUID],
        isConverged: Bool = true
    ) -> [UUID: SketchDOFStatus] {
        guard !system.entities.isEmpty else { return [:] }
        if activeConstraints.isEmpty {
            return baselineEntityDOF(entities: system.entities, fixedIds: system.fixedEntityIds)
        }

        var effectiveConflicting = conflictingConstraintIds
        if effectiveConflicting.isEmpty && !isConverged {
            let entities = system.unpackParameters(solvedX)
            let entityMap = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
            for c in activeConstraints {
                let res = evaluateSingleConstraint(c, entityMap: entityMap)
                if (res.map { abs($0) }.max() ?? 0.0) > convergenceTolerance {
                    effectiveConflicting.append(c.id)
                }
            }
        }

        var conflictingEntityIds = Set<UUID>()
        for cId in effectiveConflicting {
            if let c = system.constraints.first(where: { $0.id == cId }) {
                conflictingEntityIds.formUnion(c.entityIds)
                if let refId = c.referenceEntityId {
                    conflictingEntityIds.insert(refId)
                }
            }
        }

        let paramRanges = system.parameterRanges()
        let n = solvedX.count
        guard n > 0 else {
            return baselineEntityDOF(entities: system.entities, fixedIds: system.fixedEntityIds)
        }

        let entities = system.unpackParameters(solvedX)
        let residuals = evaluateResiduals(entities: entities, constraints: activeConstraints)
        let J = evaluateJacobian(system: system, constraints: activeConstraints, X: solvedX, currentF: residuals)

        var fixedIndices = Set<Int>()
        for fixedId in system.fixedEntityIds {
            if let range = paramRanges.first(where: { $0.entityId == fixedId }) {
                for i in range.startIndex..<(range.startIndex + range.count) {
                    fixedIndices.insert(i)
                }
            }
        }

        var J_aug = J
        for idx in fixedIndices.sorted() {
            var lockRow = Array(repeating: 0.0, count: n)
            lockRow[idx] = 1.0
            J_aug.append(lockRow)
        }

        let V = computeNullSpaceBasis(J_aug, tolerance: convergenceTolerance)

        var result: [UUID: SketchDOFStatus] = [:]

        for entity in system.entities {
            if conflictingEntityIds.contains(entity.id) {
                result[entity.id] = .overConstrained(dof: 0)
                continue
            }

            if system.fixedEntityIds.contains(entity.id) {
                result[entity.id] = .fullyConstrained
                continue
            }

            guard let range = paramRanges.first(where: { $0.entityId == entity.id }) else {
                result[entity.id] = .fullyConstrained
                continue
            }

            let base = baselineDOF(for: entity)
            if base == 0 {
                result[entity.id] = .fullyConstrained
                continue
            }

            let Ve: [[Double]]
            if range.startIndex < V.count && (range.startIndex + range.count) <= V.count {
                Ve = Array(V[range.startIndex..<(range.startIndex + range.count)])
            } else {
                Ve = []
            }

            let rankVe = computeRank(Ve, tolerance: convergenceTolerance)
            let remaining = min(base, rankVe)

            if remaining == 0 {
                result[entity.id] = .fullyConstrained
            } else {
                result[entity.id] = .underConstrained(dof: remaining)
            }
        }

        return result
    }

    // MARK: - Redundancy & Conflict Isolation

    private static func findRedundantConstraints(
        system: ConstraintSystem,
        constraints: [SketchConstraint],
        solvedX: [Double]
    ) -> [UUID] {
        guard constraints.count > 1 else { return [] }
        var redundant: [UUID] = []
        let baseRank = computeSystemRank(system: system, constraints: constraints, X: solvedX)

        for i in 0..<constraints.count {
            var subset = constraints
            let candidate = subset.remove(at: i)
            let subRank = computeSystemRank(system: system, constraints: subset, X: solvedX)
            if subRank == baseRank {
                redundant.append(candidate.id)
            }
        }
        return redundant
    }

    private static func isolateConflictingConstraints(
        system: ConstraintSystem,
        constraints: [SketchConstraint],
        dragTarget: DragTarget?,
        initialX: [Double],
        paramRanges: [ConstraintSystem.EntityParamRange]
    ) -> [UUID] {
        guard constraints.count > 1 else { return [] }
        var conflicting: [UUID] = []

        for i in 0..<constraints.count {
            var subset = constraints
            let excluded = subset.remove(at: i)
            let outcome = solveInternal(
                system: system,
                constraints: subset,
                dragTarget: dragTarget,
                initialX: initialX,
                paramRanges: paramRanges
            )
            if outcome.converged {
                conflicting.append(excluded.id)
            }
        }

        if conflicting.count == 1, let firstId = conflicting.first, let firstConstraint = constraints.first(where: { $0.id == firstId }) {
            let entitySet = Set(firstConstraint.entityIds)
            for other in constraints where other.id != firstId {
                if !Set(other.entityIds).isDisjoint(with: entitySet) {
                    conflicting.append(other.id)
                }
            }
        }
        return conflicting
    }

    private static func applyDragToEntity(_ entity: inout SketchEntity, drag: DragTarget) {
        switch entity.kind {
        case "line":
            if drag.endpoint == .start {
                entity.startPoint = drag.targetPosition
            } else {
                entity.endPoint = drag.targetPosition
            }
        case "circle", "arc":
            entity.centerPoint = drag.targetPosition
        default:
            break
        }
    }
}

// MARK: - Entity Accessor Helpers

private extension SketchEntity {
    func asLine() -> (start: SIMD2<Double>, end: SIMD2<Double>)? {
        guard kind == "line", let s = startPoint, let e = endPoint else { return nil }
        return (start: s, end: e)
    }

    func asCircle() -> (center: SIMD2<Double>, radius: Double)? {
        guard kind == "circle", let c = centerPoint, let r = radius else { return nil }
        return (center: c, radius: r)
    }
}
