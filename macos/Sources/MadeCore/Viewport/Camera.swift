import Foundation
import simd
import CoreGraphics

/// A 3D camera maintaining +Z world up orientation for CAD viewports.
/// Enforces Invariant 2 (on-demand rendering), Invariant 8 (gesture separation), and CAD navigation rules:
/// - World up is always +Z (Orientation.worldUp)
/// - Pure turntable orbit preventing camera roll
/// - Pitch clamped safely before poles to prevent view flipping
/// - Distance clamped to [minDistance, maxDistance]
public struct Camera: Sendable, Equatable {
    public var positionDouble: SIMD3<Double>
    public var targetDouble: SIMD3<Double>
    public var minDistance: Float
    public var maxDistance: Float
    public var minPitch: Float
    public var maxPitch: Float
    public var projection: CameraProjection
    public var orthographicScale: Float
    
    public var position: SIMD3<Float> {
        get { SIMD3<Float>(positionDouble) }
        set { positionDouble = SIMD3<Double>(newValue) }
    }
    
    public var target: SIMD3<Float> {
        get { SIMD3<Float>(targetDouble) }
        set { targetDouble = SIMD3<Double>(newValue) }
    }
    
    public var distanceDouble: Double {
        get { simd_length(positionDouble - targetDouble) }
        set {
            let v = positionDouble - targetDouble
            let currentDist = simd_length(v)
            if currentDist > 1e-9 {
                let dir = v / currentDist
                positionDouble = targetDouble + dir * newValue
            } else {
                positionDouble = targetDouble + SIMD3<Double>(0, 0, newValue)
            }
        }
    }
    
    public var yawDouble: Double {
        get {
            let v = positionDouble - targetDouble
            return atan2(v.y, v.x)
        }
        set {
            let r = distanceDouble
            let p = pitchDouble
            let cosP = cos(p)
            let sinP = sin(p)
            positionDouble = targetDouble + SIMD3<Double>(
                r * cosP * cos(newValue),
                r * cosP * sin(newValue),
                r * sinP
            )
        }
    }
    
    public var pitchDouble: Double {
        get {
            let v = positionDouble - targetDouble
            let r = simd_length(v)
            guard r > 1e-9 else { return 0.0 }
            return asin(min(max(v.z / r, -1.0), 1.0))
        }
        set {
            let clampedPitch = min(max(newValue, Double(minPitch)), Double(maxPitch))
            let r = distanceDouble
            let y = yawDouble
            let cosP = cos(clampedPitch)
            let sinP = sin(clampedPitch)
            positionDouble = targetDouble + SIMD3<Double>(
                r * cosP * cos(y),
                r * cosP * sin(y),
                r * sinP
            )
        }
    }
    
    public static let defaultPosition: SIMD3<Float> = Orientation.defaultViewDirection * 150.0
    public static let defaultTarget: SIMD3<Float> = SIMD3<Float>(0, 0, 10)
    public static let defaultPositionDouble: SIMD3<Double> = SIMD3<Double>(defaultPosition)
    public static let defaultTargetDouble: SIMD3<Double> = SIMD3<Double>(defaultTarget)
    public static let defaultMinDistance: Float = 1.0
    public static let defaultMaxDistance: Float = 800.0
    public static let defaultMinPitch: Float = -1.545 // ~ -88.5 degrees
    public static let defaultMaxPitch: Float = 1.545  // ~ +88.5 degrees
    
    public init(
        position: SIMD3<Float> = defaultPosition,
        target: SIMD3<Float> = defaultTarget,
        minDistance: Float = defaultMinDistance,
        maxDistance: Float = defaultMaxDistance,
        minPitch: Float = defaultMinPitch,
        maxPitch: Float = defaultMaxPitch,
        projection: CameraProjection = .perspective,
        orthographicScale: Float = 1.0
    ) {
        self.positionDouble = SIMD3<Double>(position)
        self.targetDouble = SIMD3<Double>(target)
        self.minDistance = minDistance
        self.maxDistance = maxDistance
        self.minPitch = minPitch
        self.maxPitch = maxPitch
        self.projection = projection
        self.orthographicScale = orthographicScale
    }
    
