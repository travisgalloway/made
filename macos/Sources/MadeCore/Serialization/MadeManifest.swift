import Foundation

/// Canonical manifest stored as `manifest.json` inside a `.made` package.
public struct MadeManifest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var appVersion: String
    public var units: UnitSettings
    public var tolerances: KernelTolerances

    public init(
        schemaVersion: Int = 1,
        appVersion: String = "0.1",
        units: UnitSettings = UnitSettings(),
        tolerances: KernelTolerances = KernelTolerances()
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.units = units
        self.tolerances = tolerances
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case appVersion
        case units
        case tolerances
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "0.1"
        self.units = try container.decodeIfPresent(UnitSettings.self, forKey: .units) ?? UnitSettings()
        self.tolerances = try container.decodeIfPresent(KernelTolerances.self, forKey: .tolerances) ?? KernelTolerances()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(units, forKey: .units)
        try container.encode(tolerances, forKey: .tolerances)
    }
}
