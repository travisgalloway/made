import Foundation

/// Per-solid record of the last failed recompute, read by the Inspector until the next success.
public struct RecomputeFailures: Equatable, Sendable {
    public private(set) var errors: [SolidId: KernelError] = [:]

    public init() {}

    /// The user-facing message for a failure, or nil for `.cancelled`, which a newer job supersedes.
    public static func message(for error: KernelError, solidId: SolidId) -> String? {
        guard error.code != .cancelled else { return nil }
        return "\(solidId.rawValue) failed to recompute (\(error.code.rawValue)): \(error.message)"
    }

    /// Updates the solid's entry from a result and returns the message to log, if any.
    public mutating func record(_ result: KernelResult<MeshPayload>, for id: SolidId) -> String? {
        switch result {
        case .success:
            errors.removeValue(forKey: id)
            return nil
        case .failure(_, let error):
            // A cancelled job means a newer one is pending; keep any earlier real failure visible.
            guard let message = Self.message(for: error, solidId: id) else { return nil }
            errors[id] = error
            return message
        }
    }

    public mutating func clear(_ id: SolidId) {
        errors.removeValue(forKey: id)
    }

    public func message(for id: SolidId) -> String? {
        errors[id].flatMap { Self.message(for: $0, solidId: id) }
    }
}
