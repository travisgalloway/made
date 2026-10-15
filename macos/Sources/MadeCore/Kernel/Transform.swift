import simd

public struct Transform: Sendable, Equatable, Codable {
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

extension simd_quatf: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case w, x, y, z
        case ix, iy, iz, r
    }

    public init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            guard unkeyed.count == 4 else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected 4 elements for quaternion vector [x, y, z, w]")
                )
            }
            let x = try unkeyed.decode(Float.self)
            let y = try unkeyed.decode(Float.self)
            let z = try unkeyed.decode(Float.self)
            let w = try unkeyed.decode(Float.self)
            self.init(ix: x, iy: y, iz: z, r: w)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let w = try container.decodeIfPresent(Float.self, forKey: .w)
            ?? container.decodeIfPresent(Float.self, forKey: .r)
            ?? 1.0
        let x = try container.decodeIfPresent(Float.self, forKey: .x)
            ?? container.decodeIfPresent(Float.self, forKey: .ix)
            ?? 0.0
        let y = try container.decodeIfPresent(Float.self, forKey: .y)
            ?? container.decodeIfPresent(Float.self, forKey: .iy)
            ?? 0.0
        let z = try container.decodeIfPresent(Float.self, forKey: .z)
            ?? container.decodeIfPresent(Float.self, forKey: .iz)
            ?? 0.0
        self.init(ix: x, iy: y, iz: z, r: w)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(real, forKey: .w)
        try container.encode(imag.x, forKey: .x)
        try container.encode(imag.y, forKey: .y)
        try container.encode(imag.z, forKey: .z)
    }
}

extension Transform {
    private enum CodingKeys: String, CodingKey {
        case position
        case rotation
        case scale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.position = try container.decodeIfPresent(SIMD3<Float>.self, forKey: .position) ?? SIMD3<Float>(0, 0, 0)
        self.rotation = try container.decodeIfPresent(simd_quatf.self, forKey: .rotation) ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        self.scale = try container.decodeIfPresent(SIMD3<Float>.self, forKey: .scale) ?? SIMD3<Float>(1, 1, 1)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(scale, forKey: .scale)
    }
}
