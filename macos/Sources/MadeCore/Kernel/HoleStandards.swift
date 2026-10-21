import Foundation

/// Types of holes supported by the Hole Wizard (BL-PRT-10).
public enum HoleType: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case simple = "simple"
    case counterbore = "counterbore"
    case countersink = "countersink"
    case tapped = "tapped"

    public var displayName: String {
        switch self {
        case .simple: return "Simple"
        case .counterbore: return "Counterbore"
        case .countersink: return "Countersink"
        case .tapped: return "Tapped"
        }
    }
}

/// Fastener hole standards supported by the Hole Wizard (BL-PRT-10).
public enum HoleStandard: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case isoMetric = "isoMetric"
    case unc = "unc"
    case unf = "unf"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .isoMetric: return "ISO Metric"
        case .unc: return "UNC"
        case .unf: return "UNF"
        case .custom: return "Custom"
        }
    }
}

/// Dimensional specifications for a standardized hole size.
public struct StandardHoleSize: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: String { designation }
    public var designation: String
    public var nominalDiameter: Double
    public var pitch: Double
    public var tapDrillDiameter: Double
    public var closeClearanceDiameter: Double
    public var normalClearanceDiameter: Double
    public var counterboreDiameter: Double
    public var counterboreDepth: Double
    public var countersinkDiameter: Double
    public var countersinkAngle: Double

    public init(
        designation: String,
        nominalDiameter: Double,
        pitch: Double,
        tapDrillDiameter: Double,
        closeClearanceDiameter: Double,
        normalClearanceDiameter: Double,
        counterboreDiameter: Double,
        counterboreDepth: Double,
        countersinkDiameter: Double,
        countersinkAngle: Double
    ) {
        self.designation = designation
        self.nominalDiameter = nominalDiameter
        self.pitch = pitch
        self.tapDrillDiameter = tapDrillDiameter
        self.closeClearanceDiameter = closeClearanceDiameter
        self.normalClearanceDiameter = normalClearanceDiameter
        self.counterboreDiameter = counterboreDiameter
        self.counterboreDepth = counterboreDepth
        self.countersinkDiameter = countersinkDiameter
        self.countersinkAngle = countersinkAngle
    }
}

/// Metadata describing thread details for tapped holes and drawing generation.
public struct ThreadMetadata: Sendable, Codable, Equatable, Hashable {
    public var designation: String
    public var pitch: Double
    public var threadDepth: Double
    public var threadClass: String
    public var isRightHand: Bool

    public init(
        designation: String,
        pitch: Double,
        threadDepth: Double,
        threadClass: String = "6H",
        isRightHand: Bool = true
    ) {
        self.designation = designation
        self.pitch = pitch
        self.threadDepth = threadDepth
        self.threadClass = threadClass
        self.isRightHand = isRightHand
    }
}

