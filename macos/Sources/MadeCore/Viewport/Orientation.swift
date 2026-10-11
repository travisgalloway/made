import Foundation
import simd
import Spatial

public enum Orientation {
    /// World Up axis: +Z (standard for CAD: AutoCAD, SketchUp, Blender, OpenCASCADE)
    public static let worldUp = SIMD3<Float>(0, 0, 1)
    
    /// Normal of the ground plane (Z = 0)
    public static let groundNormal = SIMD3<Float>(0, 0, 1)
    
    /// 3/4 view direction from front-right above (matching orientation.ts)
    public static let defaultViewDirection = simd_normalize(SIMD3<Float>(1, -1, 0.6))
    
    /// Right-handed view matrix for a camera at `eye` looking at `target`.
    /// Spatial's pose faces +Z toward its target, and a view looks down -Z, so the pose aims away from `target`.
    public static func makeLookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = worldUp) -> simd_float4x4 {
        var up = up
        if simd_length_squared(simd_cross(simd_normalize(target - eye), up)) < 1e-6 {
            // Looking along the up vector is singular, so fall back to another up axis.
            up = abs(up.z) > 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(0, 0, 1)
        }
        let pose = Pose3D(position: Point3D(eye), target: Point3D(eye + (eye - target)), up: Vector3D(up))
        return simd_float4x4(pose.matrix.inverse)
    }
    
    /// Right-handed perspective projection for Metal (NDC depth in [0, 1]), from Spatial.
    public static func makePerspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let projection = ProjectiveTransform3D(
            fovY: Angle2D(radians: Double(fovyRadians)),
            aspectRatio: Double(aspect),
            nearZ: Double(nearZ),
            farZ: Double(farZ),
            reverseZ: false
        )
        return simd_float4x4(projection.matrix)
    }
    
    /// Constructs a right-handed orthographic projection matrix for Metal (NDC depth in [0, 1]).
    public static func makeOrthographic(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let xs = 2.0 / (right - left)
        let ys = 2.0 / (top - bottom)
        let zs = 1.0 / (nearZ - farZ)
        
        var m = matrix_identity_float4x4
        m.columns.0 = SIMD4<Float>(xs, 0, 0, 0)
        m.columns.1 = SIMD4<Float>(0, ys, 0, 0)
        m.columns.2 = SIMD4<Float>(0, 0, zs, 0)
        m.columns.3 = SIMD4<Float>(
            -(right + left) / (right - left),
            -(top + bottom) / (top - bottom),
            zs * nearZ,
            1.0
        )
        return m
    }
}

extension simd_float4x4 {
    init(_ m: simd_double4x4) {
        self.init(SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1), SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3))
    }
}
