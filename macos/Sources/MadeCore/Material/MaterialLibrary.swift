import Foundation

/// Engineering material library catalog providing preset definitions, querying, and category filtering.
public struct MaterialLibrary: Sendable, Equatable, Codable {
    /// Preset standard material library containing the compiled engineering materials.
    public static let standard = MaterialLibrary(materials: StandardMaterials.all)

    /// Registered materials in this library.
    public var materials: [MaterialDefinition]

    public init(materials: [MaterialDefinition] = StandardMaterials.all) {
        self.materials = materials
    }

    /// Looks up a material definition by its unique identifier.
    public func material(withId id: String) -> MaterialDefinition? {
        materials.first { $0.id == id }
    }

    /// Returns materials filtered by engineering category.
    public func materials(in category: MaterialCategory) -> [MaterialDefinition] {
        materials.filter { $0.category == category }
    }

    /// Filters materials matching a search query string across name, description, category, and citations.
    public func filter(query: String) -> [MaterialDefinition] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return materials }

        return materials.filter { mat in
            if mat.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if mat.description.localizedCaseInsensitiveContains(trimmed) { return true }
            if mat.category.displayName.localizedCaseInsensitiveContains(trimmed) { return true }
            if mat.id.localizedCaseInsensitiveContains(trimmed) { return true }
            for citation in mat.citations {
                if citation.sourceName.localizedCaseInsensitiveContains(trimmed) { return true }
                if citation.specification.localizedCaseInsensitiveContains(trimmed) { return true }
                if citation.notes.localizedCaseInsensitiveContains(trimmed) { return true }
            }
            return false
        }
    }

    /// Filters materials matching an optional category and optional text query.
    public func filter(category: MaterialCategory?, query: String) -> [MaterialDefinition] {
        let base = category == nil ? materials : materials(in: category!)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        return base.filter { mat in
            if mat.name.localizedCaseInsensitiveContains(trimmed) { return true }
            if mat.description.localizedCaseInsensitiveContains(trimmed) { return true }
            if mat.id.localizedCaseInsensitiveContains(trimmed) { return true }
            for citation in mat.citations {
                if citation.sourceName.localizedCaseInsensitiveContains(trimmed) { return true }
                if citation.specification.localizedCaseInsensitiveContains(trimmed) { return true }
                if citation.notes.localizedCaseInsensitiveContains(trimmed) { return true }
            }
            return false
        }
    }
}
