import Foundation

/// General classification for engineering materials.
public enum MaterialCategory: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case metal
    case plastic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .metal:
            return "Metal"
        case .plastic:
            return "Plastic"
        }
    }
}

/// Bibliographic citation and standards reference for material property provenance.
public struct MaterialCitation: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var sourceName: String
    public var specification: String
    public var notes: String
    public var urlString: String?

    public init(
        id: String = UUID().uuidString,
        sourceName: String,
        specification: String,
        notes: String,
        urlString: String? = nil
    ) {
        self.id = id
        self.sourceName = sourceName
        self.specification = specification
        self.notes = notes
        self.urlString = urlString
    }
}

/// Engineering material carrying physical properties, appearance attributes, and standard citations.
public struct MaterialDefinition: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var name: String
    public var category: MaterialCategory
    public var description: String
    public var color: SIMD4<Float>
    public var citations: [MaterialCitation]

    // Mechanical properties
    public var density: DensityQuantity
    public var youngsModulus: StressQuantity
    public var poissonsRatio: DimensionlessQuantity
    public var yieldStrength: StressQuantity
    public var ultimateStrength: StressQuantity

    // Thermal properties
    public var thermalConductivity: ThermalConductivityQuantity
    public var thermalExpansion: ThermalExpansionQuantity
    public var specificHeat: SpecificHeatQuantity

    public init(
        id: String,
        name: String,
        category: MaterialCategory,
        description: String,
        color: SIMD4<Float>,
        citations: [MaterialCitation],
        density: DensityQuantity,
        youngsModulus: StressQuantity,
        poissonsRatio: DimensionlessQuantity,
        yieldStrength: StressQuantity,
        ultimateStrength: StressQuantity,
        thermalConductivity: ThermalConductivityQuantity,
        thermalExpansion: ThermalExpansionQuantity,
        specificHeat: SpecificHeatQuantity
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.color = color
        self.citations = citations
        self.density = density
        self.youngsModulus = youngsModulus
        self.poissonsRatio = poissonsRatio
        self.yieldStrength = yieldStrength
        self.ultimateStrength = ultimateStrength
        self.thermalConductivity = thermalConductivity
        self.thermalExpansion = thermalExpansion
        self.specificHeat = specificHeat
    }

    // Standardized engineering/SI accessors
    public var densityKgPerM3: Double {
        density.unit.toBaseSI(density.value)
    }

    public var youngsModulusGPa: Double {
        StressUnit.gigapascals.fromBaseSI(youngsModulus.unit.toBaseSI(youngsModulus.value))
    }

    public var poissonsRatioValue: Double {
        poissonsRatio.value
    }

    public var yieldStrengthMPa: Double {
        StressUnit.megapascals.fromBaseSI(yieldStrength.unit.toBaseSI(yieldStrength.value))
    }

    public var ultimateStrengthMPa: Double {
        StressUnit.megapascals.fromBaseSI(ultimateStrength.unit.toBaseSI(ultimateStrength.value))
    }

    public var thermalConductivityWPerMK: Double {
        thermalConductivity.unit.toBaseSI(thermalConductivity.value)
    }

    public var thermalExpansionPerK: Double {
        thermalExpansion.unit.toBaseSI(thermalExpansion.value)
    }

    public var specificHeatJPerKgK: Double {
        specificHeat.unit.toBaseSI(specificHeat.value)
    }

    /// Formatted text summary suitable for clipboard copy or documentation export.
    public func formattedSummary() -> String {
        var lines: [String] = []
        lines.append("Material: \(name)")
        lines.append("Category: \(category.displayName)")
        lines.append("Description: \(description)")
        lines.append("")
        lines.append("Mechanical Properties:")
        lines.append("  • Density: \(density.formattedValue)")
        lines.append("  • Young's Modulus: \(youngsModulus.formattedValue)")
        lines.append("  • Poisson's Ratio: \(poissonsRatio.formattedValue)")
        lines.append("  • Yield Strength: \(yieldStrength.formattedValue)")
        lines.append("  • Ultimate Tensile Strength: \(ultimateStrength.formattedValue)")
        lines.append("")
        lines.append("Thermal Properties:")
        lines.append("  • Thermal Conductivity: \(thermalConductivity.formattedValue)")
        lines.append("  • Thermal Expansion: \(thermalExpansion.formattedValue)")
        lines.append("  • Specific Heat Capacity: \(specificHeat.formattedValue)")
        if !citations.isEmpty {
            lines.append("")
            lines.append("Citations & Standards:")
            for citation in citations {
                var citeLine = "  • \(citation.sourceName) [\(citation.specification)]: \(citation.notes)"
                if let url = citation.urlString, !url.isEmpty {
                    citeLine += " (\(url))"
                }
                lines.append(citeLine)
            }
        }
        return lines.joined(separator: "\n")
    }
}
