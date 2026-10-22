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
    public var selection: [Reference]?
    public var parameters: [DocumentParameter]?
    public var documentType: DocumentType?
    public var componentInstances: [ComponentInstance]?
    public var assemblyConstraints: [AssemblyConstraint]?
    public var componentPatterns: [ComponentPattern]?
    public var componentMirrors: [ComponentMirror]?

    public init(
        schemaVersion: Int = DocumentData.currentSchemaVersion,
        features: [Feature]? = nil,
        objects: [SceneObject]? = nil,
        selectedId: ObjectId? = nil,
        rollbackIndex: Int? = nil,
        bodies: [Body]? = nil,
        selection: [Reference]? = nil,
        parameters: [DocumentParameter]? = nil,
        documentType: DocumentType? = nil,
        componentInstances: [ComponentInstance]? = nil,
        assemblyConstraints: [AssemblyConstraint]? = nil,
        componentPatterns: [ComponentPattern]? = nil,
        componentMirrors: [ComponentMirror]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.rollbackIndex = rollbackIndex
        self.parameters = parameters
        self.documentType = documentType
        self.componentInstances = componentInstances
        self.assemblyConstraints = assemblyConstraints
        self.componentPatterns = componentPatterns
        self.componentMirrors = componentMirrors
        let projectedCompObjects: [SceneObject] = (componentInstances ?? []).flatMap { $0.toSceneObjects() }
        if let features {
            self.features = features
            let effectiveIndex = rollbackIndex ?? features.count
            let clampedIndex = max(0, min(effectiveIndex, features.count))
            let active = Array(features.prefix(clampedIndex)).compactMap { $0.toSceneObject() }
            self.objects = active + projectedCompObjects
            self.bodies = bodies ?? self.objects.map { Body(from: $0) }
        } else if let objects {
            let clamped = objects.map { obj in
                var copy = obj
                copy.def = DocumentLimits.clamp(obj.def)
                return copy
            }
            self.objects = clamped
            self.features = clamped.map { Feature(from: $0) }
            self.bodies = bodies ?? clamped.map { Body(from: $0) }
        } else {
            self.features = []
            self.objects = projectedCompObjects
            self.bodies = bodies ?? projectedCompObjects.map { Body(from: $0) }
        }
        self.selectedId = selectedId
        self.selection = selection
    }

    public init(schemaVersion: Int = DocumentData.currentSchemaVersion, objects: [SceneObject], selectedId: ObjectId? = nil, rollbackIndex: Int? = nil, bodies: [Body]? = nil, selection: [Reference]? = nil, parameters: [DocumentParameter]? = nil, documentType: DocumentType? = nil, componentInstances: [ComponentInstance]? = nil, assemblyConstraints: [AssemblyConstraint]? = nil, componentPatterns: [ComponentPattern]? = nil, componentMirrors: [ComponentMirror]? = nil) {
        self.init(schemaVersion: schemaVersion, features: nil, objects: objects, selectedId: selectedId, rollbackIndex: rollbackIndex, bodies: bodies, selection: selection, parameters: parameters, documentType: documentType, componentInstances: componentInstances, assemblyConstraints: assemblyConstraints, componentPatterns: componentPatterns, componentMirrors: componentMirrors)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case features
        case objects
        case selectedId
        case rollbackIndex
        case bodies
        case selection
        case parameters
        case documentType
        case componentInstances
        case assemblyConstraints
        case componentPatterns
        case componentMirrors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.rollbackIndex = try container.decodeIfPresent(Int.self, forKey: .rollbackIndex)
        self.documentType = try container.decodeIfPresent(DocumentType.self, forKey: .documentType)
        let decodedInstances = try container.decodeIfPresent([ComponentInstance].self, forKey: .componentInstances)
        self.componentInstances = decodedInstances
        let projectedCompObjects: [SceneObject] = (decodedInstances ?? []).flatMap { $0.toSceneObjects() }
        let decodedFeatures = try container.decodeIfPresent([Feature].self, forKey: .features)
        let rawObjects = try container.decodeIfPresent([SceneObject].self, forKey: .objects)
        let rawBodies = try container.decodeIfPresent([Body].self, forKey: .bodies)

        if let decodedFeatures {
            self.features = decodedFeatures
            let effectiveIndex = rollbackIndex ?? decodedFeatures.count
            let clampedIndex = max(0, min(effectiveIndex, decodedFeatures.count))
            let activeFeatures = Array(decodedFeatures.prefix(clampedIndex))
            let derivedObjects = activeFeatures.compactMap { $0.toSceneObject() } + projectedCompObjects
            let derivedBodies = derivedObjects.map { Body(from: $0) }

            if let rawObjects {
                let clampedRawObjects = rawObjects.map { obj in
                    var copy = obj
                    copy.def = DocumentLimits.clamp(obj.def)
                    return copy
                }
                guard Self.sceneObjectsMatch(clampedRawObjects, derivedObjects) else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: [CodingKeys.objects],
                            debugDescription: "Declared objects disagree with active features projection. Features is the single owner of document.json."
                        )
                    )
                }
            }
            self.objects = derivedObjects

            if let rawBodies {
                guard rawBodies == derivedBodies else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: [CodingKeys.bodies],
                            debugDescription: "Declared bodies disagree with active features projection. Features is the single owner of document.json."
                        )
                    )
                }
            }
            self.bodies = derivedBodies
        } else {
            let clampedRawObjects = (rawObjects ?? []).map { obj in
                var copy = obj
                copy.def = DocumentLimits.clamp(obj.def)
                return copy
            }
            if clampedRawObjects.isEmpty && !projectedCompObjects.isEmpty {
                self.objects = projectedCompObjects
                self.features = []
                self.bodies = rawBodies ?? projectedCompObjects.map { Body(from: $0) }
            } else {
                self.objects = clampedRawObjects
                self.features = clampedRawObjects.map { Feature(from: $0) }
                self.bodies = rawBodies ?? clampedRawObjects.map { Body(from: $0) }
            }
        }

        self.selectedId = try container.decodeIfPresent(ObjectId.self, forKey: .selectedId)
        self.selection = try container.decodeIfPresent([Reference].self, forKey: .selection)
        self.parameters = try container.decodeIfPresent([DocumentParameter].self, forKey: .parameters)
        self.assemblyConstraints = try container.decodeIfPresent([AssemblyConstraint].self, forKey: .assemblyConstraints)
        self.componentPatterns = try container.decodeIfPresent([ComponentPattern].self, forKey: .componentPatterns)
        self.componentMirrors = try container.decodeIfPresent([ComponentMirror].self, forKey: .componentMirrors)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(features, forKey: .features)
        if features == nil {
            try container.encode(objects, forKey: .objects)
            try container.encodeIfPresent(bodies, forKey: .bodies)
        }
        try container.encodeIfPresent(selectedId, forKey: .selectedId)
        try container.encodeIfPresent(rollbackIndex, forKey: .rollbackIndex)
        try container.encodeIfPresent(selection, forKey: .selection)
        try container.encodeIfPresent(parameters, forKey: .parameters)
        try container.encodeIfPresent(documentType, forKey: .documentType)
        try container.encodeIfPresent(componentInstances, forKey: .componentInstances)
        try container.encodeIfPresent(assemblyConstraints, forKey: .assemblyConstraints)
        try container.encodeIfPresent(componentPatterns, forKey: .componentPatterns)
        try container.encodeIfPresent(componentMirrors, forKey: .componentMirrors)
    }

    private static func sceneObjectsMatch(_ a: [SceneObject], _ b: [SceneObject]) -> Bool {
        guard a.count == b.count else { return false }
        for (objA, objB) in zip(a, b) {
            guard objA.id == objB.id,
                  objA.name == objB.name,
                  objA.transform == objB.transform,
                  objA.isVisible == objB.isVisible,
                  objA.isLocked == objB.isLocked,
                  objA.material == objB.material else {
                return false
            }
            switch (objA.def, objB.def) {
            case (.imported(let nA, let uA, let dA, let lA, let mA, let cA), .imported(let nB, let uB, let dB, let lB, let mB, let cB)):
                guard nA == nB, dA == dB, lA == lB, mA == mB, cA == cB else { return false }
                if let uA, let uB {
                    if uA != uB && uA.path != uB.path && uA.lastPathComponent != uB.lastPathComponent {
                        return false
                    }
                } else if (uA == nil) != (uB == nil) {
                    return false
                }
            case (.part(let uA, let sA), .part(let uB, let sB)):
                guard sA == sB else { return false }
                if uA != uB && uA.path != uB.path && uA.lastPathComponent != uB.lastPathComponent {
                    return false
                }
            default:
                guard objA.def == objB.def else { return false }
            }
        }
        return true
    }
}

