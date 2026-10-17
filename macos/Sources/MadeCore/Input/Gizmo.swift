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
public let defaultGizmoScaleLength: Float = 42.0
public let defaultGizmoScaleBoxHalfSize: Float = 1.5
public let defaultGizmoTolerancePx: Float = 16.0
public let touchPickOffsetPt: Float = 28.0

/// 3D manipulation handles for translation axes, rotation rings, and scale cubes.
public enum GizmoHandle: String, Sendable, CaseIterable, Equatable, Hashable {
    case translateX
    case translateY
    case translateZ
    case rotateX
    case rotateY
    case rotateZ
    case scaleX
    case scaleY
    case scaleZ
    
    public var axis: SIMD3<Float> {
        switch self {
        case .translateX, .rotateX, .scaleX: return SIMD3<Float>(1, 0, 0)
        case .translateY, .rotateY, .scaleY: return SIMD3<Float>(0, 1, 0)
        case .translateZ, .rotateZ, .scaleZ: return SIMD3<Float>(0, 0, 1)
        }
    }
    
    public var isTranslation: Bool {
        switch self {
        case .translateX, .translateY, .translateZ: return true
        default: return false
        }
    }
    
    public var isRotation: Bool {
        switch self {
        case .rotateX, .rotateY, .rotateZ: return true
        default: return false
        }
    }

    public var isScale: Bool {
        switch self {
        case .scaleX, .scaleY, .scaleZ: return true
        default: return false
        }
    }
    
