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
}
