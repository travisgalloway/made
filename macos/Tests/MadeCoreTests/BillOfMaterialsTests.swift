import Testing
import Foundation
@testable import MadeCore

@Suite struct BillOfMaterialsTests {

    @Test func testBOMStructureDisplayNames() {
        #expect(BOMStructure.flat.rawValue == "flat")
        #expect(BOMStructure.hierarchical.rawValue == "hierarchical")
        #expect(BOMStructure.flat.displayName == "Flat")
        #expect(BOMStructure.hierarchical.displayName == "Hierarchical")
        #expect(BOMStructure.allCases == [.flat, .hierarchical])
    }

    @Test func testFlatBOMSingleComponent() {
        let instance = ComponentInstance(
            name: "Bracket",
            reference: .internalPart(name: "BracketPart"),
            metadata: [
                CustomPropertyKey.partNumber: "BRK-001",
                CustomPropertyKey.description: "Angle Bracket"
            ]
        )

        let bom = BillOfMaterials.generate(from: [instance], structure: .flat)
        #expect(bom.structure == .flat)
        #expect(bom.items.count == 1)

        let item = bom.items[0]
        #expect(item.itemNumber == "1")
        #expect(item.level == 1)
        #expect(item.name == "Bracket")
        #expect(item.partNumber == "BRK-001")
        #expect(item.description == "Angle Bracket")
        #expect(item.quantity == 1)
        #expect(item.isSubassembly == false)
    }

    @Test func testFlatBOMGroupsIdenticalPartNumbersAcrossTopLevel() {
        let inst1 = ComponentInstance(
            name: "Hex Bolt M6x20 Left",
            reference: .internalPart(name: "HexBolt"),
            metadata: [CustomPropertyKey.partNumber: "BLT-M6-20", CustomPropertyKey.vendor: "Acme Fasteners"]
        )
        let inst2 = ComponentInstance(
            name: "Hex Bolt M6x20 Right",
            reference: .internalPart(name: "HexBolt"),
            metadata: [CustomPropertyKey.partNumber: "BLT-M6-20", CustomPropertyKey.vendor: "Acme Fasteners"]
        )
        let inst3 = ComponentInstance(
            name: "Hex Nut M6",
            reference: .internalPart(name: "HexNut"),
            metadata: [CustomPropertyKey.partNumber: "NUT-M6-01", CustomPropertyKey.vendor: "Acme Fasteners"]
        )

        let bom = BillOfMaterials.generate(from: [inst1, inst2, inst3], structure: .flat)
        #expect(bom.items.count == 2)

        let boltItem = bom.items.first(where: { $0.partNumber == "BLT-M6-20" })
        #expect(boltItem != nil)
        #expect(boltItem?.quantity == 2)
        #expect(boltItem?.vendor == "Acme Fasteners")

        let nutItem = bom.items.first(where: { $0.partNumber == "NUT-M6-01" })
        #expect(nutItem != nil)
        #expect(nutItem?.quantity == 1)
    }

    @Test func testFlatBOMGroupsIdenticalPartsWithoutPartNumberByNameAndRef() {
        let bodyId = SolidId("body-pin")
        let inst1 = ComponentInstance(
            name: "Dowel Pin",
            reference: .internalPart(name: "Dowel", bodyId: bodyId)
        )
        let inst2 = ComponentInstance(
            name: "Dowel Pin",
            reference: .internalPart(name: "Dowel", bodyId: bodyId)
        )
        let inst3 = ComponentInstance(
            name: "Custom Dowel Pin",
            reference: .internalPart(name: "Dowel", bodyId: bodyId)
        )

        let bom = BillOfMaterials.generate(from: [inst1, inst2, inst3], structure: .flat)
        #expect(bom.items.count == 2)

        let groupedDowel = bom.items.first(where: { $0.name == "Dowel Pin" })
        #expect(groupedDowel?.quantity == 2)

        let distinctDowel = bom.items.first(where: { $0.name == "Custom Dowel Pin" })
        #expect(distinctDowel?.quantity == 1)
    }

