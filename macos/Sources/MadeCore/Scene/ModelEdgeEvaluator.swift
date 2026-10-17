import Foundation
import simd

/// Engine-neutral representation of a 3D geometric curve evaluated from model edges or upstream sketches.
public enum EvaluatedCurve3D: Sendable, Equatable {
    case line(start: SIMD3<Float>, end: SIMD3<Float>)
    case circle(center: SIMD3<Float>, normal: SIMD3<Float>, radius: Double)
    case arc(
        center: SIMD3<Float>,
        normal: SIMD3<Float>,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        startPoint: SIMD3<Float>,
        endPoint: SIMD3<Float>,
        clockwise: Bool = false
    )
}

/// Evaluates 3D curves from parametric features, topology references, and sketch entities (Invariant 4).
@MainActor
public enum ModelEdgeEvaluator {

    /// Evaluates a 3D curve from a reference in the document.
    public static func evaluate(
        reference: Reference,
        in document: DocumentModel
    ) -> Result<EvaluatedCurve3D, ReferenceResolutionError> {
        switch reference.target {
        case .sketchEntity(let featureId, let entityId):
            return evaluateSketchEntity(featureId: featureId, entityId: entityId, in: document)

        case .edge(let topRef):
            return evaluateTopologicalEdge(reference: topRef, in: document)

        case .feature, .body, .face, .vertex:
            return .failure(.typeMismatch(expected: "edge or sketchEntity", actual: "\(reference.target)"))
        }
    }

    // MARK: - Sketch Entity Evaluation

    private static func evaluateSketchEntity(
        featureId: UUID,
        entityId: UUID,
        in document: DocumentModel
    ) -> Result<EvaluatedCurve3D, ReferenceResolutionError> {
        guard let sourceFeature = document.feature(for: featureId) else {
            return .failure(.targetFeatureNotFound(featureId))
        }
        guard !sourceFeature.isSuppressed else {
            return .failure(.targetFeatureSuppressed(featureId))
        }
        guard case .sketch(let sketchData) = sourceFeature.operation else {
            return .failure(.targetNotASketch(featureId))
        }
        guard let entity = sketchData.entities.first(where: { $0.id == entityId }) else {
            return .failure(.sketchEntityNotFound(featureId: featureId, entityId: entityId))
        }

        let plane = document.resolveSketchPlane(for: sketchData)

        switch entity.kind {
        case "line":
            guard let sp = entity.startPoint, let ep = entity.endPoint else {
                return .failure(.sketchEntityNotFound(featureId: featureId, entityId: entityId))
            }
            let startWorld = plane.unprojectPoint(sp)
            let endWorld = plane.unprojectPoint(ep)
            return .success(.line(start: startWorld, end: endWorld))

        case "circle":
            guard let cp = entity.centerPoint, let r = entity.radius else {
                return .failure(.sketchEntityNotFound(featureId: featureId, entityId: entityId))
            }
            let centerWorld = plane.unprojectPoint(cp)
            return .success(.circle(center: centerWorld, normal: plane.normal, radius: r))

        case "arc":
            guard let cp = entity.centerPoint, let sp = entity.startPoint, let ep = entity.endPoint else {
                return .failure(.sketchEntityNotFound(featureId: featureId, entityId: entityId))
            }
            let r = entity.radius ?? hypot(sp.x - cp.x, sp.y - cp.y)
            let centerWorld = plane.unprojectPoint(cp)
            let startWorld = plane.unprojectPoint(sp)
            let endWorld = plane.unprojectPoint(ep)
            let a0 = atan2(sp.y - cp.y, sp.x - cp.x)
            let a1 = atan2(ep.y - cp.y, ep.x - cp.x)
            return .success(.arc(
                center: centerWorld,
                normal: plane.normal,
                radius: r,
                startAngle: a0,
                endAngle: a1,
                startPoint: startWorld,
                endPoint: endWorld,
                clockwise: entity.isClockwise
            ))

        default:
            return .failure(.typeMismatch(expected: "line, circle, or arc", actual: entity.kind))
        }
    }

    // MARK: - Topological Edge Evaluation

