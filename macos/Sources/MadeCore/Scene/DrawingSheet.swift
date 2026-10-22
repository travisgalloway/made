import Foundation

/// Engineering standard classification for drawing sheets.
public enum DrawingStandard: String, Sendable, Codable, CaseIterable {
    case iso
    case ansi
    case custom

    public var displayName: String {
        switch self {
        case .iso:
            return "ISO"
        case .ansi:
            return "ANSI"
        case .custom:
            return "Custom"
        }
    }
}

/// Standard drawing sheet orientations.
public enum DrawingSheetOrientation: String, Sendable, Codable, CaseIterable {
    case landscape
    case portrait

    public var displayName: String {
        switch self {
        case .landscape:
            return "Landscape"
        case .portrait:
            return "Portrait"
        }
    }
}

/// Title block layout template styles.
public enum TitleBlockTemplate: String, Sendable, Codable, CaseIterable {
    case isoStandard
    case ansiStandard
    case minimal
    case none

    public var displayName: String {
        switch self {
        case .isoStandard:
            return "ISO Standard"
        case .ansiStandard:
            return "ANSI Standard"
        case .minimal:
            return "Minimal"
        case .none:
            return "None"
        }
    }
}

/// Standard sheet sizes for engineering drawings with millimeter dimensions (ISO, ANSI, and custom).
public enum DrawingSheetSize: Sendable, Codable, Equatable, Hashable {
    case isoA0
    case isoA1
    case isoA2
    case isoA3
    case isoA4
    case ansiA
    case ansiB
    case ansiC
    case ansiD
    case ansiE
    case custom(width: Double, height: Double)

    /// Minimum dimension allowed for custom sheet sizes in millimeters.
    public static let minimumCustomDimensionMM: Double = 50.0

    /// All pre-defined standard sheet sizes.
    public static let standardSizes: [DrawingSheetSize] = [
        .isoA0, .isoA1, .isoA2, .isoA3, .isoA4,
        .ansiA, .ansiB, .ansiC, .ansiD, .ansiE
    ]

    /// Standard classification of the sheet size.
    public var standard: DrawingStandard {
        switch self {
        case .isoA0, .isoA1, .isoA2, .isoA3, .isoA4:
            return .iso
        case .ansiA, .ansiB, .ansiC, .ansiD, .ansiE:
            return .ansi
        case .custom:
            return .custom
        }
    }

    /// User-facing display name.
    public var displayName: String {
        switch self {
        case .isoA0:
            return "ISO A0"
        case .isoA1:
            return "ISO A1"
        case .isoA2:
            return "ISO A2"
        case .isoA3:
            return "ISO A3"
        case .isoA4:
            return "ISO A4"
        case .ansiA:
            return "ANSI A (Letter)"
        case .ansiB:
            return "ANSI B (Tabloid)"
        case .ansiC:
            return "ANSI C"
        case .ansiD:
            return "ANSI D"
        case .ansiE:
            return "ANSI E"
        case .custom(let width, let height):
            let w = max(Self.minimumCustomDimensionMM, width)
            let h = max(Self.minimumCustomDimensionMM, height)
            return "Custom (\(Int(w))×\(Int(h)) mm)"
        }
    }

    /// Base un-oriented dimensions in millimeters (width: short edge, height: long edge).
    public var baseDimensions: (width: Double, height: Double) {
        switch self {
        case .isoA0:
            return (841.0, 1189.0)
        case .isoA1:
            return (594.0, 841.0)
        case .isoA2:
            return (420.0, 594.0)
        case .isoA3:
            return (297.0, 420.0)
        case .isoA4:
            return (210.0, 297.0)
        case .ansiA:
            return (215.9, 279.4)
        case .ansiB:
            return (279.4, 431.8)
        case .ansiC:
            return (431.8, 558.8)
        case .ansiD:
            return (558.8, 863.6)
        case .ansiE:
            return (863.6, 1117.6)
        case .custom(let width, let height):
            let w = max(Self.minimumCustomDimensionMM, width)
            let h = max(Self.minimumCustomDimensionMM, height)
            return (min(w, h), max(w, h))
        }
    }

