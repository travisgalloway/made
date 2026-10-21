import Foundation

/// Supported length units in the CAD scene.
public enum LengthUnit: String, CaseIterable, Identifiable, Sendable, Codable, Equatable {
    case millimeters = "mm"
    case centimeters = "cm"
    case meters = "m"
    case inches = "in"
    case feet = "ft"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .millimeters: return "Millimeters (mm)"
        case .centimeters: return "Centimeters (cm)"
        case .meters: return "Meters (m)"
        case .inches: return "Inches (in)"
        case .feet: return "Feet (ft)"
        }
    }

    public var symbol: String {
        rawValue
    }

    /// Converts a value in this unit to millimeters (the internal CAD scene unit).
    public func toMillimeters(_ value: Double) -> Double {
        switch self {
        case .millimeters: return value
        case .centimeters: return value * 10.0
        case .meters: return value * 1000.0
        case .inches: return value * 25.4
        case .feet: return value * 304.8
        }
    }

    /// Converts a value in millimeters (internal CAD scene unit) to this unit.
    public func fromMillimeters(_ value: Double) -> Double {
        switch self {
        case .millimeters: return value
        case .centimeters: return value / 10.0
        case .meters: return value / 1000.0
        case .inches: return value / 25.4
        case .feet: return value / 304.8
        }
    }

    /// Default increment for steppers and sliders in the UI.
    public var defaultStep: Double {
        switch self {
        case .millimeters: return 1.0
        case .centimeters: return 0.1
        case .meters: return 0.001
        case .inches: return 0.1
        case .feet: return 0.01
        }
    }
}

/// Supported angular units in the CAD scene.
public enum AngleUnit: String, CaseIterable, Identifiable, Sendable, Codable, Equatable {
    case degrees = "deg"
    case radians = "rad"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .degrees: return "Degrees (deg)"
        case .radians: return "Radians (rad)"
        }
    }

    public var symbol: String {
        rawValue
    }

    /// Converts a value in this unit to degrees.
    public func toDegrees(_ value: Double) -> Double {
        switch self {
        case .degrees: return value
        case .radians: return value * (180.0 / .pi)
        }
    }

    /// Converts a value in degrees to this unit.
    public func fromDegrees(_ value: Double) -> Double {
        switch self {
        case .degrees: return value
        case .radians: return value * (.pi / 180.0)
        }
    }

    /// Default increment for steppers and sliders in the UI.
    public var defaultStep: Double {
        switch self {
        case .degrees: return 1.0
        case .radians: return 0.1
        }
    }
}

/// Unit formatting and settings utilities.
public struct UnitSettings: Sendable, Codable, Equatable {
    public static let minDecimalPrecision: Int = 0
    public static let maxDecimalPrecision: Int = 6
    public static let defaultDecimalPrecision: Int = 2

    public var lengthUnit: LengthUnit
    public var angleUnit: AngleUnit
    public var decimalPrecision: Int

    public init(
        lengthUnit: LengthUnit = .millimeters,
        angleUnit: AngleUnit = .degrees,
        decimalPrecision: Int = Self.defaultDecimalPrecision
    ) {
        self.lengthUnit = lengthUnit
        self.angleUnit = angleUnit
        self.decimalPrecision = Self.clampPrecision(decimalPrecision)
    }

    public static func clampPrecision(_ precision: Int) -> Int {
        min(max(precision, minDecimalPrecision), maxDecimalPrecision)
    }

    public func formatLength(_ valueInMillimeters: Double, includeSymbol: Bool = true) -> String {
        Self.format(value: lengthUnit.fromMillimeters(valueInMillimeters), precision: decimalPrecision, symbol: includeSymbol ? lengthUnit.symbol : nil)
    }

    public func formatAngle(_ valueInDegrees: Double, includeSymbol: Bool = true) -> String {
        Self.format(value: angleUnit.fromDegrees(valueInDegrees), precision: decimalPrecision, symbol: includeSymbol ? angleUnit.symbol : nil)
    }

    public func formatArea(_ valueInSquareMillimeters: Double, includeSymbol: Bool = true) -> String {
        let factor = lengthUnit.fromMillimeters(1.0)
        let convertedArea = valueInSquareMillimeters * (factor * factor)
        return Self.format(value: convertedArea, precision: decimalPrecision, symbol: includeSymbol ? "\(lengthUnit.symbol)²" : nil)
    }

    public static func format(value: Double, precision: Int, symbol: String? = nil) -> String {
        let clamped = clampPrecision(precision)
        let formatted = String(format: "%.\(clamped)f", value)
        guard let symbol, !symbol.isEmpty else { return formatted }
        return "\(formatted) \(symbol)"
    }
}