    public init(
        positionDouble: SIMD3<Double>,
        targetDouble: SIMD3<Double>,
        minDistance: Float = defaultMinDistance,
        maxDistance: Float = defaultMaxDistance,
        minPitch: Float = defaultMinPitch,
        maxPitch: Float = defaultMaxPitch,
        projection: CameraProjection = .perspective,
        orthographicScale: Float = 1.0
    ) {
        self.positionDouble = positionDouble
        self.targetDouble = targetDouble
        self.minDistance = minDistance
        self.maxDistance = maxDistance
        self.minPitch = minPitch
        self.maxPitch = maxPitch
        self.projection = projection
        self.orthographicScale = orthographicScale
    }
    
    /// Camera-relative 4x4 view matrix with optional world-space anchor for 64-bit precision rendering.
    /// Computes view rotation and relative eye translation in 64-bit Double precision
    /// before casting the final matrix to simd_float4x4 for GPU upload.
    public func cameraRelativeViewMatrix(anchor: SIMD3<Double> = .zero) -> simd_float4x4 {
        let relativeEye = positionDouble - anchor
        var forward = targetDouble - positionDouble
        let dist = simd_length(forward)
        if dist < 1e-9 {
            forward = SIMD3<Double>(0, 1, 0)
        } else {
            forward /= dist
        }
        
        var up = SIMD3<Double>(0, 0, 1)
        if simd_length_squared(simd_cross(forward, up)) < 1e-6 {
            up = abs(up.z) > 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(0, 0, 1)
        }
        
        let right = simd_normalize(simd_cross(forward, up))
        let cameraUp = simd_normalize(simd_cross(right, forward))
        let cameraBack = -forward
        
        return simd_float4x4(
            SIMD4<Float>(Float(right.x), Float(cameraUp.x), Float(cameraBack.x), 0),
            SIMD4<Float>(Float(right.y), Float(cameraUp.y), Float(cameraBack.y), 0),
            SIMD4<Float>(Float(right.z), Float(cameraUp.z), Float(cameraBack.z), 0),
            SIMD4<Float>(
                Float(-simd_dot(right, relativeEye)),
                Float(-simd_dot(cameraUp, relativeEye)),
                Float(-simd_dot(cameraBack, relativeEye)),
                1.0
            )
        )
    }
    
    /// View matrix for this camera, computed in 64-bit Double precision and converted to simd_float4x4.
    public var viewMatrix: simd_float4x4 {
        cameraRelativeViewMatrix(anchor: .zero)
    }
    
    /// Pure function: orbits the camera around `pivot` (or `target` if nil) with the given azimuth (yaw around +Z) and elevation (pitch above XY plane) deltas.
    /// Pitch is clamped to `[minPitch, maxPitch]` so the view never flips. Zero movement leaves camera unchanged.
    public static func orbit(
        camera: Camera,
        deltaAzimuth: Float,
        deltaElevation: Float,
        pivot: SIMD3<Float>? = nil
    ) -> Camera {
        if deltaAzimuth == 0 && deltaElevation == 0 {
            return camera
        }
        let v = camera.positionDouble - camera.targetDouble
        let r = max(Double(camera.minDistance), simd_length(v))
        if r < 1e-9 {
            return camera
        }
        
        let currentElevation = asin(min(max(v.z / r, -1.0), 1.0))
        let currentAzimuth = atan2(v.y, v.x)
        
        let newAzimuth = currentAzimuth + Double(deltaAzimuth)
        let newElevation = min(max(currentElevation + Double(deltaElevation), Double(camera.minPitch)), Double(camera.maxPitch))
        
        let p = pivot.map { SIMD3<Double>($0) } ?? camera.targetDouble
        if p == camera.targetDouble {
            let cosElev = cos(newElevation)
            let sinElev = sin(newElevation)
            let newOffset = SIMD3<Double>(
                r * cosElev * cos(newAzimuth),
                r * cosElev * sin(newAzimuth),
                r * sinElev
            )
            var result = camera
            result.positionDouble = camera.targetDouble + newOffset
            return result
        }
        
        let deltaTheta = newElevation - currentElevation
        let deltaPhi = Double(deltaAzimuth)
        
        let cosYaw = cos(deltaPhi)
        let sinYaw = sin(deltaPhi)
        let rotYaw = { (w: SIMD3<Double>) -> SIMD3<Double> in
            SIMD3<Double>(
                w.x * cosYaw - w.y * sinYaw,
                w.x * sinYaw + w.y * cosYaw,
                w.z
            )
        }
        
        let cameraRightAtNewAzimuth = SIMD3<Double>(-sin(newAzimuth), cos(newAzimuth), 0)
        let angle = -deltaTheta
        let cosA = cos(angle)
        let sinA = sin(angle)
        let k = simd_normalize(cameraRightAtNewAzimuth)
        let rotPitch = { (w: SIMD3<Double>) -> SIMD3<Double> in
            w * cosA + simd_cross(k, w) * sinA + k * simd_dot(k, w) * (1.0 - cosA)
        }
        
        let rot = { (w: SIMD3<Double>) -> SIMD3<Double> in
            rotPitch(rotYaw(w))
        }
        
        var result = camera
        result.positionDouble = p + rot(camera.positionDouble - p)
        result.targetDouble = p + rot(camera.targetDouble - p)
        return result
    }
    
