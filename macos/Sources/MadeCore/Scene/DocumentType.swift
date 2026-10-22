import Foundation

/// Distinguishes between part documents and assembly documents.
public enum DocumentType: String, Sendable, Codable, CaseIterable {
    case part
    case assembly
    case drawing

    public var displayName: String {
        switch self {
        case .part:
            return "Part"
        case .assembly:
            return "Assembly"
        case .drawing:
            return "Drawing"
        }
    }
}
