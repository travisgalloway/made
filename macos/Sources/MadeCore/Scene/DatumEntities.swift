import Foundation
import simd

// MARK: - Datum Axis

/// Supported creation modes for datum axes in the parametric timeline (ADR-D2).
public enum DatumAxisMode: String, Sendable, Codable, Equatable, CaseIterable {
    case twoPoints
    case edge
    case cylinder
    case normalToPlane
    case preset
}

/// Evaluated 3D geometry representing an infinite directed datum axis.
public struct DatumAxisGeometry: Sendable, Codable, Equatable {
    public var origin: SIMD3<Float>
    public var direction: SIMD3<Float>

    public init(origin: SIMD3<Float> = .zero, direction: SIMD3<Float> = SIMD3<Float>(0, 0, 1)) {
        self.origin = origin
        let len = simd_length(direction)
        self.direction = len > 1e-6 ? direction / len : SIMD3<Float>(0, 0, 1)
    }
}

/// Feature parameters defining a datum axis.
public struct DatumAxisFeatureData: Sendable, Codable, Equatable {
    public var mode: DatumAxisMode
    public var presetName: String?              // "X", "Y", "Z"
    public var point1: SIMD3<Float>?            // First endpoint or explicit origin
    public var point2: SIMD3<Float>?            // Second endpoint
    public var isFlipped: Bool                  // Direction flip flag
    public var cachedAxis: DatumAxisGeometry?

    public init(
        mode: DatumAxisMode = .preset,
        presetName: String? = "Z",
        point1: SIMD3<Float>? = nil,
        point2: SIMD3<Float>? = nil,
        isFlipped: Bool = false,
        cachedAxis: DatumAxisGeometry? = nil
    ) {
        self.mode = mode
        self.presetName = presetName
        self.point1 = point1
        self.point2 = point2
        self.isFlipped = isFlipped
        self.cachedAxis = cachedAxis
    }
}

/// Errors raised during geometric evaluation of datum axes.
public enum DatumAxisError: Error, Equatable, LocalizedError, Sendable {
    case missingReference(String)
    case invalidReference(String)
    case coincidentPoints
    case zeroLengthDirection
    case degenerateGeometry(String)

    public var errorDescription: String? {
        switch self {
        case .missingReference(let msg):
            return "Missing reference: \(msg)"
        case .invalidReference(let msg):
            return "Invalid reference: \(msg)"
        case .coincidentPoints:
            return "Two points are coincident"
        case .zeroLengthDirection:
            return "Zero length direction vector"
        case .degenerateGeometry(let msg):
            return "Degenerate geometry: \(msg)"
        }
    }
}

/// Pure geometric evaluation engine for datum axes.
@MainActor
public enum DatumAxisEvaluator {

