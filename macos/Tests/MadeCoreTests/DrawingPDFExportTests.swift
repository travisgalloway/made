import Testing
import Foundation
import CoreGraphics
import simd
@testable import MadeCore

@Suite @MainActor struct DrawingPDFExportTests {

    @Test func testSingleSheetPDFExportProducesValidPDFData() throws {
        let doc = DocumentModel()
        doc.setDocumentType(.drawing)
        let sheet = doc.addSheet(DrawingSheet(name: "Sheet 1", size: .isoA3, orientation: .landscape))

        let pdfData = try DrawingPDFExporter.exportPDF(sheet: sheet, document: doc)
        #expect(!pdfData.isEmpty)

        // Verify %PDF- header magic bytes
        let header = String(decoding: pdfData.prefix(5), as: UTF8.self)
        #expect(header == "%PDF-")

        // Verify valid CGPDFDocument with 1 page
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let cgDoc = CGPDFDocument(provider) else {
            Issue.record("Failed to create CGPDFDocument from exported PDF data")
            return
        }
        #expect(cgDoc.numberOfPages == 1)

        guard let page = cgDoc.page(at: 1) else {
            Issue.record("First page not found in CGPDFDocument")
            return
        }
        let box = page.getBoxRect(.mediaBox)
        let expectedW = sheet.dimensionsPoints.width
        let expectedH = sheet.dimensionsPoints.height
        #expect(abs(Double(box.width) - expectedW) < 1.0)
        #expect(abs(Double(box.height) - expectedH) < 1.0)
    }

    @Test func testMultiSheetPDFExportProducesMultiPagePDF() throws {
        let doc = DocumentModel()
        doc.setDocumentType(.drawing)
        _ = doc.addSheet(DrawingSheet(name: "Sheet 1", size: .isoA3, orientation: .landscape))
        _ = doc.addSheet(DrawingSheet(name: "Detail Sheet", size: .isoA4, orientation: .portrait))

        #expect(doc.sheets.count == 2)
        let pdfData = try DrawingPDFExporter.exportPDF(sheets: doc.sheets, document: doc)
        #expect(!pdfData.isEmpty)

        guard let provider = CGDataProvider(data: pdfData as CFData),
              let cgDoc = CGPDFDocument(provider) else {
            Issue.record("Failed to load multi-page CGPDFDocument")
            return
        }
        #expect(cgDoc.numberOfPages == 2)

        // Page 1: A3 Landscape
        guard let page1 = cgDoc.page(at: 1) else {
            Issue.record("Page 1 missing")
            return
        }
        let box1 = page1.getBoxRect(.mediaBox)
        #expect(abs(Double(box1.width) - doc.sheets[0].dimensionsPoints.width) < 1.0)
        #expect(abs(Double(box1.height) - doc.sheets[0].dimensionsPoints.height) < 1.0)

        // Page 2: A4 Portrait
        guard let page2 = cgDoc.page(at: 2) else {
            Issue.record("Page 2 missing")
            return
        }
        let box2 = page2.getBoxRect(.mediaBox)
        #expect(abs(Double(box2.width) - doc.sheets[1].dimensionsPoints.width) < 1.0)
        #expect(abs(Double(box2.height) - doc.sheets[1].dimensionsPoints.height) < 1.0)
    }

    @Test func testPDFExportRespectsLineWeights() {
        #expect(DrawingPDFExporter.borderLineWidthPt > 0)
        #expect(DrawingPDFExporter.visibleOutlineLineWidthPt > 0)
        #expect(DrawingPDFExporter.hiddenLineWidthPt > 0)
        #expect(DrawingPDFExporter.dimensionLineWidthPt > 0)

        // Standard ratios: border (0.70mm) > visible (0.50mm) > hidden (0.25mm)
        #expect(DrawingPDFExporter.borderLineWidthPt > DrawingPDFExporter.visibleOutlineLineWidthPt)
        #expect(DrawingPDFExporter.visibleOutlineLineWidthPt > DrawingPDFExporter.hiddenLineWidthPt)
        #expect(DrawingPDFExporter.hiddenLineWidthPt == DrawingPDFExporter.dimensionLineWidthPt)
    }

