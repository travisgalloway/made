import Foundation
import CoreGraphics
import simd

/// Principal 3D Cartesian axes with corresponding unit vectors and translation gizmo handles.
public enum Axis3D: String, Sendable, CaseIterable, Equatable, Hashable {
    case x
    case y
    case z

    public var vector: SIMD3<Float> {
        switch self {
        case .x: return SIMD3<Float>(1, 0, 0)
        case .y: return SIMD3<Float>(0, 1, 0)
        case .z: return SIMD3<Float>(0, 0, 1)
        }
    }

    public var translationHandle: GizmoHandle {
        switch self {
        case .x: return .translateX
        case .y: return .translateY
        case .z: return .translateZ
        }
    }
}

/// Geometric constraints applied to viewport transforms.
public enum TransformConstraint: Sendable, Equatable {
    case none
    case axis(Axis3D)
    case groundPlane(elevation: Float)

    public var isConstrained: Bool {
        switch self {
        case .none: return false
        case .axis, .groundPlane: return true
        }
    }
}

/// Active drag tracking state for widget-less constrained transforms.
public struct WidgetlessDragState: Sendable, Equatable {
    public let selectedId: SolidId
    public let initialTransform: Transform
    public let startPointer: SIMD2<Float>
    public let startRay: Ray3D
    public var latchedAxis: Axis3D?
    public var hasMoved: Bool

    public init(
        selectedId: SolidId,
        initialTransform: Transform,
        startPointer: SIMD2<Float>,
        startRay: Ray3D,
        latchedAxis: Axis3D? = nil,
        hasMoved: Bool = false
    ) {
        self.selectedId = selectedId
        self.initialTransform = initialTransform
        self.startPointer = startPointer
        self.startRay = startRay
        self.latchedAxis = latchedAxis
        self.hasMoved = hasMoved
    }
}

/// Determines the dominant world axis from screen-projected pointer displacement.
/// Returns nil if displacement is below `mouseClickThresholdPx` or if projections fail.
public func determineDominantAxis(
    deltaPointer: SIMD2<Float>,
    origin: SIMD3<Float>,
    viewProjectionMatrix: simd_float4x4,
    viewportSize: CGSize
) -> Axis3D? {
    let dist = simd_length(deltaPointer)
    guard dist >= mouseClickThresholdPx else { return nil }
    guard let screenOrigin = projectToScreen(
        point: origin,
        viewProjectionMatrix: viewProjectionMatrix,
        viewportSize: viewportSize
    ) else {
        return nil
    }

    var bestAxis: Axis3D? = nil
    var maxScore: Float = -1.0

    for axis in Axis3D.allCases {
        let axisPoint10 = origin + axis.vector * 10.0
        let screenAxisPoint = projectToScreen(
            point: axisPoint10,
            viewProjectionMatrix: viewProjectionMatrix,
            viewportSize: viewportSize
        ) ?? projectToScreen(
            point: origin + axis.vector,
            viewProjectionMatrix: viewProjectionMatrix,
            viewportSize: viewportSize
        )
        guard let screenPoint = screenAxisPoint else { continue }
        let dir2D = screenPoint - screenOrigin
        let len2D = simd_length(dir2D)
        guard len2D > 1e-4 else { continue }
        let u = dir2D / len2D
        let score = abs(simd_dot(deltaPointer, u))
        if score > maxScore {
            maxScore = score
            bestAxis = axis
        }
    }

    return bestAxis
}

/// Computes translation delta along a constrained axis between start and current rays, applying optional snap.
public func computeConstrainedAxisTranslation(
    axis: Axis3D,
    origin: SIMD3<Float>,
    startRay: Ray3D,
    currentRay: Ray3D,
    snapPoint: SIMD3<Float>?
) -> SIMD3<Float> {
    let u = axis.vector
    if let snapPoint = snapPoint {
        let deltaS = simd_dot(snapPoint - origin, u)
        return deltaS * u
    }
    let s0 = closestPointParamOnAxis(axisOrigin: origin, axisDirection: u, rayOrigin: startRay.origin, rayDirection: startRay.direction) ?? 0
    let s1 = closestPointParamOnAxis(axisOrigin: origin, axisDirection: u, rayOrigin: currentRay.origin, rayDirection: currentRay.direction) ?? s0
    let deltaS = s1 - s0
    return deltaS * u
}