    public static func evaluate(
        feature: Feature? = nil,
        data: DatumAxisFeatureData,
        in document: DocumentModel? = nil
    ) throws -> DatumAxisGeometry {
        switch data.mode {
        case .preset:
            var dir: SIMD3<Float>
            switch data.presetName?.uppercased() {
            case "X":
                dir = SIMD3<Float>(1, 0, 0)
            case "Y":
                dir = SIMD3<Float>(0, 1, 0)
            default:
                dir = SIMD3<Float>(0, 0, 1)
            }
            if data.isFlipped {
                dir = -dir
            }
            return DatumAxisGeometry(origin: data.point1 ?? .zero, direction: dir)

        case .twoPoints:
            let p1: SIMD3<Float>
            let p2: SIMD3<Float>

            if let pt1 = data.point1, let pt2 = data.point2 {
                p1 = pt1
                p2 = pt2
            } else if let refs = feature?.references {
                let vertexRefs = refs.compactMap { ref -> SIMD3<Float>? in
                    if case .vertex(let topRef) = ref.target {
                        return topRef.disambiguator?.centroid
                    }
                    return nil
                }
                if vertexRefs.count >= 2 {
                    p1 = vertexRefs[0]
                    p2 = vertexRefs[1]
                } else {
                    throw DatumAxisError.missingReference("Two points mode requires two distinct points or vertex references")
                }
            } else {
                throw DatumAxisError.missingReference("Two points mode requires two distinct points or vertex references")
            }

            let diff = p2 - p1
            let dist = simd_length(diff)
            guard dist > 1e-6 else {
                throw DatumAxisError.coincidentPoints
            }
            var dir = diff / dist
            if data.isFlipped {
                dir = -dir
            }
            return DatumAxisGeometry(origin: p1, direction: dir)

        case .edge:
            var origin: SIMD3<Float>?
            var direction: SIMD3<Float>?

            if let refs = feature?.references {
                for ref in refs {
                    switch ref.target {
                    case .sketchEntity(let featId, let entId):
                        if let doc = document,
                           let sketchFeat = doc.feature(for: featId),
                           case .sketch(let sketchData) = sketchFeat.operation,
                           let ent = sketchData.entities.first(where: { $0.id == entId }),
                           ent.kind == "line",
                           let sp = ent.startPoint,
                           let ep = ent.endPoint {
                            let sketchPlane = doc.resolveSketchPlane(for: sketchData)
                            let yAxis = simd_cross(sketchPlane.normal, sketchPlane.xAxis)
                            let toWorld: (SIMD2<Float>) -> SIMD3<Float> = { pt in
                                sketchPlane.origin + sketchPlane.xAxis * pt.x + yAxis * pt.y
                            }
                            let pStart = toWorld(SIMD2<Float>(Float(sp.x), Float(sp.y)))
                            let pEnd = toWorld(SIMD2<Float>(Float(ep.x), Float(ep.y)))
                            let diff = pEnd - pStart
                            let len = simd_length(diff)
                            if len > 1e-6 {
                                origin = pStart
                                direction = diff / len
                            }
                        }
                    case .edge(let topRef):
                        if let normal = topRef.disambiguator?.normal {
                            let len = simd_length(normal)
                            if len > 1e-6 {
                                direction = normal / len
                            }
                        }
                        if let c = topRef.disambiguator?.centroid {
                            origin = c
                        }
                    default:
                        break
                    }
                    if origin != nil && direction != nil { break }
                }
            }

            if direction == nil, let p1 = data.point1, let p2 = data.point2 {
                let diff = p2 - p1
                let len = simd_length(diff)
                if len > 1e-6 {
                    origin = p1
                    direction = diff / len
                } else {
                    throw DatumAxisError.coincidentPoints
                }
            }

            guard let orig = origin, var dir = direction else {
                throw DatumAxisError.missingReference("Edge mode requires edge or line sketch entity reference")
            }
            guard simd_length(dir) > 1e-6 else {
                throw DatumAxisError.zeroLengthDirection
            }
            if data.isFlipped {
                dir = -dir
            }
            return DatumAxisGeometry(origin: orig, direction: dir)

        case .cylinder:
            var origin: SIMD3<Float>?
            var direction: SIMD3<Float>?

            if let refs = feature?.references {
                for ref in refs {
                    switch ref.target {
                    case .body(let solidId):
                        if let obj = document?.objects.first(where: { $0.id == solidId }) {
                            origin = obj.transform.position
                            direction = simd_act(obj.transform.rotation, SIMD3<Float>(0, 0, 1))
                        }
                    case .face(let topRef):
                        if let n = topRef.disambiguator?.normal {
                            let len = simd_length(n)
                            if len > 1e-6 {
                                direction = n / len
                            }
                        }
                        if let c = topRef.disambiguator?.centroid {
                            origin = c
                        }
                    default:
                        break
                    }
                    if origin != nil && direction != nil { break }
                }
            }

            if direction == nil, let p1 = data.point1, let p2 = data.point2 {
                let diff = p2 - p1
                let len = simd_length(diff)
                if len > 1e-6 {
                    origin = p1
                    direction = diff / len
                } else {
                    throw DatumAxisError.coincidentPoints
                }
            }

            guard let orig = origin ?? data.point1, var dir = direction else {
                throw DatumAxisError.missingReference("Cylinder mode requires cylinder body, cylindrical face, or axis endpoints")
            }
            guard simd_length(dir) > 1e-6 else {
                throw DatumAxisError.zeroLengthDirection
            }
            if data.isFlipped {
                dir = -dir
            }
            return DatumAxisGeometry(origin: orig, direction: dir)

        case .normalToPlane:
            var origin: SIMD3<Float>?
            var direction: SIMD3<Float>?

            if let firstRef = feature?.references.first {
                if let plane = try? DatumPlaneEvaluator.resolveBasePlane(from: firstRef, in: document) {
                    origin = plane.origin
                    direction = plane.normal
                }
            }

            if direction == nil, let p1 = data.point1, let p2 = data.point2 {
                let diff = p2 - p1
                let len = simd_length(diff)
                if len > 1e-6 {
                    origin = p1
                    direction = diff / len
                } else {
                    throw DatumAxisError.coincidentPoints
                }
            }

            guard let orig = origin ?? data.point1, var dir = direction else {
                throw DatumAxisError.missingReference("Normal to plane mode requires a planar face or datum plane reference")
            }
            guard simd_length(dir) > 1e-6 else {
                throw DatumAxisError.zeroLengthDirection
            }
            if data.isFlipped {
                dir = -dir
            }
            return DatumAxisGeometry(origin: orig, direction: dir)
        }
    }
}

