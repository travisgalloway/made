import Foundation
import simd

/// Supported creation modes for datum construction planes in the parametric timeline (ADR-D2).
public enum DatumPlaneMode: String, Sendable, Codable, Equatable, CaseIterable {
    case origin
    case offset
    case atAngle
    case threePoints
    case normalToCurve
    case midplane
    case tangent
}

/// Feature parameters defining a datum construction plane.
public struct DatumPlaneFeatureData: Sendable, Codable, Equatable {
    public var mode: DatumPlaneMode
    public var originPreset: String?            // "XY", "XZ", "YZ"
    public var offsetDistance: Double           // Signed offset distance
    public var angleDegrees: Double             // Rotation angle in degrees
    public var curveParameter: Double           // Parameter t along curve [0, 1]
    public var point1: SIMD3<Float>?            // Explicit or resolved coordinates
    public var point2: SIMD3<Float>?
    public var point3: SIMD3<Float>?
    public var isFlipped: Bool
    public var cachedPlane: SketchPlane?

    public init(
        mode: DatumPlaneMode = .origin,
        originPreset: String? = "XY",
        offsetDistance: Double = 0.0,
        angleDegrees: Double = 0.0,
        curveParameter: Double = 0.0,
        point1: SIMD3<Float>? = nil,
        point2: SIMD3<Float>? = nil,
        point3: SIMD3<Float>? = nil,
        isFlipped: Bool = false,
        cachedPlane: SketchPlane? = nil
    ) {
        self.mode = mode
        self.originPreset = originPreset
        self.offsetDistance = offsetDistance
        self.angleDegrees = angleDegrees
        self.curveParameter = curveParameter
        self.point1 = point1
        self.point2 = point2
        self.point3 = point3
        self.isFlipped = isFlipped
        self.cachedPlane = cachedPlane
    }
}

/// Errors raised during geometric evaluation of datum planes.
public enum DatumPlaneError: Error, Equatable, LocalizedError, Sendable {
    case missingReference(String)
    case invalidReference(String)
    case collinearPoints
    case coincidentPoints
    case zeroLengthNormal
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
        case .zeroLengthNormal:
            return "Zero length normal or tangent vector"
        case .degenerateGeometry(let msg):
            return "Degenerate geometry: \(msg)"
        }
    }
}

/// Pure geometric evaluation engine computing 3D coordinate frames (`SketchPlane`) for datum planes.
@MainActor
public enum DatumPlaneEvaluator {

    /// Constructs an orthogonal unit vector along X for a given unit normal vector.
    public static func buildOrthogonalXAxis(normal: SIMD3<Float>) -> SIMD3<Float> {
        let n = simd_normalize(normal)
        if abs(n.z) > 0.9 {
            let v = SIMD3<Float>(1, 0, 0)
            let projected = v - n * simd_dot(v, n)
            let len = simd_length(projected)
            return len > 1e-6 ? projected / len : SIMD3<Float>(0, 1, 0)
        } else {
            let v = SIMD3<Float>(0, 0, 1)
            let projected = v - n * simd_dot(v, n)
            let len = simd_length(projected)
            return len > 1e-6 ? projected / len : SIMD3<Float>(1, 0, 0)
        }
    }

    /// Returns the preset coordinate frame for "XY", "XZ", or "YZ".
    public static func presetPlane(named name: String?) -> SketchPlane {
        switch name?.uppercased() {
        case "XZ":
            return .xz
        case "YZ":
            return .yz
        default:
            return .xy
        }
    }

