import Foundation
import simd
import CoreGraphics

/// Visual colors for the 3D manipulation gizmo handles adhering to right-handed Z-up coordinates.
public enum GizmoColors {
    public static let red = SIMD4<Float>(0.95, 0.22, 0.22, 1.0)
    public static let green = SIMD4<Float>(0.22, 0.85, 0.22, 1.0)
    public static let blue = SIMD4<Float>(0.25, 0.55, 1.0, 1.0)
    public static let active = SIMD4<Float>(1.0, 0.85, 0.1, 1.0)
}

public let defaultGizmoArrowLength: Float = 30.0
public let defaultGizmoRingRadius: Float = 24.0
public let defaultGizmoTolerancePx: Float = 16.0
public let touchPickOffsetPt: Float = 28.0

/// 3D manipulation handles for translation axes and rotation rings.
public enum GizmoHandle: String, Sendable, CaseIterable, Equatable, Hashable {
    case translateX
    case translateY
    case translateZ
    case rotateX
    case rotateY
    case rotateZ
    
    public var axis: SIMD3<Float> {
        switch self {
        case .translateX, .rotateX: return SIMD3<Float>(1, 0, 0)
        case .translateY, .rotateY: return SIMD3<Float>(0, 1, 0)
        case .translateZ, .rotateZ: return SIMD3<Float>(0, 0, 1)
        }
    }
    
    public var isTranslation: Bool {
        switch self {
        case .translateX, .translateY, .translateZ: return true
        case .rotateX, .rotateY, .rotateZ: return false
        }
    }
    
    public var isRotation: Bool {
        !isTranslation
    }
    
    public var defaultColor: SIMD4<Float> {
        switch self {
        case .translateX, .rotateX: return GizmoColors.red
        case .translateY, .rotateY: return GizmoColors.green
        case .translateZ, .rotateZ: return GizmoColors.blue
        }
    }
}

/// The result of a hit test against the gizmo handles.
public struct GizmoHitResult: Sendable, Equatable {
    public let handle: GizmoHandle
    public let screenDistancePx: Float
    public let hitPoint: SIMD3<Float>
    
    public init(handle: GizmoHandle, screenDistancePx: Float, hitPoint: SIMD3<Float>) {
        self.handle = handle
        self.screenDistancePx = screenDistancePx
        self.hitPoint = hitPoint
    }
}

/// Active drag tracking state for interactive gizmo manipulation.
public struct GizmoDragState: Sendable, Equatable {
    public let selectedId: SolidId
    public let handle: GizmoHandle
    public let initialTransform: Transform
    public let startPointer: SIMD2<Float>
    public let startRay: Ray3D
    public let startAxisParam: Float
    public let startRadialVector: SIMD3<Float>
    public var hasMoved: Bool
    
    public init(
        selectedId: SolidId,
        handle: GizmoHandle,
        initialTransform: Transform,
        startPointer: SIMD2<Float>,
        startRay: Ray3D,
        startAxisParam: Float = 0,
        startRadialVector: SIMD3<Float> = .zero,
        hasMoved: Bool = false
    ) {
        self.selectedId = selectedId
        self.handle = handle
        self.initialTransform = initialTransform
        self.startPointer = startPointer
        self.startRay = startRay
        self.startAxisParam = startAxisParam
        self.startRadialVector = startRadialVector
        self.hasMoved = hasMoved
    }
}