    private static func evaluateTopologicalEdge(
        reference: TopologicalReference,
        in document: DocumentModel
    ) -> Result<EvaluatedCurve3D, ReferenceResolutionError> {
        guard reference.elementType == .edge else {
            return .failure(.typeMismatch(expected: "edge", actual: reference.elementType.rawValue))
        }
        guard let sourceFeature = document.feature(for: reference.sourceFeatureId) else {
            return .failure(.topologicalSourceFeatureNotFound(reference.sourceFeatureId))
        }
        guard !sourceFeature.isSuppressed else {
            return .failure(.topologicalSourceFeatureSuppressed(reference.sourceFeatureId))
        }

        let label = reference.historyPath.last?.label

        switch sourceFeature.operation {
        case .primitive(.box(let params)):
            return evaluateBoxEdge(params: params, label: label, reference: reference, transform: sourceFeature.transform)

        case .primitive(.cylinder(let params)):
            return evaluateCylinderEdge(params: params, label: label, reference: reference, transform: sourceFeature.transform)

        case .primitive(.cone(let params)):
            return evaluateConeEdge(params: params, label: label, reference: reference, transform: sourceFeature.transform)

        case .primitive(.torus(let params)):
            return evaluateTorusEdge(params: params, label: label, reference: reference, transform: sourceFeature.transform)

        case .primitive(.wedge(let params)):
            return evaluateWedgeEdge(params: params, label: label, reference: reference, transform: sourceFeature.transform)

        case .extrude(let extrudeData):
            return evaluateExtrudeEdge(extrudeData: extrudeData, label: label, reference: reference, feature: sourceFeature, in: document)

        default:
            // Generic fallback using disambiguator if present
            if let disambiguator = reference.disambiguator, let centroid = disambiguator.centroid {
                let worldCentroid = sourceFeature.transform.transformPoint(centroid)
                if disambiguator.surfaceOrCurveType == "circle" {
                    let r = disambiguator.areaOrLength.map { $0 / (2.0 * Double.pi) } ?? 10.0
                    let normal = disambiguator.normal.map { sourceFeature.transform.rotation.act($0) } ?? SIMD3<Float>(0, 0, 1)
                    return .success(.circle(center: worldCentroid, normal: normal, radius: r))
                }
            }
            return .failure(.topologicalElementMissing(reference))
        }
    }

    // MARK: - Primitive Evaluators

    private static func evaluateBoxEdge(
        params: BoxParams,
        label: String?,
        reference: TopologicalReference,
        transform: Transform
    ) -> Result<EvaluatedCurve3D, ReferenceResolutionError> {
        let hw = Float(params.width) / 2.0
        let hd = Float(params.depth) / 2.0
        let hh = Float(params.height) / 2.0

        let edges: [String: (SIMD3<Float>, SIMD3<Float>)] = [
            "edge:top-front": (SIMD3<Float>(-hw, -hd, hh), SIMD3<Float>(hw, -hd, hh)),
            "edge:top-back": (SIMD3<Float>(-hw, hd, hh), SIMD3<Float>(hw, hd, hh)),
            "edge:top-left": (SIMD3<Float>(-hw, -hd, hh), SIMD3<Float>(-hw, hd, hh)),
            "edge:top-right": (SIMD3<Float>(hw, -hd, hh), SIMD3<Float>(hw, hd, hh)),
            "edge:bottom-front": (SIMD3<Float>(-hw, -hd, -hh), SIMD3<Float>(hw, -hd, -hh)),
            "edge:bottom-back": (SIMD3<Float>(-hw, hd, -hh), SIMD3<Float>(hw, hd, -hh)),
            "edge:bottom-left": (SIMD3<Float>(-hw, -hd, -hh), SIMD3<Float>(-hw, hd, -hh)),
            "edge:bottom-right": (SIMD3<Float>(hw, -hd, -hh), SIMD3<Float>(hw, hd, -hh)),
            "edge:front-left": (SIMD3<Float>(-hw, -hd, -hh), SIMD3<Float>(-hw, -hd, hh)),
            "edge:front-right": (SIMD3<Float>(hw, -hd, -hh), SIMD3<Float>(hw, -hd, hh)),
            "edge:back-left": (SIMD3<Float>(-hw, hd, -hh), SIMD3<Float>(-hw, hd, hh)),
            "edge:back-right": (SIMD3<Float>(hw, hd, -hh), SIMD3<Float>(hw, hd, hh))
        ]

        if let label, let (localStart, localEnd) = edges[label] {
            let start = transform.transformPoint(localStart)
            let end = transform.transformPoint(localEnd)
            return .success(.line(start: start, end: end))
        }

        // Match by centroid disambiguator
        if let targetCentroid = reference.disambiguator?.centroid {
            var closest: (label: String, dist: Float)?
            for (key, pair) in edges {
                let mid = (pair.0 + pair.1) / 2.0
                let d = simd_distance(mid, targetCentroid)
                if let cur = closest {
                    if d < cur.dist { closest = (key, d) }
                } else {
                    closest = (key, d)
                }
            }
            if let closest, closest.dist < 0.1, let pair = edges[closest.label] {
                let start = transform.transformPoint(pair.0)
                let end = transform.transformPoint(pair.1)
                return .success(.line(start: start, end: end))
            }
        }

        return .failure(.topologicalElementMissing(reference))
    }

