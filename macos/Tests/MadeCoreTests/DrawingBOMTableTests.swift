import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct DrawingBOMTableTests {

    @Test func testBOMTableCreationAndMetrics() {
        var table = DrawingBOMTable(
            name: "Main BOM",
            positionMM: SIMD2(15.0, 25.0),
            structure: .flat,
            columns: [.itemNumber, .name, .quantity],
            title: "PARTS LIST",
            showTitle: true,
            fontSizePt: 10.0,
            rowHeightMM: 8.0,
            customColumnWidths: ["name": 60.0]
        )

        #expect(table.name == "Main BOM")
        #expect(table.positionMM == SIMD2(15.0, 25.0))
        #expect(table.structure == .flat)
        #expect(table.title == "PARTS LIST")
        #expect(table.showTitle == true)
        #expect(table.fontSizePt == 10.0)
        #expect(table.rowHeightMM == 8.0)

        // Column widths
        #expect(table.width(for: .itemNumber) == DrawingBOMColumn.itemNumber.defaultWidthMM)
        #expect(table.width(for: .name) == 60.0) // custom override
        #expect(table.width(for: .quantity) == DrawingBOMColumn.quantity.defaultWidthMM)

        let expectedTotalWidth = DrawingBOMColumn.itemNumber.defaultWidthMM + 60.0 + DrawingBOMColumn.quantity.defaultWidthMM
        #expect(abs(table.totalWidthMM - expectedTotalWidth) < 1e-6)

        // Height: Title (8) + Header (8) + 3 rows (24) = 40 mm
        #expect(abs(table.totalHeightMM(rowCount: 3) - 40.0) < 1e-6)

        // Without title
        table.showTitle = false
        #expect(abs(table.totalHeightMM(rowCount: 3) - 32.0) < 1e-6)
    }

    @Test func testBOMColumnValueExtraction() {
        let item = BOMItem(
            itemNumber: "3",
            level: 1,
            name: "Hex Bolt",
            partNumber: "HB-M6-20",
            description: "M6x20 Grade 8.8",
            revision: "B",
            vendor: "Fastenal",
            material: "Steel 8.8",
            quantity: 4
        )

        #expect(DrawingBOMColumn.itemNumber.value(for: item) == "3")
        #expect(DrawingBOMColumn.name.value(for: item) == "Hex Bolt")
        #expect(DrawingBOMColumn.partNumber.value(for: item) == "HB-M6-20")
        #expect(DrawingBOMColumn.description.value(for: item) == "M6x20 Grade 8.8")
        #expect(DrawingBOMColumn.quantity.value(for: item) == "4")
        #expect(DrawingBOMColumn.revision.value(for: item) == "B")
        #expect(DrawingBOMColumn.vendor.value(for: item) == "Fastenal")
        #expect(DrawingBOMColumn.material.value(for: item) == "Steel 8.8")
    }

    @Test func testBOMTableWithEmptyDocumentDisplaysPlaceholder() {
        let doc = DocumentModel(documentType: .drawing, sheets: [DrawingSheet()])
        let table = DrawingBOMTable()
        let items = table.resolvedItems(from: doc)

        #expect(items.count == 1)
        #expect(items[0].name == "No components")
        #expect(items[0].quantity == 0)
        #expect(items[0].itemNumber == "1")
    }

    @Test func testBOMTableResolvesItemsFromComponents() {
        let comp1 = ComponentInstance(
            name: "Bracket",
            reference: .internalPart(name: "Bracket", bodyId: nil),
            metadata: [
                CustomPropertyKey.partNumber: "BRK-001",
                CustomPropertyKey.description: "Mounting Bracket"
            ]
        )
        let comp2 = ComponentInstance(
            name: "Bracket",
            reference: .internalPart(name: "Bracket", bodyId: nil),
            metadata: [
                CustomPropertyKey.partNumber: "BRK-001",
                CustomPropertyKey.description: "Mounting Bracket"
            ]
        )
        let comp3 = ComponentInstance(
            name: "Pin",
            reference: .internalPart(name: "Pin", bodyId: nil),
            metadata: [
                CustomPropertyKey.partNumber: "PIN-100"
            ]
        )

        let doc = DocumentModel(documentType: .assembly, componentInstances: [comp1, comp2, comp3], sheets: [DrawingSheet()])
        let table = DrawingBOMTable(structure: .flat)
        let items = table.resolvedItems(from: doc)

        #expect(items.count == 2)
        let brkItem = items.first(where: { $0.partNumber == "BRK-001" })
        #expect(brkItem?.quantity == 2)
        #expect(brkItem?.name == "Bracket")

        let pinItem = items.first(where: { $0.partNumber == "PIN-100" })
        #expect(pinItem?.quantity == 1)
        #expect(pinItem?.name == "Pin")
    }

    @Test func testBOMTableResolvesItemsFromMultiBodyObjects() {
        let obj1 = SceneObject(
            id: ObjectId("body-1"),
            name: "Lower Base",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            metadata: [CustomPropertyKey.partNumber: "BASE-01"]
        )
        let obj2 = SceneObject(
            id: ObjectId("body-2"),
            name: "Upper Cover",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            metadata: [CustomPropertyKey.partNumber: "COV-02"]
        )

        let doc = DocumentModel(documentType: .part, sheets: [DrawingSheet()])
        doc.reset(with: [obj1, obj2], documentType: .part, sheets: [DrawingSheet()])

        let table = DrawingBOMTable(structure: .flat)
        let items = table.resolvedItems(from: doc)

        #expect(items.count == 2)
        #expect(items[0].name == "Lower Base")
        #expect(items[0].partNumber == "BASE-01")
        #expect(items[1].name == "Upper Cover")
        #expect(items[1].partNumber == "COV-02")
    }

    @Test func testLegacySheetDecodingWithoutBOMTables() throws {
        // Legacy JSON format of DrawingSheet before bomTables was added
        let legacyJson = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy Sheet",
            "size": "isoA3",
            "orientation": "landscape",
            "scale": "1:1",
            "titleBlockTemplate": "isoStandard",
            "customProperties": {},
            "views": [],
            "annotations": []
        }
        """

        let data = Data(legacyJson.utf8)
        let decoded = try JSONDecoder().decode(DrawingSheet.self, from: data)

        #expect(decoded.name == "Legacy Sheet")
        #expect(decoded.bomTables.isEmpty)
    }

    @Test func testSheetBOMTableCodableRoundTrip() throws {
        var sheet = DrawingSheet(name: "Production Sheet")
        let table = DrawingBOMTable(
            name: "Assembly BOM",
            positionMM: SIMD2(30.0, 40.0),
            structure: .hierarchical,
            columns: [.itemNumber, .name, .quantity, .material],
            title: "BILL OF MATERIALS",
            showTitle: true,
            fontSizePt: 8.5,
            rowHeightMM: 6.5,
            customColumnWidths: ["material": 35.0]
        )
        sheet.bomTables = [table]

        let encoded = try JSONEncoder().encode(sheet)
        let decoded = try JSONDecoder().decode(DrawingSheet.self, from: encoded)

        #expect(decoded.bomTables.count == 1)
        let decodedTable = decoded.bomTables[0]
        #expect(decodedTable.id == table.id)
        #expect(decodedTable.name == "Assembly BOM")
        #expect(decodedTable.structure == .hierarchical)
        #expect(decodedTable.columns == [.itemNumber, .name, .quantity, .material])
        #expect(decodedTable.fontSizePt == 8.5)
        #expect(decodedTable.rowHeightMM == 6.5)
        #expect(decodedTable.width(for: .material) == 35.0)
    }

    @Test func testDocumentModelBOMTableUndoRedo() {
        let sheet = DrawingSheet(name: "Sheet 1")
        let doc = DocumentModel(documentType: .drawing, sheets: [sheet])
        #expect(doc.sheets.first?.bomTables.isEmpty == true)

        let table = DrawingBOMTable(
            name: "BOM 1",
            positionMM: SIMD2(10.0, 10.0),
            title: "ORIGINAL TITLE"
        )

        // 1. Add BOM table
        let added = doc.addDrawingBOMTable(table)
        #expect(added != nil)
        #expect(doc.sheets.first?.bomTables.count == 1)
        #expect(doc.selectedDrawingBOMTableId == table.id)

        // 2. Undo addition
        doc.undoManager?.undo()
        #expect(doc.sheets.first?.bomTables.isEmpty == true)
        #expect(doc.selectedDrawingBOMTableId == nil)

        // 3. Redo addition
        doc.undoManager?.redo()
        #expect(doc.sheets.first?.bomTables.count == 1)
        #expect(doc.selectedDrawingBOMTableId == table.id)

        // 4. Update BOM table
        var updated = table
        updated.title = "NEW TITLE"
        let updateResult = doc.updateDrawingBOMTable(updated)
        #expect(updateResult == true)
        #expect(doc.sheets.first?.bomTables.first?.title == "NEW TITLE")

        // 5. Undo update
        doc.undoManager?.undo()
        #expect(doc.sheets.first?.bomTables.first?.title == "ORIGINAL TITLE")

        // 6. Redo update
        doc.undoManager?.redo()
        #expect(doc.sheets.first?.bomTables.first?.title == "NEW TITLE")

        // 7. Remove BOM table
        let removeResult = doc.removeDrawingBOMTable(id: table.id)
        #expect(removeResult == true)
        #expect(doc.sheets.first?.bomTables.isEmpty == true)
        #expect(doc.selectedDrawingBOMTableId == nil)

        // 8. Undo removal
        doc.undoManager?.undo()
        #expect(doc.sheets.first?.bomTables.count == 1)
        #expect(doc.sheets.first?.bomTables.first?.title == "NEW TITLE")
    }
}
