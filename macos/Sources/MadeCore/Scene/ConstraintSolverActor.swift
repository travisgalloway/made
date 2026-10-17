import Foundation

/// In-process Swift 6 background actor executing constraint solver operations off the main thread (Invariants 1 & 7, ADR-D4, #37).
public actor ConstraintSolverActor {
    public init() {}

    /// Solves the given constraint system asynchronously off the main thread.
    public func solve(system: ConstraintSystem, dragTarget: DragTarget? = nil) -> SolverResult {
        ConstraintSolver.solve(system: system, dragTarget: dragTarget)
    }

    /// Evaluates the degree of freedom status of a sketch asynchronously.
    public func computeDOFStatus(system: ConstraintSystem) -> SketchDOFStatus {
        ConstraintSolver.computeDOFStatus(system: system)
    }

    /// Evaluates per-entity degrees of freedom status asynchronously off the main thread (BL-CON-05, #196).
    public func computeEntityDOF(system: ConstraintSystem) -> [UUID: SketchDOFStatus] {
        ConstraintSolver.computeEntityDOF(system: system)
    }
}
