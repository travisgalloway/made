import Foundation

/// Defines bitmask filters for interactive viewport picking and preselection.
public struct SelectionFilter: OptionSet, Sendable, Codable, Equatable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let faces = SelectionFilter(rawValue: 1 << 0)
    public static let edges = SelectionFilter(rawValue: 1 << 1)
    public static let vertices = SelectionFilter(rawValue: 1 << 2)
    public static let bodies = SelectionFilter(rawValue: 1 << 3)
    public static let sketchEntities = SelectionFilter(rawValue: 1 << 4)
    public static let components = SelectionFilter(rawValue: 1 << 5)

    public static let all: SelectionFilter = [
        .faces,
        .edges,
        .vertices,
        .bodies,
        .sketchEntities,
        .components
    ]

    // MARK: - Query Helpers

    /// Indicates whether picking or preselection may resolve faces.
    public var allowsFaces: Bool {
        contains(.faces)
    }

    /// Indicates whether picking or preselection may resolve edges.
    public var allowsEdges: Bool {
        contains(.edges)
    }

    /// Indicates whether picking or preselection may resolve vertices.
    public var allowsVertices: Bool {
        contains(.vertices)
    }

    /// Indicates whether picking may resolve solid bodies directly.
    public var allowsBodies: Bool {
        contains(.bodies)
    }

    /// Indicates whether picking may resolve 2D sketch entities.
    public var allowsSketchEntities: Bool {
        contains(.sketchEntities)
    }

    /// Indicates whether picking may resolve assembly components.
    public var allowsComponents: Bool {
        contains(.components)
    }

    /// Indicates whether any topological sub-element (face, edge, or vertex) is enabled.
    public var allowsSubElements: Bool {
        allowsFaces || allowsEdges || allowsVertices
    }
}
