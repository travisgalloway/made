import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchGeometryGeneratorTests {

    @Test func testEmptyEntitiesProducesEmptyGeometry() {
        let geom = SketchGeometryGenerator.generateGeometry(entities: [], plane: .xy)
        #expect(geom.items.isEmpty)
        #expect(geom.positions.isEmpty)
        #expect(geom.colors.isEmpty)
        #expect(geom.vertexCount == 0)
    }

    @Test func testRegularLineProducesContinuousSegment() {
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 0), isConstruction: false)
        let geom = SketchGeometryGenerator.generateGeometry(entities: [line], plane: .xy)

        #expect(geom.items.count == 1)
        #expect(geom.items[0].kind == "line")
        #expect(geom.items[0].isConstruction == false)
        #expect(geom.items[0].dashFlag == false)
        #expect(geom.items[0].isDashed == false)
        #expect(geom.items[0].vertexCount == 2)
        #expect(geom.vertexCount == 2)

        // Check positions: (0, 0, 0) to (10, 0, 0)
        #expect(abs(geom.positions[0] - 0) < 1e-4)
        #expect(abs(geom.positions[1] - 0) < 1e-4)
        #expect(abs(geom.positions[2] - 0) < 1e-4)
        #expect(abs(geom.positions[3] - 10) < 1e-4)
        #expect(abs(geom.positions[4] - 0) < 1e-4)
        #expect(abs(geom.positions[5] - 0) < 1e-4)
    }

    @Test func testConstructionLineProducesDashedSegments() {
        // Line length 20. With dash 3 and gap 2, period = 5.
        // Dashes: [0..3], [5..8], [10..13], [15..18]. 4 dashes = 8 vertices.
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0), isConstruction: true)
        let geom = SketchGeometryGenerator.generateGeometry(
            entities: [line],
            plane: .xy,
            dashLength: 3.0,
            gapLength: 2.0
        )

        #expect(geom.items.count == 1)
        #expect(geom.items[0].isConstruction == true)
        #expect(geom.items[0].dashFlag == true)
        #expect(geom.items[0].isDashed == true)
        #expect(geom.items[0].vertexCount == 8)
        #expect(geom.vertexCount == 8)
    }

    @Test func testShortConstructionEntityEmitsAtLeastOneVisibleSegment() {
        // Line length 1.0 < dashLength 3.0
        let shortLine = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(1, 0), isConstruction: true)
        let geom = SketchGeometryGenerator.generateGeometry(
            entities: [shortLine],
            plane: .xy,
            dashLength: 3.0,
            gapLength: 2.0
        )

        #expect(geom.items.count == 1)
        #expect(geom.items[0].dashFlag == true)
        #expect(geom.items[0].vertexCount == 2)
        #expect(geom.vertexCount == 2)
        #expect(abs(geom.positions[3] - 1.0) < 1e-4)
    }

    @Test func testRegularArcDiscretizesIntoSegments() {
        let arc = SketchEntity.arc(
            start: SIMD2(10, 0),
            end: SIMD2(0, 10),
            center: SIMD2(0, 0),
            clockwise: false,
            isConstruction: false
        )
        let geom = SketchGeometryGenerator.generateGeometry(entities: [arc], plane: .xy)

        #expect(geom.items.count == 1)
        #expect(geom.items[0].kind == "arc")
        #expect(geom.items[0].isConstruction == false)
        #expect(geom.items[0].dashFlag == false)
        #expect(geom.items[0].vertexCount >= 8)
    }

    @Test func testConstructionArcDividesCleanlyIntoDashedSegments() {
        // Quarter arc with radius 20: arc length = 20 * pi / 2 = ~31.4
        let arc = SketchEntity.arc(
            start: SIMD2(20, 0),
            end: SIMD2(0, 20),
            center: SIMD2(0, 0),
            clockwise: false,
            isConstruction: true
        )
        let geom = SketchGeometryGenerator.generateGeometry(
            entities: [arc],
            plane: .xy,
            dashLength: 3.0,
            gapLength: 2.0
        )

        #expect(geom.items.count == 1)
        #expect(geom.items[0].kind == "arc")
        #expect(geom.items[0].isConstruction == true)
        #expect(geom.items[0].dashFlag == true)
        #expect(geom.items[0].vertexCount > 4)
    }

    @Test func testRegularCircleDiscretizesInto32Segments() {
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 10, isConstruction: false)
        let geom = SketchGeometryGenerator.generateGeometry(entities: [circle], plane: .xy)

        #expect(geom.items.count == 1)
        #expect(geom.items[0].kind == "circle")
        #expect(geom.items[0].dashFlag == false)
        #expect(geom.items[0].vertexCount == 64) // 32 line segments * 2 vertices
    }

    @Test func testConstructionCircleDividesCleanlyIntoDashedSegments() {
        // Circle with radius 10: circumference = 2 * pi * 10 = ~62.8
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 10, isConstruction: true)
        let geom = SketchGeometryGenerator.generateGeometry(
            entities: [circle],
            plane: .xy,
            dashLength: 3.0,
            gapLength: 2.0
        )

        #expect(geom.items.count == 1)
        #expect(geom.items[0].kind == "circle")
        #expect(geom.items[0].dashFlag == true)
        #expect(geom.items[0].isConstruction == true)
        #expect(geom.items[0].vertexCount > 8)
    }

    @Test func testDifferentPlanesUnprojectCorrectly() {
        let line = SketchEntity.line(start: SIMD2(5, 10), end: SIMD2(15, 20), isConstruction: false)

        // On XZ plane: unproject maps (u, v) -> origin + u*xAxis + v*yAxis
        let geomXZ = SketchGeometryGenerator.generateGeometry(entities: [line], plane: .xz)
        #expect(geomXZ.items.count == 1)
        let expectedP0 = SketchPlane.xz.unprojectPoint(SIMD2(5, 10))
        #expect(abs(geomXZ.positions[0] - expectedP0.x) < 1e-4)
        #expect(abs(geomXZ.positions[1] - expectedP0.y) < 1e-4)
        #expect(abs(geomXZ.positions[2] - expectedP0.z) < 1e-4)
    }
}