    /// Pure function: pans both `position` and `target` in the plane perpendicular to the view direction.
    /// Preserves distance, azimuth, and elevation. Zero movement leaves camera unchanged.
    public static func pan(
        camera: Camera,
        deltaX: Float,
        deltaY: Float,
        viewportSize: CGSize = CGSize(width: 800, height: 600)
    ) -> Camera {
        if deltaX == 0 && deltaY == 0 {
            return camera
        }
        let forward = camera.targetDouble - camera.positionDouble
        let dist = simd_length(forward)
        if dist < 1e-9 {
            return camera
        }
        let fNorm = simd_normalize(forward)
        
        let worldUpDouble = SIMD3<Double>(0, 0, 1)
        var right = simd_cross(fNorm, worldUpDouble)
        if simd_length_squared(right) < 1e-9 {
            let altUp = abs(worldUpDouble.z) > 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(0, 0, 1)
            right = simd_cross(fNorm, altUp)
        }
        let rightNorm = simd_normalize(right)
        let upNorm = simd_normalize(simd_cross(rightNorm, fNorm))
        
        let fovFactor: Double = 2.0 * tan(Double.pi / 8.0) // 45-degree vertical FOV matching Orientation.makePerspective
        let viewHeight = max(1.0, Double(viewportSize.height))
        let unitsPerPixel = (dist * fovFactor) / viewHeight
        
        let offset = (-rightNorm * Double(deltaX) + upNorm * Double(deltaY)) * unitsPerPixel
        
        var result = camera
        result.positionDouble = camera.positionDouble + offset
        result.targetDouble = camera.targetDouble + offset
        return result
    }
    
    /// Pure function: zooms the camera by scaling distance to target by `factor`.
    /// `factor > 1.0` moves camera closer (zooms in). `factor < 1.0` moves camera farther (zooms out).
    /// If `cursorRay` is provided, zooms toward the cursor ray while keeping the view direction and the point under cursor stationary.
    /// Distance is clamped to `[minDistance, maxDistance]`. Factor 1.0 leaves camera unchanged.
    public static func zoom(
        camera: Camera,
        factor: Float,
        cursorRay: Ray3D? = nil
    ) -> Camera {
        if factor == 1.0 || factor <= 0.0 || factor.isNaN || factor.isInfinite {
            return camera
        }
        let forward = camera.positionDouble - camera.targetDouble
        let dist = simd_length(forward)
        if dist < 1e-9 {
            return camera
        }
        let factorDouble = Double(factor)
        if camera.projection == .orthographic {
            let currentEffective = dist * Double(camera.orthographicScale)
            let newEffective = min(max(currentEffective / factorDouble, Double(camera.minDistance)), Double(camera.maxDistance))
            guard newEffective > 1e-9 else { return camera }
            let effectiveFactor = currentEffective / newEffective
            let cursorOffset: SIMD3<Double>
            if let cursorRay {
                let fNorm = simd_normalize(camera.targetDouble - camera.positionDouble)
                let nearPlaneCenter = camera.positionDouble + fNorm * 0.1
                cursorOffset = SIMD3<Double>(cursorRay.origin) - nearPlaneCenter
            } else {
                cursorOffset = .zero
            }
            let shift = (1.0 - 1.0 / effectiveFactor) * cursorOffset
            var result = camera
            result.positionDouble = camera.positionDouble + shift
            result.targetDouble = camera.targetDouble + shift
            result.orthographicScale = Float(newEffective / dist)
            return result
        }
        let fNorm = simd_normalize(camera.targetDouble - camera.positionDouble)
        let newDist = min(max(dist / factorDouble, Double(camera.minDistance)), Double(camera.maxDistance))
        let deltaD = dist - newDist
        
        var result = camera
        if let cursorRay {
            let dNorm = simd_normalize(SIMD3<Double>(cursorRay.direction))
            let dot = simd_dot(dNorm, fNorm)
            if dot > 0.1 {
                let s = deltaD / dot
                let deltaX = s * dNorm
                let deltaXPerp = deltaX - deltaD * fNorm
                result.positionDouble = camera.positionDouble + deltaX
                result.targetDouble = camera.targetDouble + deltaXPerp
            } else {
                result.positionDouble = camera.targetDouble + simd_normalize(camera.positionDouble - camera.targetDouble) * newDist
            }
        } else {
            result.positionDouble = camera.targetDouble + simd_normalize(camera.positionDouble - camera.targetDouble) * newDist
        }
        return result
    }
    