    private static func evaluateCylinderEdge(
        params: CylinderParams,
        label: String?,
        reference: TopologicalReference,
        transform: Transform
    ) -> Result<EvaluatedCurve3D, ReferenceResolutionError> {
        let r = Double(params.radius)
        let rf = Float(params.radius)
        let hh = Float(params.height) / 2.0

        let effectiveLabel = label ?? (reference.disambiguator?.centroid?.z ?? 0 > 0 ? "edge:top" : (reference.disambiguator?.surfaceOrCurveType == "line" ? "edge:seam" : "edge:bottom"))

        switch effectiveLabel {
        case "edge:top":
            let localCenter = SIMD3<Float>(0, 0, hh)
            let localNormal = SIMD3<Float>(0, 0, 1)
            let center = transform.transformPoint(localCenter)
            let normal = transform.rotation.act(localNormal)
            return .success(.circle(center: center, normal: normal, radius: r))

        case "edge:bottom":
            let localCenter = SIMD3<Float>(0, 0, -hh)
            let localNormal = SIMD3<Float>(0, 0, 1)
            let center = transform.transformPoint(localCenter)
            let normal = transform.rotation.act(localNormal)
            return .success(.circle(center: center, normal: normal, radius: r))

        case "edge:seam":
            let localStart = SIMD3<Float>(rf, 0, -hh)
            let localEnd = SIMD3<Float>(rf, 0, hh)
            let start = transform.transformPoint(localStart)
            let end = transform.transformPoint(localEnd)
            return .success(.line(start: start, end: end))

        default:
            return .failure(.topologicalElementMissing(reference))
        }
    }

    private static func evaluateConeEdge(
        params: ConeParams,
        label: String?,
        reference: TopologicalReference,
        transform: Transform
    ) -> Result<EvaluatedCurve3D, ReferenceResolutionError> {
        let hh = Float(params.height) / 2.0
        let effectiveLabel = label ?? (reference.disambiguator?.surfaceOrCurveType == "line" ? "edge:seam" : (reference.disambiguator?.centroid?.z ?? 0 > 0 ? "edge:top" : "edge:bottom"))

        switch effectiveLabel {
        case "edge:bottom":
            let center = transform.transformPoint(SIMD3<Float>(0, 0, -hh))
            let normal = transform.rotation.act(SIMD3<Float>(0, 0, 1))
            return .success(.circle(center: center, normal: normal, radius: Double(params.bottomRadius)))

        case "edge:top":
            guard params.topRadius > 0 else { return .failure(.topologicalElementMissing(reference)) }
            let center = transform.transformPoint(SIMD3<Float>(0, 0, hh))
            let normal = transform.rotation.act(SIMD3<Float>(0, 0, 1))
            return .success(.circle(center: center, normal: normal, radius: Double(params.topRadius)))

        case "edge:seam":
            let start = transform.transformPoint(SIMD3<Float>(Float(params.bottomRadius), 0, -hh))
            let end = transform.transformPoint(SIMD3<Float>(Float(params.topRadius), 0, hh))
            return .success(.line(start: start, end: end))

        default:
            return .failure(.topologicalElementMissing(reference))
        }
    }

