import Foundation

/// Compiled static catalog of standard engineering materials with cited mechanical and thermal properties.
public enum StandardMaterials {
    /// Structural Steel (S235 / ASTM A36)
    public static let structuralSteel = MaterialDefinition(
        id: "structural-steel-a36",
        name: "Structural Steel (A36 / S235)",
        category: .metal,
        description: "Standard low-carbon structural steel widely used in general construction, framing, and fabrication.",
        color: SIMD4<Float>(0.60, 0.62, 0.65, 1.0),
        citations: [
            MaterialCitation(
                id: "astm-a36",
                sourceName: "ASTM International",
                specification: "ASTM A36 / A36M-19",
                notes: "Standard Specification for Carbon Structural Steel",
                urlString: "https://www.astm.org/a0036_a0036m-19.html"
            ),
            MaterialCitation(
                id: "en-10025-2",
                sourceName: "European Standards",
                specification: "EN 10025-2:2019",
                notes: "Hot rolled products of structural steels - Part 2: Technical delivery conditions for non-alloy structural steels (Grade S235)",
                urlString: "https://www.en-standard.eu"
            )
        ],
        density: DensityQuantity(value: 7850, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 200, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.26, unit: .ratio),
        yieldStrength: StressQuantity(value: 250, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 400, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 50.0, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 12.0, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 480, unit: .joulesPerKilogramKelvin)
    )

    /// Stainless Steel 304 (AISI 304 / EN 1.4301)
    public static let stainlessSteel304 = MaterialDefinition(
        id: "stainless-steel-304",
        name: "Stainless Steel 304",
        category: .metal,
        description: "Austenitic chromium-nickel stainless steel with high corrosion resistance and formability.",
        color: SIMD4<Float>(0.75, 0.76, 0.78, 1.0),
        citations: [
            MaterialCitation(
                id: "astm-a240",
                sourceName: "ASTM International",
                specification: "ASTM A240 / A240M-20a",
                notes: "Standard Specification for Chromium and Chromium-Nickel Stainless Steel Plate, Sheet, and Strip",
                urlString: "https://www.astm.org/a0240_a0240m-20a.html"
            ),
            MaterialCitation(
                id: "asm-handbook",
                sourceName: "ASM Specialty Handbook",
                specification: "Stainless Steels (ASM International)",
                notes: "Austenitic Grade 304 / EN 1.4301 Room Temperature Properties",
                urlString: "https://www.asminternational.org"
            )
        ],
        density: DensityQuantity(value: 8000, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 193, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.29, unit: .ratio),
        yieldStrength: StressQuantity(value: 215, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 505, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 16.2, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 17.2, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 500, unit: .joulesPerKilogramKelvin)
    )

    /// Aluminum 6061-T6
    public static let aluminum6061T6 = MaterialDefinition(
        id: "aluminum-6061-t6",
        name: "Aluminum 6061-T6",
        category: .metal,
        description: "Precipitation-hardened structural aluminum alloy with magnesium and silicon, widely used in machined aerospace and robotic assemblies.",
        color: SIMD4<Float>(0.82, 0.84, 0.86, 1.0),
        citations: [
            MaterialCitation(
                id: "mmpds-6061",
                sourceName: "MMPDS-01",
                specification: "MMPDS-01 §3.2.6",
                notes: "Metallic Materials Properties Development and Standardization - 6061-T6 Sheet and Plate",
                urlString: "https://www.mmpds.org"
            ),
            MaterialCitation(
                id: "astm-b221",
                sourceName: "ASTM International",
                specification: "ASTM B221M-21",
                notes: "Standard Specification for Aluminum and Aluminum-Alloy Extruded Bars, Rods, Wire, Profiles, and Tubes",
                urlString: "https://www.astm.org/b0221_b0221m-21.html"
            )
        ],
        density: DensityQuantity(value: 2700, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 68.9, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.33, unit: .ratio),
        yieldStrength: StressQuantity(value: 276, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 310, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 167.0, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 23.6, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 896, unit: .joulesPerKilogramKelvin)
    )

    /// Aluminum 7075-T6
    public static let aluminum7075T6 = MaterialDefinition(
        id: "aluminum-7075-t6",
        name: "Aluminum 7075-T6",
        category: .metal,
        description: "High-strength zinc-alloyed aerospace aluminum providing superior yield strength for critical structural airframe components.",
        color: SIMD4<Float>(0.80, 0.81, 0.83, 1.0),
        citations: [
            MaterialCitation(
                id: "mmpds-7075",
                sourceName: "MMPDS-01",
                specification: "MMPDS-01 §3.7.4",
                notes: "Aerospace Structural Metallic Materials Handbooks - 7075-T6 Alloy",
                urlString: "https://www.mmpds.org"
            ),
            MaterialCitation(
                id: "astm-b209",
                sourceName: "ASTM International",
                specification: "ASTM B209M-14",
                notes: "Standard Specification for Aluminum and Aluminum-Alloy Sheet and Plate",
                urlString: "https://www.astm.org/b0209m-14.html"
            )
        ],
        density: DensityQuantity(value: 2810, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 71.7, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.33, unit: .ratio),
        yieldStrength: StressQuantity(value: 503, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 572, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 130.0, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 23.4, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 960, unit: .joulesPerKilogramKelvin)
    )