    /// Pure function: zooms the camera by adjusting distance to target by `deltaDistance`.
    /// `deltaDistance < 0` moves camera closer (zooms in). `deltaDistance > 0` moves camera farther (zooms out).
    /// If `cursorRay` is provided, zooms toward the cursor ray while keeping the view direction and the point under cursor stationary.
    /// Distance is clamped to `[minDistance, maxDistance]`. Delta 0 leaves camera unchanged.
    public static func zoom(
        camera: Camera,
        deltaDistance: Float,
        cursorRay: Ray3D? = nil
    ) -> Camera {
        if deltaDistance == 0 || deltaDistance.isNaN || deltaDistance.isInfinite {
            return camera
        }
        let forward = camera.positionDouble - camera.targetDouble
        let dist = simd_length(forward)
        if dist < 1e-9 {
            return camera
        }
        let deltaDistanceDouble = Double(deltaDistance)
        if camera.projection == .orthographic {
            let currentEffective = dist * Double(camera.orthographicScale)
            let newEffective = min(max(currentEffective + deltaDistanceDouble, Double(camera.minDistance)), Double(camera.maxDistance))
            guard newEffective > 1e-9 else { return camera }
            let effectiveFactor = currentEffective / newEffective
            let cursorOffset: SIMD3<Double>
            if let cursorRay {
                let fNorm = simd_normalize(camera.targetDouble - camera.positionDouble)
                let nearPlaneCenter = camera.positionDouble + fNorm * 0.1
                cursorOffset = SIMD3<Double>(cursorRay.origin) - nearPlaneCenter
            } else {
                cursorOffset = .zero
            }
            let shift = (1.0 - 1.0 / effectiveFactor) * cursorOffset
            var result = camera
            result.positionDouble = camera.positionDouble + shift
            result.targetDouble = camera.targetDouble + shift
            result.orthographicScale = Float(newEffective / dist)
            return result
        }
        let fNorm = simd_normalize(camera.targetDouble - camera.positionDouble)
        let newDist = min(max(dist + deltaDistanceDouble, Double(camera.minDistance)), Double(camera.maxDistance))
        let deltaD = dist - newDist
        
        var result = camera
        if let cursorRay {
            let dNorm = simd_normalize(SIMD3<Double>(cursorRay.direction))
            let dot = simd_dot(dNorm, fNorm)
            if dot > 0.1 {
                let s = deltaD / dot
                let deltaX = s * dNorm
                let deltaXPerp = deltaX - deltaD * fNorm
                result.positionDouble = camera.positionDouble + deltaX
                result.targetDouble = camera.targetDouble + deltaXPerp
            } else {
                result.positionDouble = camera.targetDouble + simd_normalize(camera.positionDouble - camera.targetDouble) * newDist
            }
        } else {
            result.positionDouble = camera.targetDouble + simd_normalize(camera.positionDouble - camera.targetDouble) * newDist
        }
        return result
    }
    
