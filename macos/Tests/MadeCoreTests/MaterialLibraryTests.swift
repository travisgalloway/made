import Testing
import Foundation
@testable import MadeCore

@Suite struct MaterialLibraryTests {

    @Test func testStandardLibraryContainsAllRequiredMaterials() {
        let library = MaterialLibrary.standard
        #expect(library.materials.count == 11)

        let requiredIDs = [
            "structural-steel-a36",
            "stainless-steel-304",
            "aluminum-6061-t6",
            "aluminum-7075-t6",
            "titanium-ti-6al-4v",
            "brass-c36000",
            "pla",
            "petg",
            "abs",
            "nylon-pa12",
            "polycarbonate"
        ]

        for id in requiredIDs {
            let mat = library.material(withId: id)
            #expect(mat != nil, "Expected standard material with ID '\(id)'")
        }

        let metals = library.materials(in: .metal)
        let plastics = library.materials(in: .plastic)
        #expect(metals.count == 6)
        #expect(plastics.count == 5)
        #expect(metals.count + plastics.count == 11)
    }

    @Test func testMaterialPropertiesCarriedWithUnits() {
        for material in StandardMaterials.all {
            // Mechanical properties
            #expect(material.density.value > 0)
            #expect(material.density.unit == .kgPerCubicMeter)
            #expect(material.densityKgPerM3 > 0)
            #expect(material.density.formattedValue.contains("kg/m³"))

            #expect(material.youngsModulus.value > 0)
            #expect(material.youngsModulus.unit == .gigapascals)
            #expect(material.youngsModulusGPa > 0)
            #expect(material.youngsModulus.formattedValue.contains("GPa"))

            #expect(material.poissonsRatio.value > 0.1 && material.poissonsRatio.value < 0.5)
            #expect(material.poissonsRatio.unit == .ratio)
            #expect(material.poissonsRatioValue > 0.1 && material.poissonsRatioValue < 0.5)

            #expect(material.yieldStrength.value > 0)
            #expect(material.yieldStrength.unit == .megapascals)
            #expect(material.yieldStrengthMPa > 0)
            #expect(material.yieldStrength.formattedValue.contains("MPa"))

            #expect(material.ultimateStrength.value >= material.yieldStrength.value)
            #expect(material.ultimateStrength.unit == .megapascals)
            #expect(material.ultimateStrengthMPa >= material.yieldStrengthMPa)
            #expect(material.ultimateStrength.formattedValue.contains("MPa"))

            // Thermal properties
            #expect(material.thermalConductivity.value > 0)
            #expect(material.thermalConductivity.unit == .wattsPerMeterKelvin)
            #expect(material.thermalConductivityWPerMK > 0)
            #expect(material.thermalConductivity.formattedValue.contains("W/(m·K)"))

            #expect(material.thermalExpansion.value > 0)
            #expect(material.thermalExpansion.unit == .microstrainPerKelvin)
            #expect(material.thermalExpansionPerK > 0)
            #expect(material.thermalExpansion.formattedValue.contains("10⁻⁶/K"))

            #expect(material.specificHeat.value > 0)
            #expect(material.specificHeat.unit == .joulesPerKilogramKelvin)
            #expect(material.specificHeatJPerKgK > 0)
            #expect(material.specificHeat.formattedValue.contains("J/(kg·K)"))
        }
    }

    @Test func testMaterialCitationsAreAuthoritativeAndNonEmpty() {
        for material in StandardMaterials.all {
            #expect(!material.citations.isEmpty, "Material \(material.name) missing citations")
            for citation in material.citations {
                #expect(!citation.sourceName.isEmpty)
                #expect(!citation.specification.isEmpty)
                #expect(!citation.notes.isEmpty)
                if let urlString = citation.urlString {
                    #expect(!urlString.isEmpty)
                    #expect(urlString.starts(with: "https://") || urlString.starts(with: "http://"))
                }
            }
        }

        let a36 = StandardMaterials.structuralSteel
        #expect(a36.citations.contains { $0.specification.contains("ASTM A36") })

        let al6061 = StandardMaterials.aluminum6061T6
        #expect(al6061.citations.contains { $0.sourceName.contains("MMPDS") })

        let pla = StandardMaterials.pla
        #expect(pla.citations.contains { $0.sourceName.contains("NatureWorks") })
    }

