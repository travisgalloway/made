import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchEllipseTests {

    @Test func testEllipseEntityProperties() throws {
        let center = SIMD2<Double>(10, 20)
        let rx = 30.0
        let ry = 15.0
        let rot = Double.pi / 4.0
        let res = try SketchEllipse.makeEllipse(center: center, radiusX: rx, radiusY: ry, rotation: rot, addAxes: true)

        #expect(res.entities.count == 3) // 1 ellipse + 2 construction axes
        let ellipse = res.entities[0]
        #expect(ellipse.kind == "ellipse")
        #expect(ellipse.centerPoint == center)
        #expect(ellipse.radiusX == rx)
        #expect(ellipse.radiusY == ry)
        #expect(ellipse.rotationAngle == rot)
        #expect(!ellipse.isConstruction)

        let axes = res.entities.filter { $0.isConstruction }
        #expect(axes.count == 2)
        #expect(axes.allSatisfy { $0.kind == "line" })
    }

    @Test func testEllipticalArcProperties() throws {
        let center = SIMD2<Double>(0, 0)
        let rx = 20.0
        let ry = 10.0
        let startAngle = 0.0
        let endAngle = Double.pi
        let res = try SketchEllipse.makeEllipticalArc(
            center: center,
            radiusX: rx,
            radiusY: ry,
            rotation: 0.0,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        #expect(res.entities.count == 1)
        let arc = res.entities[0]
        #expect(arc.kind == "ellipticalArc")
        #expect(arc.centerPoint == center)
        #expect(arc.radiusX == rx)
        #expect(arc.radiusY == ry)
        #expect(arc.startAngle == startAngle)
        #expect(arc.endAngle == endAngle)
        #expect(!arc.isClockwise)

        let sp = try #require(arc.startPoint)
        let ep = try #require(arc.endPoint)
        #expect(abs(sp.x - 20.0) < 1e-4 && abs(sp.y) < 1e-4)
        #expect(abs(ep.x - (-20.0)) < 1e-4 && abs(ep.y) < 1e-4)
    }

    @Test func testDegenerateEllipseThrows() {
        // Zero radiusX
        #expect(throws: SketchError.self) {
            try SketchEllipse.makeEllipse(center: SIMD2(0, 0), radiusX: 0, radiusY: 10)
        }
        // Zero radiusY
        #expect(throws: SketchError.self) {
            try SketchEllipse.makeEllipse(center: SIMD2(0, 0), radiusX: 10, radiusY: 0)
        }
        // Negative radius
        #expect(throws: SketchError.self) {
            try SketchEllipse.makeEllipse(center: SIMD2(0, 0), radiusX: -5, radiusY: 10)
        }
        // Degenerate elliptical arc span 0
        #expect(throws: SketchError.self) {
            try SketchEllipse.makeEllipticalArc(
                center: SIMD2(0, 0),
                radiusX: 10,
                radiusY: 5,
                startAngle: 1.0,
                endAngle: 1.0
            )
        }
    }

    @Test func testSingleEllipseExtrusionProfile() throws {
        let ellipse = try SketchEllipse.makeEllipse(center: SIMD2(0, 0), radiusX: 25, radiusY: 15, rotation: 0.5)
        let profile = try SketchProfileBuilder.build(from: ellipse.entities)
        #expect(profile.points.count == 32)
    }

    @Test func testEllipseWireframeGeneration() throws {
        let ellipse = SketchEntity.ellipse(center: SIMD2(0, 0), radiusX: 20, radiusY: 10)
        let dashedEllipse = SketchEntity.ellipse(center: SIMD2(0, 0), radiusX: 20, radiusY: 10, isConstruction: true)
        let arc = SketchEntity.ellipticalArc(
            center: SIMD2(0, 0),
            radiusX: 20,
            radiusY: 10,
            startAngle: 0,
            endAngle: .pi
        )
        let dashedArc = SketchEntity.ellipticalArc(
            center: SIMD2(0, 0),
            radiusX: 20,
            radiusY: 10,
            startAngle: 0,
            endAngle: .pi,
            isConstruction: true
        )

        let geom1 = SketchGeometryGenerator.generateGeometry(entities: [ellipse])
        #expect(!geom1.positions.isEmpty)

        let geom2 = SketchGeometryGenerator.generateGeometry(entities: [dashedEllipse])
        #expect(!geom2.positions.isEmpty)

        let geom3 = SketchGeometryGenerator.generateGeometry(entities: [arc])
        #expect(!geom3.positions.isEmpty)

        let geom4 = SketchGeometryGenerator.generateGeometry(entities: [dashedArc])
        #expect(!geom4.positions.isEmpty)
    }

    @Test @MainActor func testCADAddSketchEntityEllipseAndArc() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let sketch = doc.addSketchFeature(planeName: "xy", entities: [])

        // Add ellipse via MCP tool
        let ellipseArgs: [String: AnyCodableValue] = [
            "sketchId": .string(sketch.id.uuidString),
            "type": .string("ellipse"),
            "centerX": .double(10.0),
            "centerY": .double(20.0),
            "radiusX": .double(30.0),
            "radiusY": .double(15.0),
            "rotationAngle": .double(0.5)
        ]
        let ellipseResult = await registry.callTool(name: "cad_add_sketch_entity", arguments: ellipseArgs)
        #expect(ellipseResult.isError == false)

        // Add elliptical arc via MCP tool
        let arcArgs: [String: AnyCodableValue] = [
            "sketchId": .string(sketch.id.uuidString),
            "type": .string("ellipticalArc"),
            "centerX": .double(0.0),
            "centerY": .double(0.0),
            "radiusX": .double(25.0),
            "radiusY": .double(12.0),
            "startAngle": .double(0.0),
            "endAngle": .double(Double.pi)
        ]
        let arcResult = await registry.callTool(name: "cad_add_sketch_entity", arguments: arcArgs)
        #expect(arcResult.isError == false)

        let feat = try #require(doc.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 2)
            #expect(data.entities[0].kind == "ellipse")
            #expect(data.entities[1].kind == "ellipticalArc")
        } else {
            Issue.record("Expected sketch operation")
        }
    }
}
