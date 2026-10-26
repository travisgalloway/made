import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchPolygonTests {

    @Test func testRegularPolygonVertices() throws {
        // Triangle (3 sides)
        let tri = try SketchPolygon.makeRegularPolygon(center: SIMD2(0, 0), radius: 10, sides: 3)
        #expect(tri.vertices.count == 3)
        #expect(tri.entities.count == 3)

        // Hexagon (6 sides)
        let hex = try SketchPolygon.makeRegularPolygon(center: SIMD2(0, 0), radius: 20, sides: 6)
        #expect(hex.vertices.count == 6)
        #expect(hex.entities.count == 6)

        // Octagon (8 sides)
        let oct = try SketchPolygon.makeRegularPolygon(center: SIMD2(0, 0), radius: 25, sides: 8)
        #expect(oct.vertices.count == 8)
        #expect(oct.entities.count == 8)

        // Verify all entities are lines and form a closed chain
        for i in 0..<6 {
            let line = hex.entities[i]
            #expect(line.kind == "line")
            #expect(line.startPoint == hex.vertices[i])
            #expect(line.endPoint == hex.vertices[(i + 1) % 6])
        }
    }

    @Test func testInscribedVsCircumscribedRadius() throws {
        let r = 10.0
        let inscribedHex = try SketchPolygon.makeRegularPolygon(
            center: SIMD2(0, 0),
            radius: r,
            sides: 6,
            kind: .inscribed
        )
        let circumscribedHex = try SketchPolygon.makeRegularPolygon(
            center: SIMD2(0, 0),
            radius: r,
            sides: 6,
            kind: .circumscribed
        )

        // Inscribed vertex distance from center is exactly r
        let dIn = hypot(inscribedHex.vertices[0].x, inscribedHex.vertices[0].y)
        #expect(abs(dIn - r) < 1e-4)

        // Circumscribed vertex distance is r / cos(pi/6) = r / (sqrt(3)/2) > r
        let dCirc = hypot(circumscribedHex.vertices[0].x, circumscribedHex.vertices[0].y)
        let expectedR = r / cos(Double.pi / 6.0)
        #expect(abs(dCirc - expectedR) < 1e-4)
    }

    @Test func testDegeneratePolygonThrows() {
        // Less than 3 sides
        #expect(throws: SketchError.self) {
            try SketchPolygon.makeRegularPolygon(center: SIMD2(0, 0), radius: 10, sides: 2)
        }
        // More than 64 sides
        #expect(throws: SketchError.self) {
            try SketchPolygon.makeRegularPolygon(center: SIMD2(0, 0), radius: 10, sides: 65)
        }
        // Zero radius
        #expect(throws: SketchError.self) {
            try SketchPolygon.makeRegularPolygon(center: SIMD2(0, 0), radius: 0, sides: 5)
        }
    }

    @Test func testPolygonConstraints() throws {
        let sides = 5
        let poly = try SketchPolygon.makeRegularPolygon(center: SIMD2(0, 0), radius: 15, sides: sides)
        #expect(poly.constraints.count == sides)
        #expect(poly.constraints.allSatisfy { $0.kind == .coincident })
    }

    @Test func testPolygonExtrusionProfile() throws {
        let hex = try SketchPolygon.makeRegularPolygon(center: SIMD2(0, 0), radius: 20, sides: 6)
        let profile = try SketchProfileBuilder.build(from: hex.entities)
        #expect(profile.points.count == 6)
    }

    @Test func testGuideCircleConstructionFlag() throws {
        let poly = try SketchPolygon.makeRegularPolygon(
            center: SIMD2(0, 0),
            radius: 20,
            sides: 6,
            addGuideCircle: true
        )
        #expect(poly.entities.count == 7) // 6 lines + 1 guide circle
        let guide = try #require(poly.guideCircle)
        #expect(guide.isConstruction)
        #expect(guide.kind == "circle")

        // Profile builder ignores construction guide
        let profile = try SketchProfileBuilder.build(from: poly.entities)
        #expect(profile.points.count == 6)
    }
}
