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
        case .revolveSolid(let params, let slices):
            return revolveMesh(params: params, slices: slices)
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
        var outerPts = orientedPoints(profile.points, clockwise: false)
        if let first = outerPts.first {
            outerPts.append(first)
        }
        let outerPathPoints = outerPts.map { PathPoint.point(Double($0.x), Double($0.y), 0) }
        let outerPath = Path(outerPathPoints)

        let compositePath: Path
        if profile.holes.isEmpty {
            compositePath = outerPath
        } else {
            let holeSubpaths: [Path] = profile.holes.compactMap { hole in
                guard !hole.isEmpty else { return nil }
                var holePts = orientedPoints(hole, clockwise: true)
                if let first = holePts.first {
                    holePts.append(first)
                }
                let holePathPoints = holePts.map { PathPoint.point(Double($0.x), Double($0.y), 0) }
                return Path(holePathPoints)
            }
            compositePath = Path(subpaths: [outerPath] + holeSubpaths)
        }

        var extruded = Mesh.extrude(compositePath, depth: Double(distance))
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

    static func validateRevolveAxis(
        profile: SketchProfile,
        axisOrigin: SIMD3<Float>,
        axisDirection: SIMD3<Float>
    ) -> String? {
        let dirLen = simd_length(axisDirection)
        guard dirLen > 1e-6 else {
            return "Revolve axis direction must not be zero"
        }
        let aDir = simd_normalize(SIMD3<Double>(Double(axisDirection.x), Double(axisDirection.y), Double(axisDirection.z)))
        let a0 = SIMD3<Double>(Double(axisOrigin.x), Double(axisOrigin.y), Double(axisOrigin.z))
        let planeNorm = simd_normalize(SIMD3<Double>(Double(profile.plane.normal.x), Double(profile.plane.normal.y), Double(profile.plane.normal.z)))

        var v = simd_cross(aDir, planeNorm)
        if simd_length(v) < 1e-6 {
            v = simd_cross(planeNorm, aDir)
        }
        guard simd_length(v) > 1e-6 else {
            return "Revolve axis cannot be perpendicular to the sketch plane"
        }
        var rDir = simd_normalize(v)

        let points3D = profile.points.map { pt -> SIMD3<Double> in
            let unproj = profile.plane.unprojectPoint(SIMD2<Double>(Double(pt.x), Double(pt.y)))
            return SIMD3<Double>(Double(unproj.x), Double(unproj.y), Double(unproj.z))
        }

        var rValues = points3D.map { p -> Double in
            let delta = p - a0
            return simd_dot(delta, rDir)
        }

        let maxR = rValues.max() ?? 0
        let minR = rValues.min() ?? 0

        if maxR > 1e-4 && minR < -1e-4 {
            return "Revolve axis crosses the sketch profile"
        }

        if maxR <= 1e-4 {
            rDir = -rDir
            rValues = rValues.map { -$0 }
        }

        let nonZeroR = rValues.filter { $0 > 1e-4 }
        if nonZeroR.isEmpty {
            return "Revolve axis has zero radial extent"
        }

        return nil
    }

    static func revolveMesh(params: RevolveParams, slices: Int = 128) -> Euclid.Mesh {
        let dirLen = simd_length(params.axisDirection)
        guard dirLen > 1e-6 else { return Mesh([]) }
        let aDir = simd_normalize(SIMD3<Double>(Double(params.axisDirection.x), Double(params.axisDirection.y), Double(params.axisDirection.z)))
        let a0 = SIMD3<Double>(Double(params.axisOrigin.x), Double(params.axisOrigin.y), Double(params.axisOrigin.z))
        let planeNorm = simd_normalize(SIMD3<Double>(Double(params.profile.plane.normal.x), Double(params.profile.plane.normal.y), Double(params.profile.plane.normal.z)))

        var v = simd_cross(aDir, planeNorm)
        if simd_length(v) < 1e-6 {
            v = simd_cross(planeNorm, aDir)
        }
        guard simd_length(v) > 1e-6 else { return Mesh([]) }
        var rDir = simd_normalize(v)

        let points3D = params.profile.points.map { pt -> SIMD3<Double> in
            let unproj = params.profile.plane.unprojectPoint(SIMD2<Double>(Double(pt.x), Double(pt.y)))
            return SIMD3<Double>(Double(unproj.x), Double(unproj.y), Double(unproj.z))
        }

        var localRZ: [(r: Double, z: Double)] = points3D.map { p in
            let delta = p - a0
            return (r: simd_dot(delta, rDir), z: simd_dot(delta, aDir))
        }

        let maxR = localRZ.map(\.r).max() ?? 0
        let minR = localRZ.map(\.r).min() ?? 0

        if maxR > 1e-4 && minR < -1e-4 {
            return Mesh([])
        }

        if maxR <= 1e-4 {
            rDir = -rDir
            localRZ = localRZ.map { (r: -$0.r, z: $0.z) }
        }

        localRZ = localRZ.map { (r: abs($0.r) <= 1e-4 ? 0.0 : $0.r, z: $0.z) }
        guard (localRZ.map(\.r).max() ?? 0) > 1e-4 else {
            return Mesh([])
        }

        let tDir = simd_cross(aDir, rDir)
        let local2DPts = localRZ.map { SIMD2<Float>(Float($0.r), Float($0.z)) }

        let isFull = params.mode == .full || (params.mode == .angle && params.angle >= 360.0 - 1e-4)

        if isFull {
            var pts = orientedPoints(local2DPts, clockwise: false)
            if let first = pts.first {
                pts.append(first)
            }
            let pathPoints = pts.map { PathPoint.point(-Double($0.x), Double($0.y), 0) }
            let path = Path(pathPoints)
            let segs = max(128, slices)
            let lathed = Mesh.lathe(path, slices: segs).rotated(by: .pitch(-.halfPi))
            return transformFromLocalFrame(lathed, rDir: rDir, tDir: tDir, aDir: aDir, origin: a0)
        }

        let thetaStart: Double
        let thetaEnd: Double
        switch params.mode {
        case .full:
            thetaStart = 0
            thetaEnd = 2.0 * .pi
        case .angle:
            thetaStart = 0
            thetaEnd = params.angle * .pi / 180.0
        case .symmetric:
            let half = (params.angle / 2.0) * .pi / 180.0
            thetaStart = -half
            thetaEnd = half
        case .twoDirection:
            thetaStart = -params.angle2 * .pi / 180.0
            thetaEnd = params.angle * .pi / 180.0
        }

        let pts = orientedPoints(local2DPts, clockwise: true)
        let sweepSpan = abs(thetaEnd - thetaStart)
        let segs = max(16, Int(ceil(Double(max(64, slices)) * (sweepSpan / (2.0 * .pi)))))
        var sections: [Path] = []
        sections.reserveCapacity(segs + 1)
        for i in 0...segs {
            let t = Double(i) / Double(segs)
            let theta = thetaStart + t * (thetaEnd - thetaStart)
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
        return transformFromLocalFrame(lofted, rDir: rDir, tDir: tDir, aDir: aDir, origin: a0)
    }

    private static func transformFromLocalFrame(
        _ mesh: Euclid.Mesh,
        rDir: SIMD3<Double>,
        tDir: SIMD3<Double>,
        aDir: SIMD3<Double>,
        origin: SIMD3<Double>
    ) -> Euclid.Mesh {
        let matrix = simd_double3x3(columns: (rDir, tDir, aDir))
        let quat = simd_quatd(matrix)
        var result = mesh
        let angle = quat.angle
        if abs(angle) > 1e-9, simd_length_squared(quat.axis) > 1e-12 {
            let axis = simd_normalize(quat.axis)
            if let rot = Rotation(axis: Vector(axis.x, axis.y, axis.z), angle: .radians(-angle)) {
                result = result.rotated(by: rot)
            }
        }
        if origin != .zero {
            result = result.translated(by: Vector(origin.x, origin.y, origin.z))
        }
        return result
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
