import Testing
import Foundation
import simd
@testable import MadeCore

/// Pins the Spatial-backed matrices to their closed forms, so a convention change in Spatial fails here.
@Suite struct OrientationTests {
    private func assertEqual(_ a: simd_float4x4, _ b: simd_float4x4, accuracy: Float = 1e-5, sourceLocation: SourceLocation = #_sourceLocation) {
        for c in 0..<4 {
            for r in 0..<4 {
                #expect(abs(a[c][r] - b[c][r]) <= accuracy, "column \(c) row \(r)", sourceLocation: sourceLocation)
            }
        }
    }

    @Test func testPerspectiveMatchesMetalZeroToOneForm() {
        let fovy = Float.pi / 4, aspect: Float = 1.6, near: Float = 0.1, far: Float = 1000
        let ys = 1 / tan(fovy / 2)
        let zs = far / (near - far)
        let expected = simd_float4x4(
            SIMD4(ys / aspect, 0, 0, 0),
            SIMD4(0, ys, 0, 0),
            SIMD4(0, 0, zs, -1),
            SIMD4(0, 0, zs * near, 0)
        )
        assertEqual(Orientation.makePerspective(fovyRadians: fovy, aspect: aspect, nearZ: near, farZ: far), expected)
    }

    @Test func testPerspectiveMapsNearAndFarToDepthZeroAndOne() {
        let p = Orientation.makePerspective(fovyRadians: .pi / 4, aspect: 1, nearZ: 0.1, farZ: 1000)
        let nearClip = p * SIMD4<Float>(0, 0, -0.1, 1)
        let farClip = p * SIMD4<Float>(0, 0, -1000, 1)
        #expect(abs((nearClip.z / nearClip.w) - 0) <= 1e-5)
        #expect(abs((farClip.z / farClip.w) - 1) <= 1e-4)
    }

    @Test func testLookAtPutsEyeAtOriginAndTargetDownNegativeZ() {
        let eye = SIMD3<Float>(90, -90, 60), target = SIMD3<Float>(0, 0, 10)
        let view = Orientation.makeLookAt(eye: eye, target: target)
        let eyeInView = view * SIMD4<Float>(eye, 1)
        let targetInView = view * SIMD4<Float>(target, 1)
        #expect(abs(simd_length(SIMD3(eyeInView.x, eyeInView.y, eyeInView.z)) - 0) <= 1e-3)
        #expect(abs(targetInView.x - 0) <= 1e-3)
        #expect(abs(targetInView.y - 0) <= 1e-3)
        #expect(abs(targetInView.z - (-simd_length(target - eye))) <= 1e-3)
    }

    @Test func testLookAtKeepsWorldUpPointingUpOnScreen() {
        let view = Orientation.makeLookAt(eye: SIMD3(90, -90, 60), target: .zero)
        let up = view * SIMD4<Float>(Orientation.worldUp, 0)
        #expect(up.y > 0)
        #expect(abs(up.x - 0) <= 1e-5)
    }
}
