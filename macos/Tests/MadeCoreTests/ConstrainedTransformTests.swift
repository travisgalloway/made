import Testing
import Foundation
import simd
import CoreGraphics
@testable import MadeCore

@Suite struct ConstrainedTransformTests {
    private let width: CGFloat = 800
    private let height: CGFloat = 600

    @Test func testDominantAxisResolutionIsometric() throws {
        let viewportSize = CGSize(width: width, height: height)
        let eye = SIMD3<Float>(100, -100, 100)
        let target = SIMD3<Float>(0, 0, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: Float(width / height), nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix
        let origin = SIMD3<Float>(0, 0, 0)

        let screenOrigin = try #require(projectToScreen(point: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        let screenX = try #require(projectToScreen(point: origin + SIMD3<Float>(10, 0, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let screenY = try #require(projectToScreen(point: origin + SIMD3<Float>(0, 10, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let screenZ = try #require(projectToScreen(point: origin + SIMD3<Float>(0, 0, 10), viewProjectionMatrix: vp, viewportSize: viewportSize))

        // Sub-threshold drag returns nil
        let subThresholdDelta = simd_normalize(screenX - screenOrigin) * (mouseClickThresholdPx - 1.0)
        #expect(determineDominantAxis(deltaPointer: subThresholdDelta, origin: origin, viewProjectionMatrix: vp, viewportSize: viewportSize) == nil)

        // Drag along X projection
        let deltaX = (screenX - screenOrigin) * 2.0
        let axisX = try #require(determineDominantAxis(deltaPointer: deltaX, origin: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        #expect(axisX == .x)

        // Drag along Y projection
        let deltaY = (screenY - screenOrigin) * 2.0
        let axisY = try #require(determineDominantAxis(deltaPointer: deltaY, origin: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        #expect(axisY == .y)

        // Drag along Z projection
        let deltaZ = (screenZ - screenOrigin) * 2.0
        let axisZ = try #require(determineDominantAxis(deltaPointer: deltaZ, origin: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        #expect(axisZ == .z)
    }

    @Test func testDominantAxisResolutionTopView() throws {
        let viewportSize = CGSize(width: width, height: height)
        let eye = SIMD3<Float>(0, 0, 100)
        let target = SIMD3<Float>(0, 0, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: Float(width / height), nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix
        let origin = SIMD3<Float>(0, 0, 0)

        let screenOrigin = try #require(projectToScreen(point: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        let screenX = try #require(projectToScreen(point: origin + SIMD3<Float>(10, 0, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let screenY = try #require(projectToScreen(point: origin + SIMD3<Float>(0, 10, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))

        // In Top view, X and Y are visible in screen space, while Z projects to zero length
        let deltaX = (screenX - screenOrigin) * 2.0
        let axisX = try #require(determineDominantAxis(deltaPointer: deltaX, origin: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        #expect(axisX == .x)

        let deltaY = (screenY - screenOrigin) * 2.0
        let axisY = try #require(determineDominantAxis(deltaPointer: deltaY, origin: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        #expect(axisY == .y)
    }

    @Test func testDominantAxisResolutionFrontView() throws {
        let viewportSize = CGSize(width: width, height: height)
        let eye = SIMD3<Float>(0, -100, 0)
        let target = SIMD3<Float>(0, 0, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: Float(width / height), nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix
        let origin = SIMD3<Float>(0, 0, 0)

        let screenOrigin = try #require(projectToScreen(point: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        let screenX = try #require(projectToScreen(point: origin + SIMD3<Float>(10, 0, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let screenZ = try #require(projectToScreen(point: origin + SIMD3<Float>(0, 0, 10), viewProjectionMatrix: vp, viewportSize: viewportSize))

        // In Front view, X and Z are visible in screen space, while Y projects to zero length
        let deltaX = (screenX - screenOrigin) * 2.0
        let axisX = try #require(determineDominantAxis(deltaPointer: deltaX, origin: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        #expect(axisX == .x)

        let deltaZ = (screenZ - screenOrigin) * 2.0
        let axisZ = try #require(determineDominantAxis(deltaPointer: deltaZ, origin: origin, viewProjectionMatrix: vp, viewportSize: viewportSize))
        #expect(axisZ == .z)
    }

    @Test func testConstrainedAxisTranslationWithoutSnap() throws {
        let origin = SIMD3<Float>(0, 0, 0)
        let startRay = Ray3D(origin: SIMD3<Float>(0, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        let currentRay = Ray3D(origin: SIMD3<Float>(15, -50, 0), direction: SIMD3<Float>(0, 1, 0))

        let delta = computeConstrainedAxisTranslation(
            axis: .x,
            origin: origin,
            startRay: startRay,
            currentRay: currentRay,
            snap: nil
        )

        #expect(abs(delta.x - 15.0) < 1e-4)
        #expect(abs(delta.y) < 1e-4)
        #expect(abs(delta.z) < 1e-4)
    }

    @Test func testConstrainedAxisTranslationWithSnap() throws {
        let origin = SIMD3<Float>(10, 0, 0)
        let startRay = Ray3D(origin: SIMD3<Float>(10, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        let currentRay = Ray3D(origin: SIMD3<Float>(20, -50, 0), direction: SIMD3<Float>(0, 1, 0))
        let snapResult = SnapResult(kind: .vertex, point: SIMD3<Float>(35, 12, 8))

        let delta = computeConstrainedAxisTranslation(
            axis: .x,
            origin: origin,
            startRay: startRay,
            currentRay: currentRay,
            snap: snapResult
        )

        // Projection along X: (35 - 10) = 25
        #expect(abs(delta.x - 25.0) < 1e-4)
        #expect(abs(delta.y) < 1e-4)
        #expect(abs(delta.z) < 1e-4)
    }

    @Test func testConstrainedPlaneTranslationWithoutSnap() throws {
        let planeOrigin = SIMD3<Float>(0, 0, 10)
        let planeNormal = SIMD3<Float>(0, 0, 1)
        let startRay = Ray3D(origin: SIMD3<Float>(0, 0, 50), direction: SIMD3<Float>(0, 0, -1))
        let currentRay = Ray3D(origin: SIMD3<Float>(18, -12, 50), direction: SIMD3<Float>(0, 0, -1))

        let delta = computeConstrainedPlaneTranslation(
            planeOrigin: planeOrigin,
            planeNormal: planeNormal,
            startRay: startRay,
            currentRay: currentRay,
            snap: nil
        )

        #expect(abs(delta.x - 18.0) < 1e-4)
        #expect(abs(delta.y - (-12.0)) < 1e-4)
        #expect(abs(delta.z) < 1e-4, "Z elevation must remain strictly unperturbed on the horizontal plane")
    }

    @Test func testConstrainedPlaneTranslationWithSnap() throws {
        let planeOrigin = SIMD3<Float>(5, 5, 20)
        let planeNormal = SIMD3<Float>(0, 0, 1)
        let startRay = Ray3D(origin: SIMD3<Float>(5, 5, 50), direction: SIMD3<Float>(0, 0, -1))
        let currentRay = Ray3D(origin: SIMD3<Float>(10, 10, 50), direction: SIMD3<Float>(0, 0, -1))
        let snapResult = SnapResult(kind: .endpoint, point: SIMD3<Float>(40, 60, 99))

        let delta = computeConstrainedPlaneTranslation(
            planeOrigin: planeOrigin,
            planeNormal: planeNormal,
            startRay: startRay,
            currentRay: currentRay,
            snap: snapResult
        )

        // Delta should be snap.xy - planeOrigin.xy, with delta.z = 0
        #expect(abs(delta.x - 35.0) < 1e-4)
        #expect(abs(delta.y - 55.0) < 1e-4)
        #expect(abs(delta.z) < 1e-4, "Snap displacement must project strictly onto the horizontal plane")
    }

    @Test func testZeroKernelDispatchesDuringDrag() async throws {
        let engine = LocalKernelEngine()
        let kernel = KernelClient(engine: engine)
        let initialDispatched = await kernel.getStats().dispatched

        var transform = Transform(position: SIMD3<Float>(0, 0, 0))
        for step in 1...20 {
            let currentX = Float(step) * 2.0
            let delta = computeConstrainedAxisTranslation(
                axis: .x,
                origin: SIMD3<Float>(0, 0, 0),
                startRay: Ray3D(origin: SIMD3<Float>(0, -50, 0), direction: SIMD3<Float>(0, 1, 0)),
                currentRay: Ray3D(origin: SIMD3<Float>(currentX, -50, 0), direction: SIMD3<Float>(0, 1, 0)),
                snap: nil
            )
            transform.position = delta
        }

        let finalDispatched = await kernel.getStats().dispatched
        #expect(finalDispatched == initialDispatched, "Interactive constrained drag steps must issue zero kernel jobs")
    }
}