    private static func evaluateTorusEdge(
        params: TorusParams,
        label: String?,
        reference: TopologicalReference,
        transform: Transform
    ) -> Result<EvaluatedCurve3D, ReferenceResolutionError> {
        let effectiveLabel = label ?? "edge:major-seam"
        switch effectiveLabel {
        case "edge:major-seam":
            let center = transform.transformPoint(.zero)
            let normal = transform.rotation.act(SIMD3<Float>(0, 0, 1))
            return .success(.circle(center: center, normal: normal, radius: Double(params.majorRadius)))

        case "edge:minor-seam":
            let center = transform.transformPoint(SIMD3<Float>(Float(params.majorRadius), 0, 0))
            let normal = transform.rotation.act(SIMD3<Float>(0, 1, 0))
            return .success(.circle(center: center, normal: normal, radius: Double(params.minorRadius)))

        default:
            return .failure(.topologicalElementMissing(reference))
        }
    }

    private static func evaluateWedgeEdge(
        params: WedgeParams,
        label: String?,
        reference: TopologicalReference,
        transform: Transform
    ) -> Result<EvaluatedCurve3D, ReferenceResolutionError> {
        let hw = Float(params.width) / 2.0
        let hd = Float(params.depth) / 2.0
        let hh = Float(params.height) / 2.0
        let tw = Float(params.topWidth)

        var edges: [String: (SIMD3<Float>, SIMD3<Float>)] = [
            "edge:bottom-front": (SIMD3<Float>(-hw, -hd, -hh), SIMD3<Float>(hw, -hd, -hh)),
            "edge:bottom-back": (SIMD3<Float>(-hw, hd, -hh), SIMD3<Float>(hw, hd, -hh)),
            "edge:bottom-left": (SIMD3<Float>(-hw, -hd, -hh), SIMD3<Float>(-hw, hd, -hh)),
            "edge:bottom-right": (SIMD3<Float>(hw, -hd, -hh), SIMD3<Float>(hw, hd, -hh)),
            "edge:front-left": (SIMD3<Float>(-hw, -hd, -hh), SIMD3<Float>(-hw, -hd, hh)),
            "edge:back-left": (SIMD3<Float>(-hw, hd, -hh), SIMD3<Float>(-hw, hd, hh)),
            "edge:slanted-front": (SIMD3<Float>(hw, -hd, -hh), SIMD3<Float>(-hw + tw, -hd, hh)),
            "edge:slanted-back": (SIMD3<Float>(hw, hd, -hh), SIMD3<Float>(-hw + tw, hd, hh))
        ]

        if tw > 0 {
            edges["edge:top-front"] = (SIMD3<Float>(-hw, -hd, hh), SIMD3<Float>(-hw + tw, -hd, hh))
            edges["edge:top-back"] = (SIMD3<Float>(-hw, hd, hh), SIMD3<Float>(-hw + tw, hd, hh))
            edges["edge:top-left"] = (SIMD3<Float>(-hw, -hd, hh), SIMD3<Float>(-hw, hd, hh))
            edges["edge:top-slanted"] = (SIMD3<Float>(-hw + tw, -hd, hh), SIMD3<Float>(-hw + tw, hd, hh))
        } else {
            edges["edge:top-knife"] = (SIMD3<Float>(-hw, -hd, hh), SIMD3<Float>(-hw, hd, hh))
        }

        if let label, let pair = edges[label] {
            return .success(.line(start: transform.transformPoint(pair.0), end: transform.transformPoint(pair.1)))
        }

        if let targetCentroid = reference.disambiguator?.centroid {
            var closest: (label: String, dist: Float)?
            for (key, pair) in edges {
                let mid = (pair.0 + pair.1) / 2.0
                let d = simd_distance(mid, targetCentroid)
                if let cur = closest {
                    if d < cur.dist { closest = (key, d) }
                } else {
                    closest = (key, d)
                }
            }
            if let closest, closest.dist < 0.1, let pair = edges[closest.label] {
                return .success(.line(start: transform.transformPoint(pair.0), end: transform.transformPoint(pair.1)))
            }
        }

        return .failure(.topologicalElementMissing(reference))
    }