    @Test func testFlatBOMExplodesNestedSubassembliesWithMultipliedQuantities() {
        // Subassembly: Wheel Assembly (contains 1 Rim and 5 Lug Nuts)
        let rim = ComponentInstance(
            name: "Rim 17in",
            reference: .internalPart(name: "Rim"),
            metadata: [CustomPropertyKey.partNumber: "RIM-17"]
        )
        let lugNut1 = ComponentInstance(
            name: "Lug Nut A",
            reference: .internalPart(name: "LugNut"),
            metadata: [CustomPropertyKey.partNumber: "LUG-01"]
        )
        let lugNut2 = ComponentInstance(
            name: "Lug Nut B",
            reference: .internalPart(name: "LugNut"),
            metadata: [CustomPropertyKey.partNumber: "LUG-01"]
        )
        let lugNut3 = ComponentInstance(
            name: "Lug Nut C",
            reference: .internalPart(name: "LugNut"),
            metadata: [CustomPropertyKey.partNumber: "LUG-01"]
        )
        let lugNut4 = ComponentInstance(
            name: "Lug Nut D",
            reference: .internalPart(name: "LugNut"),
            metadata: [CustomPropertyKey.partNumber: "LUG-01"]
        )
        let lugNut5 = ComponentInstance(
            name: "Lug Nut E",
            reference: .internalPart(name: "LugNut"),
            metadata: [CustomPropertyKey.partNumber: "LUG-01"]
        )

        let wheelSub1 = ComponentInstance(
            name: "Front Left Wheel",
            reference: .subassembly(name: "WheelSub"),
            childInstances: [rim, lugNut1, lugNut2, lugNut3, lugNut4, lugNut5]
        )
        let wheelSub2 = ComponentInstance(
            name: "Front Right Wheel",
            reference: .subassembly(name: "WheelSub"),
            childInstances: [rim, lugNut1, lugNut2, lugNut3, lugNut4, lugNut5]
        )

        // Chassis Assembly containing the 2 wheels plus a Chassis Frame
        let frame = ComponentInstance(
            name: "Chassis Frame",
            reference: .internalPart(name: "Frame"),
            metadata: [CustomPropertyKey.partNumber: "FRM-001"]
        )
        let carAssembly = ComponentInstance(
            name: "Car System",
            reference: .subassembly(name: "Car"),
            childInstances: [wheelSub1, wheelSub2, frame]
        )

        let bom = BillOfMaterials.generate(from: [carAssembly], structure: .flat)
        // Subassemblies are exploded, only leaf parts remain
        #expect(bom.items.count == 3) // Rim, Lug Nut, Frame

        let rimItem = bom.items.first(where: { $0.partNumber == "RIM-17" })
        #expect(rimItem?.quantity == 2)

        let lugItem = bom.items.first(where: { $0.partNumber == "LUG-01" })
        #expect(lugItem?.quantity == 10)

        let frameItem = bom.items.first(where: { $0.partNumber == "FRM-001" })
        #expect(frameItem?.quantity == 1)
    }

    @Test func testHierarchicalBOMPreservesLevelsAndItemNumbers() {
        let child1 = ComponentInstance(
            name: "Child Part A",
            reference: .internalPart(name: "PartA"),
            metadata: [CustomPropertyKey.partNumber: "PA-1"]
        )
        let child2 = ComponentInstance(
            name: "Child Part B",
            reference: .internalPart(name: "PartB"),
            metadata: [CustomPropertyKey.partNumber: "PB-1"]
        )
        let subassembly = ComponentInstance(
            name: "Subassembly 1",
            reference: .subassembly(name: "Sub1"),
            childInstances: [child1, child2]
        )
        let standalonePart = ComponentInstance(
            name: "Standalone Part",
            reference: .internalPart(name: "PartC"),
            metadata: [CustomPropertyKey.partNumber: "PC-1"]
        )

        let bom = BillOfMaterials.generate(from: [subassembly, standalonePart], structure: .hierarchical)
        #expect(bom.structure == .hierarchical)
        #expect(bom.items.count == 4)

        // Item 1: Subassembly 1
        #expect(bom.items[0].itemNumber == "1")
        #expect(bom.items[0].level == 1)
        #expect(bom.items[0].name == "Subassembly 1")
        #expect(bom.items[0].isSubassembly == true)

        // Item 1.1: Child Part A
        #expect(bom.items[1].itemNumber == "1.1")
        #expect(bom.items[1].level == 2)
        #expect(bom.items[1].name == "Child Part A")
        #expect(bom.items[1].partNumber == "PA-1")
        #expect(bom.items[1].isSubassembly == false)

        // Item 1.2: Child Part B
        #expect(bom.items[2].itemNumber == "1.2")
        #expect(bom.items[2].level == 2)
        #expect(bom.items[2].name == "Child Part B")
        #expect(bom.items[2].partNumber == "PB-1")
        #expect(bom.items[2].isSubassembly == false)

        // Item 2: Standalone Part
        #expect(bom.items[3].itemNumber == "2")
        #expect(bom.items[3].level == 1)
        #expect(bom.items[3].name == "Standalone Part")
        #expect(bom.items[3].partNumber == "PC-1")
        #expect(bom.items[3].isSubassembly == false)
    }

