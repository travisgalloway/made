import Foundation

/// Canonical manifest stored as `manifest.json` inside a `.made` package.
public struct MadeManifest: Codable, Sendable, Equatable {
    public static let currentSchemaVersion: Int = 2
    public static let minimumSupportedSchemaVersion: Int = 1

    public var schemaVersion: Int
    public var appVersion: String
    public var units: UnitSettings
    public var tolerances: KernelTolerances
    public var defaultMaterial: MaterialAttributes
    public var documentType: DocumentType
    public var metadata: [String: String]

    public init(
        schemaVersion: Int = MadeManifest.currentSchemaVersion,
        appVersion: String = "0.1",
        units: UnitSettings = UnitSettings(),
        tolerances: KernelTolerances = KernelTolerances(),
        defaultMaterial: MaterialAttributes = MaterialAttributes(),
        documentType: DocumentType = .part,
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.units = units
        self.tolerances = tolerances.clamped()
        self.defaultMaterial = defaultMaterial
        self.documentType = documentType
        self.metadata = metadata
    }

    public init(
        schemaVersion: Int = MadeManifest.currentSchemaVersion,
        appVersion: String = "0.1",
        documentSettings: DocumentSettings,
        documentType: DocumentType = .part,
        metadata: [String: String] = [:]
    ) {
        self.init(
            schemaVersion: schemaVersion,
            appVersion: appVersion,
            units: documentSettings.units,
            tolerances: documentSettings.tolerances,
            defaultMaterial: documentSettings.defaultMaterial,
            documentType: documentType,
            metadata: metadata
        )
    }

    public var documentSettings: DocumentSettings {
        get {
            DocumentSettings(units: units, tolerances: tolerances, defaultMaterial: defaultMaterial)
        }
        set {
            units = newValue.units
            tolerances = newValue.tolerances
            defaultMaterial = newValue.defaultMaterial
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case appVersion
        case units
        case tolerances
        case defaultMaterial
        case documentType
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "0.1"
        self.units = try container.decodeIfPresent(UnitSettings.self, forKey: .units) ?? UnitSettings()
        let decodedTolerances = try container.decodeIfPresent(KernelTolerances.self, forKey: .tolerances) ?? KernelTolerances()
        self.tolerances = decodedTolerances.clamped()
        self.defaultMaterial = try container.decodeIfPresent(MaterialAttributes.self, forKey: .defaultMaterial) ?? MaterialAttributes()
        self.documentType = try container.decodeIfPresent(DocumentType.self, forKey: .documentType) ?? .part
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(units, forKey: .units)
        try container.encode(tolerances.clamped(), forKey: .tolerances)
        try container.encode(defaultMaterial, forKey: .defaultMaterial)
        try container.encode(documentType, forKey: .documentType)
        try container.encode(metadata, forKey: .metadata)
    }
}