    public var defaultColor: SIMD4<Float> {
        switch self {
        case .translateX, .rotateX, .scaleX: return GizmoColors.red
        case .translateY, .rotateY, .scaleY: return GizmoColors.green
        case .translateZ, .rotateZ, .scaleZ: return GizmoColors.blue
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

/// Evaluates screen proximity against translation arrows, rotation rings, and scale handles.
/// If `isTouch` is true, lifts the screen contact point by `touchPickOffsetPt` (28 pt).
public func gizmoHitTestAtPointer(
    pointer: SIMD2<Float>,
    isTouch: Bool = false,
    gizmoCenter: SIMD3<Float>,
    arrowLength: Float = defaultGizmoArrowLength,
    ringRadius: Float = defaultGizmoRingRadius,
    scaleLength: Float = defaultGizmoScaleLength,
    scaleBoxHalfSize: Float = defaultGizmoScaleBoxHalfSize,
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
    
    // 3. Scale handle tests
    let scaleHandles: [GizmoHandle] = [.scaleX, .scaleY, .scaleZ]
    for handle in scaleHandles {
        let axis = handle.axis
        
        // Shaft extension segment: arrowLength to (scaleLength + scaleBoxHalfSize)
        let p0 = gizmoCenter + axis * arrowLength
        let p1 = gizmoCenter + axis * (scaleLength + scaleBoxHalfSize)
        if let s0 = projectToScreenWithW(point: p0, viewProjectionMatrix: vp, viewportSize: viewportSize),
           let s1 = projectToScreenWithW(point: p1, viewProjectionMatrix: vp, viewportSize: viewportSize) {
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
        
        // Wireframe cube edges at tip
        let c = gizmoCenter + axis * scaleLength
        let s = scaleBoxHalfSize
        let corners: [SIMD3<Float>] = [
            c + SIMD3<Float>(-s, -s, -s), // 0
            c + SIMD3<Float>(-s, -s,  s), // 1
            c + SIMD3<Float>(-s,  s, -s), // 2
            c + SIMD3<Float>(-s,  s,  s), // 3
            c + SIMD3<Float>( s, -s, -s), // 4
            c + SIMD3<Float>( s, -s,  s), // 5
            c + SIMD3<Float>( s,  s, -s), // 6
            c + SIMD3<Float>( s,  s,  s)  // 7
        ]
        let cubeEdges: [(Int, Int)] = [
            (0, 4), (1, 5), (2, 6), (3, 7), // X parallel
            (0, 2), (1, 3), (4, 6), (5, 7), // Y parallel
            (0, 1), (2, 3), (4, 5), (6, 7)  // Z parallel
        ]
        for (i0, i1) in cubeEdges {
            let cp0 = corners[i0]
            let cp1 = corners[i1]
            guard let cs0 = projectToScreenWithW(point: cp0, viewProjectionMatrix: vp, viewportSize: viewportSize),
                  let cs1 = projectToScreenWithW(point: cp1, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                continue
            }
            let (worldPoint, dist) = closestPointOnSegment(
                p1: cp0, p2: cp1,
                s1: cs0.screen, s2: cs1.screen,
                screenPointer: testPointer,
                w1: cs0.w, w2: cs1.w
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

/// Computes scale factor given startParam and currentParam along an axis.
public func computeGizmoScale(
    startParam: Float,
    currentParam: Float,
    baseParam: Float = defaultGizmoScaleLength
) -> Float {
    guard abs(baseParam) > 1e-5 else { return 1.0 }
    let ratio = (baseParam + (currentParam - startParam)) / baseParam
    return max(0.01, ratio)
}

/// Computes scale factor along a gizmo axis between two rays.
public func computeGizmoScale(
    axisOrigin: SIMD3<Float>,
    axisDirection: SIMD3<Float>,
    baseParam: Float = defaultGizmoScaleLength,
    startRay: Ray3D,
    currentRay: Ray3D
) -> Float? {
    let u = simd_normalize(axisDirection)
    guard let s0 = closestPointParamOnAxis(axisOrigin: axisOrigin, axisDirection: u, rayOrigin: startRay.origin, rayDirection: startRay.direction),
          let s1 = closestPointParamOnAxis(axisOrigin: axisOrigin, axisDirection: u, rayOrigin: currentRay.origin, rayDirection: currentRay.direction) else {
        return nil
    }
    return computeGizmoScale(startParam: s0, currentParam: s1, baseParam: baseParam)
}

/// Converts a 3D relative scale factor into clamped parameters for parametric solid definitions.
/// Returns an array of key-value pairs to commit to `DocumentModel.setParam`.
/// For non-parametric definitions (imported, boolean, part), returns an empty array.
public func computeResizedParameters(
    for def: ObjectDef,
    scale: SIMD3<Float>
) -> [(key: String, value: Float)] {
    switch def {
    case .box(let params):
        let w = DocumentLimits.clampBox(key: "width", value: params.width * scale.x)
        let d = DocumentLimits.clampBox(key: "depth", value: params.depth * scale.y)
        let h = DocumentLimits.clampBox(key: "height", value: params.height * scale.z)
        return [("width", w), ("depth", d), ("height", h)]
    case .cylinder(let params):
        let radialScale = max(scale.x, scale.y)
        let r = DocumentLimits.clampCylinder(key: "radius", value: params.radius * radialScale)
        let h = DocumentLimits.clampCylinder(key: "height", value: params.height * scale.z)
        return [("radius", r), ("height", h)]
    case .sphere(let params):
        let uniformScale = max(scale.x, max(scale.y, scale.z))
        let r = DocumentLimits.clampSphere(key: "radius", value: params.radius * uniformScale)
        return [("radius", r)]
    case .cone(let params):
        let radialScale = max(scale.x, scale.y)
        let br = DocumentLimits.clampCone(key: "bottomRadius", value: params.bottomRadius * radialScale)
        let tr = DocumentLimits.clampCone(key: "topRadius", value: params.topRadius * radialScale)
        let h = DocumentLimits.clampCone(key: "height", value: params.height * scale.z)
        return [("bottomRadius", br), ("topRadius", tr), ("height", h)]
    case .torus(let params):
        let radialScale = max(scale.x, scale.y)
        let maj = DocumentLimits.clampTorus(key: "majorRadius", value: params.majorRadius * radialScale)
        let minR = DocumentLimits.clampTorus(key: "minorRadius", value: params.minorRadius * scale.z)
        return [("majorRadius", maj), ("minorRadius", minR)]
    case .wedge(let params):
        let w = DocumentLimits.clampWedge(key: "width", value: params.width * scale.x)
        let d = DocumentLimits.clampWedge(key: "depth", value: params.depth * scale.y)
        let h = DocumentLimits.clampWedge(key: "height", value: params.height * scale.z)
        let tw = DocumentLimits.clampWedge(key: "topWidth", value: params.topWidth * scale.x)
        return [("width", w), ("depth", d), ("height", h), ("topWidth", tw)]
    case .extrude(let params):
        let d = DocumentLimits.clampExtrude(key: "distance", value: Float(params.distance) * scale.z)
        return [("distance", d)]
    case .imported, .boolean, .part:
        return []
    }
}