// MARK: - Datum Point

/// Supported creation modes for datum points in the parametric timeline (ADR-D2).
public enum DatumPointMode: String, Sendable, Codable, Equatable, CaseIterable {
    case coordinates
    case onVertex
    case arcCenter
    case alongCurve
    case midpoint
    case intersection
}

/// Evaluated 3D geometry representing a datum point.
public struct DatumPointGeometry: Sendable, Codable, Equatable {
    public var position: SIMD3<Float>

    public init(position: SIMD3<Float> = .zero) {
        self.position = position
    }
}

/// Feature parameters defining a datum point.
public struct DatumPointFeatureData: Sendable, Codable, Equatable {
    public var mode: DatumPointMode
    public var coordinates: SIMD3<Float>?       // Explicit 3D position
    public var point1: SIMD3<Float>?            // Secondary / helper point 1
    public var point2: SIMD3<Float>?            // Secondary / helper point 2
    public var curveParameter: Double           // Normalized curve parameter t in [0, 1]
    public var cachedPoint: DatumPointGeometry?

    public init(
        mode: DatumPointMode = .coordinates,
        coordinates: SIMD3<Float>? = .zero,
        point1: SIMD3<Float>? = nil,
        point2: SIMD3<Float>? = nil,
        curveParameter: Double = 0.5,
        cachedPoint: DatumPointGeometry? = nil
    ) {
        self.mode = mode
        self.coordinates = coordinates
        self.point1 = point1
        self.point2 = point2
        self.curveParameter = curveParameter
        self.cachedPoint = cachedPoint
    }
}

/// Errors raised during geometric evaluation of datum points.
public enum DatumPointError: Error, Equatable, LocalizedError, Sendable {
    case missingReference(String)
    case invalidReference(String)
    case noIntersection
    case coincidentPoints
    case degenerateGeometry(String)

    public var errorDescription: String? {
        switch self {
        case .missingReference(let msg):
            return "Missing reference: \(msg)"
        case .invalidReference(let msg):
            return "Invalid reference: \(msg)"
        case .noIntersection:
            return "Line and plane do not intersect (parallel)"
        case .coincidentPoints:
            return "Points are coincident"
        case .degenerateGeometry(let msg):
            return "Degenerate geometry: \(msg)"
        }
    }
}

/// Pure geometric evaluation engine for datum points.
@MainActor
public enum DatumPointEvaluator {

