import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct DrawingDXFExportTests {

    @Test func testDXFHeaderAndTablesStructure() {
        let sheet = DrawingSheet(size: .isoA3, orientation: .landscape)
        let dxf = DrawingDXFExporter.exportDXF(sheet: sheet, metadata: [:])

        // Verify AutoCAD 2000 AC1015 header
        #expect(dxf.contains("$ACADVER\n1\nAC1015\n"))
        #expect(dxf.contains("$INSUNITS\n70\n4\n")) // Millimeters
        #expect(dxf.contains("$MEASUREMENT\n70\n1\n")) // Metric

        // Extents
        #expect(dxf.contains("$EXTMIN"))
        #expect(dxf.contains("$EXTMAX"))

        // Standard tables
        #expect(dxf.contains("TABLE\n2\nLTYPE"))
        #expect(dxf.contains("2\nCONTINUOUS"))
        #expect(dxf.contains("2\nHIDDEN"))
        #expect(dxf.contains("2\nCENTER"))
        #expect(dxf.contains("2\nPHANTOM"))

        #expect(dxf.contains("TABLE\n2\nLAYER"))
        #expect(dxf.contains("TABLE\n2\nSTYLE"))
        #expect(dxf.contains("2\nSTANDARD"))

        // Must end with EOF
        #expect(dxf.hasSuffix("0\nEOF\n"))
    }

    @Test func testDXFLayerAssignmentsAndLineWeights() {
        let sheet = DrawingSheet(size: .isoA3, orientation: .landscape)
        let dxf = DrawingDXFExporter.exportDXF(sheet: sheet, metadata: [:])

        // Required layers
        let expectedLayers = [
            "BORDER",
            "TITLE_BLOCK",
            "VISIBLE",
            "HIDDEN",
            "DIMENSIONS",
            "ANNOTATIONS",
            "CENTER",
            "BOM",
            "HATCH"
        ]
        for layer in expectedLayers {
            #expect(dxf.contains("0\nLAYER\n2\n\(layer)\n"))
        }

        // Line weights in 1/100 mm: BORDER (70), VISIBLE (50), TITLE_BLOCK (35), DIMENSIONS/ANNOTATIONS/BOM (25)
        #expect(dxf.contains("2\nBORDER\n70\n0\n62\n7\n6\nCONTINUOUS\n370\n70\n"))
        #expect(dxf.contains("2\nVISIBLE\n70\n0\n62\n7\n6\nCONTINUOUS\n370\n50\n"))
        #expect(dxf.contains("2\nTITLE_BLOCK\n70\n0\n62\n7\n6\nCONTINUOUS\n370\n35\n"))
        #expect(dxf.contains("2\nHIDDEN\n70\n0\n62\n8\n6\nHIDDEN\n370\n25\n"))
        #expect(dxf.contains("2\nDIMENSIONS\n70\n0\n62\n3\n6\nCONTINUOUS\n370\n25\n"))
    }

    @Test func testDXFEntitiesGeneration() {
        var sheet = DrawingSheet(size: .isoA3, orientation: .landscape)

        // Add view with visible & hidden lines
        let edges = [
            HLREdge(category: .visibleSharp, points2D: [SIMD2(0, 0), SIMD2(50, 0), SIMD2(50, 30)]),
            HLREdge(category: .hiddenSharp, points2D: [SIMD2(10, 10), SIMD2(40, 10)])
        ]
        let hlr = HLRResult(edges: edges, viewDirection: SIMD3(0, 0, 1))
        let view = DrawingView(
            name: "Test View",
            kind: .base,
            standardView: .front,
            positionMM: SIMD2(100, 100),
            scale: .full,
            displayStyle: .hiddenLinesVisible,
            cachedHLR: hlr
        )
        sheet.views.append(view)

        // Add linear dimension
        sheet.annotations.append(DrawingAnnotation(
            name: "Linear Dim",
            data: .linear(LinearDimensionData(startPointMM: SIMD2(10, 10), endPointMM: SIMD2(50, 10), offsetMM: 15))
        ))

        // Add radial dimension
        sheet.annotations.append(DrawingAnnotation(
            name: "Radial Dim",
            data: .radial(RadialDimensionData(centerMM: SIMD2(80, 80), arcPointMM: SIMD2(95, 95)))
        ))

        // Add balloon
        sheet.annotations.append(DrawingAnnotation(
            name: "Balloon 1",
            data: .balloon(BalloonAnnotationData(anchorPointMM: SIMD2(30, 30), balloonCenterMM: SIMD2(50, 50), itemNumber: "4"))
        ))

        let dxf = DrawingDXFExporter.exportDXF(sheet: sheet, metadata: [:])

        #expect(dxf.contains("0\nSECTION\n2\nENTITIES\n"))
        #expect(dxf.contains("0\nLINE\n8\nVISIBLE\n"))
        #expect(dxf.contains("0\nLINE\n8\nHIDDEN\n6\nHIDDEN\n"))
        #expect(dxf.contains("0\nCIRCLE\n8\nANNOTATIONS\n"))
        #expect(dxf.contains("0\nTEXT\n8\nDIMENSIONS\n"))
        #expect(dxf.contains("0\nSOLID\n8\nDIMENSIONS\n")) // Filled arrowhead
        #expect(dxf.contains("0\nSOLID\n8\nANNOTATIONS\n")) // Balloon arrowhead
    }

    @Test func testDXFSheetCoordinatesMapping() {
        let sheet = DrawingSheet(size: .isoA3, orientation: .landscape) // 420 x 297 mm
        let H = sheet.dimensionsMM.height // 297 mm

        var testSheet = sheet
        // Add note at sheet top-left: (x: 20, y: 15) in sheet mm
        testSheet.annotations.append(DrawingAnnotation(
            name: "Corner Note",
            data: .note(NoteAnnotationData(positionMM: SIMD2(20.0, 15.0), text: "TOP-LEFT NOTE"))
        ))

        let dxf = DrawingDXFExporter.exportDXF(sheet: testSheet, metadata: [:])
        let expectedCAD_Y = H - 15.0 // 282.0

        #expect(dxf.contains("TOP-LEFT NOTE"))
        #expect(dxf.contains(String(format: "%.4f", expectedCAD_Y)))
    }

    @Test func testDXFTitleBlockAndZoneMarks() {
        let sheet = DrawingSheet(size: .isoA3, orientation: .landscape, titleBlockTemplate: .isoStandard)
        let metadata = [
            "title": "Gearbox Housing",
            "drawingNumber": "GB-2026-001",
            "author": "Chief Engineer"
        ]
        let dxf = DrawingDXFExporter.exportDXF(sheet: sheet, metadata: metadata)

        #expect(dxf.contains("0\nLINE\n8\nBORDER\n"))
        #expect(dxf.contains("0\nTEXT\n8\nBORDER\n")) // Zone marks
        #expect(dxf.contains("1\nGearbox Housing\n"))
        #expect(dxf.contains("1\nGB-2026-001\n"))
        #expect(dxf.contains("1\nChief Engineer\n"))
        #expect(dxf.contains("0\nLINE\n8\nTITLE_BLOCK\n"))
        #expect(dxf.contains("0\nTEXT\n8\nTITLE_BLOCK\n"))
    }

    @Test func testDXFAnnotationsAndBOMTable() {
        var sheet = DrawingSheet(size: .isoA3, orientation: .landscape)
        sheet.bomTables.append(DrawingBOMTable(
            name: "DXF BOM",
            positionMM: SIMD2(25, 25),
            columns: [.itemNumber, .name, .quantity]
        ))
        let items = [
            BOMItem(itemNumber: "1", name: "Spur Gear", quantity: 2),
            BOMItem(itemNumber: "2", name: "Pinion Shaft", quantity: 1)
        ]
        let dxf = DrawingDXFExporter.exportDXF(sheet: sheet, metadata: [:], bomItems: items)

        #expect(dxf.contains("0\nLINE\n8\nBOM\n"))
        #expect(dxf.contains("0\nTEXT\n8\nBOM\n"))
        #expect(dxf.contains("1\nBILL OF MATERIALS\n"))
        #expect(dxf.contains("1\nSpur Gear\n"))
        #expect(dxf.contains("1\nPinion Shaft\n"))
    }

    @Test func testDXFEdgeCasesEmptySheetAndMissingHLR() {
        let emptySheet = DrawingSheet(
            size: .custom(width: 200, height: 100),
            orientation: .landscape,
            titleBlockTemplate: .none
        )
        let dxf = DrawingDXFExporter.exportDXF(sheet: emptySheet, metadata: [:])

        #expect(dxf.contains("$ACADVER\n1\nAC1015\n"))
        #expect(dxf.contains("0\nSECTION\n2\nENTITIES\n"))
        // Border lines must still exist
        #expect(dxf.contains("0\nLINE\n8\nBORDER\n"))
        // Title block should not exist because template is .none
        #expect(!dxf.contains("8\nTITLE_BLOCK\n"))
        // Ends cleanly with EOF
        #expect(dxf.hasSuffix("0\nEOF\n"))
    }
}