    /// Orientation-adjusted dimensions in millimeters.
    public func dimensions(for orientation: DrawingSheetOrientation) -> (width: Double, height: Double) {
        let base = baseDimensions
        let shortSide = min(base.width, base.height)
        let longSide = max(base.width, base.height)
        switch orientation {
        case .landscape:
            return (width: longSide, height: shortSide)
        case .portrait:
            return (width: shortSide, height: longSide)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        // First try single-value string decoding (e.g. "isoA3", "ansiA")
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            switch stringValue {
            case "isoA0": self = .isoA0; return
            case "isoA1": self = .isoA1; return
            case "isoA2": self = .isoA2; return
            case "isoA3": self = .isoA3; return
            case "isoA4": self = .isoA4; return
            case "ansiA": self = .ansiA; return
            case "ansiB": self = .ansiB; return
            case "ansiC": self = .ansiC; return
            case "ansiD": self = .ansiD; return
            case "ansiE": self = .ansiE; return
            default:
                break
            }
        }

        // Keyed container decoding for custom and structured representations
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "isoA0": self = .isoA0
        case "isoA1": self = .isoA1
        case "isoA2": self = .isoA2
        case "isoA3": self = .isoA3
        case "isoA4": self = .isoA4
        case "ansiA": self = .ansiA
        case "ansiB": self = .ansiB
        case "ansiC": self = .ansiC
        case "ansiD": self = .ansiD
        case "ansiE": self = .ansiE
        case "custom":
            let width = try container.decode(Double.self, forKey: .width)
            let height = try container.decode(Double.self, forKey: .height)
            self = .custom(
                width: max(Self.minimumCustomDimensionMM, width),
                height: max(Self.minimumCustomDimensionMM, height)
            )
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown drawing sheet size type: \(type)"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .isoA0:
            var container = encoder.singleValueContainer()
            try container.encode("isoA0")
        case .isoA1:
            var container = encoder.singleValueContainer()
            try container.encode("isoA1")
        case .isoA2:
            var container = encoder.singleValueContainer()
            try container.encode("isoA2")
        case .isoA3:
            var container = encoder.singleValueContainer()
            try container.encode("isoA3")
        case .isoA4:
            var container = encoder.singleValueContainer()
            try container.encode("isoA4")
        case .ansiA:
            var container = encoder.singleValueContainer()
            try container.encode("ansiA")
        case .ansiB:
            var container = encoder.singleValueContainer()
            try container.encode("ansiB")
        case .ansiC:
            var container = encoder.singleValueContainer()
            try container.encode("ansiC")
        case .ansiD:
            var container = encoder.singleValueContainer()
            try container.encode("ansiD")
        case .ansiE:
            var container = encoder.singleValueContainer()
            try container.encode("ansiE")
        case .custom(let width, let height):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("custom", forKey: .type)
            try container.encode(max(Self.minimumCustomDimensionMM, width), forKey: .width)
            try container.encode(max(Self.minimumCustomDimensionMM, height), forKey: .height)
        }
    }
}

/// Represents an individual drawing sheet inside a drawing document.
public struct DrawingSheet: Identifiable, Sendable, Codable, Equatable {
    /// Points per millimeter at standard 72 DPI screen resolution (1 mm = 72 / 25.4 pt).
    public static let pointsPerMillimeter: Double = 72.0 / 25.4

    public var id: UUID
    public var name: String
    public var size: DrawingSheetSize
    public var orientation: DrawingSheetOrientation
    public var scale: String
    public var titleBlockTemplate: TitleBlockTemplate
    public var projectionAngle: DrawingProjectionAngle
    public var views: [DrawingView]
    public var customProperties: [String: String]

