import Foundation
import simd

/// A 2D coordinate frame in right-handed Z-up world space on which a sketch profile lies.
public struct SketchPlane: Hashable, Equatable, Sendable, Codable {
    public var origin: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var xAxis: SIMD3<Float>

    public init(
        origin: SIMD3<Float> = .zero,
        normal: SIMD3<Float> = SIMD3(0, 0, 1),
        xAxis: SIMD3<Float> = SIMD3(1, 0, 0)
    ) {
        self.origin = origin
        self.normal = normal
        self.xAxis = xAxis
    }

    public static let xy = SketchPlane(origin: .zero, normal: SIMD3(0, 0, 1), xAxis: SIMD3(1, 0, 0))
    public static let xz = SketchPlane(origin: .zero, normal: SIMD3(0, -1, 0), xAxis: SIMD3(1, 0, 0))
    public static let yz = SketchPlane(origin: .zero, normal: SIMD3(1, 0, 0), xAxis: SIMD3(0, 1, 0))

    public func offset(_ distance: Float) -> SketchPlane {
        let len = simd_length(normal)
        guard len > 1e-6 else { return self }
        let unitNormal = normal / len
        return SketchPlane(origin: origin + unitNormal * distance, normal: unitNormal, xAxis: xAxis)
    }
}

/// A closed 2D polygon defined on a `SketchPlane`.
public struct SketchProfile: Hashable, Equatable, Sendable, Codable {
    public var plane: SketchPlane
    public var points: [SIMD2<Float>]

    public init(plane: SketchPlane = .xy, points: [SIMD2<Float>]) {
        self.plane = plane
        self.points = points
    }
}

/// A shape description: an operation tree a script or the Swift DSL builds, and the kernel evaluates in one request (ADR-D6).
public indirect enum ShapeNode: Sendable, Codable, Equatable {
    case box(BoxParams)
    case cylinder(CylinderParams, slices: Int)
    case sphere(SphereParams, slices: Int)
    case cone(ConeParams, slices: Int)
    case extrude(profile: SketchProfile, distance: Float, centered: Bool)
    case revolve(profile: SketchProfile, angleDegrees: Float, slices: Int)
    case translate(ShapeNode, offset: SIMD3<Float>)
    case rotate(ShapeNode, axis: SIMD3<Float>, angleDegrees: Float)
    case scale(ShapeNode, factor: SIMD3<Float>)
    case boolean(BooleanOp, ShapeNode, ShapeNode)
}

/// Bounds on a shape tree, shared by every producer so the kernel rejects a runaway tree before evaluating it.
public enum ShapeLimits {
    /// Nesting levels below the root, so a chain of `maxDepth` translates around a leaf is allowed.
    public static let maxDepth = 64
    public static let maxNodes = 4096
    public static let minSlices = 3
    public static let maxSlices = 512
    public static let maxProfilePoints = 1024
}

