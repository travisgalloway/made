import Foundation

/// In-process Swift 6 background actor executing 3D assembly constraint solver operations off the main thread (ADR-D4, #164).
public actor AssemblyConstraintSolverActor {
    public init() {}

    /// Solves the given 3D assembly constraint system asynchronously off the main thread.
    public func solve(system: AssemblyConstraintSystem, dragTarget: AssemblyDragTarget? = nil) -> AssemblySolverResult {
        AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)
    }

    /// Evaluates total and per-instance degrees of freedom asynchronously off the main thread.
    public func computeSystemDOF(system: AssemblyConstraintSystem) -> (totalDOF: Int, instanceDOF: [UUID: Int]) {
        AssemblyConstraintSolver.computeSystemDOF(system: system)
    }
}