    /// Titanium Ti-6Al-4V (Grade 5)
    public static let titaniumTi6Al4V = MaterialDefinition(
        id: "titanium-ti-6al-4v",
        name: "Titanium Ti-6Al-4V (Grade 5)",
        category: .metal,
        description: "Alpha-beta titanium alloy combining high specific strength, fracture toughness, and superior corrosion resistance.",
        color: SIMD4<Float>(0.55, 0.56, 0.58, 1.0),
        citations: [
            MaterialCitation(
                id: "mmpds-ti64",
                sourceName: "MMPDS-01",
                specification: "MMPDS-01 §5.3.1",
                notes: "Grade 5 Annealed Titanium Alloy Sheet, Strip, and Plate",
                urlString: "https://www.mmpds.org"
            ),
            MaterialCitation(
                id: "astm-b265",
                sourceName: "ASTM International",
                specification: "ASTM B265-20",
                notes: "Standard Specification for Titanium and Titanium Alloy Strip, Sheet, and Plate (Grade 5)",
                urlString: "https://www.astm.org/b0265-20.html"
            )
        ],
        density: DensityQuantity(value: 4430, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 113.8, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.342, unit: .ratio),
        yieldStrength: StressQuantity(value: 880, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 950, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 6.7, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 8.6, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 526, unit: .joulesPerKilogramKelvin)
    )

    /// Free-Cutting Brass (C36000)
    public static let freeCuttingBrassC36000 = MaterialDefinition(
        id: "brass-c36000",
        name: "Free-Cutting Brass (C36000)",
        category: .metal,
        description: "Leaded copper-zinc brass benchmark alloy with exceptional machinability for high-speed turning and precision fasteners.",
        color: SIMD4<Float>(0.88, 0.72, 0.32, 1.0),
        citations: [
            MaterialCitation(
                id: "astm-b16",
                sourceName: "ASTM International",
                specification: "ASTM B16 / B16M-19",
                notes: "Standard Specification for Free-Cutting Brass Rod, Bar and Shapes for Use in Screw Machines",
                urlString: "https://www.astm.org/b0016_b0016m-19.html"
            ),
            MaterialCitation(
                id: "cda-c36000",
                sourceName: "Copper Development Association",
                specification: "CDA Alloy UNS C36000",
                notes: "High Speed Machinability Copper Alloy Standards",
                urlString: "https://www.copper.org"
            )
        ],
        density: DensityQuantity(value: 8490, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 97.0, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.31, unit: .ratio),
        yieldStrength: StressQuantity(value: 310, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 400, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 115.0, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 20.5, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 380, unit: .joulesPerKilogramKelvin)
    )

    /// PLA (Polylactic Acid)
    public static let pla = MaterialDefinition(
        id: "pla",
        name: "PLA (Polylactic Acid)",
        category: .plastic,
        description: "Biodegradable thermoplastic polyester derived from renewable resources, standard for rapid prototyping and additive manufacturing.",
        color: SIMD4<Float>(0.92, 0.90, 0.85, 1.0),
        citations: [
            MaterialCitation(
                id: "natureworks-ingeo",
                sourceName: "NatureWorks LLC",
                specification: "Ingeo Biopolymer Technical Data Sheet",
                notes: "Physical and Mechanical Test Values per ASTM D638 / ASTM D792",
                urlString: "https://www.natureworksllc.com"
            ),
            MaterialCitation(
                id: "astm-d638-pla",
                sourceName: "ASTM International",
                specification: "ASTM D638-14",
                notes: "Standard Test Method for Tensile Properties of Plastics",
                urlString: "https://www.astm.org/d0638-14.html"
            )
        ],
        density: DensityQuantity(value: 1240, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 3.5, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.36, unit: .ratio),
        yieldStrength: StressQuantity(value: 60, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 65, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 0.13, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 68.0, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 1800, unit: .joulesPerKilogramKelvin)
    )

    /// PETG (Polyethylene Terephthalate Glycol)
    public static let petg = MaterialDefinition(
        id: "petg",
        name: "PETG (Polyethylene Terephthalate Glycol)",
        category: .plastic,
        description: "Copolyester combining chemical resistance, impact toughness, and dimensional stability for functional enclosures.",
        color: SIMD4<Float>(0.70, 0.82, 0.88, 0.95),
        citations: [
            MaterialCitation(
                id: "eastman-spectar",
                sourceName: "Eastman Chemical Company",
                specification: "Eastman Spectar Copolyester Technical Datasheet",
                notes: "Tensile and flexural properties tested per ISO 527 and ASTM D638",
                urlString: "https://www.eastman.com"
            ),
            MaterialCitation(
                id: "iso-527-petg",
                sourceName: "International Organization for Standardization",
                specification: "ISO 527-2:2012",
                notes: "Plastics - Determination of tensile properties - Part 2: Test conditions for moulding and extrusion plastics",
                urlString: "https://www.iso.org/standard/56046.html"
            )
        ],
        density: DensityQuantity(value: 1270, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 2.1, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.38, unit: .ratio),
        yieldStrength: StressQuantity(value: 50, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 53, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 0.19, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 60.0, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 1200, unit: .joulesPerKilogramKelvin)
    )

