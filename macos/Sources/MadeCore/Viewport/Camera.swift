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
    public var position: SIMD3<Float>
    public var target: SIMD3<Float>
    public var minDistance: Float
    public var maxDistance: Float
    public var minPitch: Float
    public var maxPitch: Float
    
    public static let defaultPosition: SIMD3<Float> = Orientation.defaultViewDirection * 150.0
    public static let defaultTarget: SIMD3<Float> = SIMD3<Float>(0, 0, 10)
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
        maxPitch: Float = defaultMaxPitch
    ) {
        self.position = position
        self.target = target
        self.minDistance = minDistance
        self.maxDistance = maxDistance
        self.minPitch = minPitch
        self.maxPitch = maxPitch
    }
    
    /// Pure function: orbits the camera around `target` with the given azimuth (yaw around +Z) and elevation (pitch above XY plane) deltas.
    /// Pitch is clamped to `[minPitch, maxPitch]` so the view never flips. Zero movement leaves camera unchanged.
    public static func orbit(
        camera: Camera,
        deltaAzimuth: Float,
        deltaElevation: Float
    ) -> Camera {
        if deltaAzimuth == 0 && deltaElevation == 0 {
            return camera
        }
        let v = camera.position - camera.target
        let r = max(camera.minDistance, simd_length(v))
        if r < 1e-6 {
            return camera
        }
        
        let currentElevation = asin(min(max(v.z / r, -1.0), 1.0))
        let currentAzimuth = atan2(v.y, v.x)
        
        let newAzimuth = currentAzimuth + deltaAzimuth
        let newElevation = min(max(currentElevation + deltaElevation, camera.minPitch), camera.maxPitch)
        
        let cosElev = cos(newElevation)
        let sinElev = sin(newElevation)
        
        let newOffset = SIMD3<Float>(
            r * cosElev * cos(newAzimuth),
            r * cosElev * sin(newAzimuth),
            r * sinElev
        )
        
        var result = camera
        result.position = camera.target + newOffset
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
        let forward = camera.target - camera.position
        let dist = simd_length(forward)
        if dist < 1e-6 {
            return camera
        }
        let fNorm = simd_normalize(forward)
        
        var right = simd_cross(fNorm, Orientation.worldUp)
        if simd_length_squared(right) < 1e-6 {
            let altUp = abs(Orientation.worldUp.z) > 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(0, 0, 1)
            right = simd_cross(fNorm, altUp)
        }
        let rightNorm = simd_normalize(right)
        let upNorm = simd_normalize(simd_cross(rightNorm, fNorm))
        
        let fovFactor: Float = 2.0 * tan(Float.pi / 8.0) // 45-degree vertical FOV matching Orientation.makePerspective
        let viewHeight = max(1.0, Float(viewportSize.height))
        let unitsPerPixel = (dist * fovFactor) / viewHeight
        
        let offset = (-rightNorm * deltaX + upNorm * deltaY) * unitsPerPixel
        
        var result = camera
        result.position = camera.position + offset
        result.target = camera.target + offset
        return result
    }
    
    /// Pure function: zooms the camera by scaling distance to target by `factor`.
    /// `factor > 1.0` moves camera closer (zooms in). `factor < 1.0` moves camera farther (zooms out).
    /// Distance is clamped to `[minDistance, maxDistance]`. Factor 1.0 leaves camera unchanged.
    public static func zoom(
        camera: Camera,
        factor: Float
    ) -> Camera {
        if factor == 1.0 || factor <= 0.0 || factor.isNaN || factor.isInfinite {
            return camera
        }
        let forward = camera.position - camera.target
        let dist = simd_length(forward)
        if dist < 1e-6 {
            return camera
        }
        let dir = simd_normalize(forward)
        let newDist = min(max(dist / factor, camera.minDistance), camera.maxDistance)
        
        var result = camera
        result.position = camera.target + dir * newDist
        return result
    }
    
    /// Pure function: zooms the camera by adjusting distance to target by `deltaDistance`.
    /// `deltaDistance < 0` moves camera closer (zooms in). `deltaDistance > 0` moves camera farther (zooms out).
    /// Distance is clamped to `[minDistance, maxDistance]`. Delta 0 leaves camera unchanged.
    public static func zoom(
        camera: Camera,
        deltaDistance: Float
    ) -> Camera {
        if deltaDistance == 0 || deltaDistance.isNaN || deltaDistance.isInfinite {
            return camera
        }
        let forward = camera.position - camera.target
        let dist = simd_length(forward)
        if dist < 1e-6 {
            return camera
        }
        let dir = simd_normalize(forward)
        let newDist = min(max(dist + deltaDistance, camera.minDistance), camera.maxDistance)
        
        var result = camera
        result.position = camera.target + dir * newDist
        return result
    }
    
    public func orbited(deltaAzimuth: Float, deltaElevation: Float) -> Camera {
        Camera.orbit(camera: self, deltaAzimuth: deltaAzimuth, deltaElevation: deltaElevation)
    }
    
    public func panned(deltaX: Float, deltaY: Float, viewportSize: CGSize = CGSize(width: 800, height: 600)) -> Camera {
        Camera.pan(camera: self, deltaX: deltaX, deltaY: deltaY, viewportSize: viewportSize)
    }
    
    public func zoomed(factor: Float) -> Camera {
        Camera.zoom(camera: self, factor: factor)
    }
    
    public func zoomed(deltaDistance: Float) -> Camera {
        Camera.zoom(camera: self, deltaDistance: deltaDistance)
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
        case .front:
            return Camera(position: target + SIMD3<Float>(0, -distance, 0), target: target)
        case .right:
            return Camera(position: target + SIMD3<Float>(distance, 0, 0), target: target)
        case .isometric:
            let isoDir = simd_normalize(SIMD3<Float>(1, -1, 1))
            return Camera(position: target + isoDir * distance, target: target)
        }
    }
}

public enum ViewportPerspective: String, CaseIterable, Identifiable, Sendable {
    case perspective = "Perspective"
    case top = "Top"
    case front = "Front"
    case right = "Right"
    case isometric = "Isometric"
    
    public var id: String { rawValue }
}

public enum CameraProjection: String, CaseIterable, Identifiable, Sendable {
    case perspective = "Perspective"
    case orthographic = "Orthographic"
    
    public var id: String { rawValue }
}
