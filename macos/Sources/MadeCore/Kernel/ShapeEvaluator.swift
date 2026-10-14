import Foundation
import Euclid
import simd

/// Evaluates a validated DSL shape tree into a Tier 1 Euclid mesh (ADR-D1, ADR-D9 #247).
///
/// Executes pure-Swift procedural geometry evaluation for Cadova-style scripting and procedural primitives.
/// Only `LocalKernelEngine` calls it, on the engine actor (Invariant 1). Euclid types do not escape past
/// the kernel boundary (Invariant 4).
enum ShapeEvaluator {
    static func mesh(for node: ShapeNode) -> Euclid.Mesh {
        switch node {
        case .box(let p):
            return EuclidEngine.makeBox(width: p.width, depth: p.depth, height: p.height)
        case .cylinder(let p, let slices):
            return EuclidEngine.makeCylinder(radius: p.radius, height: p.height, slices: slices)
        case .sphere(let p, let slices):
            return EuclidEngine.makeSphere(radius: p.radius, slices: slices)
        case .cone(let p, let slices):
            return EuclidEngine.makeCone(bottomRadius: p.bottomRadius, topRadius: p.topRadius, height: p.height, slices: slices)
        case .extrude(let profile, let distance, let centered):
            return extrudeMesh(profile: profile, distance: distance, centered: centered)
        case .revolve(let profile, let angleDegrees, let slices):
            return revolveMesh(profile: profile, angleDegrees: angleDegrees, slices: slices)
        case .translate(let child, let offset):
            return mesh(for: child).translated(by: Vector(Double(offset.x), Double(offset.y), Double(offset.z)))
        case .rotate(let child, let axis, let angleDegrees):
            let norm = simd_normalize(SIMD3<Double>(axis))
            let euclidAxis = Vector(norm.x, norm.y, norm.z)
            let rotation = Rotation(axis: euclidAxis, angle: .degrees(-Double(angleDegrees))) ?? .identity
            return mesh(for: child).rotated(by: rotation)
        case .scale(let child, let factor):
            return mesh(for: child).scaled(by: Vector(Double(factor.x), Double(factor.y), Double(factor.z)))
        case .boolean(let op, let lhs, let rhs):
            let a = mesh(for: lhs), b = mesh(for: rhs)
            switch op {
            case .subtract: return EuclidEngine.subtract(a, b)
            case .union: return EuclidEngine.union(a, b)
            case .intersect: return EuclidEngine.intersect(a, b)
            }
        }
    }

    private static func extrudeMesh(profile: SketchProfile, distance: Float, centered: Bool) -> Euclid.Mesh {
        var pts = orientedPoints(profile.points, clockwise: false)
        if let first = pts.first {
            pts.append(first)
        }
        let pathPoints = pts.map { PathPoint.point(Double($0.x), Double($0.y), 0) }
        let path = Path(pathPoints)
        var extruded = Mesh.extrude(path, depth: Double(distance))
        if !centered {
            extruded = extruded.translated(by: Vector(0, 0, Double(distance) / 2.0))
        }
        return transformFromPlane(extruded, plane: profile.plane)
    }

    private static func revolveMesh(profile: SketchProfile, angleDegrees: Float, slices: Int) -> Euclid.Mesh {
        let segs = max(3, slices)
        if angleDegrees >= 360.0 - 1e-4 {
            var pts = orientedPoints(profile.points, clockwise: false)
            if let first = pts.first {
                pts.append(first)
            }
            let pathPoints = pts.map { PathPoint.point(-Double($0.x), Double($0.y), 0) }
            let path = Path(pathPoints)
            let lathed = Mesh.lathe(path, slices: segs).rotated(by: .pitch(-.halfPi))
            return transformRevolvedFromPlane(lathed, plane: profile.plane)
        }

        let pts = orientedPoints(profile.points, clockwise: true)
        let totalRad = Double(angleDegrees) * .pi / 180.0
        var sections: [Path] = []
        sections.reserveCapacity(segs + 1)
        for i in 0...segs {
            let theta = (Double(i) / Double(segs)) * totalRad
            let cosT = cos(theta)
            let sinT = sin(theta)
            var ring: [PathPoint] = pts.map { pt in
                let r = Double(pt.x)
                let z = Double(pt.y)
                return .point(r * cosT, r * sinT, z)
            }
            if let first = ring.first {
                ring.append(first)
            }
            sections.append(Path(ring))
        }
        let lofted = Mesh.loft(sections)
        return transformRevolvedFromPlane(lofted, plane: profile.plane)
    }

    private static func orientedPoints(_ points: [SIMD2<Float>], clockwise: Bool) -> [SIMD2<Float>] {
        var twiceArea: Double = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            twiceArea += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        let isCCW = twiceArea > 0
        if clockwise {
            return isCCW ? points.reversed() : points
        } else {
            return isCCW ? points : points.reversed()
        }
    }

    private static func transformFromPlane(_ mesh: Euclid.Mesh, plane: SketchPlane) -> Euclid.Mesh {
        let n = simd_normalize(SIMD3<Double>(plane.normal))
        let rawX = SIMD3<Double>(plane.xAxis)
        let u = simd_normalize(rawX - simd_dot(rawX, n) * n)
        let v = simd_cross(n, u)
        let matrix = simd_double3x3(columns: (u, v, n))
        let quat = simd_quatd(matrix)
        var result = mesh
        let angle = quat.angle
        if abs(angle) > 1e-9, simd_length_squared(quat.axis) > 1e-12 {
            let axis = simd_normalize(quat.axis)
            if let rot = Rotation(axis: Vector(axis.x, axis.y, axis.z), angle: .radians(-angle)) {
                result = result.rotated(by: rot)
            }
        }
        let origin = plane.origin
        if origin != .zero {
            result = result.translated(by: Vector(Double(origin.x), Double(origin.y), Double(origin.z)))
        }
        return result
    }

    private static func transformRevolvedFromPlane(_ mesh: Euclid.Mesh, plane: SketchPlane) -> Euclid.Mesh {
        var result = mesh
        let origin = plane.origin
        if origin != .zero {
            result = result.translated(by: Vector(Double(origin.x), Double(origin.y), Double(origin.z)))
        }
        return result
    }
}