    public func orbited(deltaAzimuth: Float, deltaElevation: Float, pivot: SIMD3<Float>? = nil) -> Camera {
        Camera.orbit(camera: self, deltaAzimuth: deltaAzimuth, deltaElevation: deltaElevation, pivot: pivot)
    }
    
    public func panned(deltaX: Float, deltaY: Float, viewportSize: CGSize = CGSize(width: 800, height: 600)) -> Camera {
        Camera.pan(camera: self, deltaX: deltaX, deltaY: deltaY, viewportSize: viewportSize)
    }
    
    public func zoomed(factor: Float, cursorRay: Ray3D? = nil) -> Camera {
        Camera.zoom(camera: self, factor: factor, cursorRay: cursorRay)
    }
    
    public func zoomed(deltaDistance: Float, cursorRay: Ray3D? = nil) -> Camera {
        Camera.zoom(camera: self, deltaDistance: deltaDistance, cursorRay: cursorRay)
    }
    
    /// Returns a camera positioned at a standard engineering perspective preset.
    public static func preset(
        _ perspective: ViewportPerspective,
        target: SIMD3<Float> = defaultTarget,
        distance: Float = 150.0
    ) -> Camera {
        switch perspective {
        case .perspective:
            return Camera(position: target + Orientation.defaultViewDirection * distance, target: target)
        case .top:
            return Camera(position: target + SIMD3<Float>(0, 0.001, distance), target: target)
        case .bottom:
            return Camera(position: target + SIMD3<Float>(0, 0.001, -distance), target: target)
        case .front:
            return Camera(position: target + SIMD3<Float>(0, -distance, 0), target: target)
        case .back:
            return Camera(position: target + SIMD3<Float>(0, distance, 0), target: target)
        case .right:
            return Camera(position: target + SIMD3<Float>(distance, 0, 0), target: target)
        case .left:
            return Camera(position: target + SIMD3<Float>(-distance, 0, 0), target: target)
        case .isometric:
            let isoDir = simd_normalize(SIMD3<Float>(1, -1, 1))
            return Camera(position: target + isoDir * distance, target: target)
        }
    }
    
    /// Pure function: computes a camera positioned along +normal * distance looking at target.
    /// If |normal.z| > 0.999, applies a 0.001 Y offset to eye position to prevent singular look-at.
    /// If `allowFlip` is true and `currentCamera` is already aligned with `normal`, inverts the normal by 180°.
    public static func alignedToNormal(
        _ normal: SIMD3<Float>,
        target: SIMD3<Float>,
        distance: Float = 150.0,
        currentCamera: Camera? = nil,
        allowFlip: Bool = false,
        projection: CameraProjection = .perspective
    ) -> Camera {
        let len = simd_length(normal)
        guard len > 1e-6 else { return Camera(target: target) }
        var norm = normal / len
        
        if allowFlip, let current = currentCamera {
            let eyeVec = current.position - target
            let eyeDist = simd_length(eyeVec)
            if eyeDist > 1e-4 {
                let eyeDir = eyeVec / eyeDist
                if simd_dot(eyeDir, norm) > 0.99 {
                    norm = -norm
                }
            }
        }
        
        var eyePos = target + norm * distance
        if abs(norm.z) > 0.999 {
            eyePos.y += 0.001
        }
        
        return Camera(
            position: eyePos,
            target: target,
            minDistance: currentCamera?.minDistance ?? defaultMinDistance,
            maxDistance: currentCamera?.maxDistance ?? defaultMaxDistance,
            minPitch: currentCamera?.minPitch ?? defaultMinPitch,
            maxPitch: currentCamera?.maxPitch ?? defaultMaxPitch,
            projection: projection,
            orthographicScale: currentCamera?.orthographicScale ?? 1.0
        )
    }
    