    public static func evaluate(
        feature: Feature? = nil,
        data: DatumPointFeatureData,
        in document: DocumentModel? = nil
    ) throws -> DatumPointGeometry {
        switch data.mode {
        case .coordinates:
            let pos = data.coordinates ?? data.point1 ?? .zero
            return DatumPointGeometry(position: pos)

        case .onVertex:
            if let refs = feature?.references {
                for ref in refs {
                    if case .vertex(let topRef) = ref.target,
                       let c = topRef.disambiguator?.centroid {
                        return DatumPointGeometry(position: c)
                    }
                    if case .sketchEntity(let featId, let entId) = ref.target,
                       let doc = document,
                       let sketchFeat = doc.feature(for: featId),
                       case .sketch(let sketchData) = sketchFeat.operation,
                       let ent = sketchData.entities.first(where: { $0.id == entId }) {
                        let sketchPlane = doc.resolveSketchPlane(for: sketchData)
                        let yAxis = simd_cross(sketchPlane.normal, sketchPlane.xAxis)
                        let toWorld: (SIMD2<Float>) -> SIMD3<Float> = { pt in
                            sketchPlane.origin + sketchPlane.xAxis * pt.x + yAxis * pt.y
                        }
                        if let sp = ent.startPoint {
                            return DatumPointGeometry(position: toWorld(SIMD2<Float>(Float(sp.x), Float(sp.y))))
                        }
                    }
                }
            }
            if let pt = data.coordinates ?? data.point1 {
                return DatumPointGeometry(position: pt)
            }
            throw DatumPointError.missingReference("On vertex mode requires a vertex reference or sketch point")

        case .arcCenter:
            if let refs = feature?.references {
                for ref in refs {
                    if case .sketchEntity(let featId, let entId) = ref.target,
                       let doc = document,
                       let sketchFeat = doc.feature(for: featId),
                       case .sketch(let sketchData) = sketchFeat.operation,
                       let ent = sketchData.entities.first(where: { $0.id == entId }),
                       let cp = ent.centerPoint {
                        let sketchPlane = doc.resolveSketchPlane(for: sketchData)
                        let yAxis = simd_cross(sketchPlane.normal, sketchPlane.xAxis)
                        let pos = sketchPlane.origin + sketchPlane.xAxis * Float(cp.x) + yAxis * Float(cp.y)
                        return DatumPointGeometry(position: pos)
                    }
                    if case .face(let topRef) = ref.target, let c = topRef.disambiguator?.centroid {
                        return DatumPointGeometry(position: c)
                    }
                    if case .edge(let topRef) = ref.target, let c = topRef.disambiguator?.centroid {
                        return DatumPointGeometry(position: c)
                    }
                }
            }
            if let pt = data.coordinates ?? data.point1 {
                return DatumPointGeometry(position: pt)
            }
            throw DatumPointError.missingReference("Arc center mode requires a circle or arc sketch entity or circular edge reference")

        case .alongCurve:
            let t = min(max(Float(data.curveParameter), 0.0), 1.0)
            if let refs = feature?.references {
                for ref in refs {
                    if case .sketchEntity(let featId, let entId) = ref.target,
                       let doc = document,
                       let sketchFeat = doc.feature(for: featId),
                       case .sketch(let sketchData) = sketchFeat.operation,
                       let ent = sketchData.entities.first(where: { $0.id == entId }) {
                        let sketchPlane = doc.resolveSketchPlane(for: sketchData)
                        let yAxis = simd_cross(sketchPlane.normal, sketchPlane.xAxis)
                        let toWorld: (SIMD2<Float>) -> SIMD3<Float> = { pt in
                            sketchPlane.origin + sketchPlane.xAxis * pt.x + yAxis * pt.y
                        }
                        switch ent.kind {
                        case "line":
                            if let sp = ent.startPoint, let ep = ent.endPoint {
                                let spF = SIMD2<Float>(Float(sp.x), Float(sp.y))
                                let epF = SIMD2<Float>(Float(ep.x), Float(ep.y))
                                let pt2D = spF + (epF - spF) * t
                                return DatumPointGeometry(position: toWorld(pt2D))
                            }
                        case "circle", "arc":
                            if let cp = ent.centerPoint {
                                let cpF = SIMD2<Float>(Float(cp.x), Float(cp.y))
                                let radius = Float(ent.radius ?? 10.0)
                                let startAngle: Float
                                let sweepAngle: Float
                                if ent.kind == "circle" {
                                    startAngle = 0.0
                                    sweepAngle = 2.0 * .pi
                                } else {
                                    let sp = ent.startPoint ?? SIMD2(Double(cpF.x + radius), Double(cpF.y))
                                    let ep = ent.endPoint ?? SIMD2(Double(cpF.x), Double(cpF.y + radius))
                                    startAngle = atan2(Float(sp.y - cp.y), Float(sp.x - cp.x))
                                    var endAngle = atan2(Float(ep.y - cp.y), Float(ep.x - cp.x))
                                    if ent.isClockwise && endAngle > startAngle {
                                        endAngle -= 2.0 * .pi
                                    } else if !ent.isClockwise && endAngle < startAngle {
                                        endAngle += 2.0 * .pi
                                    }
                                    sweepAngle = endAngle - startAngle
                                }
                                let angle = startAngle + sweepAngle * t
                                let pt2D = cpF + SIMD2<Float>(cos(angle), sin(angle)) * radius
                                return DatumPointGeometry(position: toWorld(pt2D))
                            }
                        default:
                            break
                        }
                    }
                }
            }
            if let p1 = data.point1, let p2 = data.point2 {
                let pos = p1 + (p2 - p1) * t
                return DatumPointGeometry(position: pos)
            }
            throw DatumPointError.missingReference("Along curve mode requires a curve reference or two bounding points")

        case .midpoint:
            var pts: [SIMD3<Float>] = []
            if let p1 = data.point1, let p2 = data.point2 {
                pts = [p1, p2]
            } else if let refs = feature?.references {
                for ref in refs {
                    if case .vertex(let topRef) = ref.target, let c = topRef.disambiguator?.centroid {
                        pts.append(c)
                    }
                }
            }
            guard pts.count >= 2 else {
                throw DatumPointError.missingReference("Midpoint mode requires two points or vertex references")
            }
            let diff = pts[1] - pts[0]
            guard simd_length(diff) > 1e-6 else {
                throw DatumPointError.coincidentPoints
            }
            return DatumPointGeometry(position: (pts[0] + pts[1]) * 0.5)

        case .intersection:
            var lineOrigin: SIMD3<Float>?
            var lineDir: SIMD3<Float>?
            var planeOrigin: SIMD3<Float>?
            var planeNormal: SIMD3<Float>?

            if let refs = feature?.references {
                for ref in refs {
                    switch ref.target {
                    case .feature(let featId):
                        if let feat = document?.feature(for: featId),
                           case .datumPlane(let planeData) = feat.operation {
                            let plane = planeData.cachedPlane ?? (try? DatumPlaneEvaluator.evaluate(feature: feat, data: planeData, in: document)) ?? SketchPlane.xy
                            planeOrigin = plane.origin
                            planeNormal = plane.normal
                        }
                    case .face:
                        if let plane = try? DatumPlaneEvaluator.resolveBasePlane(from: ref, in: document) {
                            planeOrigin = plane.origin
                            planeNormal = plane.normal
                        }
                    case .edge(let topRef):
                        if let n = topRef.disambiguator?.normal, simd_length(n) > 1e-6 {
                            lineDir = simd_normalize(n)
                        }
                        if let c = topRef.disambiguator?.centroid {
                            lineOrigin = c
                        }
                    default:
                        break
                    }
                }
            }

            if lineOrigin == nil || lineDir == nil {
                if let p1 = data.point1, let p2 = data.point2 {
                    let diff = p2 - p1
                    let len = simd_length(diff)
                    if len > 1e-6 {
                        lineOrigin = p1
                        lineDir = diff / len
                    }
                }
            }

            if planeOrigin == nil || planeNormal == nil {
                let plane = SketchPlane.xy
                planeOrigin = plane.origin
                planeNormal = plane.normal
            }

            guard let lOrig = lineOrigin, let lDir = lineDir,
                  let pOrig = planeOrigin, let pNorm = planeNormal else {
                throw DatumPointError.missingReference("Intersection mode requires a line reference and a plane reference")
            }

            let denom = simd_dot(lDir, pNorm)
            guard abs(denom) > 1e-6 else {
                throw DatumPointError.noIntersection
            }

            let t = simd_dot(pOrig - lOrig, pNorm) / denom
            let intersectionPt = lOrig + lDir * t
            return DatumPointGeometry(position: intersectionPt)
        }
    }
}