/// Evaluates screen proximity against translation arrows and rotation rings.
/// If `isTouch` is true, lifts the screen contact point by `touchPickOffsetPt` (28 pt).
public func gizmoHitTestAtPointer(
    pointer: SIMD2<Float>,
    isTouch: Bool = false,
    gizmoCenter: SIMD3<Float>,
    arrowLength: Float = defaultGizmoArrowLength,
    ringRadius: Float = defaultGizmoRingRadius,
    tolerancePx: Float = defaultGizmoTolerancePx,
    viewportSize: CGSize,
    viewMatrix: simd_float4x4,
    projectionMatrix: simd_float4x4
) -> GizmoHitResult? {
    let testPointer = isTouch ? SIMD2<Float>(pointer.x, pointer.y + touchPickOffsetPt) : pointer
    let vp = projectionMatrix * viewMatrix
    var bestResult: GizmoHitResult? = nil
    
    // 1. Translation arrow tests
    let translationHandles: [GizmoHandle] = [.translateX, .translateY, .translateZ]
    for handle in translationHandles {
        let p0 = gizmoCenter
        let p1 = gizmoCenter + handle.axis * arrowLength
        guard let s0 = projectToScreenWithW(point: p0, viewProjectionMatrix: vp, viewportSize: viewportSize),
              let s1 = projectToScreenWithW(point: p1, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
            continue
        }
        let (worldPoint, dist) = closestPointOnSegment(
            p1: p0, p2: p1,
            s1: s0.screen, s2: s1.screen,
            screenPointer: testPointer,
            w1: s0.w, w2: s1.w
        )
        if dist <= tolerancePx {
            if bestResult == nil || dist < bestResult!.screenDistancePx {
                bestResult = GizmoHitResult(handle: handle, screenDistancePx: dist, hitPoint: worldPoint)
            }
        }
    }
    
    // 2. Rotation ring tests
    let rotationHandles: [GizmoHandle] = [.rotateX, .rotateY, .rotateZ]
    for handle in rotationHandles {
        let axis = handle.axis
        
        // Ray-plane intersection test
        if let ray = screenPointToRay(screenPoint: testPointer, viewportSize: viewportSize, viewMatrix: viewMatrix, projectionMatrix: projectionMatrix) {
            let denom = simd_dot(ray.direction, axis)
            if abs(denom) > 1e-5 {
                let t = simd_dot(gizmoCenter - ray.origin, axis) / denom
                if t > 0 {
                    let hitPlane = ray.origin + ray.direction * t
                    let radial = hitPlane - gizmoCenter
                    let distToCenter = simd_length(radial)
                    if distToCenter > 1e-4 {
                        let ringPt = gizmoCenter + (radial / distToCenter) * ringRadius
                        if let sRing = projectToScreen(point: ringPt, viewProjectionMatrix: vp, viewportSize: viewportSize) {
                            let dist = simd_distance(testPointer, sRing)
                            if dist <= tolerancePx {
                                if bestResult == nil || dist < bestResult!.screenDistancePx {
                                    bestResult = GizmoHitResult(handle: handle, screenDistancePx: dist, hitPoint: ringPt)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Discretized ring segments test (32 segments)
        let segments = 32
        for i in 0..<segments {
            let theta0 = Float(i) * (2.0 * .pi / Float(segments))
            let theta1 = Float(i + 1) * (2.0 * .pi / Float(segments))
            let p0: SIMD3<Float>
            let p1: SIMD3<Float>
            switch handle {
            case .rotateX:
                p0 = gizmoCenter + SIMD3<Float>(0, ringRadius * cos(theta0), ringRadius * sin(theta0))
                p1 = gizmoCenter + SIMD3<Float>(0, ringRadius * cos(theta1), ringRadius * sin(theta1))
            case .rotateY:
                p0 = gizmoCenter + SIMD3<Float>(ringRadius * cos(theta0), 0, ringRadius * sin(theta0))
                p1 = gizmoCenter + SIMD3<Float>(ringRadius * cos(theta1), 0, ringRadius * sin(theta1))
            case .rotateZ:
                p0 = gizmoCenter + SIMD3<Float>(ringRadius * cos(theta0), ringRadius * sin(theta0), 0)
                p1 = gizmoCenter + SIMD3<Float>(ringRadius * cos(theta1), ringRadius * sin(theta1), 0)
            default:
                continue
            }
            guard let s0 = projectToScreenWithW(point: p0, viewProjectionMatrix: vp, viewportSize: viewportSize),
                  let s1 = projectToScreenWithW(point: p1, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                continue
            }
            let (worldPoint, dist) = closestPointOnSegment(
                p1: p0, p2: p1,
                s1: s0.screen, s2: s1.screen,
                screenPointer: testPointer,
                w1: s0.w, w2: s1.w
            )
            if dist <= tolerancePx {
                if bestResult == nil || dist < bestResult!.screenDistancePx {
                    bestResult = GizmoHitResult(handle: handle, screenDistancePx: dist, hitPoint: worldPoint)
                }
            }
        }
    }
    
    return bestResult
}

/// Computes the parameter s along an axis (axisOrigin + s * axisDirection) closest to a 3D ray.
public func closestPointParamOnAxis(
    axisOrigin: SIMD3<Float>,
    axisDirection: SIMD3<Float>,
    rayOrigin: SIMD3<Float>,
    rayDirection: SIMD3<Float>
) -> Float? {
    let u = simd_normalize(axisDirection)
    let d = simd_normalize(rayDirection)
    let v0 = axisOrigin - rayOrigin
    let uDotD = simd_dot(u, d)
    let denom = 1.0 - uDotD * uDotD
    guard abs(denom) > 1e-5 else { return nil }
    let s = (simd_dot(v0, d) * uDotD - simd_dot(v0, u)) / denom
    return s
}

/// Computes delta translation along a gizmo axis between two rays.
public func computeGizmoTranslation(
    axisOrigin: SIMD3<Float>,
    axisDirection: SIMD3<Float>,
    startRay: Ray3D,
    currentRay: Ray3D
) -> SIMD3<Float>? {
    let u = simd_normalize(axisDirection)
    guard let s0 = closestPointParamOnAxis(axisOrigin: axisOrigin, axisDirection: u, rayOrigin: startRay.origin, rayDirection: startRay.direction),
          let s1 = closestPointParamOnAxis(axisOrigin: axisOrigin, axisDirection: u, rayOrigin: currentRay.origin, rayDirection: currentRay.direction) else {
        return nil
    }
    let deltaS = s1 - s0
    return deltaS * u
}

/// Intersects a ray with a plane defined by planeCenter and planeNormal.
/// Falls back to the nearest projected ray point if parallel.
public func intersectRayPlane(
    ray: Ray3D,
    planeCenter: SIMD3<Float>,
    planeNormal: SIMD3<Float>
) -> SIMD3<Float>? {
    let u = simd_normalize(planeNormal)
    let denom = simd_dot(ray.direction, u)
    if abs(denom) > 1e-5 {
        let t = simd_dot(planeCenter - ray.origin, u) / denom
        if t > 0 {
            return ray.origin + ray.direction * t
        }
    }
    // Fallback for glancing or parallel ray: project ray point closest to planeCenter onto the plane
    let d = simd_normalize(ray.direction)
    let t = max(0, simd_dot(planeCenter - ray.origin, d))
    let p = ray.origin + d * t
    let pProj = p - simd_dot(p - planeCenter, u) * u
    return pProj
}

/// Computes signed rotation angle around axis between startRay and currentRay relative to center.
public func computeGizmoRotationAngle(
    center: SIMD3<Float>,
    axis: SIMD3<Float>,
    startRay: Ray3D,
    currentRay: Ray3D
) -> Float? {
    let u = simd_normalize(axis)
    guard let p0 = intersectRayPlane(ray: startRay, planeCenter: center, planeNormal: u),
          let p1 = intersectRayPlane(ray: currentRay, planeCenter: center, planeNormal: u) else {
        return nil
    }
    let v0 = p0 - center
    let v1 = p1 - center
    let len0 = simd_length(v0)
    let len1 = simd_length(v1)
    guard len0 > 1e-4 && len1 > 1e-4 else { return nil }
    let n0 = v0 / len0
    let n1 = v1 / len1
    let sinTheta = simd_dot(simd_cross(n0, n1), u)
    let cosTheta = simd_dot(n0, n1)
    return atan2(sinTheta, cosTheta)
}

/// Computes updated rotation quaternion given start and current rays.
public func computeGizmoRotation(
    center: SIMD3<Float>,
    axis: SIMD3<Float>,
    initialRotation: simd_quatf,
    startRay: Ray3D,
    currentRay: Ray3D
) -> simd_quatf? {
    guard let theta = computeGizmoRotationAngle(center: center, axis: axis, startRay: startRay, currentRay: currentRay) else {
        return nil
    }
    let u = simd_normalize(axis)
    let deltaQ = simd_quatf(angle: theta, axis: u)
    return deltaQ * initialRotation
}