extension CodingUserInfoKey {
    public static let packageURL = CodingUserInfoKey(rawValue: "packageURL")!
}

/// Canonical JSON encoder and decoder for `DocumentData` and `.made` packages.
public enum DocumentModelCoder {
    public static func makeJSONEncoder(packageURL: URL? = nil) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let packageURL {
            encoder.userInfo[.packageURL] = packageURL
        }
        return encoder
    }

    public static func makeJSONDecoder(packageURL: URL? = nil) -> JSONDecoder {
        let decoder = JSONDecoder()
        if let packageURL {
            decoder.userInfo[.packageURL] = packageURL
        }
        return decoder
    }

    /// Encodes `DocumentData` to canonical UTF-8 JSON with sorted keys, 2-space indentation, and a trailing newline.
    public static func encode(_ documentData: DocumentData, packageURL: URL? = nil) throws -> Data {
        let encoder = makeJSONEncoder(packageURL: packageURL)
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
    public static func decode(from data: Data, packageURL: URL? = nil) throws -> DocumentData {
        let decoder = makeJSONDecoder(packageURL: packageURL)
        return try decoder.decode(DocumentData.self, from: data)
    }

    /// Convenience encoder for `DocumentModel`.
    @MainActor
    public static func encode(document: DocumentModel, schemaVersion: Int = DocumentData.currentSchemaVersion, packageURL: URL? = nil) throws -> Data {
        let docData = DocumentData(
            schemaVersion: schemaVersion,
            features: document.features,
            objects: document.objects,
            selectedId: document.selectedId,
            rollbackIndex: document.rollbackIndex,
            bodies: document.bodies,
            selection: Array(document.selection).sorted { $0.id.uuidString < $1.id.uuidString },
            parameters: document.parameters,
            documentType: document.documentType,
            componentInstances: document.componentInstances,
            assemblyConstraints: document.assemblyConstraints,
            componentPatterns: document.componentPatterns,
            componentMirrors: document.componentMirrors
        )
        return try encode(docData, packageURL: packageURL)
    }

    /// Convenience decoder restoring into `DocumentModel`.
    @MainActor
    public static func decode(into document: DocumentModel, from data: Data, packageURL: URL? = nil) throws {
        let docData = try decode(from: data, packageURL: packageURL)
        let restoredSelection: Set<Reference>? = {
            if let sel = docData.selection {
                return Set(sel)
            } else if let selId = docData.selectedId {
                return [Reference.body(selId)]
            } else {
                return nil
            }
        }()
        let docType = docData.documentType ?? .part
        let instances = docData.componentInstances ?? []
        let constraints = docData.assemblyConstraints ?? []
        let patterns = docData.componentPatterns ?? []
        let mirrors = docData.componentMirrors ?? []
        if let features = docData.features {
            document.reset(
                with: features,
                selection: restoredSelection,
                selectedId: docData.selectedId,
                rollbackIndex: docData.rollbackIndex,
                parameters: docData.parameters ?? [],
                documentType: docType,
                componentInstances: instances,
                assemblyConstraints: constraints,
                componentPatterns: patterns,
                componentMirrors: mirrors
            )
        } else {
            document.reset(
                with: docData.objects,
                selection: restoredSelection,
                selectedId: docData.selectedId,
                rollbackIndex: docData.rollbackIndex,
                parameters: docData.parameters ?? [],
                documentType: docType,
                componentInstances: instances,
                assemblyConstraints: constraints,
                componentPatterns: patterns,
                componentMirrors: mirrors
            )
        }
    }
}