// MARK: - Datum Coordinate System (UCS)

/// Supported creation modes for User Coordinate Systems in the parametric timeline (ADR-D2).
public enum DatumCoordinateSystemMode: String, Sendable, Codable, Equatable, CaseIterable {
    case originAndAxes
    case threePoints
    case alignedWithPlane
    case offsetFromParent
}

/// Evaluated 3D geometry representing an orthogonal User Coordinate System (UCS).
public struct DatumCoordinateSystemGeometry: Sendable, Codable, Equatable {
    public var origin: SIMD3<Float>
    public var xAxis: SIMD3<Float>
    public var yAxis: SIMD3<Float>
    public var zAxis: SIMD3<Float>

    public init(
        origin: SIMD3<Float> = .zero,
        xAxis: SIMD3<Float> = SIMD3<Float>(1, 0, 0),
        yAxis: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        zAxis: SIMD3<Float> = SIMD3<Float>(0, 0, 1)
    ) {
        self.origin = origin
        let xLen = simd_length(xAxis)
        let yLen = simd_length(yAxis)
        let zLen = simd_length(zAxis)
        self.xAxis = xLen > 1e-6 ? xAxis / xLen : SIMD3<Float>(1, 0, 0)
        self.yAxis = yLen > 1e-6 ? yAxis / yLen : SIMD3<Float>(0, 1, 0)
        self.zAxis = zLen > 1e-6 ? zAxis / zLen : SIMD3<Float>(0, 0, 1)
    }

