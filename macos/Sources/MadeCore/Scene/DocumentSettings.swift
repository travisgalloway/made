import Foundation

/// Document-level settings governing units, kernel modeling tolerances, and default solid material (BL-FND-11).
public struct DocumentSettings: Codable, Sendable, Equatable {
    public var units: UnitSettings
    public var unitSettings: UnitSettings {
        get { units }
        set { units = newValue }
    }
    public var tolerances: KernelTolerances
    public var defaultMaterial: MaterialAttributes

    public init(
        units: UnitSettings = UnitSettings(),
        tolerances: KernelTolerances = KernelTolerances(),
        defaultMaterial: MaterialAttributes = MaterialAttributes()
    ) {
        self.units = units
        self.tolerances = tolerances.clamped()
        self.defaultMaterial = defaultMaterial
    }

    private enum CodingKeys: String, CodingKey {
        case units
        case tolerances
        case defaultMaterial
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.units = try container.decodeIfPresent(UnitSettings.self, forKey: .units) ?? UnitSettings()
        let decodedTolerances = try container.decodeIfPresent(KernelTolerances.self, forKey: .tolerances) ?? KernelTolerances()
        self.tolerances = decodedTolerances.clamped()
        self.defaultMaterial = try container.decodeIfPresent(MaterialAttributes.self, forKey: .defaultMaterial) ?? MaterialAttributes()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(units, forKey: .units)
        try container.encode(tolerances.clamped(), forKey: .tolerances)
        try container.encode(defaultMaterial, forKey: .defaultMaterial)
    }
}
