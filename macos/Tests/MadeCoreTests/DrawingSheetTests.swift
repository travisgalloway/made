import Testing
import Foundation
@testable import MadeCore

@Suite @MainActor struct DrawingSheetTests {

    // MARK: - DocumentType Tests

    @Test func testDocumentTypeDrawingCase() {
        #expect(DocumentType.drawing.rawValue == "drawing")
        #expect(DocumentType.drawing.displayName == "Drawing")
        #expect(DocumentType.allCases.contains(.drawing))
    }

    // MARK: - Sheet Size and Dimension Tests

    @Test func testStandardSheetSizesDimensions() {
        // ISO A series dimensions
        #expect(DrawingSheetSize.isoA0.baseDimensions.width == 841.0)
        #expect(DrawingSheetSize.isoA0.baseDimensions.height == 1189.0)
        #expect(DrawingSheetSize.isoA0.standard == .iso)

        #expect(DrawingSheetSize.isoA1.baseDimensions.width == 594.0)
        #expect(DrawingSheetSize.isoA1.baseDimensions.height == 841.0)

        #expect(DrawingSheetSize.isoA2.baseDimensions.width == 420.0)
        #expect(DrawingSheetSize.isoA2.baseDimensions.height == 594.0)

        #expect(DrawingSheetSize.isoA3.baseDimensions.width == 297.0)
        #expect(DrawingSheetSize.isoA3.baseDimensions.height == 420.0)

        #expect(DrawingSheetSize.isoA4.baseDimensions.width == 210.0)
        #expect(DrawingSheetSize.isoA4.baseDimensions.height == 297.0)

        // ANSI series dimensions
        #expect(DrawingSheetSize.ansiA.baseDimensions.width == 215.9)
        #expect(DrawingSheetSize.ansiA.baseDimensions.height == 279.4)
        #expect(DrawingSheetSize.ansiA.standard == .ansi)

        #expect(DrawingSheetSize.ansiB.baseDimensions.width == 279.4)
        #expect(DrawingSheetSize.ansiB.baseDimensions.height == 431.8)

        #expect(DrawingSheetSize.ansiC.baseDimensions.width == 431.8)
        #expect(DrawingSheetSize.ansiC.baseDimensions.height == 558.8)

        #expect(DrawingSheetSize.ansiD.baseDimensions.width == 558.8)
        #expect(DrawingSheetSize.ansiD.baseDimensions.height == 863.6)

        #expect(DrawingSheetSize.ansiE.baseDimensions.width == 863.6)
        #expect(DrawingSheetSize.ansiE.baseDimensions.height == 1117.6)
    }

    @Test func testCustomSheetSizeAndMinimumBound() {
        let validCustom = DrawingSheetSize.custom(width: 500, height: 350)
        #expect(validCustom.standard == .custom)
        #expect(validCustom.baseDimensions.width == 350)
        #expect(validCustom.baseDimensions.height == 500)

        // Minimum clamp: values below 50mm must be clamped to 50mm
        let clampedCustom = DrawingSheetSize.custom(width: 20, height: 10)
        #expect(clampedCustom.baseDimensions.width >= DrawingSheetSize.minimumCustomDimensionMM)
        #expect(clampedCustom.baseDimensions.height >= DrawingSheetSize.minimumCustomDimensionMM)
        #expect(clampedCustom.baseDimensions == (50.0, 50.0))
    }

    @Test func testSheetOrientationCalculations() {
        let a3 = DrawingSheetSize.isoA3
        let landscape = a3.dimensions(for: .landscape)
        #expect(landscape.width == 420.0)
        #expect(landscape.height == 297.0)

        let portrait = a3.dimensions(for: .portrait)
        #expect(portrait.width == 297.0)
        #expect(portrait.height == 420.0)

        let sheet = DrawingSheet(name: "A3 Sheet", size: .isoA3, orientation: .landscape)
        #expect(sheet.dimensionsMM.width == 420.0)
        #expect(sheet.dimensionsMM.height == 297.0)
        #expect(sheet.dimensionsPoints.width > 0)
        #expect(sheet.dimensionsPoints.height > 0)
    }

