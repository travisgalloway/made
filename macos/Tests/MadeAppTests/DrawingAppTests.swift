import Testing
import Foundation
import SwiftUI
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct DrawingAppTests {

    @Test func testNewDrawingShortcutConstants() {
        #expect(WorkspaceModel.newDrawingShortcutKey == "d")
        #expect(WorkspaceModel.newDrawingShortcutModifiers == [.command, .shift])
    }

    @Test func testNewDrawingDocumentInWorkspace() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        #expect(ws.document.documentType == .drawing)
        #expect(ws.document.sheets.count == 1)
        #expect(ws.document.activeSheet?.name == "Sheet 1")
        #expect(ws.document.activeSheet?.size == .isoA3)
        #expect(ws.document.activeSheet?.orientation == .landscape)
        #expect(!ws.isDocumentModified)
        #expect(ws.currentDocumentURL == nil)
    }

    @Test func testSheetOperationsInWorkspace() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        // 1. Add sheet
        let sheet2 = ws.addSheet(name: "Fabrication Details", size: .ansiC, orientation: .landscape)
        #expect(ws.document.sheets.count == 2)
        #expect(ws.document.activeSheetId == sheet2.id)
        #expect(ws.isDocumentModified)

        // 2. Duplicate sheet
        let duplicate = ws.duplicateSheet(id: sheet2.id)
        #expect(duplicate != nil)
        #expect(ws.document.sheets.count == 3)
        #expect(ws.document.sheets[2].name == "Fabrication Details Copy")
        #expect(ws.document.activeSheetId == duplicate?.id)

        // 3. Update sheet
        if var active = ws.document.activeSheet {
            active.scale = "1:5"
            active.titleBlockTemplate = .minimal
            let updated = ws.updateSheet(active)
            #expect(updated)
            #expect(ws.document.activeSheet?.scale == "1:5")
            #expect(ws.document.activeSheet?.titleBlockTemplate == .minimal)
        }

        // 4. Set sheet property
        let propSet = ws.setSheetProperty(sheetId: sheet2.id, key: "DrawnBy", value: "CAD Specialist")
        #expect(propSet)
        #expect(ws.document.sheets.first(where: { $0.id == sheet2.id })?.property(forKey: "DrawnBy") == "CAD Specialist")

        // 5. Remove sheet
        ws.document.undoManager?.removeAllActions()
        if let dupId = duplicate?.id {
            let removed = ws.removeSheet(id: dupId)
            #expect(removed)
            #expect(ws.document.sheets.count == 2)
        }

        // 6. Undo through workspace
        ws.undo()
        #expect(ws.document.sheets.count == 3)

        // 7. Redo through workspace
        ws.redo()
        #expect(ws.document.sheets.count == 2)
    }

    @Test func testWorkspacePackageSaveAndReopenDrawing() throws {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        _ = ws.addSheet(name: "Sheet 2", size: .isoA4, orientation: .portrait)
        ws.setDocumentProperty(key: CustomPropertyKey.partNumber, value: "PRJ-DRAW-001")
        ws.setDocumentProperty(key: CustomPropertyKey.description, value: "Project Assembly Drawing")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("DrawingWorkspaceTest.made")
        let package = try ws.makePackage()
        try package.write(to: packageURL)

        // Open in new workspace
        let ws2 = WorkspaceModel()
        let opened = ws2.openDocument(at: packageURL)
        #expect(opened)
        #expect(ws2.document.documentType == .drawing)
        #expect(ws2.document.sheets.count == 2)
        #expect(ws2.document.sheets[0].name == "Sheet 1")
        #expect(ws2.document.sheets[1].name == "Sheet 2")
        #expect(ws2.document.sheets[1].size == .isoA4)
        #expect(ws2.document.metadata[CustomPropertyKey.partNumber] == "PRJ-DRAW-001")
        #expect(ws2.document.metadata[CustomPropertyKey.description] == "Project Assembly Drawing")
    }
}
