import Testing
import Foundation
import simd
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct DrawingExportAppTests {

    @Test func testWorkspaceCanExportDrawing() {
        let ws = WorkspaceModel()
        // Default part document has no drawing sheets
        #expect(ws.canExportDrawing == false)

        // Switch to drawing document
        ws.newDrawingDocument()
        #expect(ws.canExportDrawing == true)
        #expect(ws.document.sheets.count == 1)

        // Switch to new part document
        ws.newDocument()
        #expect(ws.canExportDrawing == false)
    }

    @Test func testWorkspaceExportDrawingPDFToFile() async throws {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()
        guard let sheet = ws.document.activeSheet else {
            Issue.record("Missing active drawing sheet")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let pdfURL = tempDir.appendingPathComponent("test-export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let success = await ws.exportDrawingPDF(sheetId: sheet.id, to: pdfURL)
        #expect(success == true)
        #expect(ws.pendingExportError == nil)
        #expect(ws.isShowingExportErrorAlert == false)
        #expect(FileManager.default.fileExists(atPath: pdfURL.path))

        let data = try Data(contentsOf: pdfURL)
        let header = String(decoding: data.prefix(5), as: UTF8.self)
        #expect(header == "%PDF-")
    }

    @Test func testWorkspaceExportDrawingDXFToFile() async throws {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()
        guard let sheet = ws.document.activeSheet else {
            Issue.record("Missing active drawing sheet")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let dxfURL = tempDir.appendingPathComponent("test-export-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: dxfURL) }

        let success = await ws.exportDrawingDXF(sheetId: sheet.id, to: dxfURL)
        #expect(success == true)
        #expect(ws.pendingExportError == nil)
        #expect(ws.isShowingExportErrorAlert == false)
        #expect(FileManager.default.fileExists(atPath: dxfURL.path))

        let text = try String(contentsOf: dxfURL, encoding: .utf8)
        #expect(text.contains("$ACADVER\n1\nAC1015\n"))
        #expect(text.hasSuffix("0\nEOF\n"))
    }

    @Test func testWorkspaceExportDrawingHandlesInvalidURL() async {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        let invalidURL = URL(fileURLWithPath: "/non_existent_folder_xyz/unwritable/drawing.pdf")
        let success = await ws.exportDrawingPDF(to: invalidURL)
        #expect(success == false)
        #expect(ws.pendingExportError != nil)
        #expect(ws.isShowingExportErrorAlert == true)

        let invalidDXFURL = URL(fileURLWithPath: "/non_existent_folder_xyz/unwritable/drawing.dxf")
        let dxfSuccess = await ws.exportDrawingDXF(to: invalidDXFURL)
        #expect(dxfSuccess == false)
        #expect(ws.pendingExportError != nil)
        #expect(ws.isShowingExportErrorAlert == true)
    }

    @Test func testWorkspaceExportDrawingFailsWhenNoSheets() async {
        let ws = WorkspaceModel()
        // No sheets
        let tempDir = FileManager.default.temporaryDirectory
        let pdfURL = tempDir.appendingPathComponent("no-sheets-\(UUID().uuidString).pdf")

        let success = await ws.exportDrawingPDF(to: pdfURL)
        #expect(success == false)
        #expect(ws.pendingExportError != nil)
        #expect(ws.isShowingExportErrorAlert == true)

        let dxfURL = tempDir.appendingPathComponent("no-sheets-\(UUID().uuidString).dxf")
        let dxfSuccess = await ws.exportDrawingDXF(to: dxfURL)
        #expect(dxfSuccess == false)
        #expect(ws.pendingExportError != nil)
        #expect(ws.isShowingExportErrorAlert == true)
    }
}
