import Foundation

/// Canonical scene data representation stored as `document.json` inside a `.made` package.
public struct DocumentData: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var objects: [SceneObject]
    public var selectedId: ObjectId?

    public init(schemaVersion: Int = 1, objects: [SceneObject], selectedId: ObjectId? = nil) {
        self.schemaVersion = schemaVersion
        self.objects = objects.map { obj in
            var copy = obj
            copy.def = DocumentLimits.clamp(obj.def)
            return copy
        }
        self.selectedId = selectedId
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case objects
        case selectedId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let rawObjects = try container.decodeIfPresent([SceneObject].self, forKey: .objects) ?? []
        self.objects = rawObjects.map { obj in
            var copy = obj
            copy.def = DocumentLimits.clamp(obj.def)
            return copy
        }
        self.selectedId = try container.decodeIfPresent(ObjectId.self, forKey: .selectedId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(objects, forKey: .objects)
        try container.encodeIfPresent(selectedId, forKey: .selectedId)
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
        let docData = DocumentData(schemaVersion: schemaVersion, objects: document.objects, selectedId: document.selectedId)
        return try encode(docData)
    }

    /// Convenience decoder restoring into `DocumentModel`.
    @MainActor
    public static func decode(into document: DocumentModel, from data: Data) throws {
        let docData = try decode(from: data)
        document.reset(with: docData.objects, selectedId: docData.selectedId)
    }
}