    @Test func testHierarchicalBOMDeeplyNestedSubassemblies() {
        let leaf = ComponentInstance(
            name: "Inner Leaf",
            reference: .internalPart(name: "Leaf"),
            metadata: [CustomPropertyKey.partNumber: "LEAF-99"]
        )
        let level3Sub = ComponentInstance(
            name: "Level 3 Sub",
            reference: .subassembly(name: "L3"),
            childInstances: [leaf]
        )
        let level2Sub = ComponentInstance(
            name: "Level 2 Sub",
            reference: .subassembly(name: "L2"),
            childInstances: [level3Sub]
        )
        let rootSub = ComponentInstance(
            name: "Root Sub",
            reference: .subassembly(name: "L1"),
            childInstances: [level2Sub]
        )

        let bom = BillOfMaterials.generate(from: [rootSub], structure: .hierarchical)
        #expect(bom.items.count == 4)

        #expect(bom.items[0].itemNumber == "1")
        #expect(bom.items[0].level == 1)

        #expect(bom.items[1].itemNumber == "1.1")
        #expect(bom.items[1].level == 2)

        #expect(bom.items[2].itemNumber == "1.1.1")
        #expect(bom.items[2].level == 3)

        #expect(bom.items[3].itemNumber == "1.1.1.1")
        #expect(bom.items[3].level == 4)
        #expect(bom.items[3].partNumber == "LEAF-99")
    }

    @Test func testBOMIncludesStandardPropertiesAndCustomMetadataColumns() {
        let instance = ComponentInstance(
            name: "Machined Bracket",
            reference: .internalPart(name: "Bracket"),
            metadata: [
                CustomPropertyKey.partNumber: "BRK-4000",
                CustomPropertyKey.description: "Heavy Duty Bracket",
                CustomPropertyKey.revision: "Rev C",
                CustomPropertyKey.vendor: "Titan Machining",
                "material": "6061-T6 Aluminum",
                "Coating": "Hard Anodize",
                "Weight": "450g"
            ]
        )

        let bom = BillOfMaterials.generate(from: [instance], structure: .flat)
        #expect(bom.items.count == 1)

        let item = bom.items[0]
        #expect(item.partNumber == "BRK-4000")
        #expect(item.description == "Heavy Duty Bracket")
        #expect(item.revision == "Rev C")
        #expect(item.vendor == "Titan Machining")
        #expect(item.material == "6061-T6 Aluminum")
        #expect(item.customProperties["Coating"] == "Hard Anodize")
        #expect(item.customProperties["Weight"] == "450g")

        // Standard properties should not be duplicated in customPropertyKeys
        #expect(bom.customPropertyKeys == ["Coating", "Weight"])

        let csv = bom.toCSV()
        #expect(csv.contains("Item,Name,Part Number,Description,Revision,Vendor,Material,Quantity,Coating,Weight\r\n"))
        #expect(csv.contains("1,Machined Bracket,BRK-4000,Heavy Duty Bracket,Rev C,Titan Machining,6061-T6 Aluminum,1,Hard Anodize,450g\r\n"))
    }

    @Test func testBOMDeterministicCustomPropertyColumnOrdering() {
        let instA = ComponentInstance(
            name: "Part A",
            reference: .internalPart(name: "A"),
            metadata: [
                CustomPropertyKey.partNumber: "P-A",
                "Zeta": "Last",
                "Alpha": "First"
            ]
        )
        let instB = ComponentInstance(
            name: "Part B",
            reference: .internalPart(name: "B"),
            metadata: [
                CustomPropertyKey.partNumber: "P-B",
                "Beta": "Middle"
            ]
        )

        let bom = BillOfMaterials.generate(from: [instA, instB], structure: .flat)
        #expect(bom.customPropertyKeys == ["Alpha", "Beta", "Zeta"])

        let csv = bom.toCSV()
        #expect(csv.contains("Item,Name,Part Number,Description,Revision,Vendor,Material,Quantity,Alpha,Beta,Zeta\r\n"))
        // Part A has empty Beta
        #expect(csv.contains("1,Part A,P-A,,,,,1,First,,Last\r\n"))
        // Part B has empty Alpha and Zeta
        #expect(csv.contains("2,Part B,P-B,,,,,1,,Middle,\r\n"))
    }

