import simd

public struct Transform: Sendable, Equatable {
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: SIMD3<Float>
    
    public static let identity = Transform(
        position: SIMD3<Float>(0, 0, 0),
        rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        scale: SIMD3<Float>(1, 1, 1)
    )
    
    public init(
        position: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
    
    public func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let scaled = point * scale
        let rotated = rotation.act(scaled)
        return rotated + position
    }

    public var matrix: simd_float4x4 {
        var m = simd_float4x4(rotation)
        m.columns.0 *= scale.x
        m.columns.1 *= scale.y
        m.columns.2 *= scale.z
        m.columns.3 = SIMD4<Float>(position, 1.0)
        return m
    }

    public var normalMatrix: simd_float3x3 {
        guard abs(scale.x) > 1e-6, abs(scale.y) > 1e-6, abs(scale.z) > 1e-6,
              abs(scale.x * scale.y * scale.z) >= 1e-6 else {
            return simd_float3x3(rotation)
        }
        var m = simd_float3x3(rotation)
        m.columns.0 *= (1.0 / scale.x)
        m.columns.1 *= (1.0 / scale.y)
        m.columns.2 *= (1.0 / scale.z)
        return m
    }
}