    /// ABS (Acrylonitrile Butadiene Styrene)
    public static let abs = MaterialDefinition(
        id: "abs",
        name: "ABS (Acrylonitrile Butadiene Styrene)",
        category: .plastic,
        description: "Rigid engineering thermoplastic known for impact resistance, structural rigidity, and post-processing machinability.",
        color: SIMD4<Float>(0.80, 0.80, 0.78, 1.0),
        citations: [
            MaterialCitation(
                id: "sabic-cycolac",
                sourceName: "SABIC",
                specification: "Cycolac Resin MG47F Datasheet",
                notes: "Standard injection molding and extrusion ABS resin properties per ASTM D638",
                urlString: "https://www.sabic.com"
            ),
            MaterialCitation(
                id: "astm-d638-abs",
                sourceName: "ASTM International",
                specification: "ASTM D638-14",
                notes: "Standard Test Method for Tensile Properties of Rigid Thermoplastics",
                urlString: "https://www.astm.org/d0638-14.html"
            )
        ],
        density: DensityQuantity(value: 1040, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 2.3, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.35, unit: .ratio),
        yieldStrength: StressQuantity(value: 40, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 45, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 0.17, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 88.0, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 1400, unit: .joulesPerKilogramKelvin)
    )

    /// Nylon PA12 (Polyamide 12)
    public static let nylonPA12 = MaterialDefinition(
        id: "nylon-pa12",
        name: "Nylon PA12 (Polyamide 12)",
        category: .plastic,
        description: "Semi-crystalline polyamide with minimal moisture absorption, high fatigue endurance, and broad chemical resistance.",
        color: SIMD4<Float>(0.32, 0.33, 0.35, 1.0),
        citations: [
            MaterialCitation(
                id: "evonik-vestamid",
                sourceName: "Evonik Industries",
                specification: "VESTAMID L PA12 Engineering Datasheet",
                notes: "Extrusion and powder bed fusion polyamide properties per ISO 1874-1 / ISO 527",
                urlString: "https://corporate.evonik.com"
            ),
            MaterialCitation(
                id: "iso-1874",
                sourceName: "International Organization for Standardization",
                specification: "ISO 1874-1 / ISO 16396-PA12",
                notes: "Plastics - Polyamide (PA) moulding and extrusion materials",
                urlString: "https://www.iso.org"
            )
        ],
        density: DensityQuantity(value: 1010, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 1.4, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.40, unit: .ratio),
        yieldStrength: StressQuantity(value: 45, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 48, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 0.22, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 110.0, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 1700, unit: .joulesPerKilogramKelvin)
    )

    /// Polycarbonate (PC)
    public static let polycarbonate = MaterialDefinition(
        id: "polycarbonate",
        name: "Polycarbonate (PC)",
        category: .plastic,
        description: "Tough, optically clear amorphous thermoplastic possessing high heat deflection and impact resistance.",
        color: SIMD4<Float>(0.75, 0.80, 0.88, 0.95),
        citations: [
            MaterialCitation(
                id: "sabic-lexan",
                sourceName: "SABIC Innovative Plastics",
                specification: "Lexan Resin 101R Datasheet",
                notes: "General purpose high-impact polycarbonate properties per ISO 527 and ASTM D638",
                urlString: "https://www.sabic.com"
            ),
            MaterialCitation(
                id: "iso-527-pc",
                sourceName: "International Organization for Standardization",
                specification: "ISO 527-1:2019",
                notes: "Plastics - Determination of tensile properties",
                urlString: "https://www.iso.org"
            )
        ],
        density: DensityQuantity(value: 1200, unit: .kgPerCubicMeter),
        youngsModulus: StressQuantity(value: 2.38, unit: .gigapascals),
        poissonsRatio: DimensionlessQuantity(value: 0.37, unit: .ratio),
        yieldStrength: StressQuantity(value: 62, unit: .megapascals),
        ultimateStrength: StressQuantity(value: 70, unit: .megapascals),
        thermalConductivity: ThermalConductivityQuantity(value: 0.20, unit: .wattsPerMeterKelvin),
        thermalExpansion: ThermalExpansionQuantity(value: 65.0, unit: .microstrainPerKelvin),
        specificHeat: SpecificHeatQuantity(value: 1250, unit: .joulesPerKilogramKelvin)
    )

    /// Complete list of all 11 compiled standard engineering materials.
    public static let all: [MaterialDefinition] = [
        structuralSteel,
        stainlessSteel304,
        aluminum6061T6,
        aluminum7075T6,
        titaniumTi6Al4V,
        freeCuttingBrassC36000,
        pla,
        petg,
        abs,
        nylonPA12,
        polycarbonate
    ]
}