    /// 4x4 affine transformation matrix projecting from local UCS space to world space.
    public var transformMatrix: simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(xAxis, 0),
            SIMD4<Float>(yAxis, 0),
            SIMD4<Float>(zAxis, 0),
            SIMD4<Float>(origin, 1)
        )
    }

    /// Inverse 4x4 transformation matrix projecting from world space into local UCS space.
    public var inverseTransformMatrix: simd_float4x4 {
        simd_inverse(transformMatrix)
    }

    /// Projects a 3D point from world space into local UCS coordinates.
    public func toLocal(point: SIMD3<Float>) -> SIMD3<Float> {
        let delta = point - origin
        return SIMD3<Float>(
            simd_dot(delta, xAxis),
            simd_dot(delta, yAxis),
            simd_dot(delta, zAxis)
        )
    }

    /// Projects a 3D point from local UCS coordinates into world space.
    public func toWorld(point: SIMD3<Float>) -> SIMD3<Float> {
        origin + xAxis * point.x + yAxis * point.y + zAxis * point.z
    }

    /// Projects a direction vector from world space into local UCS coordinates.
    public func toLocal(vector: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            simd_dot(vector, xAxis),
            simd_dot(vector, yAxis),
            simd_dot(vector, zAxis)
        )
    }

    /// Projects a direction vector from local UCS coordinates into world space.
    public func toWorld(vector: SIMD3<Float>) -> SIMD3<Float> {
        xAxis * vector.x + yAxis * vector.y + zAxis * vector.z
    }

    /// Converts this coordinate system into a standard `Transform`.
    public var asTransform: Transform {
        let rotMatrix = simd_float3x3(columns: (xAxis, yAxis, zAxis))
        let quat = simd_quatf(rotMatrix)
        return Transform(position: origin, rotation: quat, scale: SIMD3<Float>(1, 1, 1))
    }
}