    // MARK: - Title Block and Property Resolution Tests

    @Test func testTitleBlockPropertyResolution() {
        var sheet = DrawingSheet(name: "Detail Sheet", size: .isoA3, orientation: .landscape, scale: "1:2")
        sheet.setProperty(key: "author", value: "Lead Engineer")
        sheet.setProperty(key: "notes", value: "Tolerances ±0.1mm")

        let docMetadata: [String: String] = [
            CustomPropertyKey.partNumber: "MD-900",
            CustomPropertyKey.description: "Shaft Mount Bracket",
            CustomPropertyKey.revision: "C",
            CustomPropertyKey.vendor: "Acme Industrial"
        ]

        let props = sheet.resolvedTitleBlockProperties(
            documentMetadata: docMetadata,
            sheetIndex: 2,
            totalSheets: 5
        )

        #expect(props[CustomPropertyKey.partNumber] == "MD-900")
        #expect(props[CustomPropertyKey.description] == "Shaft Mount Bracket")
        #expect(props[CustomPropertyKey.revision] == "C")
        #expect(props[CustomPropertyKey.vendor] == "Acme Industrial")
        #expect(props["author"] == "Lead Engineer")
        #expect(props["scale"] == "1:2")
        #expect(props["sheet"] == "Sheet 2 of 5")
        #expect(props["sheetNumber"] == "2")
        #expect(props["sheetTotal"] == "5")
        #expect(props["notes"] == "Tolerances ±0.1mm")
    }

    @Test func testEmptyAndWhitespacePropertyKeysRejected() {
        var sheet = DrawingSheet()
        sheet.setProperty(key: "", value: "Invalid")
        sheet.setProperty(key: "   \t\n  ", value: "Invalid")
        #expect(sheet.customProperties.isEmpty)

        sheet.setProperty(key: "  trimmedKey  ", value: "ValidValue")
        #expect(sheet.property(forKey: "trimmedKey") == "ValidValue")
        #expect(sheet.property(forKey: "  trimmedKey  ") == "ValidValue")
    }

    // MARK: - DocumentModel Sheet State & Undo/Redo Mutators

    @Test func testDocumentModelDefaultDrawingSheet() {
        let doc = DocumentModel(documentType: .drawing)
        #expect(doc.documentType == .drawing)
        #expect(doc.sheets.count == 1)
        #expect(doc.activeSheet != nil)
        #expect(doc.activeSheet?.name == "Sheet 1")
        #expect(doc.activeSheet?.size == .isoA3)
        #expect(doc.activeSheet?.orientation == .landscape)
    }

    @Test func testDocumentModelAddAndRemoveSheetUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let initialSheet = doc.sheets[0]
        #expect(doc.sheets.count == 1)

        // Add a second sheet
        let sheet2 = DrawingSheet(name: "Assembly Overview", size: .isoA2, orientation: .landscape)
        let addedSheet = doc.addSheet(sheet2)
        #expect(doc.sheets.count == 2)
        #expect(doc.activeSheetId == addedSheet.id)
        #expect(doc.activeSheet?.name == "Assembly Overview")

        // Undo addSheet -> reverts back to 1 sheet and original active sheet
        doc.undoManager?.undo()
        #expect(doc.sheets.count == 1)
        #expect(doc.activeSheetId == initialSheet.id)

        // Redo addSheet -> restores sheet2
        doc.undoManager?.redo()
        #expect(doc.sheets.count == 2)
        #expect(doc.activeSheetId == addedSheet.id)

        // Remove sheet2
        doc.undoManager?.removeAllActions()
        let removed = doc.removeSheet(id: addedSheet.id)
        #expect(removed)
        #expect(doc.sheets.count == 1)
        #expect(doc.activeSheetId == initialSheet.id)