    @Test func testPDFExportRendersAnnotationsAndBOM() throws {
        var sheet = DrawingSheet(name: "Test Sheet", size: .isoA3, orientation: .landscape)

        // Add 2D views with cached HLR edges
        let edges = [
            HLREdge(category: .visibleSharp, points2D: [SIMD2(-20, -10), SIMD2(20, -10), SIMD2(20, 10), SIMD2(-20, 10), SIMD2(-20, -10)]),
            HLREdge(category: .hiddenSharp, points2D: [SIMD2(-10, -5), SIMD2(10, -5)])
        ]
        let hlrResult = HLRResult(edges: edges, viewDirection: SIMD3(0, 0, 1))
        let view = DrawingView(
            name: "Front View",
            kind: .base,
            standardView: .front,
            positionMM: SIMD2(150.0, 150.0),
            scale: .full,
            displayStyle: .hiddenLinesVisible,
            cachedHLR: hlrResult
        )
        sheet.views.append(view)

        // Add child section view
        let childSection = DrawingView(
            name: "Section A-A",
            kind: .section,
            standardView: .front,
            parentViewId: view.id,
            positionMM: SIMD2(250.0, 150.0),
            scale: .full,
            cachedHLR: hlrResult,
            sectionDefinition: SectionLineDefinition(label: "A", startPointMM: SIMD2(-25, 0), endPointMM: SIMD2(25, 0))
        )
        sheet.views.append(childSection)

        // Add child detail view
        let childDetail = DrawingView(
            name: "Detail B",
            kind: .detail,
            standardView: .front,
            parentViewId: view.id,
            positionMM: SIMD2(150.0, 250.0),
            scale: .double,
            cachedHLR: hlrResult,
            detailDefinition: DetailCircleDefinition(label: "B", centerMM: SIMD2(0, 0), radiusMM: 15.0)
        )
        sheet.views.append(childDetail)

        // Add annotations (linear, angular, radial, ordinate, baseline, note, leader, centerMark, centerline, holeCallout, balloon)
        sheet.annotations.append(DrawingAnnotation(
            name: "Linear Dim",
            data: .linear(LinearDimensionData(startPointMM: SIMD2(50, 100), endPointMM: SIMD2(100, 100)))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Angular Dim",
            data: .angular(AngularDimensionData(vertexMM: SIMD2(50, 50), startPointMM: SIMD2(80, 50), endPointMM: SIMD2(50, 80), arcRadiusMM: 20))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Radial Dim",
            data: .radial(RadialDimensionData(centerMM: SIMD2(100, 100), arcPointMM: SIMD2(115, 115)))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Ordinate Dim",
            data: .ordinate(OrdinateDimensionData(datumOriginMM: SIMD2(50, 50), locationMM: SIMD2(90, 50)))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Baseline Dim",
            data: .baseline(BaselineDimensionData(basePointMM: SIMD2(40, 80), targetPointsMM: [SIMD2(60, 80), SIMD2(80, 80)]))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Note",
            data: .note(NoteAnnotationData(positionMM: SIMD2(50, 40), text: "TEST DRAWING NOTE"))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Leader",
            data: .leader(LeaderAnnotationData(arrowPointMM: SIMD2(60, 60), elbowPointMM: SIMD2(80, 70), text: "SURFACE FINISH"))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Center Mark",
            data: .centerMark(CenterMarkData(centerMM: SIMD2(100, 100)))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Centerline",
            data: .centerline(CenterlineData(startPointMM: SIMD2(100, 80), endPointMM: SIMD2(100, 120)))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Hole Callout",
            data: .holeCallout(HoleCalloutAnnotationData(anchorPointMM: SIMD2(120, 100), elbowPointMM: SIMD2(140, 110)))
        ))
        sheet.annotations.append(DrawingAnnotation(
            name: "Balloon",
            data: .balloon(BalloonAnnotationData(anchorPointMM: SIMD2(70, 70), balloonCenterMM: SIMD2(90, 90), itemNumber: "1", quantity: 2, showQuantity: true))
        ))

        // Add BOM table
        sheet.bomTables.append(DrawingBOMTable(
            name: "Sheet BOM",
            positionMM: SIMD2(20, 20),
            columns: [.itemNumber, .name, .quantity]
        ))

        let customItems = [
            BOMItem(itemNumber: "1", name: "Bracket", partNumber: "BRK-01", description: "Steel bracket", quantity: 2),
            BOMItem(itemNumber: "2", name: "Bolt", partNumber: "BLT-M6", description: "Hex bolt", quantity: 8)
        ]

        let pdfData = try DrawingPDFExporter.exportPDF(
            sheet: sheet,
            metadata: ["title": "Assembly Drawing", "drawingNumber": "DWG-1001", "author": "Engineer"],
            bomItems: customItems
        )
        #expect(!pdfData.isEmpty)

        guard let provider = CGDataProvider(data: pdfData as CFData),
              let cgDoc = CGPDFDocument(provider) else {
            Issue.record("Failed to load PDF document")
            return
        }
        #expect(cgDoc.numberOfPages == 1)
    }

    @Test func testPDFExportWithMinimalAndNoneTitleBlocks() throws {
        var sheet = DrawingSheet(size: .isoA4, orientation: .landscape, titleBlockTemplate: .minimal)
        let pdfMinimal = try DrawingPDFExporter.exportPDF(sheet: sheet, metadata: ["title": "Minimal Title Block"])
        #expect(!pdfMinimal.isEmpty)

        sheet.titleBlockTemplate = .none
        let pdfNone = try DrawingPDFExporter.exportPDF(sheet: sheet)
        #expect(!pdfNone.isEmpty)
    }

    @Test func testPDFExportEdgeCasesEmptyAndCustomSheets() throws {
        // Empty sheet list error
        #expect(throws: DrawingPDFExporterError.emptySheetsList) {
            try DrawingPDFExporter.exportPDF(sheets: [], metadata: [:])
        }

        // Custom sheet dimensions: portrait 150x220 mm
        let customSheet = DrawingSheet(
            size: .custom(width: 150, height: 220),
            orientation: .portrait,
            titleBlockTemplate: .isoStandard
        )
        let pdfData = try DrawingPDFExporter.exportPDF(sheet: customSheet)
        #expect(!pdfData.isEmpty)

        guard let provider = CGDataProvider(data: pdfData as CFData),
              let cgDoc = CGPDFDocument(provider),
              let page = cgDoc.page(at: 1) else {
            Issue.record("Failed to read custom sheet PDF")
            return
        }
        let box = page.getBoxRect(.mediaBox)
        #expect(abs(Double(box.width) - customSheet.dimensionsPoints.width) < 1.0)
        #expect(abs(Double(box.height) - customSheet.dimensionsPoints.height) < 1.0)
    }
}