/// Feature parameters defining a User Coordinate System (UCS).
public struct DatumCoordinateSystemFeatureData: Sendable, Codable, Equatable {
    public var mode: DatumCoordinateSystemMode
    public var origin: SIMD3<Float>?
    public var xAxis: SIMD3<Float>?
    public var yAxis: SIMD3<Float>?
    public var zAxis: SIMD3<Float>?
    public var point1: SIMD3<Float>?            // Three points: Origin
    public var point2: SIMD3<Float>?            // Three points: +X axis
    public var point3: SIMD3<Float>?            // Three points: +XY plane
    public var offsetDistance: SIMD3<Float>?    // Local translation offset (dx, dy, dz)
    public var rotationAngles: SIMD3<Float>?    // Euler rotation angles in degrees (rx, ry, rz)
    public var cachedCoordinateSystem: DatumCoordinateSystemGeometry?

    public init(
        mode: DatumCoordinateSystemMode = .originAndAxes,
        origin: SIMD3<Float>? = .zero,
        xAxis: SIMD3<Float>? = SIMD3<Float>(1, 0, 0),
        yAxis: SIMD3<Float>? = SIMD3<Float>(0, 1, 0),
        zAxis: SIMD3<Float>? = SIMD3<Float>(0, 0, 1),
        point1: SIMD3<Float>? = nil,
        point2: SIMD3<Float>? = nil,
        point3: SIMD3<Float>? = nil,
        offsetDistance: SIMD3<Float>? = nil,
        rotationAngles: SIMD3<Float>? = nil,
        cachedCoordinateSystem: DatumCoordinateSystemGeometry? = nil
    ) {
        self.mode = mode
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
        self.point1 = point1
        self.point2 = point2
        self.point3 = point3
        self.offsetDistance = offsetDistance
        self.rotationAngles = rotationAngles
        self.cachedCoordinateSystem = cachedCoordinateSystem
    }
}

/// Errors raised during geometric evaluation of datum coordinate systems.
public enum DatumCoordinateSystemError: Error, Equatable, LocalizedError, Sendable {
    case missingReference(String)
    case invalidReference(String)
    case collinearPoints
    case coincidentPoints
    case zeroLengthAxis
    case degenerateGeometry(String)

    public var errorDescription: String? {
        switch self {
        case .missingReference(let msg):
            return "Missing reference: \(msg)"
        case .invalidReference(let msg):
            return "Invalid reference: \(msg)"
        case .collinearPoints:
            return "Three points are collinear"
        case .coincidentPoints:
            return "Points are coincident"
        case .zeroLengthAxis:
            return "Zero length coordinate axis"
        case .degenerateGeometry(let msg):
            return "Degenerate geometry: \(msg)"
        }
    }
}

/// Pure geometric evaluation engine for User Coordinate Systems.
@MainActor
public enum DatumCoordinateSystemEvaluator {