        // Undo removeSheet -> restores sheet2
        doc.undoManager?.undo()
        #expect(doc.sheets.count == 2)
        #expect(doc.activeSheetId == addedSheet.id)

        // Redo removeSheet -> removes sheet2 again
        doc.undoManager?.redo()
        #expect(doc.sheets.count == 1)
        #expect(doc.activeSheetId == initialSheet.id)
    }

    @Test func testDocumentModelRejectDeletingLastSheet() {
        let doc = DocumentModel(documentType: .drawing)
        #expect(doc.sheets.count == 1)
        let singleSheetId = doc.sheets[0].id

        let removed = doc.removeSheet(id: singleSheetId)
        #expect(!removed)
        #expect(doc.sheets.count == 1)
        #expect(doc.activeSheetId == singleSheetId)
    }

    @Test func testDocumentModelUpdateSheetUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        guard var sheet = doc.activeSheet else {
            Issue.record("Missing active sheet")
            return
        }

        sheet.name = "Renamed Drawing Sheet"
        sheet.scale = "2:1"
        sheet.orientation = .portrait

        let updated = doc.updateSheet(sheet)
        #expect(updated)
        #expect(doc.activeSheet?.name == "Renamed Drawing Sheet")
        #expect(doc.activeSheet?.scale == "2:1")
        #expect(doc.activeSheet?.orientation == .portrait)

        // Undo update
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.name == "Sheet 1")
        #expect(doc.activeSheet?.scale == "1:1")
        #expect(doc.activeSheet?.orientation == .landscape)

        // Redo update
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.name == "Renamed Drawing Sheet")
        #expect(doc.activeSheet?.scale == "2:1")
        #expect(doc.activeSheet?.orientation == .portrait)
    }

    @Test func testDocumentModelDuplicateSheetUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let initialId = doc.sheets[0].id

        let duplicated = doc.duplicateSheet(id: initialId)
        #expect(duplicated != nil)
        #expect(doc.sheets.count == 2)
        #expect(doc.sheets[1].name == "Sheet 1 Copy")
        #expect(doc.activeSheetId == duplicated?.id)

        // Undo duplicate
        doc.undoManager?.undo()
        #expect(doc.sheets.count == 1)
        #expect(doc.activeSheetId == initialId)

        // Redo duplicate
        doc.undoManager?.redo()
        #expect(doc.sheets.count == 2)
        #expect(doc.activeSheetId == duplicated?.id)
    }

    @Test func testDocumentModelReorderSheetsUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet1 = doc.sheets[0]
        let sheet2 = doc.addSheet(DrawingSheet(name: "Sheet 2", size: .isoA4, orientation: .portrait))
        #expect(doc.sheets.map(\.id) == [sheet1.id, sheet2.id])
        doc.undoManager?.removeAllActions()

        // Reorder [sheet2, sheet1]
        doc.reorderSheets([sheet2, sheet1])
        #expect(doc.sheets.map(\.id) == [sheet2.id, sheet1.id])

        // Undo reorder
        doc.undoManager?.undo()
        #expect(doc.sheets.map(\.id) == [sheet1.id, sheet2.id])

        // Redo reorder
        doc.undoManager?.redo()
        #expect(doc.sheets.map(\.id) == [sheet2.id, sheet1.id])
    }

    @Test func testDocumentModelSetSheetPropertyUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let sheetId = doc.sheets[0].id

        let result = doc.setSheetProperty(sheetId: sheetId, key: "CheckedBy", value: "Lead QA")
        #expect(result)
        #expect(doc.sheets[0].property(forKey: "CheckedBy") == "Lead QA")

        // Empty key rejected
        let invalid = doc.setSheetProperty(sheetId: sheetId, key: "   ", value: "None")
        #expect(!invalid)

        // Undo property set
        doc.undoManager?.undo()
        #expect(doc.sheets[0].property(forKey: "CheckedBy") == nil)

        // Redo property set
        doc.undoManager?.redo()
        #expect(doc.sheets[0].property(forKey: "CheckedBy") == "Lead QA")
    }
}