    private static func evaluateExtrudeEdge(
        extrudeData: ExtrudeFeatureData,
        label: String?,
        reference: TopologicalReference,
        feature: Feature,
        in document: DocumentModel
    ) -> Result<EvaluatedCurve3D, ReferenceResolutionError> {
        let profileOpt: SketchProfile?
        if let p = extrudeData.profile {
            profileOpt = p
        } else if let sId = extrudeData.sketchFeatureId,
                  let sFeat = document.feature(for: sId),
                  case .sketch(let sData) = sFeat.operation {
            let plane = document.resolveSketchPlane(for: sData)
            profileOpt = try? SketchProfileBuilder.build(from: sData.entities, plane: plane)
        } else {
            profileOpt = nil
        }

        guard let profile = profileOpt, !profile.points.isEmpty else {
            return .failure(.topologicalElementMissing(reference))
        }

        // Check if upstream sketch was a single circle
        if let sId = extrudeData.sketchFeatureId,
           let sFeat = document.feature(for: sId),
           case .sketch(let sData) = sFeat.operation {
            let active = sData.entities.filter { !$0.isConstruction }
            if active.count == 1, active[0].kind == "circle", let r = active[0].radius, let cp = active[0].centerPoint {
                let dist = Float(extrudeData.distance)
                let normal = profile.plane.normal
                let isSym = extrudeData.isSymmetric
                let baseOffset: Float = isSym ? -(dist / 2.0) : 0.0
                let centerBase = profile.plane.unprojectPoint(cp) + baseOffset * normal
                let centerTop = centerBase + dist * normal

                if label == "edge:top" || (reference.disambiguator?.centroid?.z ?? 0 > 0) {
                    return .success(.circle(
                        center: feature.transform.transformPoint(centerTop),
                        normal: feature.transform.rotation.act(normal),
                        radius: r
                    ))
                } else {
                    return .success(.circle(
                        center: feature.transform.transformPoint(centerBase),
                        normal: feature.transform.rotation.act(normal),
                        radius: r
                    ))
                }
            }
        }

        let pts = profile.points
        let count = pts.count
        guard count >= 2 else {
            return .failure(.topologicalElementMissing(reference))
        }

        let dist = Float(extrudeData.distance)
        let normal = profile.plane.normal
        let isSym = extrudeData.isSymmetric
        let baseOffset: Float = isSym ? -(dist / 2.0) : 0.0

        var candidateEdges: [(name: String, start: SIMD3<Float>, end: SIMD3<Float>)] = []

        // Bottom loop edges
        for i in 0..<count {
            let next = (i + 1) % count
            let p0 = profile.plane.unprojectPoint(SIMD2<Double>(Double(pts[i].x), Double(pts[i].y))) + baseOffset * normal
            let p1 = profile.plane.unprojectPoint(SIMD2<Double>(Double(pts[next].x), Double(pts[next].y))) + baseOffset * normal
            candidateEdges.append(("edge:bottom-\(i)", p0, p1))
        }

        // Top loop edges
        for i in 0..<count {
            let next = (i + 1) % count
            let p0 = profile.plane.unprojectPoint(SIMD2<Double>(Double(pts[i].x), Double(pts[i].y))) + (baseOffset + dist) * normal
            let p1 = profile.plane.unprojectPoint(SIMD2<Double>(Double(pts[next].x), Double(pts[next].y))) + (baseOffset + dist) * normal
            candidateEdges.append(("edge:top-\(i)", p0, p1))
        }

        // Lateral edges
        for i in 0..<count {
            let p0 = profile.plane.unprojectPoint(SIMD2<Double>(Double(pts[i].x), Double(pts[i].y))) + baseOffset * normal
            let p1 = p0 + dist * normal
            candidateEdges.append(("edge:lateral-\(i)", p0, p1))
        }

        if let label, let match = candidateEdges.first(where: { $0.name == label }) {
            return .success(.line(
                start: feature.transform.transformPoint(match.start),
                end: feature.transform.transformPoint(match.end)
            ))
        }

        if let centroid = reference.disambiguator?.centroid {
            if let best = candidateEdges.min(by: {
                let mid1 = ($0.start + $0.end) / 2.0
                let mid2 = ($1.start + $1.end) / 2.0
                return simd_distance(mid1, centroid) < simd_distance(mid2, centroid)
            }) {
                return .success(.line(
                    start: feature.transform.transformPoint(best.start),
                    end: feature.transform.transformPoint(best.end)
                ))
            }
        }

        if let first = candidateEdges.first {
            return .success(.line(
                start: feature.transform.transformPoint(first.start),
                end: feature.transform.transformPoint(first.end)
            ))
        }

        return .failure(.topologicalElementMissing(reference))
    }
}
