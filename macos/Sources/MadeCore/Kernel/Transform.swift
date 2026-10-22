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

    /// Composes two transforms such that `(lhs * rhs).transformPoint(p) == lhs.transformPoint(rhs.transformPoint(p))`.
    public static func * (lhs: Transform, rhs: Transform) -> Transform {
        let scaledPos = lhs.scale * rhs.position
        let rotatedPos = lhs.rotation.act(scaledPos)
        let newPos = lhs.position + rotatedPos
        let newRot = simd_normalize(lhs.rotation * rhs.rotation)
        let newScale = lhs.scale * rhs.scale
        return Transform(position: newPos, rotation: newRot, scale: newScale)
    }

    /// Computes the inverse transform.
    public var inverse: Transform {
        let invRot = rotation.conjugate
        let invScale = SIMD3<Float>(
            abs(scale.x) > 1e-6 ? 1.0 / scale.x : 1.0,
            abs(scale.y) > 1e-6 ? 1.0 / scale.y : 1.0,
            abs(scale.z) > 1e-6 ? 1.0 / scale.z : 1.0
        )
        let invPos = invRot.act(-position) * invScale
        return Transform(position: invPos, rotation: invRot, scale: invScale)
    }

    /// Computes a step transform for a linear pattern along a direction vector.
    public static func linearStepTransform(direction: SIMD3<Float>, spacing: Float, index: Int) -> Transform {
        guard simd_length_squared(direction) > 1e-12 else {
            return .identity
        }
        let normDir = simd_normalize(direction)
        return Transform(position: normDir * (spacing * Float(index)))
    }

    /// Computes a step transform for a circular pattern around an axis.
    public static func circularStepTransform(axisOrigin: SIMD3<Float>, axisDirection: SIMD3<Float>, angleRadians: Float) -> Transform {
        guard simd_length_squared(axisDirection) > 1e-12 else {
            return .identity
        }
        let normAxis = simd_normalize(axisDirection)
        let quat = simd_quatf(angle: angleRadians, axis: normAxis)
        let pos = axisOrigin - quat.act(axisOrigin)
        return Transform(position: pos, rotation: quat)
    }

    /// Computes the mirrored transform across a plane specified by origin and normal.
    public func mirrored(
        planeOrigin: SIMD3<Float>,
        planeNormal: SIMD3<Float>,
        mode: ComponentMirrorMode = .symmetricReorient
    ) -> Transform {
        guard simd_length_squared(planeNormal) > 1e-12 else {
            return self
        }
        let n = simd_normalize(planeNormal)
        let newPos = position - 2.0 * simd_dot(position - planeOrigin, n) * n

        switch mode {
        case .symmetricReorient:
            let rotMat = simd_float3x3(rotation)
            let c0 = 2.0 * n * simd_dot(n, rotMat.columns.0) - rotMat.columns.0
            let c1 = 2.0 * n * simd_dot(n, rotMat.columns.1) - rotMat.columns.1
            let c2 = 2.0 * n * simd_dot(n, rotMat.columns.2) - rotMat.columns.2
            let reflectedRotMat = simd_float3x3(columns: (c0, c1, c2))
            let newRot = simd_quatf(reflectedRotMat)
            return Transform(position: newPos, rotation: simd_normalize(newRot), scale: scale)

        case .oppositeHand:
            let newScale = SIMD3<Float>(scale.x, scale.y, -scale.z)
            return Transform(position: newPos, rotation: rotation, scale: newScale)
        }
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

    /// Constructs a rotation from Euler angles (in degrees, applied in order Rx, Ry, Rz -> Rz * Ry * Rx).
    public static func fromEulerAngles(degrees: SIMD3<Float>) -> simd_quatf {
        let degToRad = Float.pi / 180.0
        let qx = simd_quatf(angle: degrees.x * degToRad, axis: SIMD3<Float>(1, 0, 0))
        let qy = simd_quatf(angle: degrees.y * degToRad, axis: SIMD3<Float>(0, 1, 0))
        let qz = simd_quatf(angle: degrees.z * degToRad, axis: SIMD3<Float>(0, 0, 1))
        return qz * qy * qx
    }

    /// Extracts Euler angles (in degrees) assuming Rz * Ry * Rx convention.
    public var eulerAnglesDegrees: SIMD3<Float> {
        let m = simd_float3x3(self)
        let radToDeg = 180.0 / Float.pi

        let pitch: Float
        let yaw: Float
        let roll: Float

        if abs(m.columns.0.z) < 0.99999 {
            yaw = -asin(m.columns.0.z)
            let cosYaw = cos(yaw)
            pitch = atan2(m.columns.1.z / cosYaw, m.columns.2.z / cosYaw)
            roll = atan2(m.columns.0.y / cosYaw, m.columns.0.x / cosYaw)
        } else {
            yaw = m.columns.0.z < 0 ? Float.pi / 2 : -Float.pi / 2
            pitch = 0
            roll = atan2(-m.columns.1.x, m.columns.1.y)
        }
        return SIMD3<Float>(pitch * radToDeg, yaw * radToDeg, roll * radToDeg)
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
