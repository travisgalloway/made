import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchDXFImportTests {

    // MARK: - 1. Header Units and Scaling

    @Test func testHeaderUnitsDetectionAndScaling() throws {
        // Test millimeter, inch, foot, centimeter, meter, and decimeter scaling
        let unitCases: [(code: Int, unit: LengthUnit?, expectedScale: Double)] = [
            (1, .inches, 25.4),
            (2, .feet, 304.8),
            (4, .millimeters, 1.0),
            (5, .centimeters, 10.0),
            (6, .meters, 1000.0),
            (14, nil, 100.0) // decimeters
        ]

        for (code, expectedUnit, expectedScale) in unitCases {
            let dxf = """
            0
            SECTION
            2
            HEADER
            9
            $INSUNITS
            70
            \(code)
            0
            ENDSEC
            0
            SECTION
            2
            ENTITIES
            0
            LINE
            8
            0
            10
            0.0
            20
            0.0
            11
            10.0
            21
            0.0
            0
            ENDSEC
            0
            EOF
            """

            let doc = try SketchDXFImporter.parseDXF(dxfText: dxf)
            #expect(doc.insunitsRaw == code)
            #expect(doc.headerUnits == expectedUnit)
            #expect(doc.entities.count == 1)

            guard let line = doc.entities.first, let start = line.startPoint, let end = line.endPoint else {
                Issue.record("Expected valid line entity for code \(code)")
                continue
            }
            #expect(abs(start.x) < 1e-6)
            #expect(abs(start.y) < 1e-6)
            #expect(abs(end.x - (10.0 * expectedScale)) < 1e-4)
            #expect(abs(end.y) < 1e-6)
        }
    }

    @Test func testUnitOverrideSupersedesHeader() throws {
        // DXF says feet (code 2), but user overrides to millimeters
        let dxf = """
        0
        SECTION
        2
        HEADER
        9
        $INSUNITS
        70
        2
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        0
        10
        0.0
        20
        0.0
        11
        50.0
        21
        0.0
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.unitOverride = .millimeters
        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        let line = try #require(doc.entities.first)
        let end = try #require(line.endPoint)
        #expect(abs(end.x - 50.0) < 1e-4)
    }

    // MARK: - 2. Layer Filtering & Construction Mapping

    @Test func testLayerFilteringAndConstructionMapping() throws {
        let dxf = """
        0
        SECTION
        2
        TABLES
        0
        TABLE
        2
        LAYER
        0
        LAYER
        2
        VisibleLayer
        70
        0
        62
        7
        6
        CONTINUOUS
        0
        LAYER
        2
        HiddenLayer
        70
        0
        62
        8
        6
        HIDDEN
        0
        LAYER
        2
        IgnoredLayer
        70
        0
        62
        1
        6
        CONTINUOUS
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        VisibleLayer
        10
        0.0
        20
        0.0
        11
        10.0
        21
        0.0
        0
        LINE
        8
        HiddenLayer
        10
        0.0
        20
        10.0
        11
        10.0
        21
        10.0
        0
        LINE
        8
        IgnoredLayer
        10
        0.0
        20
        20.0
        11
        10.0
        21
        20.0
        0
        LINE
        8
        VisibleLayer
        6
        CENTER
        10
        0.0
        20
        30.0
        11
        10.0
        21
        30.0
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.layerFilter = ["VisibleLayer", "HiddenLayer"]
        options.weldEndpoints = false

        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        #expect(doc.entities.count == 3) // IgnoredLayer is filtered out

        // Entity 1: VisibleLayer with CONTINUOUS line -> not construction
        #expect(doc.entities[0].isConstruction == false)

        // Entity 2: HiddenLayer (in constructionLayers or HIDDEN linetype) -> isConstruction == true
        #expect(doc.entities[1].isConstruction == true)

        // Entity 3: VisibleLayer with CENTER linetype -> isConstruction == true
        #expect(doc.entities[2].isConstruction == true)
    }

    @Test func testMarkAllConstructionOption() throws {
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        0
        10
        0.0
        20
        0.0
        11
        20.0
        21
        0.0
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.markAllConstruction = true
        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        #expect(doc.entities.count == 1)
        #expect(doc.entities.first?.isConstruction == true)
    }

    // MARK: - 3. Entity Conversion Coverage

    @Test func testStandardEntitiesConversion() throws {
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        POINT
        8
        0
        10
        5.0
        20
        7.0
        0
        LINE
        8
        0
        10
        0.0
        20
        0.0
        11
        30.0
        21
        40.0
        0
        CIRCLE
        8
        0
        10
        15.0
        20
        20.0
        40
        10.0
        0
        ARC
        8
        0
        10
        0.0
        20
        0.0
        40
        20.0
        50
        0.0
        51
        90.0
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.weldEndpoints = false
        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        #expect(doc.entities.count == 4)

        // 1. Point
        let point = doc.entities[0]
        #expect(point.kind == "point")
        #expect(point.pointPosition == SIMD2(5.0, 7.0))

        // 2. Line
        let line = doc.entities[1]
        #expect(line.kind == "line")
        #expect(line.startPoint == SIMD2(0.0, 0.0))
        #expect(line.endPoint == SIMD2(30.0, 40.0))

        // 3. Circle
        let circle = doc.entities[2]
        #expect(circle.kind == "circle")
        #expect(circle.centerPoint == SIMD2(15.0, 20.0))
        #expect(abs((circle.radius ?? 0.0) - 10.0) < 1e-6)

        // 4. Arc (0 deg to 90 deg at center 0,0 radius 20)
        let arc = doc.entities[3]
        #expect(arc.kind == "arc")
        #expect(arc.centerPoint == SIMD2(0.0, 0.0))
        let arcStart = try #require(arc.startPoint)
        let arcEnd = try #require(arc.endPoint)
        #expect(abs(arcStart.x - 20.0) < 1e-4)
        #expect(abs(arcStart.y - 0.0) < 1e-4)
        #expect(abs(arcEnd.x - 0.0) < 1e-4)
        #expect(abs(arcEnd.y - 20.0) < 1e-4)
    }

    @Test func testEllipseAndEllipticalArcConversion() throws {
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        ELLIPSE
        8
        0
        10
        10.0
        20
        10.0
        11
        20.0
        21
        0.0
        40
        0.5
        41
        0.0
        42
        6.283185307179586
        0
        ELLIPSE
        8
        0
        10
        0.0
        20
        0.0
        11
        10.0
        21
        0.0
        40
        0.5
        41
        0.0
        42
        1.5707963267948966
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.weldEndpoints = false
        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        #expect(doc.entities.count == 2)

        // Full ellipse
        let ellipse = doc.entities[0]
        #expect(ellipse.kind == "ellipse")
        #expect(ellipse.centerPoint == SIMD2(10.0, 10.0))
        #expect(abs((ellipse.radiusX ?? 0.0) - 20.0) < 1e-4)
        #expect(abs((ellipse.radiusY ?? 0.0) - 10.0) < 1e-4)

        // Elliptical arc (0 to pi/2)
        let arc = doc.entities[1]
        #expect(arc.kind == "ellipticalArc")
        #expect(arc.centerPoint == SIMD2(0.0, 0.0))
        #expect(abs((arc.radiusX ?? 0.0) - 10.0) < 1e-4)
        #expect(abs((arc.radiusY ?? 0.0) - 5.0) < 1e-4)
    }

    // MARK: - 4. Bulged Polyline Arc Math

    @Test func testBulgedPolylineArcMath() throws {
        // LWPOLYLINE from (0,0) to (20,0) with bulge 1.0 (semicircle, radius 10), then to (20, 20) with bulge 0.0
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LWPOLYLINE
        8
        0
        70
        0
        90
        3
        10
        0.0
        20
        0.0
        42
        1.0
        10
        20.0
        20
        0.0
        42
        0.0
        10
        20.0
        20
        20.0
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.weldEndpoints = false
        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        #expect(doc.entities.count == 2)

        // Segment 1: Arc with bulge 1.0 from (0,0) to (20,0)
        let arc = doc.entities[0]
        #expect(arc.kind == "arc")
        let start = try #require(arc.startPoint)
        let end = try #require(arc.endPoint)
        let center = try #require(arc.centerPoint)

        #expect(abs(start.x - 0.0) < 1e-5)
        #expect(abs(start.y - 0.0) < 1e-5)
        #expect(abs(end.x - 20.0) < 1e-5)
        #expect(abs(end.y - 0.0) < 1e-5)
        #expect(abs(center.x - 10.0) < 1e-5)
        #expect(abs(center.y - 0.0) < 1e-5)
        #expect(abs((arc.radius ?? 0.0) - 10.0) < 1e-5)

        // Segment 2: Straight line from (20,0) to (20,20)
        let line = doc.entities[1]
        #expect(line.kind == "line")
        #expect(line.startPoint == SIMD2(20.0, 0.0))
        #expect(line.endPoint == SIMD2(20.0, 20.0))
    }

    @Test func testClosedPolylineVertexSeqend() throws {
        // Classic POLYLINE with 4 VERTEX entities, closed flag (70 = 1)
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        POLYLINE
        8
        0
        70
        1
        0
        VERTEX
        8
        0
        10
        0.0
        20
        0.0
        0
        VERTEX
        8
        0
        10
        40.0
        20
        0.0
        0
        VERTEX
        8
        0
        10
        40.0
        20
        30.0
        0
        VERTEX
        8
        0
        10
        0.0
        20
        30.0
        0
        SEQEND
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.weldEndpoints = false
        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        #expect(doc.entities.count == 4) // 4 segments around the rectangle
        #expect(doc.entities.allSatisfy { $0.kind == "line" })

        let closingSegment = doc.entities[3]
        #expect(closingSegment.startPoint == SIMD2(0.0, 30.0))
        #expect(closingSegment.endPoint == SIMD2(0.0, 0.0))
    }

    // MARK: - 5. Spline de Boor Evaluation

    @Test func testSplineDeBoorEvaluationAndFitPoints() throws {
        // Spline with degree 3, 4 control points (Bezier curve segment), clamped knot vector [0, 0, 0, 0, 1, 1, 1, 1]
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        SPLINE
        8
        0
        70
        8
        71
        3
        72
        8
        73
        4
        74
        0
        40
        0.0
        40
        0.0
        40
        0.0
        40
        0.0
        40
        1.0
        40
        1.0
        40
        1.0
        40
        1.0
        10
        0.0
        20
        0.0
        10
        10.0
        20
        20.0
        10
        20.0
        20
        20.0
        10
        30.0
        20
        0.0
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.splineIntervals = 16
        options.weldEndpoints = false
        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        #expect(doc.entities.count == 16)
        #expect(doc.entities.allSatisfy { $0.kind == "line" })

        // First segment starts at (0,0), last segment ends at (30,0)
        let first = try #require(doc.entities.first)
        let last = try #require(doc.entities.last)
        let start = try #require(first.startPoint)
        let end = try #require(last.endPoint)
        #expect(abs(start.x) < 1e-4 && abs(start.y) < 1e-4)
        #expect(abs(end.x - 30.0) < 1e-4 && abs(end.y) < 1e-4)
    }

    // MARK: - 6. Text & MText Cleaning

    @Test func testTextAndMTextCleaning() throws {
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        TEXT
        8
        0
        10
        10.0
        20
        10.0
        40
        5.0
        1
        Simple Label
        0
        MTEXT
        8
        0
        10
        20.0
        20
        20.0
        40
        3.5
        1
        {\\fArial;Line 1\\PLine 2}
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.weldEndpoints = false
        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        #expect(doc.entities.count == 2)

        let t1 = doc.entities[0]
        #expect(t1.kind == "text")
        #expect(t1.text == "Simple Label")
        #expect(abs((t1.fontSize ?? 0.0) - 5.0) < 1e-4)

        let t2 = doc.entities[1]
        #expect(t2.kind == "text")
        #expect(t2.text?.contains("Line 1\nLine 2") == true)
    }

    // MARK: - 7. Endpoint Welding and Constraints

    @Test func testEndpointWeldingAndCoincidentConstraints() throws {
        // 4 lines forming an unclosed box with small 0.0005 mm gap at corners
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        0
        10
        0.0
        20
        0.0
        11
        40.0004
        21
        0.0
        0
        LINE
        8
        0
        10
        40.0
        20
        0.0003
        11
        40.0
        21
        30.0
        0
        LINE
        8
        0
        10
        39.9998
        21
        30.0
        11
        0.0
        21
        30.0
        0
        LINE
        8
        0
        10
        0.0
        20
        30.0004
        11
        0.0002
        21
        0.0001
        0
        ENDSEC
        0
        EOF
        """

        var options = DXFImportOptions()
        options.weldEndpoints = true
        options.weldTolerance = 1e-3

        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf, options: options)
        #expect(doc.entities.count == 4)
        #expect(doc.constraints.count == 4)
        #expect(doc.constraints.allSatisfy { $0.kind == .coincident })

        // Check corner (0,0) snapped
        let l1 = doc.entities[0]
        let l4 = doc.entities[3]
        let l1Start = try #require(l1.startPoint)
        let l4End = try #require(l4.endPoint)
        #expect(abs(l1Start.x - l4End.x) < 1e-9)
        #expect(abs(l1Start.y - l4End.y) < 1e-9)
    }

    // MARK: - 8. Round-Trip with DrawingDXFExporter

    @Test @MainActor func testRoundTripWithDrawingDXFExporter() throws {
        let sheet = DrawingSheet(
            size: .custom(width: 250, height: 180),
            orientation: .landscape,
            titleBlockTemplate: .none
        )
        let exportedDXF = DrawingDXFExporter.exportDXF(sheet: sheet, metadata: [:])
        #expect(!exportedDXF.isEmpty)

        let doc = try SketchDXFImporter.parseDXF(dxfText: exportedDXF)
        #expect(doc.headerUnits == .millimeters)
        #expect(!doc.layers.isEmpty)
        #expect(doc.layers.contains { $0.name == "BORDER" })
        #expect(!doc.entities.isEmpty)

        // Border has lines and zone text
        let borderLines = doc.entities.filter { $0.kind == "line" }
        #expect(borderLines.count >= 4)
    }

    // MARK: - 9. Malformed and Degenerate Resilience

    @Test func testDegenerateGeometrySkippedSafely() throws {
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        0
        10
        10.0
        20
        10.0
        11
        10.0
        21
        10.0
        0
        CIRCLE
        8
        0
        10
        20.0
        20
        20.0
        40
        0.0
        0
        LINE
        8
        0
        10
        0.0
        20
        0.0
        11
        50.0
        21
        0.0
        0
        ENDSEC
        0
        EOF
        """

        let doc = try SketchDXFImporter.parseDXF(dxfText: dxf)
        // Zero length line and zero radius circle must be filtered out, only valid line remains
        #expect(doc.entities.count == 1)
        #expect(doc.entities.first?.startPoint == SIMD2(0.0, 0.0))
        #expect(doc.entities.first?.endPoint == SIMD2(50.0, 0.0))
    }
}
