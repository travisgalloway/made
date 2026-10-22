import Foundation

/// Protocol for physical units used in engineering materials.
public protocol MaterialUnit: Sendable, Equatable, Codable, CaseIterable, CustomStringConvertible {
    var symbol: String { get }
    var displayName: String { get }
    func toBaseSI(_ value: Double) -> Double
    func fromBaseSI(_ value: Double) -> Double
    func convert(_ value: Double, to targetUnit: Self) -> Double
}

extension MaterialUnit {
    public var description: String { symbol }

    public func convert(_ value: Double, to targetUnit: Self) -> Double {
        targetUnit.fromBaseSI(toBaseSI(value))
    }
}

/// Physical unit for mass density. Base SI unit is kilograms per cubic meter (kg/m³).
public enum DensityUnit: String, MaterialUnit {
    case kgPerCubicMeter = "kg/m³"
    case gramsPerCubicCentimeter = "g/cm³"
    case poundsPerCubicInch = "lb/in³"

    public var symbol: String { rawValue }

    public var displayName: String {
        switch self {
        case .kgPerCubicMeter:
            return "Kilograms per cubic meter"
        case .gramsPerCubicCentimeter:
            return "Grams per cubic centimeter"
        case .poundsPerCubicInch:
            return "Pounds per cubic inch"
        }
    }

    public func toBaseSI(_ value: Double) -> Double {
        switch self {
        case .kgPerCubicMeter:
            return value
        case .gramsPerCubicCentimeter:
            return value * 1_000.0
        case .poundsPerCubicInch:
            // 1 lb = 0.45359237 kg, 1 in³ = 1.6387064e-5 m³
            return value * (0.45359237 / 0.000016387064)
        }
    }

    public func fromBaseSI(_ value: Double) -> Double {
        switch self {
        case .kgPerCubicMeter:
            return value
        case .gramsPerCubicCentimeter:
            return value / 1_000.0
        case .poundsPerCubicInch:
            return value / (0.45359237 / 0.000016387064)
        }
    }
}

/// Physical unit for mechanical stress and elastic modulus. Base SI unit is pascals (Pa).
public enum StressUnit: String, MaterialUnit {
    case pascals = "Pa"
    case megapascals = "MPa"
    case gigapascals = "GPa"
    case poundsPerSquareInch = "psi"
    case kilopoundsPerSquareInch = "ksi"

    public var symbol: String { rawValue }

    public var displayName: String {
        switch self {
        case .pascals:
            return "Pascals"
        case .megapascals:
            return "Megapascals"
        case .gigapascals:
            return "Gigapascals"
        case .poundsPerSquareInch:
            return "Pounds per square inch"
        case .kilopoundsPerSquareInch:
            return "Kilopounds per square inch"
        }
    }

    public func toBaseSI(_ value: Double) -> Double {
        switch self {
        case .pascals:
            return value
        case .megapascals:
            return value * 1_000_000.0
        case .gigapascals:
            return value * 1_000_000_000.0
        case .poundsPerSquareInch:
            return value * 6_894.757293168361
        case .kilopoundsPerSquareInch:
            return value * 6_894_757.293168361
        }
    }

    public func fromBaseSI(_ value: Double) -> Double {
        switch self {
        case .pascals:
            return value
        case .megapascals:
            return value / 1_000_000.0
        case .gigapascals:
            return value / 1_000_000_000.0
        case .poundsPerSquareInch:
            return value / 6_894.757293168361
        case .kilopoundsPerSquareInch:
            return value / 6_894_757.293168361
        }
    }
}

/// Unit for dimensionless mechanical properties such as Poisson's ratio.
public enum DimensionlessUnit: String, MaterialUnit {
    case ratio = "—"

    public var symbol: String { rawValue }

    public var displayName: String {
        return "Ratio"
    }

    public func toBaseSI(_ value: Double) -> Double {
        value
    }

    public func fromBaseSI(_ value: Double) -> Double {
        value
    }
}

/// Physical unit for thermal conductivity. Base SI unit is watts per meter-kelvin (W/(m·K)).
public enum ThermalConductivityUnit: String, MaterialUnit {
    case wattsPerMeterKelvin = "W/(m·K)"
    case btuPerHourFootFahrenheit = "BTU/(hr·ft·°F)"

    public var symbol: String { rawValue }

    public var displayName: String {
        switch self {
        case .wattsPerMeterKelvin:
            return "Watts per meter-kelvin"
        case .btuPerHourFootFahrenheit:
            return "BTU per hour foot fahrenheit"
        }
    }

    public func toBaseSI(_ value: Double) -> Double {
        switch self {
        case .wattsPerMeterKelvin:
            return value
        case .btuPerHourFootFahrenheit:
            return value * 1.730735
        }
    }

    public func fromBaseSI(_ value: Double) -> Double {
        switch self {
        case .wattsPerMeterKelvin:
            return value
        case .btuPerHourFootFahrenheit:
            return value / 1.730735
        }
    }
}

/// Physical unit for coefficient of linear thermal expansion. Base SI unit is reciprocal kelvin (1/K).
public enum ThermalExpansionUnit: String, MaterialUnit {
    case microstrainPerKelvin = "10⁻⁶/K"
    case partsPerMillionPerKelvin = "ppm/K"
    case microinchesPerInchFahrenheit = "10⁻⁶/°F"

    public var symbol: String { rawValue }

    public var displayName: String {
        switch self {
        case .microstrainPerKelvin:
            return "Microstrain per kelvin"
        case .partsPerMillionPerKelvin:
            return "Parts per million per kelvin"
        case .microinchesPerInchFahrenheit:
            return "Microinches per inch fahrenheit"
        }
    }

    public func toBaseSI(_ value: Double) -> Double {
        switch self {
        case .microstrainPerKelvin, .partsPerMillionPerKelvin:
            return value * 1e-6
        case .microinchesPerInchFahrenheit:
            return (value / 1.8) * 1e-6
        }
    }

    public func fromBaseSI(_ value: Double) -> Double {
        switch self {
        case .microstrainPerKelvin, .partsPerMillionPerKelvin:
            return value * 1e6
        case .microinchesPerInchFahrenheit:
            return (value * 1e6) * 1.8
        }
    }
}

/// Physical unit for specific heat capacity. Base SI unit is joules per kilogram-kelvin (J/(kg·K)).
public enum SpecificHeatUnit: String, MaterialUnit {
    case joulesPerKilogramKelvin = "J/(kg·K)"
    case btuPerPoundFahrenheit = "BTU/(lb·°F)"

    public var symbol: String { rawValue }

    public var displayName: String {
        switch self {
        case .joulesPerKilogramKelvin:
            return "Joules per kilogram-kelvin"
        case .btuPerPoundFahrenheit:
            return "BTU per pound fahrenheit"
        }
    }

    public func toBaseSI(_ value: Double) -> Double {
        switch self {
        case .joulesPerKilogramKelvin:
            return value
        case .btuPerPoundFahrenheit:
            return value * 4_186.8
        }
    }

    public func fromBaseSI(_ value: Double) -> Double {
        switch self {
        case .joulesPerKilogramKelvin:
            return value
        case .btuPerPoundFahrenheit:
            return value / 4_186.8
        }
    }
}
