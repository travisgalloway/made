import Testing
import Foundation
@testable import MadeCore

@Suite @MainActor struct DrawingDocumentCoderTests {

    @Test func testDocumentDataSerializationWithSheets() throws {
        let sheet1 = DrawingSheet(name: "Assembly Drawing", size: .isoA2, orientation: .landscape, scale: "1:2")
        let sheet2 = DrawingSheet(name: "Bill of Materials", size: .isoA4, orientation: .portrait, scale: "1:1")

        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            features: [],
            documentType: .drawing,
            sheets: [sheet1, sheet2],
            activeSheetId: sheet2.id
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(docData)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DocumentData.self, from: data)

        #expect(decoded.documentType == .drawing)
        #expect(decoded.sheets?.count == 2)
        #expect(decoded.sheets?[0].name == "Assembly Drawing")
        #expect(decoded.sheets?[0].size == .isoA2)
        #expect(decoded.sheets?[0].orientation == .landscape)
        #expect(decoded.sheets?[1].name == "Bill of Materials")
        #expect(decoded.sheets?[1].size == .isoA4)
        #expect(decoded.sheets?[1].orientation == .portrait)
        #expect(decoded.activeSheetId == sheet2.id)
    }

    @Test func testLegacyDocumentDataDecodingCompatibility() throws {
        // Legacy JSON without sheets or activeSheetId
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "documentType": "part",
            "features": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DocumentData.self, from: legacyJSON)

        #expect(decoded.documentType == .part)
        #expect(decoded.sheets == nil)
        #expect(decoded.activeSheetId == nil)
    }

    @Test func testDocumentModelPackageCoderRoundTrip() throws {
        let doc = DocumentModel(documentType: .drawing)
        let sheet2 = doc.addSheet(DrawingSheet(name: "Section Views", size: .ansiB, orientation: .landscape, scale: "1:1"))
        doc.setActiveSheetId(sheet2.id)
        doc.setDocumentProperty(key: CustomPropertyKey.partNumber, value: "DWG-5001")
        doc.setDocumentProperty(key: CustomPropertyKey.description, value: "Main Chassis Assembly")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("TestDrawing.made")
        let manifest = MadeManifest(
            schemaVersion: MadeManifest.currentSchemaVersion,
            appVersion: "0.1",
            documentSettings: doc.settings,
            documentType: doc.documentType,
            metadata: doc.metadata
        )
        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            features: doc.features,
            documentType: doc.documentType,
            sheets: doc.sheets,
            activeSheetId: doc.activeSheetId
        )
        let package = MadePackage(manifest: manifest, documentData: docData)
        try package.write(to: packageURL)

        // Read package back
        let loadedPackage = try MadePackage(directoryURL: packageURL)
        #expect(loadedPackage.manifest.documentType == .drawing)
        #expect(loadedPackage.manifest.metadata[CustomPropertyKey.partNumber] == "DWG-5001")
        #expect(loadedPackage.manifest.metadata[CustomPropertyKey.description] == "Main Chassis Assembly")

        let loadedSheets = loadedPackage.documentData.sheets ?? []
        #expect(loadedSheets.count == 2)
        #expect(loadedSheets[0].name == "Sheet 1")
        #expect(loadedSheets[1].name == "Section Views")
        #expect(loadedSheets[1].size == .ansiB)
        #expect(loadedPackage.documentData.activeSheetId == sheet2.id)

        // Restore into new DocumentModel
        let restoredDoc = DocumentModel(documentType: .part)
        try DocumentModelCoder.decode(into: restoredDoc, from: try JSONEncoder().encode(loadedPackage.documentData))

        #expect(restoredDoc.documentType == .drawing)
        #expect(restoredDoc.sheets.count == 2)
        #expect(restoredDoc.activeSheetId == sheet2.id)
        #expect(restoredDoc.activeSheet?.name == "Section Views")
    }

    @Test func testDrawingPackageWithPlacedViewsRoundTrip() throws {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let baseView = DrawingView(
            name: "Front Elevation",
            kind: .base,
            standardView: .front,
            positionMM: SIMD2(100, 100),
            scale: .half,
            displayStyle: .visibleLinesOnly
        )
        _ = doc.addDrawingView(baseView, to: sheet.id)

        let projView = DrawingView(
            name: "Right Elevation",
            kind: .projected,
            standardView: .right,
            parentViewId: baseView.id,
            projectionDirection: .right,
            positionMM: SIMD2(160, 100),
            scale: .half,
            displayStyle: .hiddenLinesVisible
        )
        _ = doc.addDrawingView(projView, to: sheet.id)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("DrawingWithViews.made")
        let manifest = MadeManifest(
            schemaVersion: MadeManifest.currentSchemaVersion,
            appVersion: "0.1",
            documentSettings: doc.settings,
            documentType: doc.documentType,
            metadata: doc.metadata
        )
        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            features: doc.features,
            documentType: doc.documentType,
            sheets: doc.sheets,
            activeSheetId: doc.activeSheetId
        )
        let package = MadePackage(manifest: manifest, documentData: docData)
        try package.write(to: packageURL)

        // Read package back
        let loadedPackage = try MadePackage(directoryURL: packageURL)
        let loadedSheets = loadedPackage.documentData.sheets ?? []
        #expect(loadedSheets.count == 1)
        #expect(loadedSheets[0].views.count == 2)
        #expect(loadedSheets[0].views[0].name == "Front Elevation")
        #expect(loadedSheets[0].views[0].standardView == .front)
        #expect(loadedSheets[0].views[0].scale == .half)
        #expect(loadedSheets[0].views[1].name == "Right Elevation")
        #expect(loadedSheets[0].views[1].kind == .projected)
        #expect(loadedSheets[0].views[1].parentViewId == baseView.id)
        #expect(loadedSheets[0].views[1].displayStyle == .hiddenLinesVisible)

        // Decode into DocumentModel
        let restoredDoc = DocumentModel(documentType: .part)
        try DocumentModelCoder.decode(into: restoredDoc, from: try JSONEncoder().encode(loadedPackage.documentData))
        #expect(restoredDoc.activeSheet?.views.count == 2)
        #expect(restoredDoc.activeSheet?.views[1].standardView == .right)
    }
}