extension ShapeNode {
    /// Returns the first problem found, or nil for a tree the kernel can evaluate.
    /// Iterative, so validating a hostile tree cannot overflow the stack.
    public func validate() -> KernelError? {
        var stack: [(node: ShapeNode, depth: Int)] = [(self, 0)]
        var count = 0
        while let (node, depth) = stack.popLast() {
            count += 1
            if count > ShapeLimits.maxNodes {
                return Self.invalid("Shape tree exceeds \(ShapeLimits.maxNodes) nodes")
            }
            if depth > ShapeLimits.maxDepth {
                return Self.invalid("Shape tree exceeds depth \(ShapeLimits.maxDepth)")
            }
            switch node {
            case .box(let p):
                if !Self.isPositive(p.width) || !Self.isPositive(p.depth) || !Self.isPositive(p.height) {
                    return Self.invalid("Shape tree box dimensions must be positive and finite")
                }
            case .cylinder(let p, let slices):
                if !Self.isPositive(p.radius) || !Self.isPositive(p.height) {
                    return Self.invalid("Shape tree cylinder dimensions must be positive and finite")
                }
                if !(ShapeLimits.minSlices...ShapeLimits.maxSlices).contains(slices) {
                    return Self.invalid("Shape tree cylinder slices must be within \(ShapeLimits.minSlices)...\(ShapeLimits.maxSlices)")
                }
            case .sphere(let p, let slices):
                if !Self.isPositive(p.radius) {
                    return Self.invalid("Shape tree sphere radius must be positive and finite")
                }
                if !(ShapeLimits.minSlices...ShapeLimits.maxSlices).contains(slices) {
                    return Self.invalid("Shape tree sphere slices must be within \(ShapeLimits.minSlices)...\(ShapeLimits.maxSlices)")
                }
            case .cone(let p, let slices):
                if !Self.isPositive(p.height)
                    || !p.bottomRadius.isFinite || p.bottomRadius < 0
                    || !p.topRadius.isFinite || p.topRadius < 0
                    || (p.bottomRadius <= 0 && p.topRadius <= 0) {
                    return Self.invalid("Shape tree cone dimensions must be positive and finite")
                }
                if !(ShapeLimits.minSlices...ShapeLimits.maxSlices).contains(slices) {
                    return Self.invalid("Shape tree cone slices must be within \(ShapeLimits.minSlices)...\(ShapeLimits.maxSlices)")
                }
            case .extrude(let profile, let distance, _):
                if !Self.isPositive(distance) {
                    return Self.invalid("Shape tree extrude distance must be positive and finite")
                }
                if let err = Self.validateProfile(profile) {
                    return err
                }
            case .revolve(let profile, let angleDegrees, let slices):
                if !Self.isPositive(angleDegrees) || angleDegrees > 360 {
                    return Self.invalid("Shape tree revolve angle must be within (0, 360]")
                }
                if !(ShapeLimits.minSlices...ShapeLimits.maxSlices).contains(slices) {
                    return Self.invalid("Shape tree revolve slices must be within \(ShapeLimits.minSlices)...\(ShapeLimits.maxSlices)")
                }
                if let err = Self.validateProfile(profile) {
                    return err
                }
                let hasPositiveR = profile.points.contains { $0.x > 1e-5 }
                let hasNegativeR = profile.points.contains { $0.x < -1e-5 }
                if hasPositiveR && hasNegativeR {
                    return Self.invalid("Shape tree revolve profile must not cross the revolve axis")
                }
                if !hasPositiveR && !hasNegativeR {
                    return Self.invalid("Shape tree revolve profile must have non-zero radial extent")
                }
            case .translate(let child, let offset):
                if !Self.isFiniteVec3(offset) {
                    return Self.invalid("Shape tree translate offset must be finite")
                }
                stack.append((child, depth + 1))
            case .rotate(let child, let axis, let angleDegrees):
                if !Self.isFiniteVec3(axis) || simd_length_squared(axis) <= 1e-12 || !angleDegrees.isFinite {
                    return Self.invalid("Shape tree rotate axis and angle must be finite and non-zero")
                }
                stack.append((child, depth + 1))
            case .scale(let child, let factor):
                if !Self.isPositive(factor.x) || !Self.isPositive(factor.y) || !Self.isPositive(factor.z) {
                    return Self.invalid("Shape tree scale factors must be positive and finite")
                }
                stack.append((child, depth + 1))
            case .boolean(_, let lhs, let rhs):
                stack.append((rhs, depth + 1))
                stack.append((lhs, depth + 1))
            }
        }
        return nil
    }

    private static func validateProfile(_ profile: SketchProfile) -> KernelError? {
        let plane = profile.plane
        if !isFiniteVec3(plane.origin) || !isFiniteVec3(plane.normal) || !isFiniteVec3(plane.xAxis) {
            return invalid("Shape tree sketch plane vectors must be finite")
        }
        if simd_length_squared(plane.normal) <= 1e-12 || simd_length_squared(plane.xAxis) <= 1e-12 {
            return invalid("Shape tree sketch plane normal and xAxis must be non-zero")
        }
        let cross = simd_cross(simd_normalize(plane.normal), simd_normalize(plane.xAxis))
        if simd_length_squared(cross) <= 1e-6 {
            return invalid("Shape tree sketch plane normal and xAxis must not be parallel")
        }
        let pts = profile.points
        if pts.count < 3 || pts.count > ShapeLimits.maxProfilePoints {
            return invalid("Shape tree sketch profile point count must be within 3...\(ShapeLimits.maxProfilePoints)")
        }
        for pt in pts {
            if !pt.x.isFinite || !pt.y.isFinite {
                return invalid("Shape tree sketch profile points must be finite")
            }
        }
        var twiceArea: Double = 0
        for i in 0..<pts.count {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            twiceArea += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        if abs(twiceArea) <= 1e-6 {
            return invalid("Shape tree sketch profile must have non-zero area")
        }
        return nil
    }

    private static func isFiniteVec3(_ v: SIMD3<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }

    private static func isPositive(_ value: Float) -> Bool { value.isFinite && value > 0 }

    private static func invalid(_ message: String) -> KernelError {
        KernelError(code: .invalidParams, message: message)
    }
}
