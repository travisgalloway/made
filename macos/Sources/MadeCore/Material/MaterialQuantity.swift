import Foundation

/// Value-unit pair holding a numeric physical quantity with typed unit representation.
public struct MaterialQuantity<Unit: MaterialUnit>: Sendable, Equatable, Codable, CustomStringConvertible {
    public var value: Double
    public var unit: Unit

    public init(value: Double, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    /// Normalized value in base SI units.
    public var baseSIValue: Double {
        unit.toBaseSI(value)
    }

    /// Converts this quantity to the target unit.
    public func converted(to targetUnit: Unit) -> MaterialQuantity<Unit> {
        MaterialQuantity(value: unit.convert(value, to: targetUnit), unit: targetUnit)
    }

    /// Clean display string combining numeric value and unit symbol.
    public var formattedValue: String {
        let absVal = abs(value)
        let formattedNumber: String
        if absVal >= 1000 {
            formattedNumber = value.formatted(.number.precision(.fractionLength(0...2)))
        } else if absVal >= 10 {
            formattedNumber = value.formatted(.number.precision(.fractionLength(0...2)))
        } else if absVal == 0 {
            formattedNumber = "0"
        } else {
            formattedNumber = value.formatted(.number.precision(.fractionLength(0...3)))
        }

        if unit.symbol.isEmpty || unit.symbol == "—" {
            return formattedNumber
        }
        return "\(formattedNumber) \(unit.symbol)"
    }

    public var description: String {
        formattedValue
    }
}

public typealias DensityQuantity = MaterialQuantity<DensityUnit>
public typealias StressQuantity = MaterialQuantity<StressUnit>
public typealias DimensionlessQuantity = MaterialQuantity<DimensionlessUnit>
public typealias ThermalConductivityQuantity = MaterialQuantity<ThermalConductivityUnit>
public typealias ThermalExpansionQuantity = MaterialQuantity<ThermalExpansionUnit>
public typealias SpecificHeatQuantity = MaterialQuantity<SpecificHeatUnit>
