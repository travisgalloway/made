import Foundation
import simd

public enum Orientation {
    /// World Up axis: +Z (standard for CAD: AutoCAD, SketchUp, Blender, OpenCASCADE)
    public static let worldUp = SIMD3<Float>(0, 0, 1)
    
    /// Normal of the ground plane (Z = 0)
    public static let groundNormal = SIMD3<Float>(0, 0, 1)
    
    /// 3/4 view direction from front-right above (matching orientation.ts)
    public static let defaultViewDirection = simd_normalize(SIMD3<Float>(1, -1, 0.6))
    
    /// Constructs a right-handed view matrix where +Z is up, looking at `target` from `eye`.
    public static func makeLookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = worldUp) -> simd_float4x4 {
        let f = simd_normalize(target - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        
        var m = matrix_identity_float4x4
        m.columns.0 = SIMD4<Float>(s.x, u.x, -f.x, 0)
        m.columns.1 = SIMD4<Float>(s.y, u.y, -f.y, 0)
        m.columns.2 = SIMD4<Float>(s.z, u.z, -f.z, 0)
        m.columns.3 = SIMD4<Float>(
            -simd_dot(s, eye),
            -simd_dot(u, eye),
            simd_dot(f, eye),
            1
        )
        return m
    }
    
    /// Constructs a right-handed perspective projection matrix for Metal (NDC depth in [0, 1]).
    public static func makePerspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let ys = 1.0 / tan(fovyRadians * 0.5)
        let xs = ys / aspect
        let zs = farZ / (nearZ - farZ)
        
        var m = matrix_identity_float4x4
        m.columns.0 = SIMD4<Float>(xs, 0, 0, 0)
        m.columns.1 = SIMD4<Float>(0, ys, 0, 0)
        m.columns.2 = SIMD4<Float>(0, 0, zs, -1)
        m.columns.3 = SIMD4<Float>(0, 0, zs * nearZ, 0)
        return m
    }
}