    public init(
        id: UUID = UUID(),
        name: String = "Sheet 1",
        size: DrawingSheetSize = .isoA3,
        orientation: DrawingSheetOrientation = .landscape,
        scale: String = "1:1",
        titleBlockTemplate: TitleBlockTemplate = .isoStandard,
        projectionAngle: DrawingProjectionAngle? = nil,
        views: [DrawingView] = [],
        customProperties: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.orientation = orientation
        self.scale = scale
        self.titleBlockTemplate = titleBlockTemplate
        self.projectionAngle = projectionAngle ?? (size.standard == .iso ? .firstAngle : .thirdAngle)
        self.views = views
        self.customProperties = customProperties
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case size
        case orientation
        case scale
        case titleBlockTemplate
        case customProperties
        case projectionAngle
        case views
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Sheet 1"
        let decodedSize = try container.decodeIfPresent(DrawingSheetSize.self, forKey: .size) ?? .isoA3
        self.size = decodedSize
        self.orientation = try container.decodeIfPresent(DrawingSheetOrientation.self, forKey: .orientation) ?? .landscape
        self.scale = try container.decodeIfPresent(String.self, forKey: .scale) ?? "1:1"
        self.titleBlockTemplate = try container.decodeIfPresent(TitleBlockTemplate.self, forKey: .titleBlockTemplate) ?? .isoStandard
        self.customProperties = try container.decodeIfPresent([String: String].self, forKey: .customProperties) ?? [:]
        self.projectionAngle = try container.decodeIfPresent(DrawingProjectionAngle.self, forKey: .projectionAngle) ?? (decodedSize.standard == .iso ? .firstAngle : .thirdAngle)
        self.views = try container.decodeIfPresent([DrawingView].self, forKey: .views) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(size, forKey: .size)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(scale, forKey: .scale)
        try container.encode(titleBlockTemplate, forKey: .titleBlockTemplate)
        try container.encode(customProperties, forKey: .customProperties)
        try container.encode(projectionAngle, forKey: .projectionAngle)
        try container.encode(views, forKey: .views)
    }

    /// Millimeter dimensions adjusted for the sheet orientation.
    public var dimensionsMM: (width: Double, height: Double) {
        size.dimensions(for: orientation)
    }

    /// Screen point dimensions at 72 DPI.
    public var dimensionsPoints: (width: Double, height: Double) {
        let mm = dimensionsMM
        return (width: mm.width * Self.pointsPerMillimeter, height: mm.height * Self.pointsPerMillimeter)
    }

    /// Retrieves a sheet custom property, trimming whitespace from the key.
    public func property(forKey key: String) -> String? {
        customProperties.property(forKey: key)
    }

    /// Sets or removes a sheet custom property, trimming whitespace and rejecting empty keys.
    public mutating func setProperty(key: String, value: String?) {
        customProperties = customProperties.settingProperty(key: key, value: value)
    }

    /// Resolves dynamic title block key-value pairs from document metadata and sheet properties.
    public func resolvedTitleBlockProperties(
        documentMetadata: [String: String] = [:],
        sheetIndex: Int = 1,
        totalSheets: Int = 1
    ) -> [String: String] {
        var properties: [String: String] = [:]

        // 1. Populate document metadata keys
        for (rawKey, value) in documentMetadata {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty {
                properties[key] = value
            }
        }

        // 2. Overlay sheet-specific custom properties
        for (rawKey, value) in customProperties {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty {
                properties[key] = value
            }
        }

        // 3. Document/Part Number fallback
        if properties[CustomPropertyKey.partNumber] == nil {
            if let drawingNum = properties["drawingNumber"], !drawingNum.isEmpty {
                properties[CustomPropertyKey.partNumber] = drawingNum
            } else {
                properties[CustomPropertyKey.partNumber] = "DRW-001"
            }
        }

        // 4. Description / Title fallback
        if properties[CustomPropertyKey.description] == nil {
            if let title = properties["title"], !title.isEmpty {
                properties[CustomPropertyKey.description] = title
            } else {
                properties[CustomPropertyKey.description] = name
            }
        }

        // Also ensure "title" is resolved
        if properties["title"] == nil {
            properties["title"] = properties[CustomPropertyKey.description] ?? name
        }

        // 5. Revision fallback
        if properties[CustomPropertyKey.revision] == nil {
            properties[CustomPropertyKey.revision] = "A"
        }

        // 6. Vendor fallback
        if properties[CustomPropertyKey.vendor] == nil {
            properties[CustomPropertyKey.vendor] = ""
        }

        // 7. Author fallback
        if properties["author"] == nil {
            properties["author"] = NSFullUserName()
        }

        // 8. Date fallback
        if properties["date"] == nil {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            properties["date"] = formatter.string(from: Date())
        }

        // 9. Sheet numbering & scale
        properties["scale"] = scale
        properties["sheet"] = "Sheet \(sheetIndex) of \(totalSheets)"
        properties["sheetNumber"] = "\(sheetIndex)"
        properties["sheetTotal"] = "\(totalSheets)"

        return properties
    }
}
