import Foundation
import simd

/// Axis-aligned world-space bounds of the visible scene.
public struct SceneBounds: Sendable, Equatable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    public var center: SIMD3<Float> { (min + max) / 2 }
    public var radius: Float { simd_length(max - min) / 2 }

    /// Bounds of the given meshes, transformed by each mesh's full transform.
    /// Returns nil when no mesh has a vertex.
    public static func of(_ meshes: [CandidateMesh]) -> SceneBounds? {
        var lo = SIMD3<Float>(repeating: .infinity)
        var hi = SIMD3<Float>(repeating: -.infinity)
        var found = false
        for mesh in meshes {
            for p in mesh.positions {
                let w = mesh.transform.transformPoint(p)
                lo = simd_min(lo, w)
                hi = simd_max(hi, w)
                found = true
            }
        }
        return found ? SceneBounds(min: lo, max: hi) : nil
    }
}

extension Camera {
    /// Default step for the zoom-in and zoom-out buttons.
    public static let zoomStepFactor: Float = 0.8

    /// Keeps the view direction and moves the camera so the bounding sphere fits the narrower field of view,
    /// in perspective and in the renderer's orthographic projection, whose half-height is 0.4 of the distance.
    public static func framing(
        camera: Camera,
        bounds: SceneBounds,
        fovyRadians: Float = Float.pi / 4.0,
        aspect: Float,
        margin: Float = 1.15
    ) -> Camera {
        var offset = camera.position - camera.target
        if simd_length(offset) < 1e-6 { offset = Orientation.defaultViewDirection }
        let direction = simd_normalize(offset)

        let halfV = fovyRadians / 2
        let halfH = atan(tan(halfV) * Swift.max(aspect, 1e-3))
        let halfAngle = Swift.min(halfV, halfH)
        let radius = Swift.max(bounds.radius, 1e-3)
        let perspectiveDistance = radius / sin(halfAngle)
        let orthographicDistance = radius / (0.4 * Swift.min(Swift.max(aspect, 1e-3), 1))
        let fitted = Swift.max(perspectiveDistance, orthographicDistance) * margin
        let distance = Swift.min(Swift.max(fitted, camera.minDistance), camera.maxDistance)

        var result = camera
        result.target = bounds.center
        result.position = bounds.center + direction * distance
        return result
    }
}