    /// Resolves an upstream base plane from a reference.
    public static func resolveBasePlane(from ref: Reference, in document: DocumentModel?) throws -> SketchPlane {
        switch ref.target {
        case .feature(let featId):
            guard let feat = document?.feature(for: featId) else {
                throw DatumPlaneError.missingReference("Referenced feature '\(featId.uuidString)' not found in document")
            }
            if feat.isSuppressed {
                throw DatumPlaneError.invalidReference("Referenced feature '\(feat.name)' is suppressed")
            }
            if case .datumPlane(let datumData) = feat.operation {
                if let cached = datumData.cachedPlane {
                    return cached
                }
                return try evaluate(feature: feat, data: datumData, in: document)
            } else if case .sketch(let sketchData) = feat.operation {
                if let doc = document {
                    return doc.resolveSketchPlane(for: sketchData)
                }
                return presetPlane(named: sketchData.planeName)
            } else {
                throw DatumPlaneError.invalidReference("Referenced feature '\(feat.name)' is not a planar datum or sketch")
            }
        case .face(let topRef):
            guard let sig = topRef.disambiguator, let normal = sig.normal else {
                throw DatumPlaneError.invalidReference("Planar face reference missing normal signature")
            }
            let len = simd_length(normal)
            guard len > 1e-6 else {
                throw DatumPlaneError.zeroLengthNormal
            }
            let norm = normal / len
            let origin = sig.centroid ?? .zero
            let xAxis = buildOrthogonalXAxis(normal: norm)
            return SketchPlane(origin: origin, normal: norm, xAxis: xAxis)
        default:
            throw DatumPlaneError.invalidReference("Unsupported reference target '\(ref.target)' for planar base")
        }
    }

    /// Evaluates datum plane feature data in the context of an optional feature and document.
    public static func evaluate(
        feature: Feature? = nil,
        data: DatumPlaneFeatureData,
        in document: DocumentModel? = nil
    ) throws -> SketchPlane {
        switch data.mode {
        case .origin:
            let basePlane = presetPlane(named: data.originPreset)
            var normal = basePlane.normal
            if data.isFlipped {
                normal = -normal
            }
            let origin = basePlane.origin + normal * Float(data.offsetDistance)
            let xAxis = basePlane.xAxis
            return SketchPlane(origin: origin, normal: simd_normalize(normal), xAxis: simd_normalize(xAxis))

        case .offset:
            let basePlane: SketchPlane
            if let firstRef = feature?.references.first {
                basePlane = try resolveBasePlane(from: firstRef, in: document)
            } else if let cached = data.cachedPlane {
                basePlane = cached
            } else if let preset = data.originPreset {
                basePlane = presetPlane(named: preset)
            } else {
                throw DatumPlaneError.missingReference("Offset plane requires a reference plane or face")
            }
            var normal = basePlane.normal
            if data.isFlipped {
                normal = -normal
            }
            let origin = basePlane.origin + normal * Float(data.offsetDistance)
            let xAxis = basePlane.xAxis
            return SketchPlane(origin: origin, normal: simd_normalize(normal), xAxis: simd_normalize(xAxis))

        case .atAngle:
            let basePlane: SketchPlane
            if let firstRef = feature?.references.first {
                basePlane = try resolveBasePlane(from: firstRef, in: document)
            } else if let cached = data.cachedPlane {
                basePlane = cached
            } else if let preset = data.originPreset {
                basePlane = presetPlane(named: preset)
            } else {
                throw DatumPlaneError.missingReference("Angle plane requires a reference plane")
            }

            var axis: SIMD3<Float>
            var axisOrigin: SIMD3<Float> = basePlane.origin

            if let p1 = data.point1, let p2 = data.point2 {
                axis = p2 - p1
                axisOrigin = p1
            } else if let refs = feature?.references, refs.count > 1, case .edge(let edgeRef) = refs[1].target {
                if let dir = edgeRef.disambiguator?.normal {
                    axis = dir
                } else {
                    axis = basePlane.xAxis
                }
                if let c = edgeRef.disambiguator?.centroid {
                    axisOrigin = c
                }
            } else {
                axis = basePlane.xAxis
            }

            let axisLen = simd_length(axis)
            guard axisLen > 1e-6 else {
                throw DatumPlaneError.zeroLengthNormal
            }
            let axisNorm = axis / axisLen

            let angleRad = Float(data.angleDegrees * .pi / 180.0)
            let q = simd_quatf(angle: angleRad, axis: axisNorm)
            var normal = simd_act(q, basePlane.normal)
            let xAxis = simd_act(q, basePlane.xAxis)

            if data.isFlipped {
                normal = -normal
            }
            var origin = axisOrigin
            if data.offsetDistance != 0 {
                origin += normal * Float(data.offsetDistance)
            }
            return SketchPlane(origin: origin, normal: simd_normalize(normal), xAxis: simd_normalize(xAxis))

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
                    throw DatumPlaneError.missingReference("Three points mode requires 3 non-collinear points or vertex references")
                }
            } else {
                throw DatumPlaneError.missingReference("Three points mode requires 3 non-collinear points or vertex references")
            }

