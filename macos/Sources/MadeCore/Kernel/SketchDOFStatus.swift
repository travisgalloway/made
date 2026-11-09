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

    /// Remaining degrees of freedom count, or 0 if fully constrained, or nil if inactive.
    public var remainingDOF: Int? {
        switch self {
        case .inactive:
            return nil
        case .underConstrained(let dof):
            return dof
        case .fullyConstrained:
            return 0
        case .overConstrained(let dof):
            return dof
        }
    }

    /// Short badge label for feature tree rows and inline badges.
    public var badgeText: String {
        switch self {
        case .inactive:
            return ""
        case .underConstrained(let dof):
            return "\(dof) DOF"
        case .fullyConstrained:
            return "Fully Defined"
        case .overConstrained:
            return "Over-constrained"
        }
    }

    /// Descriptive summary for subtitles and secondary status labels.
    public var summaryDescription: String {
        switch self {
        case .inactive:
            return "No entities"
        case .underConstrained(let dof):
            return "\(dof) DOF remaining"
        case .fullyConstrained:
            return "Fully constrained"
        case .overConstrained:
            return "Over-constrained"
        }
    }

    /// Whether the status represents an inactive sketch (no entities).
    public var isInactive: Bool {
        if case .inactive = self { return true }
        return false
    }

    /// Whether the status represents an under-constrained sketch with remaining degrees of freedom.
    public var isUnderConstrained: Bool {
        if case .underConstrained = self { return true }
        return false
    }

    /// Whether the status represents a fully constrained sketch (0 DOF remaining).
    public var isFullyConstrained: Bool {
        if case .fullyConstrained = self { return true }
        return false
    }

    /// Whether the status represents an over-constrained sketch with conflicting or redundant constraints.
    public var isOverConstrained: Bool {
        if case .overConstrained = self { return true }
        return false
    }
}
