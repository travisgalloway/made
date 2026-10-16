import Foundation

/// Canonical scene data representation stored as `document.json` inside a `.made` package.
public struct DocumentData: Codable, Sendable, Equatable {
    public static let currentSchemaVersion: Int = MadeManifest.currentSchemaVersion

    public var schemaVersion: Int
    public var features: [Feature]?
    public var objects: [SceneObject]
    public var selectedId: ObjectId?
    public var rollbackIndex: Int?
    public var bodies: [Body]?

    public init(
        schemaVersion: Int = DocumentData.currentSchemaVersion,
        features: [Feature]? = nil,
        objects: [SceneObject]? = nil,
        selectedId: ObjectId? = nil,
        rollbackIndex: Int? = nil,
        bodies: [Body]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.rollbackIndex = rollbackIndex
        if let objects {
            let clamped = objects.map { obj in
                var copy = obj
                copy.def = DocumentLimits.clamp(obj.def)
                return copy
            }
            self.objects = clamped
            self.features = features ?? clamped.map { Feature(from: $0) }
            self.bodies = bodies ?? clamped.map { Body(from: $0) }
        } else if let features {
            self.features = features
            let effectiveIndex = rollbackIndex ?? features.count
            let active = Array(features.prefix(effectiveIndex)).compactMap { $0.toSceneObject() }
            self.objects = active
            self.bodies = bodies ?? active.map { Body(from: $0) }
        } else {
            self.features = []
            self.objects = []
            self.bodies = bodies ?? []
        }
        self.selectedId = selectedId
    }

    public init(schemaVersion: Int = DocumentData.currentSchemaVersion, objects: [SceneObject], selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, bodies: [Body]? = nil) {
        self.init(schemaVersion: schemaVersion, features: nil, objects: objects, selectedId: selectedId, rollbackIndex: rollbackIndex, bodies: bodies)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case features
        case objects
        case selectedId
        case rollbackIndex
        case bodies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.rollbackIndex = try container.decodeIfPresent(Int.self, forKey: .rollbackIndex)
        let decodedFeatures = try container.decodeIfPresent([Feature].self, forKey: .features)
        let rawObjects = try container.decodeIfPresent([SceneObject].self, forKey: .objects) ?? []
        let clampedObjects = rawObjects.map { obj in
            var copy = obj
            copy.def = DocumentLimits.clamp(obj.def)
            return copy
        }
        self.objects = clampedObjects
        if let decodedFeatures {
            self.features = decodedFeatures
        } else {
            self.features = clampedObjects.map { Feature(from: $0) }
        }
        self.selectedId = try container.decodeIfPresent(ObjectId.self, forKey: .selectedId)
        self.bodies = try container.decodeIfPresent([Body].self, forKey: .bodies) ?? self.objects.map { Body(from: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(features, forKey: .features)
        try container.encode(objects, forKey: .objects)
        try container.encodeIfPresent(selectedId, forKey: .selectedId)
        try container.encodeIfPresent(rollbackIndex, forKey: .rollbackIndex)
        try container.encodeIfPresent(bodies, forKey: .bodies)
    }
}

/// Canonical JSON encoder and decoder for `DocumentData` and `.made` packages.
public enum DocumentModelCoder {
    public static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeJSONDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// Encodes `DocumentData` to canonical UTF-8 JSON with sorted keys, 2-space indentation, and a trailing newline.
    public static func encode(_ documentData: DocumentData) throws -> Data {
        let encoder = makeJSONEncoder()
        var data = try encoder.encode(documentData)
        if !data.isEmpty && data.last != UInt8(ascii: "\n") {
            data.append(UInt8(ascii: "\n"))
        }
        return data
    }

    /// Formats a JSON-serializable object into canonical UTF-8 JSON with sorted keys, 2-space indentation, unescaped slashes, and a trailing newline.
    public static func canonicalJSONData(from object: Any) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        if !data.isEmpty && data.last != UInt8(ascii: "\n") {
            data.append(UInt8(ascii: "\n"))
        }
        return data
    }

    /// Decodes `DocumentData` from JSON data, applying DocumentLimits clamping to all solids.
    public static func decode(from data: Data) throws -> DocumentData {
        let decoder = makeJSONDecoder()
        return try decoder.decode(DocumentData.self, from: data)
    }

    /// Convenience encoder for `DocumentModel`.
    @MainActor
    public static func encode(document: DocumentModel, schemaVersion: Int = DocumentData.currentSchemaVersion) throws -> Data {
        let docData = DocumentData(
            schemaVersion: schemaVersion,
            features: document.features,
            objects: document.objects,
            selectedId: document.selectedId,
            rollbackIndex: document.rollbackIndex,
            bodies: document.bodies
        )
        return try encode(docData)
    }

    /// Convenience decoder restoring into `DocumentModel`.
    @MainActor
    public static func decode(into document: DocumentModel, from data: Data) throws {
        let docData = try decode(from: data)
        if let features = docData.features {
            document.reset(with: features, selectedId: docData.selectedId, rollbackIndex: docData.rollbackIndex)
        } else {
            document.reset(with: docData.objects, selectedId: docData.selectedId, rollbackIndex: docData.rollbackIndex)
        }
    }
}