/// Computes translation delta along a constrained axis between start and current rays with optional `SnapResult`.
public func computeConstrainedAxisTranslation(
    axis: Axis3D,
    origin: SIMD3<Float>,
    startRay: Ray3D,
    currentRay: Ray3D,
    snap: SnapResult? = nil
) -> SIMD3<Float> {
    computeConstrainedAxisTranslation(
        axis: axis,
        origin: origin,
        startRay: startRay,
        currentRay: currentRay,
        snapPoint: snap?.point
    )
}

/// Computes translation delta along a constrained axis between start and current rays with a `SnapCandidate`.
public func computeConstrainedAxisTranslation(
    axis: Axis3D,
    origin: SIMD3<Float>,
    startRay: Ray3D,
    currentRay: Ray3D,
    snap: SnapCandidate
) -> SIMD3<Float> {
    computeConstrainedAxisTranslation(
        axis: axis,
        origin: origin,
        startRay: startRay,
        currentRay: currentRay,
        snapPoint: snap.point
    )
}

/// Computes translation delta on a constrained plane between start and current rays, applying optional snap.
public func computeConstrainedPlaneTranslation(
    planeOrigin: SIMD3<Float>,
    planeNormal: SIMD3<Float> = SIMD3<Float>(0, 0, 1),
    startRay: Ray3D,
    currentRay: Ray3D,
    snapPoint: SIMD3<Float>?,
    gridSpacing: Float = defaultGridSpacing
) -> SIMD3<Float> {
    let n = simd_normalize(planeNormal)
    if let snapPoint = snapPoint {
        let v = snapPoint - planeOrigin
        return v - simd_dot(v, n) * n
    }

    guard let p0 = intersectRayPlane(ray: startRay, planeCenter: planeOrigin, planeNormal: n),
          let p1 = intersectRayPlane(ray: currentRay, planeCenter: planeOrigin, planeNormal: n) else {
        return .zero
    }
    let delta = p1 - p0
    return delta - simd_dot(delta, n) * n
}

/// Computes translation delta on a constrained plane between start and current rays with optional `SnapResult`.
public func computeConstrainedPlaneTranslation(
    planeOrigin: SIMD3<Float>,
    planeNormal: SIMD3<Float> = SIMD3<Float>(0, 0, 1),
    startRay: Ray3D,
    currentRay: Ray3D,
    snap: SnapResult? = nil,
    gridSpacing: Float = defaultGridSpacing
) -> SIMD3<Float> {
    computeConstrainedPlaneTranslation(
        planeOrigin: planeOrigin,
        planeNormal: planeNormal,
        startRay: startRay,
        currentRay: currentRay,
        snapPoint: snap?.point,
        gridSpacing: gridSpacing
    )
}

/// Computes translation delta on a constrained plane between start and current rays with a `SnapCandidate`.
public func computeConstrainedPlaneTranslation(
    planeOrigin: SIMD3<Float>,
    planeNormal: SIMD3<Float> = SIMD3<Float>(0, 0, 1),
    startRay: Ray3D,
    currentRay: Ray3D,
    snap: SnapCandidate,
    gridSpacing: Float = defaultGridSpacing
) -> SIMD3<Float> {
    computeConstrainedPlaneTranslation(
        planeOrigin: planeOrigin,
        planeNormal: planeNormal,
        startRay: startRay,
        currentRay: currentRay,
        snapPoint: snap.point,
        gridSpacing: gridSpacing
    )
}
