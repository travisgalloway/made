import Foundation
import os

/// Raw package files in memory before model construction, used during forward schema migration.
public struct DocumentPackageData: Sendable, Equatable {
    public var manifestData: Data
    public var documentData: Data
    public var assets: [String: Data]
    public var parts: [String: Data]

    public init(
        manifestData: Data,
        documentData: Data,
        assets: [String: Data] = [:],
        parts: [String: Data] = [:]
    ) {
        self.manifestData = manifestData
        self.documentData = documentData
        self.assets = assets
        self.parts = parts
    }
}

/// A forward migration transforming in-memory package data from `sourceVersion` to `targetVersion`.
public protocol DocumentMigration: Sendable {
    var sourceVersion: Int { get }
    var targetVersion: Int { get }
    func migrate(package: inout DocumentPackageData) throws
}

/// Thread-safe registry that executes sequential forward migrations on document packages in memory.
public final class DocumentMigrator: Sendable {
    private let migrationsLock: OSAllocatedUnfairLock<[any DocumentMigration]>

    public static let shared: DocumentMigrator = DocumentMigrator(migrations: [MigrationV1ToV2()])

    public init(migrations: [any DocumentMigration] = [MigrationV1ToV2()]) {
        self.migrationsLock = OSAllocatedUnfairLock(initialState: migrations)
    }

    /// Registers a migration step in the migrator.
    public func register(_ migration: any DocumentMigration) {
        migrationsLock.withLock { registry in
            registry.removeAll(where: { $0.sourceVersion == migration.sourceVersion && $0.targetVersion == migration.targetVersion })
            registry.append(migration)
        }
    }

    /// Migrates package data sequentially from `sourceVersion` to `targetVersion` in memory.
    public func migrate(package: inout DocumentPackageData, from sourceVersion: Int, to targetVersion: Int) throws {
        if sourceVersion == targetVersion {
            return
        }

        guard sourceVersion < targetVersion else {
            throw MadeDocumentError.unsupportedSchemaVersion(sourceVersion)
        }

        let available = migrationsLock.withLock { $0 }
        guard let path = findMigrationPath(from: sourceVersion, to: targetVersion, in: available) else {
            throw MadeDocumentError.unsupportedSchemaVersion(sourceVersion)
        }

        for step in path {
            try step.migrate(package: &package)
        }
    }

    private func findMigrationPath(from source: Int, to target: Int, in available: [any DocumentMigration]) -> [any DocumentMigration]? {
        var queue: [(version: Int, path: [any DocumentMigration])] = [(source, [])]
        var visited: Set<Int> = [source]

        while !queue.isEmpty {
            let (curr, path) = queue.removeFirst()
            if curr == target {
                return path
            }
            for migration in available where migration.sourceVersion == curr && !visited.contains(migration.targetVersion) {
                visited.insert(migration.targetVersion)
                queue.append((migration.targetVersion, path + [migration]))
            }
        }
        return nil
    }
}

/// Forward migration from schema version 1 to schema version 2.
public struct MigrationV1ToV2: DocumentMigration {
    public let sourceVersion: Int = 1
    public let targetVersion: Int = 2

    public init() {}

    public func migrate(package: inout DocumentPackageData) throws {
        // 1. Migrate manifest.json
        let manifestObj: Any
        do {
            manifestObj = try JSONSerialization.jsonObject(with: package.manifestData, options: [])
        } catch {
            throw MadeDocumentError.corruptDocument("manifest.json is invalid: \(error.localizedDescription)")
        }

        guard var manifestDict = manifestObj as? [String: Any] else {
            throw MadeDocumentError.corruptDocument("manifest.json root must be a JSON object")
        }

        manifestDict["schemaVersion"] = targetVersion
        if manifestDict["metadata"] == nil {
            manifestDict["metadata"] = [String: String]()
        }

        do {
            package.manifestData = try DocumentModelCoder.canonicalJSONData(from: manifestDict)
        } catch {
            throw MadeDocumentError.corruptDocument("Failed to serialize migrated manifest.json: \(error.localizedDescription)")
        }

        // 2. Migrate document.json
        let docObj: Any
        do {
            docObj = try JSONSerialization.jsonObject(with: package.documentData, options: [])
        } catch {
            throw MadeDocumentError.corruptDocument("document.json is invalid: \(error.localizedDescription)")
        }

        guard var docDict = docObj as? [String: Any] else {
            throw MadeDocumentError.corruptDocument("document.json root must be a JSON object")
        }

        docDict["schemaVersion"] = targetVersion

        // Ensure "features" array is populated (if missing, constructs from "objects")
        if docDict["features"] == nil {
            if let objectsJSON = docDict["objects"] {
                do {
                    let objectsData = try JSONSerialization.data(withJSONObject: objectsJSON)
                    let objects = try JSONDecoder().decode([SceneObject].self, from: objectsData)
                    let features = objects.map { Feature(from: $0) }
                    let featuresData = try DocumentModelCoder.makeJSONEncoder().encode(features)
                    docDict["features"] = try JSONSerialization.jsonObject(with: featuresData)
                } catch {
                    throw MadeDocumentError.corruptDocument("Failed to synthesize features from objects: \(error.localizedDescription)")
                }
            } else {
                docDict["features"] = []
            }
        }

        do {
            package.documentData = try DocumentModelCoder.canonicalJSONData(from: docDict)
        } catch {
            throw MadeDocumentError.corruptDocument("Failed to serialize migrated document.json: \(error.localizedDescription)")
        }
    }
}