            let v1 = p2 - p1
            let v2 = p3 - p1
            let v3 = p3 - p2

            let len1 = simd_length(v1)
            let len2 = simd_length(v2)
            let len3 = simd_length(v3)

            if len1 < 1e-6 || len2 < 1e-6 || len3 < 1e-6 {
                throw DatumPlaneError.coincidentPoints
            }

            let n = simd_cross(v1, v2)
            let lenN = simd_length(n)
            if lenN < 1e-6 {
                throw DatumPlaneError.collinearPoints
            }

            var normal = n / lenN
            if data.isFlipped {
                normal = -normal
            }
            let xAxis = v1 / len1
            var origin = p1
            if data.offsetDistance != 0 {
                origin += normal * Float(data.offsetDistance)
            }
            return SketchPlane(origin: origin, normal: normal, xAxis: xAxis)

        case .normalToCurve:
            var tangent: SIMD3<Float>?
            var curvePt: SIMD3<Float>?

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
                        let toWorldVec: (SIMD2<Float>) -> SIMD3<Float> = { vec in
                            sketchPlane.xAxis * vec.x + yAxis * vec.y
                        }

                        switch ent.kind {
                        case "line":
                            if let sp = ent.startPoint, let ep = ent.endPoint {
                                let spF = SIMD2<Float>(Float(sp.x), Float(sp.y))
                                let epF = SIMD2<Float>(Float(ep.x), Float(ep.y))
                                let pt2D = spF + (epF - spF) * t
                                curvePt = toWorld(pt2D)
                                tangent = toWorldVec(epF - spF)
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
                                curvePt = toWorld(pt2D)
                                let tan2D = SIMD2<Float>(-sin(angle), cos(angle)) * (sweepAngle >= 0 ? 1.0 : -1.0)
                                tangent = toWorldVec(tan2D)
                            }
                        default:
                            break
                        }
                        break
                    }
                }
            }

            if tangent == nil, let p1 = data.point1, let p2 = data.point2 {
                let dir = p2 - p1
                tangent = dir
                curvePt = p1 + dir * t
            }

            guard let tVec = tangent, let cPt = curvePt else {
                throw DatumPlaneError.missingReference("Normal to curve mode requires curve reference or endpoints")
            }

            let tLen = simd_length(tVec)
            guard tLen > 1e-6 else {
                throw DatumPlaneError.zeroLengthNormal
            }

            var normal = tVec / tLen
            if data.isFlipped {
                normal = -normal
            }
            var origin = cPt
            if data.offsetDistance != 0 {
                origin += normal * Float(data.offsetDistance)
            }
            let xAxis = buildOrthogonalXAxis(normal: normal)
            return SketchPlane(origin: origin, normal: normal, xAxis: xAxis)

        case .midplane:
            if let p1 = data.point1, let p2 = data.point2 {
                let diff = p2 - p1
                let len = simd_length(diff)
                guard len > 1e-6 else {
                    throw DatumPlaneError.coincidentPoints
                }
                var normal = diff / len
                if data.isFlipped {
                    normal = -normal
                }
                var origin = (p1 + p2) * 0.5
                if data.offsetDistance != 0 {
                    origin += normal * Float(data.offsetDistance)
                }
                let xAxis = buildOrthogonalXAxis(normal: normal)
                return SketchPlane(origin: origin, normal: normal, xAxis: xAxis)
            } else if let refs = feature?.references, refs.count >= 2 {
                let plane1 = try resolveBasePlane(from: refs[0], in: document)
                let plane2 = try resolveBasePlane(from: refs[1], in: document)
                var origin = (plane1.origin + plane2.origin) * 0.5
                let dot = simd_dot(plane1.normal, plane2.normal)
                var normal: SIMD3<Float>
                if abs(dot) > 0.999 {
                    normal = plane1.normal
                } else {
                    let bisector = plane1.normal + plane2.normal
                    let bLen = simd_length(bisector)
                    if bLen < 1e-6 {
                        normal = plane1.normal
                    } else {
                        normal = bisector / bLen
                    }
                }
                if data.isFlipped {
                    normal = -normal
                }
                if data.offsetDistance != 0 {
                    origin += normal * Float(data.offsetDistance)
                }
                let xAxis = buildOrthogonalXAxis(normal: normal)
                return SketchPlane(origin: origin, normal: normal, xAxis: xAxis)
            } else {
                throw DatumPlaneError.missingReference("Midplane requires two points or two plane references")
            }

        case .tangent:
            var contactPt: SIMD3<Float>? = data.point1
            var surfaceNormal: SIMD3<Float>?

            if let firstRef = feature?.references.first {
                switch firstRef.target {
                case .face(let topRef):
                    if let normal = topRef.disambiguator?.normal {
                        surfaceNormal = normal
                    }
                    if contactPt == nil {
                        contactPt = topRef.disambiguator?.centroid
                    }
                    if let refs = feature?.references, refs.count > 1 {
                        let refPlane = try resolveBasePlane(from: refs[1], in: document)
                        surfaceNormal = refPlane.normal
                    }
                case .body(let solidId):
                    if let obj = document?.objects.first(where: { $0.id == solidId }),
                       case .cylinder = obj.def {
                        if let pt = contactPt {
                            let radial = SIMD3<Float>(pt.x, pt.y, 0)
                            let rLen = simd_length(radial)
                            if rLen > 1e-6 {
                                surfaceNormal = radial / rLen
                            }
                        }
                    }
                default:
                    break
                }
            }

            if surfaceNormal == nil, let pt = contactPt {
                if let center = data.point2 {
                    let diff = pt - center
                    let diffLen = simd_length(diff)
                    if diffLen > 1e-6 {
                        surfaceNormal = diff / diffLen
                    }
                } else {
                    let radial = SIMD3<Float>(pt.x, pt.y, 0)
                    let rLen = simd_length(radial)
                    if rLen > 1e-6 {
                        surfaceNormal = radial / rLen
                    } else {
                        let sLen = simd_length(pt)
                        if sLen > 1e-6 {
                            surfaceNormal = pt / sLen
                        }
                    }
                }
            }

            guard let pt = contactPt else {
                throw DatumPlaneError.missingReference("Tangent plane requires contact point or curved face reference")
            }
            guard let sNorm = surfaceNormal else {
                throw DatumPlaneError.zeroLengthNormal
            }

            let nLen = simd_length(sNorm)
            guard nLen > 1e-6 else {
                throw DatumPlaneError.zeroLengthNormal
            }

            var normal = sNorm / nLen
            if data.isFlipped {
                normal = -normal
            }
            var origin = pt
            if data.offsetDistance != 0 {
                origin += normal * Float(data.offsetDistance)
            }
            let xAxis = buildOrthogonalXAxis(normal: normal)
            return SketchPlane(origin: origin, normal: normal, xAxis: xAxis)
        }
    }
}