/// Standard lookup tables for fastener holes and tapped threads.
public enum HoleStandards {
    public static let isoMetricSizes: [StandardHoleSize] = [
        StandardHoleSize(designation: "M1.6", nominalDiameter: 1.6, pitch: 0.35, tapDrillDiameter: 1.25, closeClearanceDiameter: 1.7, normalClearanceDiameter: 1.8, counterboreDiameter: 3.0, counterboreDepth: 1.6, countersinkDiameter: 3.5, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M2", nominalDiameter: 2.0, pitch: 0.4, tapDrillDiameter: 1.6, closeClearanceDiameter: 2.2, normalClearanceDiameter: 2.4, counterboreDiameter: 3.8, counterboreDepth: 2.0, countersinkDiameter: 4.4, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M2.5", nominalDiameter: 2.5, pitch: 0.45, tapDrillDiameter: 2.05, closeClearanceDiameter: 2.7, normalClearanceDiameter: 2.9, counterboreDiameter: 4.5, counterboreDepth: 2.5, countersinkDiameter: 5.5, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M3", nominalDiameter: 3.0, pitch: 0.5, tapDrillDiameter: 2.5, closeClearanceDiameter: 3.2, normalClearanceDiameter: 3.4, counterboreDiameter: 5.5, counterboreDepth: 3.0, countersinkDiameter: 6.5, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M4", nominalDiameter: 4.0, pitch: 0.7, tapDrillDiameter: 3.3, closeClearanceDiameter: 4.3, normalClearanceDiameter: 4.5, counterboreDiameter: 7.0, counterboreDepth: 4.0, countersinkDiameter: 8.6, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M5", nominalDiameter: 5.0, pitch: 0.8, tapDrillDiameter: 4.2, closeClearanceDiameter: 5.3, normalClearanceDiameter: 5.5, counterboreDiameter: 8.5, counterboreDepth: 5.0, countersinkDiameter: 10.4, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M6", nominalDiameter: 6.0, pitch: 1.0, tapDrillDiameter: 5.0, closeClearanceDiameter: 6.4, normalClearanceDiameter: 6.6, counterboreDiameter: 10.0, counterboreDepth: 6.0, countersinkDiameter: 12.4, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M8", nominalDiameter: 8.0, pitch: 1.25, tapDrillDiameter: 6.8, closeClearanceDiameter: 8.4, normalClearanceDiameter: 9.0, counterboreDiameter: 13.0, counterboreDepth: 8.0, countersinkDiameter: 16.4, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M10", nominalDiameter: 10.0, pitch: 1.5, tapDrillDiameter: 8.5, closeClearanceDiameter: 10.5, normalClearanceDiameter: 11.0, counterboreDiameter: 16.0, counterboreDepth: 10.0, countersinkDiameter: 20.4, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M12", nominalDiameter: 12.0, pitch: 1.75, tapDrillDiameter: 10.2, closeClearanceDiameter: 13.0, normalClearanceDiameter: 13.5, counterboreDiameter: 18.0, counterboreDepth: 12.0, countersinkDiameter: 24.4, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M14", nominalDiameter: 14.0, pitch: 2.0, tapDrillDiameter: 12.0, closeClearanceDiameter: 15.0, normalClearanceDiameter: 15.5, counterboreDiameter: 21.0, counterboreDepth: 14.0, countersinkDiameter: 27.0, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M16", nominalDiameter: 16.0, pitch: 2.0, tapDrillDiameter: 14.0, closeClearanceDiameter: 17.0, normalClearanceDiameter: 17.5, counterboreDiameter: 24.0, counterboreDepth: 16.0, countersinkDiameter: 30.0, countersinkAngle: 90.0),
        StandardHoleSize(designation: "M20", nominalDiameter: 20.0, pitch: 2.5, tapDrillDiameter: 17.5, closeClearanceDiameter: 21.0, normalClearanceDiameter: 22.0, counterboreDiameter: 30.0, counterboreDepth: 20.0, countersinkDiameter: 36.0, countersinkAngle: 90.0)
    ]

    public static let uncSizes: [StandardHoleSize] = [
        StandardHoleSize(designation: "#2-56", nominalDiameter: 2.184, pitch: 0.4536, tapDrillDiameter: 1.85, closeClearanceDiameter: 2.39, normalClearanceDiameter: 2.57, counterboreDiameter: 4.2, counterboreDepth: 2.2, countersinkDiameter: 4.6, countersinkAngle: 82.0),
        StandardHoleSize(designation: "#4-40", nominalDiameter: 2.845, pitch: 0.635, tapDrillDiameter: 2.35, closeClearanceDiameter: 3.05, normalClearanceDiameter: 3.26, counterboreDiameter: 5.5, counterboreDepth: 2.9, countersinkDiameter: 5.8, countersinkAngle: 82.0),
        StandardHoleSize(designation: "#6-32", nominalDiameter: 3.505, pitch: 0.7938, tapDrillDiameter: 2.85, closeClearanceDiameter: 3.73, normalClearanceDiameter: 3.99, counterboreDiameter: 6.9, counterboreDepth: 3.5, countersinkDiameter: 7.1, countersinkAngle: 82.0),
        StandardHoleSize(designation: "#8-32", nominalDiameter: 4.166, pitch: 0.7938, tapDrillDiameter: 3.50, closeClearanceDiameter: 4.42, normalClearanceDiameter: 4.70, counterboreDiameter: 7.9, counterboreDepth: 4.2, countersinkDiameter: 8.4, countersinkAngle: 82.0),
        StandardHoleSize(designation: "#10-24", nominalDiameter: 4.826, pitch: 1.0583, tapDrillDiameter: 3.90, closeClearanceDiameter: 5.11, normalClearanceDiameter: 5.41, counterboreDiameter: 9.1, counterboreDepth: 4.9, countersinkDiameter: 9.8, countersinkAngle: 82.0),
        StandardHoleSize(designation: "1/4\"-20", nominalDiameter: 6.35, pitch: 1.27, tapDrillDiameter: 5.10, closeClearanceDiameter: 6.73, normalClearanceDiameter: 7.14, counterboreDiameter: 11.1, counterboreDepth: 6.4, countersinkDiameter: 12.7, countersinkAngle: 82.0),
        StandardHoleSize(designation: "5/16\"-18", nominalDiameter: 7.938, pitch: 1.411, tapDrillDiameter: 6.60, closeClearanceDiameter: 8.33, normalClearanceDiameter: 8.73, counterboreDiameter: 13.5, counterboreDepth: 8.0, countersinkDiameter: 15.8, countersinkAngle: 82.0),
        StandardHoleSize(designation: "3/8\"-16", nominalDiameter: 9.525, pitch: 1.5875, tapDrillDiameter: 8.00, closeClearanceDiameter: 9.93, normalClearanceDiameter: 10.32, counterboreDiameter: 15.9, counterboreDepth: 9.6, countersinkDiameter: 19.0, countersinkAngle: 82.0),
        StandardHoleSize(designation: "7/16\"-14", nominalDiameter: 11.112, pitch: 1.814, tapDrillDiameter: 9.40, closeClearanceDiameter: 11.51, normalClearanceDiameter: 11.91, counterboreDiameter: 18.3, counterboreDepth: 11.2, countersinkDiameter: 22.2, countersinkAngle: 82.0),
        StandardHoleSize(designation: "1/2\"-13", nominalDiameter: 12.7, pitch: 1.9538, tapDrillDiameter: 10.80, closeClearanceDiameter: 13.10, normalClearanceDiameter: 13.50, counterboreDiameter: 20.6, counterboreDepth: 12.7, countersinkDiameter: 25.4, countersinkAngle: 82.0)
    ]

    public static let unfSizes: [StandardHoleSize] = [
        StandardHoleSize(designation: "#10-32", nominalDiameter: 4.826, pitch: 0.7938, tapDrillDiameter: 4.10, closeClearanceDiameter: 5.11, normalClearanceDiameter: 5.41, counterboreDiameter: 9.1, counterboreDepth: 4.9, countersinkDiameter: 9.8, countersinkAngle: 82.0),
        StandardHoleSize(designation: "1/4\"-28", nominalDiameter: 6.35, pitch: 0.9071, tapDrillDiameter: 5.50, closeClearanceDiameter: 6.73, normalClearanceDiameter: 7.14, counterboreDiameter: 11.1, counterboreDepth: 6.4, countersinkDiameter: 12.7, countersinkAngle: 82.0),
        StandardHoleSize(designation: "5/16\"-24", nominalDiameter: 7.938, pitch: 1.0583, tapDrillDiameter: 6.90, closeClearanceDiameter: 8.33, normalClearanceDiameter: 8.73, counterboreDiameter: 13.5, counterboreDepth: 8.0, countersinkDiameter: 15.8, countersinkAngle: 82.0),
        StandardHoleSize(designation: "3/8\"-24", nominalDiameter: 9.525, pitch: 1.0583, tapDrillDiameter: 8.50, closeClearanceDiameter: 9.93, normalClearanceDiameter: 10.32, counterboreDiameter: 15.9, counterboreDepth: 9.6, countersinkDiameter: 19.0, countersinkAngle: 82.0),
        StandardHoleSize(designation: "7/16\"-20", nominalDiameter: 11.112, pitch: 1.27, tapDrillDiameter: 9.90, closeClearanceDiameter: 11.51, normalClearanceDiameter: 11.91, counterboreDiameter: 18.3, counterboreDepth: 11.2, countersinkDiameter: 22.2, countersinkAngle: 82.0),
        StandardHoleSize(designation: "1/2\"-20", nominalDiameter: 12.7, pitch: 1.27, tapDrillDiameter: 11.50, closeClearanceDiameter: 13.10, normalClearanceDiameter: 13.50, counterboreDiameter: 20.6, counterboreDepth: 12.7, countersinkDiameter: 25.4, countersinkAngle: 82.0)
    ]

    public static func sizes(for standard: HoleStandard) -> [StandardHoleSize] {
        switch standard {
        case .isoMetric: return isoMetricSizes
        case .unc: return uncSizes
        case .unf: return unfSizes
        case .custom: return []
        }
    }

    public static func lookup(standard: HoleStandard, designation: String) -> StandardHoleSize? {
        let allSizes = sizes(for: standard)
        if let exact = allSizes.first(where: { $0.designation.caseInsensitiveCompare(designation) == .orderedSame }) {
            return exact
        }
        if standard == .isoMetric {
            let base = designation.components(separatedBy: CharacterSet(charactersIn: "xX×")).first ?? designation
            return allSizes.first(where: { $0.designation.caseInsensitiveCompare(base) == .orderedSame })
        }
        return nil
    }

    public static func defaultThreadClass(for standard: HoleStandard) -> String {
        switch standard {
        case .isoMetric: return "6H"
        case .unc, .unf: return "2B"
        case .custom: return "6H"
        }
    }
}
