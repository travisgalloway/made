import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct BoundingBoxTests {

    @Test func test10x20x30BoxIdentityOrientation() {
        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 20, height: 30)
        let mesh = CandidateMesh(id: SolidId("box-identity"), payload: payload, transform: .identity)

        let result = BoundingBoxCalculator.boxes(for: mesh)
        #expect(result != nil)

        guard let (aabb, obb) = result else { return }

        // AABB
        #expect(abs(aabb.size.x - 10.0) < 0.01)
        #expect(abs(aabb.size.y - 20.0) < 0.01)
        #expect(abs(aabb.size.z - 30.0) < 0.01)
        #expect(abs(aabb.volume - 6000.0) < 0.1)
        #expect(abs(aabb.center.x) < 0.01)
        #expect(abs(aabb.center.y) < 0.01)
        #expect(abs(aabb.center.z) < 0.01)

        // OBB
        let obbDims = obb.sortedDimensions
        #expect(abs(obbDims.x - 10.0) < 0.01)
        #expect(abs(obbDims.y - 20.0) < 0.01)
        #expect(abs(obbDims.z - 30.0) < 0.01)
        #expect(abs(obb.volume - 6000.0) < 0.1)
        #expect(abs(obb.center.x) < 0.01)
        #expect(abs(obb.center.y) < 0.01)
        #expect(abs(obb.center.z) < 0.01)
    }

    @Test func test10x20x30BoxRotated45Degrees() {
        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 20, height: 30)
        let rot = simd_quatf(angle: .pi / 4.0, axis: SIMD3<Float>(0, 0, 1))
        let transform = Transform(position: SIMD3<Float>(0, 0, 0), rotation: rot, scale: SIMD3<Float>(1, 1, 1))
        let mesh = CandidateMesh(id: SolidId("box-45deg"), payload: payload, transform: transform)

        let result = BoundingBoxCalculator.boxes(for: mesh)
        #expect(result != nil)

        guard let (aabb, obb) = result else { return }

        // Rotated 45 degrees around Z: width along X & Y is (10 + 20) / sqrt(2) ~= 21.2132
        // AABB volume ~= 21.2132 * 21.2132 * 30 = 450 * 30 = 13500
        #expect(abs(aabb.volume - 13500.0) < 10.0)

        // OBB volume should remain optimal minimum-volume 6000
        #expect(abs(obb.volume - 6000.0) < 0.1)

        let obbDims = obb.sortedDimensions
        #expect(abs(obbDims.x - 10.0) < 0.01)
        #expect(abs(obbDims.y - 20.0) < 0.01)
        #expect(abs(obbDims.z - 30.0) < 0.01)

        // OBB volume is strictly smaller than AABB volume
        #expect(obb.volume < aabb.volume)
    }

    @Test func test10x20x30BoxCompound3DRotation() {
        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 20, height: 30)
        let q1 = simd_quatf(angle: .pi / 6.0, axis: SIMD3<Float>(1, 0, 0))
        let q2 = simd_quatf(angle: .pi / 4.0, axis: SIMD3<Float>(0, 1, 0))
        let q3 = simd_quatf(angle: .pi / 3.0, axis: SIMD3<Float>(0, 0, 1))
        let compoundRot = simd_normalize(q3 * q2 * q1)
        let transform = Transform(
            position: SIMD3<Float>(15, -25, 40),
            rotation: compoundRot,
            scale: SIMD3<Float>(1, 1, 1)
        )
        let mesh = CandidateMesh(id: SolidId("box-compound"), payload: payload, transform: transform)

        let result = BoundingBoxCalculator.boxes(for: mesh)
        #expect(result != nil)

        guard let (aabb, obb) = result else { return }

        let obbDims = obb.sortedDimensions
        #expect(abs(obbDims.x - 10.0) < 0.01)
        #expect(abs(obbDims.y - 20.0) < 0.01)
        #expect(abs(obbDims.z - 30.0) < 0.01)
        #expect(abs(obb.volume - 6000.0) < 1.0)
        #expect(obb.volume < aabb.volume)

        #expect(abs(obb.center.x - 15.0) < 0.01)
        #expect(abs(obb.center.y - (-25.0)) < 0.01)
        #expect(abs(obb.center.z - 40.0) < 0.01)
    }

    @Test func testPlanarBodyZeroThickness() {
        let planarPoints: [SIMD3<Double>] = [
            SIMD3<Double>(-5, -10, 0),
            SIMD3<Double>( 5, -10, 0),
            SIMD3<Double>( 5,  10, 0),
            SIMD3<Double>(-5,  10, 0)
        ]

        let result = BoundingBoxCalculator.boxes(for: planarPoints)
        #expect(result != nil)

        guard let (aabb, obb) = result else { return }

        #expect(aabb.size.z == 0.0)
        #expect(aabb.volume == 0.0)

        let obbDims = obb.sortedDimensions
        #expect(obbDims.x == 0.0)
        #expect(abs(obbDims.y - 10.0) < 0.01)
        #expect(abs(obbDims.z - 20.0) < 0.01)
        #expect(obb.volume == 0.0)
    }

    @Test func testFarFromOriginPrecision() {
        let offset = SIMD3<Double>(1_000_000.0, 1_000_000.0, 1_000_000.0)
        let points: [SIMD3<Double>] = [
            offset + SIMD3<Double>(-5, -10, -15),
            offset + SIMD3<Double>( 5, -10, -15),
            offset + SIMD3<Double>( 5,  10, -15),
            offset + SIMD3<Double>(-5,  10, -15),
            offset + SIMD3<Double>(-5, -10,  15),
            offset + SIMD3<Double>( 5, -10,  15),
            offset + SIMD3<Double>( 5,  10,  15),
            offset + SIMD3<Double>(-5,  10,  15)
        ]

        let result = BoundingBoxCalculator.boxes(for: points)
        #expect(result != nil)

        guard let (aabb, obb) = result else { return }

        // Coordinates at 1,000,000 mm maintain precision to 0.001 mm
        #expect(abs(aabb.size.x - 10.0) < 0.001)
        #expect(abs(aabb.size.y - 20.0) < 0.001)
        #expect(abs(aabb.size.z - 30.0) < 0.001)

        let obbDims = obb.sortedDimensions
        #expect(abs(obbDims.x - 10.0) < 0.001)
        #expect(abs(obbDims.y - 20.0) < 0.001)
        #expect(abs(obbDims.z - 30.0) < 0.001)

        #expect(abs(obb.center.x - 1_000_000.0) < 0.001)
        #expect(abs(obb.center.y - 1_000_000.0) < 0.001)
        #expect(abs(obb.center.z - 1_000_000.0) < 0.001)
    }

    @Test func testEmptyBodyReturnsNil() {
        #expect(BoundingBoxCalculator.boxes(for: []) == nil)

        let emptyMesh = CandidateMesh(id: SolidId("empty"), positions: [], edges: [])
        #expect(BoundingBoxCalculator.boxes(for: emptyMesh) == nil)
    }

    @Test func testDictionarySerialization() {
        let aabb = AxisAlignedBoundingBox(min: SIMD3<Double>(-5, -10, -15), max: SIMD3<Double>(5, 10, 15))
        let aabbDict = aabb.toDictionary()
        #expect(aabbDict["volume"] as? Double == 6000.0)

        let obb = OrientedBoundingBox(
            center: SIMD3<Double>(0, 0, 0),
            axes: [SIMD3<Double>(1, 0, 0), SIMD3<Double>(0, 1, 0), SIMD3<Double>(0, 0, 1)],
            size: SIMD3<Double>(10, 20, 30)
        )
        let obbDict = obb.toDictionary()
        #expect(obbDict["volume"] as? Double == 6000.0)
        #expect((obbDict["axes"] as? [[Double]])?.count == 3)
    }
}
