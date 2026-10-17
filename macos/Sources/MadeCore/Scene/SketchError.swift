import Foundation

/// Typed errors produced during 2D sketch profile validation and extrusion.
public enum SketchError: Error, Equatable, Sendable, LocalizedError {
    case openProfile(message: String)
    case zeroLengthLine(entityId: UUID)
    case degenerateArc(entityId: UUID, message: String)
    case emptySketch
    case noClosedLoop
    case invalidEntity(String)
    case overConstrained(message: String, conflictingConstraints: [UUID])
    case redundantConstraints(message: String, redundantConstraints: [UUID])
    case solverNonConvergence(message: String)

    public var errorDescription: String? {
        switch self {
        case .openProfile(let msg):
            return "Open sketch profile: \(msg)"
        case .zeroLengthLine(let id):
            return "Line entity \(id.uuidString) has zero length"
        case .degenerateArc(let id, let msg):
            return "Arc entity \(id.uuidString) is degenerate: \(msg)"
        case .emptySketch:
            return "Sketch contains no entities"
        case .noClosedLoop:
            return "Sketch does not form a closed loop"
        case .invalidEntity(let msg):
            return "Invalid sketch entity: \(msg)"
        case .overConstrained(let msg, _):
            return "Over-constrained sketch: \(msg)"
        case .redundantConstraints(let msg, _):
            return "Redundant constraints: \(msg)"
        case .solverNonConvergence(let msg):
            return "Solver failed to converge: \(msg)"
        }
    }
}
