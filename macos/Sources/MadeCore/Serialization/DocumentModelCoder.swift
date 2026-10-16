import Foundation

/// Canonical scene data representation stored as `document.json` inside a `.made` package.
public struct DocumentData: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var features: [Feature]?
    public var objects: [SceneObject]
    public var selectedId: ObjectId?
    public var rollbackIndex: Int?

    public init(
        schemaVersion: Int = 1,
        features: [Feature]? = nil,
        objects: [SceneObject]? = nil,
        selectedId: ObjectId? = nil,
        rollbackIndex: Int? = nil
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
        } else if let features {
            self.features = features
            let effectiveIndex = rollbackIndex ?? features.count
            self.objects = Array(features.prefix(effectiveIndex)).compactMap { $0.toSceneObject() }
        } else {
            self.features = []
            self.objects = []
        }
        self.selectedId = selectedId
    }

    public init(schemaVersion: Int = 1, objects: [SceneObject], selectedId: ObjectId? = nil, rollbackIndex: Int? = nil) {
        self.init(schemaVersion: schemaVersion, features: nil, objects: objects, selectedId: selectedId, rollbackIndex: rollbackIndex)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case features
        case objects
        case selectedId
        case rollbackIndex
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(features, forKey: .features)
        try container.encode(objects, forKey: .objects)
        try container.encodeIfPresent(selectedId, forKey: .selectedId)
        try container.encodeIfPresent(rollbackIndex, forKey: .rollbackIndex)
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

    /// Decodes `DocumentData` from JSON data, applying DocumentLimits clamping to all solids.
    public static func decode(from data: Data) throws -> DocumentData {
        let decoder = makeJSONDecoder()
        return try decoder.decode(DocumentData.self, from: data)
    }

    /// Convenience encoder for `DocumentModel`.
    @MainActor
    public static func encode(document: DocumentModel, schemaVersion: Int = 1) throws -> Data {
        let docData = DocumentData(
            schemaVersion: schemaVersion,
            features: document.features,
            objects: document.objects,
            selectedId: document.selectedId,
            rollbackIndex: document.rollbackIndex
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
