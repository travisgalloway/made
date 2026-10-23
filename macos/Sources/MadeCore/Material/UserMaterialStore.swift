import Foundation
import os

/// Errors thrown by `UserMaterialStore` operations.
public enum UserMaterialStoreError: Error, LocalizedError, Equatable, Sendable {
    case emptyName
    case duplicateIdentifier(String)
    case materialNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Material name cannot be empty."
        case .duplicateIdentifier(let id):
            return "Material with identifier '\(id)' already exists."
        case .materialNotFound(let id):
            return "Material with identifier '\(id)' not found."
        }
    }
}

/// Store managing persistence, loading, and mutation of user-defined custom materials in Application Support.
public struct UserMaterialStore: Sendable {
    private static let logger = Logger(subsystem: "com.made.app", category: "Materials")

    public static let defaultFilename = "materials.json"

    /// Default application support directory for Made materials: `~/Library/Application Support/made/`.
    public static var defaultDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("made", isDirectory: true)
    }

    /// Default file URL for custom user materials: `~/Library/Application Support/made/materials.json`.
    public static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent(defaultFilename, isDirectory: false)
    }

    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    /// Loads all user materials from disk.
    /// Returns an empty array if the file does not exist or if decoding fails.
    public func loadMaterials() -> [MaterialDefinition] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = DocumentModelCoder.makeJSONDecoder()
            return try decoder.decode([MaterialDefinition].self, from: data)
        } catch {
            Self.logger.error("Failed to decode user materials at \(fileURL.path): \(error.localizedDescription)")
            return []
        }
    }

    /// Atomically persists user materials to disk.
    public func saveMaterials(_ materials: [MaterialDefinition]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let encoder = DocumentModelCoder.makeJSONEncoder()
        var data = try encoder.encode(materials)
        if !data.isEmpty && data.last != UInt8(ascii: "\n") {
            data.append(UInt8(ascii: "\n"))
        }
        try data.write(to: fileURL, options: .atomic)
    }

    /// Adds a new user material.
    public func addMaterial(_ material: MaterialDefinition) throws {
        let trimmedName = material.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw UserMaterialStoreError.emptyName
        }

        var current = loadMaterials()
        guard !current.contains(where: { $0.id == material.id }) else {
            throw UserMaterialStoreError.duplicateIdentifier(material.id)
        }

        current.append(material)
        try saveMaterials(current)
    }

    /// Updates an existing user material.
    public func updateMaterial(_ material: MaterialDefinition) throws {
        let trimmedName = material.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw UserMaterialStoreError.emptyName
        }

        var current = loadMaterials()
        guard let index = current.firstIndex(where: { $0.id == material.id }) else {
            throw UserMaterialStoreError.materialNotFound(material.id)
        }

        current[index] = material
        try saveMaterials(current)
    }

    /// Removes an existing user material by identifier.
    public func removeMaterial(id: String) throws {
        var current = loadMaterials()
        guard let index = current.firstIndex(where: { $0.id == id }) else {
            throw UserMaterialStoreError.materialNotFound(id)
        }

        current.remove(at: index)
        try saveMaterials(current)
    }

    /// Looks up a user material by identifier.
    public func material(withId id: String) -> MaterialDefinition? {
        loadMaterials().first(where: { $0.id == id })
    }
}
