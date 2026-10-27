import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchSVGImportTests {

    // MARK: - 1. ViewBox Scaling and Y Inversion

    @Test func testViewBoxScalingAndYInversion() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <line x1="10" y1="20" x2="80" y2="90" />
        </svg>
        """

        // Default invertY: true -> y_cad = 100 - y_svg
        let docInverted = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: true))
        #expect(docInverted.entities.count == 1)
        guard let lineInv = docInverted.entities.first,
              let spInv = lineInv.startPoint,
              let epInv = lineInv.endPoint else {
            Issue.record("Expected valid line entity")
            return
        }
        #expect(abs(spInv.x - 10.0) < 1e-4)
        #expect(abs(spInv.y - 80.0) < 1e-4) // 100 - 20 = 80
        #expect(abs(epInv.x - 80.0) < 1e-4)
        #expect(abs(epInv.y - 10.0) < 1e-4) // 100 - 90 = 10

        // With invertY: false -> y_cad = y_svg
        let docDirect = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
        guard let lineDir = docDirect.entities.first,
              let spDir = lineDir.startPoint,
              let epDir = lineDir.endPoint else {
            Issue.record("Expected valid line entity")
            return
        }
        #expect(abs(spDir.x - 10.0) < 1e-4)
        #expect(abs(spDir.y - 20.0) < 1e-4)
        #expect(abs(epDir.x - 80.0) < 1e-4)
        #expect(abs(epDir.y - 90.0) < 1e-4)
    }

    // MARK: - 2. Physical Unit Parsing and Overrides

    @Test func testPhysicalUnitParsing() throws {
        let cases: [(widthStr: String, expectedEndDistance: Double)] = [
            ("100mm", 50.0),
            ("10cm", 50.0),
            ("4in", 50.8), // 4 in = 101.6 mm, viewBox 0..100 -> unitScale = 1.016 mm/unit -> 50 units = 50.8 mm
        ]

        for c in cases {
            let svg = """
            <svg viewBox="0 0 100 100" width="\(c.widthStr)" height="\(c.widthStr)" xmlns="http://www.w3.org/2000/svg">
                <line x1="0" y1="0" x2="50" y2="0" />
            </svg>
            """
            let doc = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
            #expect(doc.entities.count == 1)
            guard let line = doc.entities.first, let sp = line.startPoint, let ep = line.endPoint else {
                Issue.record("Missing line")
                continue
            }
            #expect(abs(sp.x) < 1e-4)
            #expect(abs(ep.x - c.expectedEndDistance) < 1e-3)
        }
    }

    @Test func testUnitOverrideSupersedesDocumentUnits() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <line x1="0" y1="0" x2="10" y2="0" />
        </svg>
        """
        // User overrides to inches: 10 units * 25.4 mm/in = 254 mm
        let options = SVGImportOptions(unitOverride: .inches, invertY: false)
        let doc = try SketchSVGImporter.importSVG(svgText: svg, options: options)
        guard let line = doc.entities.first, let ep = line.endPoint else {
            Issue.record("Missing line")
            return
        }
        #expect(abs(ep.x - 254.0) < 1e-4)
    }

    // MARK: - 3. Nested Group Affine Transforms

    @Test func testNestedGroupTransforms() throws {
        let svg = """
        <svg viewBox="0 0 200 200" width="200mm" height="200mm" xmlns="http://www.w3.org/2000/svg">
            <g transform="translate(50, 50)">
                <g transform="scale(2, 2)">
                    <line x1="0" y1="0" x2="10" y2="0" />
                </g>
            </g>
        </svg>
        """
        // InvertY: false to verify direct matrix algebra:
        // P_start = (0, 0) -> (50, 50)
        // P_end = (10, 0) -> scale(2) -> (20, 0) -> translate(50, 50) -> (70, 50)
        let doc = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
        #expect(doc.entities.count == 1)
        guard let line = doc.entities.first, let sp = line.startPoint, let ep = line.endPoint else {
            Issue.record("Missing line")
            return
        }
        #expect(abs(sp.x - 50.0) < 1e-4)
        #expect(abs(sp.y - 50.0) < 1e-4)
        #expect(abs(ep.x - 70.0) < 1e-4)
        #expect(abs(ep.y - 50.0) < 1e-4)
    }

    @Test func testRotateTransform() throws {
        let svg = """
        <svg viewBox="0 0 200 200" width="200mm" height="200mm" xmlns="http://www.w3.org/2000/svg">
            <g transform="rotate(90)">
                <line x1="10" y1="0" x2="20" y2="0" />
            </g>
        </svg>
        """
        // 90 deg rotation maps (x, y) to (-y, x).
        // (10, 0) -> (0, 10). (20, 0) -> (0, 20).
        let doc = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
        #expect(doc.entities.count == 1)
        guard let line = doc.entities.first, let sp = line.startPoint, let ep = line.endPoint else {
            Issue.record("Missing line")
            return
        }
        #expect(abs(sp.x) < 1e-4)
        #expect(abs(sp.y - 10.0) < 1e-4)
        #expect(abs(ep.x) < 1e-4)
        #expect(abs(ep.y - 20.0) < 1e-4)
    }

    // MARK: - 4. Layer Filtering and Visibility

    @Test func testLayerFilteringAndDisplayNone() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <g id="OUTLINE">
                <line x1="0" y1="0" x2="10" y2="0" />
            </g>
            <g id="DIMENSIONS">
                <line x1="0" y1="5" x2="10" y2="5" />
            </g>
            <g id="HIDDEN" display="none">
                <line x1="0" y1="10" x2="10" y2="10" />
            </g>
        </svg>
        """
        // Filter to OUTLINE only
        let doc = try SketchSVGImporter.importSVG(
            svgText: svg,
            options: SVGImportOptions(layerFilter: ["OUTLINE"])
        )
        #expect(doc.entities.count == 1)

        // Without filter, HIDDEN is still skipped because of display="none"
        let docAll = try SketchSVGImporter.importSVG(svgText: svg)
        #expect(docAll.entities.count == 2)
    }

    // MARK: - 5. Shapes Conversion

    @Test func testSharpRectGeneratesFourLines() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <rect x="10" y="10" width="40" height="30" />
        </svg>
        """
        let doc = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
        #expect(doc.entities.count == 4)
        for e in doc.entities {
            #expect(e.kind == "line")
        }
    }

    @Test func testRoundedRectGeneratesLinesAndArcs() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <rect x="10" y="10" width="40" height="30" rx="5" ry="5" />
        </svg>
        """
        let doc = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
        #expect(doc.entities.count == 8) // 4 lines + 4 corner arcs
        let lines = doc.entities.filter { $0.kind == "line" }
        let arcs = doc.entities.filter { $0.kind == "arc" }
        #expect(lines.count == 4)
        #expect(arcs.count == 4)
    }

    @Test func testCircleAndEllipse() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <circle cx="25" cy="25" r="10" />
            <ellipse cx="70" cy="50" rx="20" ry="10" />
        </svg>
        """
        let doc = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
        #expect(doc.entities.count == 2)
        let circle = try #require(doc.entities.first { $0.kind == "circle" })
        let ellipse = try #require(doc.entities.first { $0.kind == "ellipse" })

        #expect(abs((circle.data["radius"] ?? 0) - 10.0) < 1e-4)
        #expect(abs((ellipse.data["radiusX"] ?? 0) - 20.0) < 1e-4)
        #expect(abs((ellipse.data["radiusY"] ?? 0) - 10.0) < 1e-4)
    }

    @Test func testPolylineAndPolygon() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <polyline points="0,0 20,0 20,20" />
            <polygon points="50,50 80,50 80,80" />
        </svg>
        """
        let doc = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
        // Polyline: 3 points -> 2 lines
        // Polygon: 3 points -> 3 lines (includes closing line)
        #expect(doc.entities.count == 5)
    }

    // MARK: - 6. Path Commands and Bézier Discretization

    @Test func testPathLinearCommands() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <path d="M 10 10 H 50 V 40 L 60 50 Z" />
        </svg>
        """
        let doc = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
        #expect(doc.entities.count == 4)
        for e in doc.entities {
            #expect(e.kind == "line")
        }
    }

    @Test func testPathCubicAndQuadBezierDiscretization() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <path d="M 0 0 C 10 30, 40 30, 50 0 S 90 -30, 100 0" />
            <path d="M 0 50 Q 25 80, 50 50 T 100 50" />
        </svg>
        """
        let intervals = 16
        let doc = try SketchSVGImporter.importSVG(
            svgText: svg,
            options: SVGImportOptions(invertY: false, curveIntervals: intervals)
        )
        // Two cubic curves (C and S): 2 * 16 = 32 segments
        // Two quad curves (Q and T): 2 * 16 = 32 segments
        #expect(doc.entities.count == 64)
    }

    @Test func testPathEllipticalArcCenterConversion() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <path d="M 10 50 A 40 40 0 0 1 90 50" />
        </svg>
        """
        let doc = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(invertY: false))
        #expect(doc.entities.count == 1)
        guard let arc = doc.entities.first else {
            Issue.record("Missing arc entity")
            return
        }
        #expect(arc.kind == "arc")
        #expect(abs((arc.data["centerX"] ?? 0) - 50.0) < 1e-3)
        #expect(abs((arc.data["centerY"] ?? 0) - 50.0) < 1e-3)
    }

    // MARK: - 7. Construction Geometry Mapping

    @Test func testStrokeDasharrayAndConstructionLayers() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <line x1="0" y1="0" x2="10" y2="0" stroke-dasharray="2,2" />
            <g id="CONSTRUCTION">
                <line x1="0" y1="10" x2="10" y2="10" />
            </g>
            <line x1="0" y1="20" x2="10" y2="20" />
        </svg>
        """
        let doc = try SketchSVGImporter.importSVG(svgText: svg)
        #expect(doc.entities.count == 3)
        #expect(doc.entities[0].isConstruction == true)
        #expect(doc.entities[1].isConstruction == true)
        #expect(doc.entities[2].isConstruction == false)

        // With markAllConstruction = true
        let docAll = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(markAllConstruction: true))
        for e in docAll.entities {
            #expect(e.isConstruction == true)
        }
    }

    // MARK: - 8. Endpoint Welding and Constraints

    @Test func testEndpointWeldingSynthesizesCoincidentConstraints() throws {
        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <line x1="0" y1="0" x2="20" y2="0" />
            <line x1="20.0002" y1="0" x2="20" y2="20" />
            <line x1="20" y1="20" x2="0" y2="20" />
            <line x1="0" y1="20" x2="0" y2="0" />
        </svg>
        """
        // With welding: coincident vertex cluster at (20, 0) within 1e-3 mm tolerance welds and adds constraints
        let docWelded = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(weldEndpoints: true))
        #expect(docWelded.entities.count == 4)
        #expect(docWelded.constraints.count == 4)
        for c in docWelded.constraints {
            #expect(c.kind == .coincident)
        }

        // Without welding: 0 constraints
        let docUnwelded = try SketchSVGImporter.importSVG(svgText: svg, options: SVGImportOptions(weldEndpoints: false))
        #expect(docUnwelded.constraints.isEmpty)
    }

    // MARK: - 9. Malformed Input and Error Handling

    @Test func testEmptySVGThrowsEmptySketch() {
        #expect(throws: SketchError.self) {
            _ = try SketchSVGImporter.importSVG(svgText: "")
        }
    }

    @Test func testInvalidXMLWithoutEntitiesThrows() {
        #expect(throws: SketchError.self) {
            _ = try SketchSVGImporter.importSVG(svgText: "<invalid xml unclosed tag")
        }
    }
}