    @Test func testMaterialUnitConversions() {
        // Density conversions
        let densitySI = DensityUnit.kgPerCubicMeter.toBaseSI(2700)
        #expect(densitySI == 2700)
        let densityFromGrams = DensityUnit.gramsPerCubicCentimeter.toBaseSI(2.7)
        #expect(abs(densityFromGrams - 2700) < 1e-4)
        let densityInGrams = DensityUnit.gramsPerCubicCentimeter.fromBaseSI(2700)
        #expect(abs(densityInGrams - 2.7) < 1e-4)

        // Stress conversions
        let gpaInPa = StressUnit.gigapascals.toBaseSI(200)
        #expect(gpaInPa == 200_000_000_000)
        let gpaFromPa = StressUnit.gigapascals.fromBaseSI(200_000_000_000)
        #expect(gpaFromPa == 200)

        let mpaInPa = StressUnit.megapascals.toBaseSI(250)
        #expect(mpaInPa == 250_000_000)
        let mpaFromPa = StressUnit.megapascals.fromBaseSI(250_000_000)
        #expect(mpaFromPa == 250)

        let psiInPa = StressUnit.poundsPerSquareInch.toBaseSI(1)
        #expect(abs(psiInPa - 6894.757) < 0.01)
        let ksiInPa = StressUnit.kilopoundsPerSquareInch.toBaseSI(1)
        #expect(abs(ksiInPa - 6894757.29) < 0.1)

        // Thermal conductivity conversions
        let tcSI = ThermalConductivityUnit.wattsPerMeterKelvin.toBaseSI(50)
        #expect(tcSI == 50)
        let tcFromBtu = ThermalConductivityUnit.btuPerHourFootFahrenheit.toBaseSI(1)
        #expect(abs(tcFromBtu - 1.730735) < 1e-5)

        // Thermal expansion conversions
        let teSI = ThermalExpansionUnit.microstrainPerKelvin.toBaseSI(23.6)
        #expect(abs(teSI - 23.6e-6) < 1e-11)
        let teMicrostrain = ThermalExpansionUnit.microstrainPerKelvin.fromBaseSI(23.6e-6)
        #expect(abs(teMicrostrain - 23.6) < 1e-9)

        // Specific heat conversions
        let cpSI = SpecificHeatUnit.joulesPerKilogramKelvin.toBaseSI(480)
        #expect(cpSI == 480)
        let cpFromBtu = SpecificHeatUnit.btuPerPoundFahrenheit.toBaseSI(1)
        #expect(abs(cpFromBtu - 4186.8) < 1e-4)
    }

    @Test func testMaterialLibraryFilteringAndLookup() {
        let library = MaterialLibrary.standard

        // ID Lookup
        let steel = library.material(withId: "structural-steel-a36")
        #expect(steel?.name == "Structural Steel (A36 / S235)")
        #expect(library.material(withId: "unknown-id") == nil)

        // Category filtering
        let metals = library.materials(in: .metal)
        #expect(metals.count == 6)
        for m in metals {
            #expect(m.category == .metal)
        }

        let plastics = library.materials(in: .plastic)
        #expect(plastics.count == 5)
        for p in plastics {
            #expect(p.category == .plastic)
        }

        // Query filtering
        let aluminumResults = library.filter(query: "aluminum")
        #expect(aluminumResults.count == 2)

        let a36Results = library.filter(query: "ASTM A36")
        #expect(a36Results.count == 1)
        #expect(a36Results.first?.id == "structural-steel-a36")

        let emptyResults = library.filter(query: "unobtainium")
        #expect(emptyResults.isEmpty)

        // Query + category combined filtering
        let filteredPlastics = library.filter(category: .plastic, query: "nylon")
        #expect(filteredPlastics.count == 1)
        #expect(filteredPlastics.first?.id == "nylon-pa12")

        let metalQueryOnPlastics = library.filter(category: .plastic, query: "steel")
        #expect(metalQueryOnPlastics.isEmpty)
    }

    @Test func testMaterialDefinitionCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for material in StandardMaterials.all {
            let data = try encoder.encode(material)
            let decoded = try decoder.decode(MaterialDefinition.self, from: data)
            #expect(decoded == material)
        }

        let libraryData = try encoder.encode(MaterialLibrary.standard)
        let decodedLibrary = try decoder.decode(MaterialLibrary.self, from: libraryData)
        #expect(decodedLibrary == MaterialLibrary.standard)
    }

    @Test func testFormattedSummaryContainsAllPropertiesAndCitations() {
        let mat = StandardMaterials.aluminum6061T6
        let summary = mat.formattedSummary()

        #expect(summary.contains("Aluminum 6061-T6"))
        #expect(summary.contains("Metal"))
        #expect(summary.contains("Density: 2,700 kg/m³") || summary.contains("Density: 2700 kg/m³"))
        #expect(summary.contains("Young's Modulus: 68.9 GPa"))
        #expect(summary.contains("Poisson's Ratio: 0.33"))
        #expect(summary.contains("Yield Strength: 276 MPa"))
        #expect(summary.contains("Ultimate Tensile Strength: 310 MPa"))
        #expect(summary.contains("Thermal Conductivity: 167 W/(m·K)") || summary.contains("167.0 W/(m·K)"))
        #expect(summary.contains("Thermal Expansion: 23.6 10⁻⁶/K"))
        #expect(summary.contains("Specific Heat Capacity: 896 J/(kg·K)"))
        #expect(summary.contains("MMPDS-01"))
        #expect(summary.contains("ASTM B221"))
    }
}
