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
    case noIntersection(String)
    case pointNotOnEntity(entityId: UUID)
    case degenerateProjection(String)
    case degenerateRectangle(String)
    case degenerateSlot(String)
    case degeneratePolygon(String)
    case degenerateEllipse(String)

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
        case .noIntersection(let msg):
            return "No intersection found: \(msg)"
        case .pointNotOnEntity(let id):
            return "Point does not lie on sketch entity \(id.uuidString)"
        case .degenerateProjection(let msg):
            return "Degenerate projection: \(msg)"
        case .degenerateRectangle(let msg):
            return "Degenerate rectangle: \(msg)"
        case .degenerateSlot(let msg):
            return "Degenerate slot: \(msg)"
        case .degeneratePolygon(let msg):
            return "Degenerate polygon: \(msg)"
        case .degenerateEllipse(let msg):
            return "Degenerate ellipse: \(msg)"
        }
    }
}
