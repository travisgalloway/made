import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchSlotTests {

    @Test func testStraightSlotGeometryAndConstraints() throws {
        let c1 = SIMD2<Double>(0, 0)
        let c2 = SIMD2<Double>(40, 0)
        let width = 10.0
        let result = try SketchSlot.makeStraightSlot(center1: c1, center2: c2, width: width, addCenterline: true)

        #expect(result.entities.count == 5) // 2 lines + 2 arcs + 1 centerline
        #expect(result.centerline != nil)
        #expect(result.centerline?.isConstruction == true)

        let perimeter = result.entities.filter { !$0.isConstruction }
        #expect(perimeter.count == 4)

        let lines = perimeter.filter { $0.kind == "line" }
        let arcs = perimeter.filter { $0.kind == "arc" }
        #expect(lines.count == 2)
        #expect(arcs.count == 2)

        // Constraints
        let coincidents = result.constraints.filter { $0.kind == .coincident }
        let tangents = result.constraints.filter { $0.kind == .tangent }
        let parallels = result.constraints.filter { $0.kind == .parallel }
        #expect(coincidents.count == 4)
        #expect(tangents.count == 4)
        #expect(parallels.count == 1)

        // Arc radius is half width
        for arc in arcs {
            let r = try #require(arc.radius)
            #expect(abs(r - 5.0) < 1e-4)
        }
    }

    @Test func testArcSlotConcentricityAndTangency() throws {
        let center = SIMD2<Double>(0, 0)
        let radius = 30.0
        let startAngle = 0.0
        let endAngle = Double.pi
        let width = 10.0
        let result = try SketchSlot.makeArcSlot(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            width: width,
            addCenterline: true
        )

        #expect(result.entities.count == 5) // 2 concentric arcs + 2 end caps + 1 centerline
        #expect(result.centerline != nil)
        #expect(result.centerline?.isConstruction == true)

        let perimeter = result.entities.filter { !$0.isConstruction }
        #expect(perimeter.count == 4)
        #expect(perimeter.allSatisfy { $0.kind == "arc" })

        let coincidents = result.constraints.filter { $0.kind == .coincident }
        let concentrics = result.constraints.filter { $0.kind == .concentric }
        let tangents = result.constraints.filter { $0.kind == .tangent }
        #expect(coincidents.count == 4)
        #expect(concentrics.count == 1)
        #expect(tangents.count == 4)

        // Radii: inner is 25, outer is 35, end caps are 5
        let concentricArcs = perimeter.filter { $0.centerPoint == center }
        #expect(concentricArcs.count == 2)
        let r0 = try #require(concentricArcs[0].radius)
        let r1 = try #require(concentricArcs[1].radius)
        #expect((abs(r0 - 25.0) < 1e-4 && abs(r1 - 35.0) < 1e-4) || (abs(r0 - 35.0) < 1e-4 && abs(r1 - 25.0) < 1e-4))
    }

    @Test func testDegenerateSlotThrows() {
        // Zero width straight slot
        #expect(throws: SketchError.self) {
            try SketchSlot.makeStraightSlot(center1: SIMD2(0, 0), center2: SIMD2(10, 0), width: 0.0)
        }
        // Coincident centers straight slot
        #expect(throws: SketchError.self) {
            try SketchSlot.makeStraightSlot(center1: SIMD2(5, 5), center2: SIMD2(5, 5), width: 10.0)
        }
        // Arc slot radius <= width/2
        #expect(throws: SketchError.self) {
            try SketchSlot.makeArcSlot(center: SIMD2(0, 0), radius: 5.0, startAngle: 0, endAngle: .pi, width: 10.0)
        }
        // Arc slot span 0
        #expect(throws: SketchError.self) {
            try SketchSlot.makeArcSlot(center: SIMD2(0, 0), radius: 20.0, startAngle: 1.0, endAngle: 1.0, width: 10.0)
        }
    }

    @Test func testStraightSlotExtrusionProfile() throws {
        let slot = try SketchSlot.makeStraightSlot(center1: SIMD2(0, 0), center2: SIMD2(40, 0), width: 12.0)
        let profile = try SketchProfileBuilder.build(from: slot.entities)
        #expect(profile.points.count >= 20)
    }

    @Test func testArcSlotExtrusionProfile() throws {
        let slot = try SketchSlot.makeArcSlot(
            center: SIMD2(0, 0),
            radius: 30.0,
            startAngle: 0.0,
            endAngle: Double.pi,
            width: 10.0
        )
        let profile = try SketchProfileBuilder.build(from: slot.entities)
        #expect(profile.points.count >= 20)
    }

    @Test func testCenterlineConstructionFlag() throws {
        let slot = try SketchSlot.makeStraightSlot(
            center1: SIMD2(0, 0),
            center2: SIMD2(30, 0),
            width: 10.0,
            addCenterline: true
        )
        let cl = try #require(slot.centerline)
        #expect(cl.isConstruction)

        // Profile builder should ignore the centerline and succeed with a closed loop
        let profile = try SketchProfileBuilder.build(from: slot.entities)
        #expect(!profile.points.isEmpty)
    }
}