    /// Pure function: smoothly interpolates between two cameras.
    /// Uses smoothstep easing on target and distance, and spherical slerp on viewing direction to prevent camera plunge.
    public static func interpolate(from: Camera, to: Camera, t: Float) -> Camera {
        if t <= 0.0 { return from }
        if t >= 1.0 { return to }
        
        let s = t * t * (3.0 - 2.0 * t) // smoothstep
        let target = (1.0 - s) * from.target + s * to.target
        let orthoScale = (1.0 - s) * from.orthographicScale + s * to.orthographicScale
        
        let vFrom = from.position - from.target
        let vTo = to.position - to.target
        let rFrom = simd_length(vFrom)
        let rTo = simd_length(vTo)
        let r = (1.0 - s) * rFrom + s * rTo
        
        guard rFrom > 1e-6 && rTo > 1e-6 else {
            let pos = (1.0 - s) * from.position + s * to.position
            return Camera(position: pos, target: target, projection: to.projection, orthographicScale: orthoScale)
        }
        
        let dFrom = vFrom / rFrom
        let dTo = vTo / rTo
        let dotVal = simd_clamp(simd_dot(dFrom, dTo), -1.0, 1.0)
        
        let dir: SIMD3<Float>
        if dotVal > 0.9999 {
            dir = simd_normalize((1.0 - s) * dFrom + s * dTo)
        } else if dotVal < -0.9999 {
            var axis = simd_cross(dFrom, Orientation.worldUp)
            if simd_length_squared(axis) < 1e-4 {
                axis = simd_cross(dFrom, SIMD3<Float>(0, 1, 0))
            }
            let q = simd_quatf(angle: .pi * s, axis: simd_normalize(axis))
            dir = q.act(dFrom)
        } else {
            let theta = acos(dotVal)
            let sinTheta = sin(theta)
            dir = simd_normalize((sin((1.0 - s) * theta) / sinTheta) * dFrom + (sin(s * theta) / sinTheta) * dTo)
        }
        
        return Camera(
            position: target + dir * r,
            target: target,
            minDistance: to.minDistance,
            maxDistance: to.maxDistance,
            minPitch: to.minPitch,
            maxPitch: to.maxPitch,
            projection: to.projection,
            orthographicScale: orthoScale
        )
    }
}

public enum ViewportPerspective: String, CaseIterable, Identifiable, Sendable {
    case perspective = "Perspective"
    case top = "Top"
    case bottom = "Bottom"
    case front = "Front"
    case back = "Back"
    case right = "Right"
    case left = "Left"
    case isometric = "Isometric"
    
    public var id: String { rawValue }
}

public enum CameraProjection: String, CaseIterable, Identifiable, Sendable, Codable {
    case perspective = "Perspective"
    case orthographic = "Orthographic"
    
    public var id: String { rawValue }
}

extension Camera: Codable {
    private enum CodingKeys: String, CodingKey {
        case position
        case target
        case positionDouble
        case targetDouble
        case minDistance
        case maxDistance
        case minPitch
        case maxPitch
        case projection
        case orthographicScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.minDistance = try container.decode(Float.self, forKey: .minDistance)
        self.maxDistance = try container.decode(Float.self, forKey: .maxDistance)
        self.minPitch = try container.decode(Float.self, forKey: .minPitch)
        self.maxPitch = try container.decode(Float.self, forKey: .maxPitch)
        self.projection = try container.decode(CameraProjection.self, forKey: .projection)
        self.orthographicScale = try container.decode(Float.self, forKey: .orthographicScale)

        if let posD = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .positionDouble),
           let tgtD = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .targetDouble) {
            self.positionDouble = posD
            self.targetDouble = tgtD
        } else {
            let posF = try container.decode(SIMD3<Float>.self, forKey: .position)
            let tgtF = try container.decode(SIMD3<Float>.self, forKey: .target)
            self.positionDouble = SIMD3<Double>(posF)
            self.targetDouble = SIMD3<Double>(tgtF)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        try container.encode(target, forKey: .target)
        try container.encode(positionDouble, forKey: .positionDouble)
        try container.encode(targetDouble, forKey: .targetDouble)
        try container.encode(minDistance, forKey: .minDistance)
        try container.encode(maxDistance, forKey: .maxDistance)
        try container.encode(minPitch, forKey: .minPitch)
        try container.encode(maxPitch, forKey: .maxPitch)
        try container.encode(projection, forKey: .projection)
        try container.encode(orthographicScale, forKey: .orthographicScale)
    }
}