    @Test func testRFC4180CSVEscapingCommasQuotesNewlines() {
        #expect(BillOfMaterials.escapeCSVField("Plain text") == "Plain text")
        #expect(BillOfMaterials.escapeCSVField("Item, with comma") == "\"Item, with comma\"")
        #expect(BillOfMaterials.escapeCSVField("Text with \"quotes\"") == "\"Text with \"\"quotes\"\"\"")
        #expect(BillOfMaterials.escapeCSVField("Line 1\nLine 2") == "\"Line 1\nLine 2\"")
        #expect(BillOfMaterials.escapeCSVField("CRLF\r\nSplit") == "\"CRLF\r\nSplit\"")

        let instance = ComponentInstance(
            name: "Tricky, \"Component\"\nSpecial",
            reference: .internalPart(name: "SpecialPart"),
            metadata: [
                CustomPropertyKey.partNumber: "PN,100",
                CustomPropertyKey.description: "Contains \"quotes\" and, comma\nand newline"
            ]
        )

        let bom = BillOfMaterials.generate(from: [instance], structure: .flat)
        let csv = bom.toCSV()

        #expect(csv.contains("\"Tricky, \"\"Component\"\"\nSpecial\""))
        #expect(csv.contains("\"PN,100\""))
        #expect(csv.contains("\"Contains \"\"quotes\"\" and, comma\nand newline\""))
    }

    @Test func testRFC4180CSVEscapingUnicodeCharacters() {
        let instance = ComponentInstance(
            name: "Shaft ⌀ 25mm",
            reference: .internalPart(name: "Shaft"),
            metadata: [
                CustomPropertyKey.partNumber: "AX-Ø25",
                CustomPropertyKey.description: "Axe de précision — modèle déposé",
                "Spécification": "Tolérance H7 ±0.015"
            ]
        )

        let bom = BillOfMaterials.generate(from: [instance], structure: .flat)
        let csv = bom.toCSV()

        #expect(csv.contains("Shaft ⌀ 25mm"))
        #expect(csv.contains("AX-Ø25"))
        #expect(csv.contains("Axe de précision — modèle déposé"))
        #expect(csv.contains("Spécification"))
        #expect(csv.contains("Tolérance H7 ±0.015"))
    }

    @Test func testBOMExportCSVWritesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let exportURL = tempDir.appendingPathComponent("nested").appendingPathComponent("assembly-bom.csv")

        let instance = ComponentInstance(
            name: "Motor",
            reference: .internalPart(name: "MotorPart"),
            metadata: [
                CustomPropertyKey.partNumber: "MOT-100",
                CustomPropertyKey.vendor: "Maxon"
            ]
        )

        let bom = BillOfMaterials.generate(from: [instance], structure: .flat)
        try bom.exportCSV(to: exportURL)

        #expect(FileManager.default.fileExists(atPath: exportURL.path))
        let contents = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(contents.contains("MOT-100"))
        #expect(contents.contains("Maxon"))
        #expect(contents.hasSuffix("\r\n"))
    }

    @Test func testEmptyAssemblyBOMGeneration() {
        let bom = BillOfMaterials.generate(from: [], structure: .flat)
        #expect(bom.items.isEmpty)
        #expect(bom.customPropertyKeys.isEmpty)

        let csv = bom.toCSV()
        #expect(csv == "Item,Name,Part Number,Description,Revision,Vendor,Material,Quantity\r\n")

        let hierarchicalBOM = BillOfMaterials.generate(from: [], structure: .hierarchical)
        #expect(hierarchicalBOM.items.isEmpty)
        let hierarchicalCSV = hierarchicalBOM.toCSV()
        #expect(hierarchicalCSV == "Item,Level,Name,Part Number,Description,Revision,Vendor,Material,Quantity,Type\r\n")
    }
}