    public static func evaluate(
        feature: Feature? = nil,
        data: DatumCoordinateSystemFeatureData,
        in document: DocumentModel? = nil
    ) throws -> DatumCoordinateSystemGeometry {
        switch data.mode {
        case .originAndAxes:
            let origin = data.origin ?? .zero
            let rawX = data.xAxis ?? SIMD3<Float>(1, 0, 0)
            let rawY = data.yAxis ?? SIMD3<Float>(0, 1, 0)
            let rawZ = data.zAxis ?? SIMD3<Float>(0, 0, 1)

            guard simd_length(rawX) > 1e-6, simd_length(rawY) > 1e-6, simd_length(rawZ) > 1e-6 else {
                throw DatumCoordinateSystemError.zeroLengthAxis
            }

            let z = simd_normalize(rawZ)
            let xProj = rawX - z * simd_dot(rawX, z)
            let xLen = simd_length(xProj)
            guard xLen > 1e-6 else {
                throw DatumCoordinateSystemError.degenerateGeometry("X axis is parallel to Z axis")
            }
            let x = xProj / xLen
            let y = simd_cross(z, x)
            return DatumCoordinateSystemGeometry(origin: origin, xAxis: x, yAxis: y, zAxis: z)

        case .threePoints:
            let p1: SIMD3<Float>
            let p2: SIMD3<Float>
            let p3: SIMD3<Float>

            if let pt1 = data.point1, let pt2 = data.point2, let pt3 = data.point3 {
                p1 = pt1
                p2 = pt2
                p3 = pt3
            } else if let refs = feature?.references {
                let vertexRefs = refs.compactMap { ref -> SIMD3<Float>? in
                    if case .vertex(let topRef) = ref.target {
                        return topRef.disambiguator?.centroid
                    }
                    return nil
                }
                if vertexRefs.count >= 3 {
                    p1 = vertexRefs[0]
                    p2 = vertexRefs[1]
                    p3 = vertexRefs[2]
                } else {
                    throw DatumCoordinateSystemError.missingReference("Three points mode requires 3 non-collinear points or vertex references")
                }
            } else {
                throw DatumCoordinateSystemError.missingReference("Three points mode requires 3 non-collinear points or vertex references")
            }

            let v1 = p2 - p1
            let v2 = p3 - p1
            let v3 = p3 - p2

            let len1 = simd_length(v1)
            let len2 = simd_length(v2)
            let len3 = simd_length(v3)

            guard len1 > 1e-6 && len2 > 1e-6 && len3 > 1e-6 else {
                throw DatumCoordinateSystemError.coincidentPoints
            }

            let x = v1 / len1
            let cross = simd_cross(x, v2)
            let crossLen = simd_length(cross)
            guard crossLen > 1e-6 else {
                throw DatumCoordinateSystemError.collinearPoints
            }

            let z = cross / crossLen
            let y = simd_cross(z, x)
            return DatumCoordinateSystemGeometry(origin: p1, xAxis: x, yAxis: y, zAxis: z)

        case .alignedWithPlane:
            let plane: SketchPlane
            if let firstRef = feature?.references.first {
                plane = try DatumPlaneEvaluator.resolveBasePlane(from: firstRef, in: document)
            } else {
                plane = .xy
            }

            let origin = plane.origin
            let z = simd_normalize(plane.normal)
            let x = simd_normalize(plane.xAxis)
            let y = simd_cross(z, x)
            return DatumCoordinateSystemGeometry(origin: origin, xAxis: x, yAxis: y, zAxis: z)

        case .offsetFromParent:
            var parentFrame = DatumCoordinateSystemGeometry()

            if let firstRef = feature?.references.first {
                switch firstRef.target {
                case .feature(let featId):
                    if let parentFeat = document?.feature(for: featId),
                       case .datumCoordinateSystem(let parentData) = parentFeat.operation {
                        if let cached = parentData.cachedCoordinateSystem {
                            parentFrame = cached
                        } else {
                            parentFrame = try evaluate(feature: parentFeat, data: parentData, in: document)
                        }
                    }
                default:
                    break
                }
            }

            let offset = data.offsetDistance ?? .zero
            let anglesDeg = data.rotationAngles ?? .zero
            let radX = anglesDeg.x * .pi / 180.0
            let radY = anglesDeg.y * .pi / 180.0
            let radZ = anglesDeg.z * .pi / 180.0

            let qX = simd_quatf(angle: radX, axis: SIMD3<Float>(1, 0, 0))
            let qY = simd_quatf(angle: radY, axis: SIMD3<Float>(0, 1, 0))
            let qZ = simd_quatf(angle: radZ, axis: SIMD3<Float>(0, 0, 1))
            let qLocal = qZ * qY * qX

            let rotX = simd_act(qLocal, SIMD3<Float>(1, 0, 0))
            let rotY = simd_act(qLocal, SIMD3<Float>(0, 1, 0))
            let rotZ = simd_act(qLocal, SIMD3<Float>(0, 0, 1))

            let newOrigin = parentFrame.origin +
                parentFrame.xAxis * offset.x +
                parentFrame.yAxis * offset.y +
                parentFrame.zAxis * offset.z

            let worldX = parentFrame.toWorld(vector: rotX)
            let worldY = parentFrame.toWorld(vector: rotY)
            let worldZ = parentFrame.toWorld(vector: rotZ)

            return DatumCoordinateSystemGeometry(
                origin: newOrigin,
                xAxis: simd_normalize(worldX),
                yAxis: simd_normalize(worldY),
                zAxis: simd_normalize(worldZ)
            )
        }
    }
}
