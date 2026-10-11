import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct CameraFramingTests {
    private func cube(_ id: String, half: Float, at position: SIMD3<Float>) -> CandidateMesh {
        var pts: [SIMD3<Float>] = []
        for x in [-half, half] { for y in [-half, half] { for z in [-half, half] { pts.append(SIMD3(x, y, z)) } } }
        return CandidateMesh(id: SolidId(id), positions: pts, edges: [], transform: Transform(position: position))
    }

    @Test func testBoundsIncludeEachMeshTranslation() throws {
        let bounds = try #require(SceneBounds.of([cube("a", half: 5, at: SIMD3(-20, 0, 0)), cube("b", half: 5, at: SIMD3(20, 0, 0))]))
        #expect(bounds.min == SIMD3(-25, -5, -5))
        #expect(bounds.max == SIMD3(25, 5, 5))
        #expect(bounds.center == SIMD3(0, 0, 0))
    }

    @Test func testBoundsOfAnEmptySceneAreNil() {
        #expect(SceneBounds.of([]) == nil)
        #expect(SceneBounds.of([CandidateMesh(id: SolidId("e"), positions: [], edges: [])]) == nil)
    }

    @Test func testFramingCentresTargetAndKeepsViewDirection() {
        let start = Camera()
        let bounds = SceneBounds(min: SIMD3(10, 10, 0), max: SIMD3(30, 50, 20))
        let framed = Camera.framing(camera: start, bounds: bounds, aspect: 4.0 / 3.0)
        #expect(framed.target == bounds.center)
        let before = simd_normalize(start.position - start.target)
        let after = simd_normalize(framed.position - framed.target)
        #expect(abs(simd_dot(before, after) - 1) <= 1e-5)
    }

    @Test func testFramedSphereFitsBothFieldsOfView() {
        let bounds = SceneBounds(min: SIMD3(-20, -20, -20), max: SIMD3(20, 20, 20))
        let fovy = Float.pi / 4
        for aspect: Float in [0.5, 1, 2] {
            let framed = Camera.framing(camera: Camera(), bounds: bounds, fovyRadians: fovy, aspect: aspect, margin: 1)
            let distance = simd_length(framed.position - framed.target)
            let halfH = atan(tan(fovy / 2) * aspect)
            let angular = asin(bounds.radius / distance)
            #expect(angular <= (min(fovy / 2, halfH) + 1e-4), "aspect \(aspect)")
            // The orthographic half-extents are 0.4 of the distance.
            #expect((distance * 0.4 * min(1, aspect)) >= (bounds.radius * 0.99), "aspect \(aspect)")
        }
    }

    @Test func testFramingClampsToCameraDistanceLimits() {
        let tiny = SceneBounds(min: SIMD3(repeating: -0.01), max: SIMD3(repeating: 0.01))
        let huge = SceneBounds(min: SIMD3(repeating: -5000), max: SIMD3(repeating: 5000))
        let camera = Camera()
        #expect(abs(simd_length(Camera.framing(camera: camera, bounds: tiny, aspect: 1).position - tiny.center) - camera.minDistance) <= 1e-4)
        #expect(abs(simd_length(Camera.framing(camera: camera, bounds: huge, aspect: 1).position - huge.center) - camera.maxDistance) <= 1e-2)
    }
}
