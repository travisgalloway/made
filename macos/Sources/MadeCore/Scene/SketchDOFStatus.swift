import Foundation

/// Degrees-of-Freedom (DOF) constraint status of a 2D sketch (ADR-D4, #196, #397).
public enum SketchDOFStatus: Sendable, Codable, Equatable {
    case inactive
    case underConstrained(dof: Int)
    case fullyConstrained
    case overConstrained(dof: Int = 0)

    public var statusText: String {
        switch self {
        case .inactive:
            return "DOF: --"
        case .underConstrained(let dof):
            return "DOF: \(dof) under"
        case .fullyConstrained:
            return "DOF: fully constrained"
        case .overConstrained:
            return "DOF: over-constrained"
        }
    }
}
