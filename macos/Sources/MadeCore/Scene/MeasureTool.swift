import Foundation
import simd

/// Element in a CAD model that can be geometrically measured.
public enum MeasuredElement: Sendable, Equatable, Hashable {
    case body(SolidId)
    case face(solidId: SolidId, faceId: Int, deterministicId: UUID? = nil)
    case edge(solidId: SolidId, edgeId: Int, deterministicId: UUID? = nil)
    case vertex(solidId: SolidId, vertexId: Int, deterministicId: UUID? = nil)

    public var solidId: SolidId {
        switch self {
        case .body(let id): return id
        case .face(let id, _, _): return id
        case .edge(let id, _, _): return id
        case .vertex(let id, _, _): return id
        }
    }

    public var displayName: String {
        switch self {
        case .body(let id):
            return "Body (\(id.rawValue))"
        case .face(let id, let faceId, _):
            return "Face \(faceId) (\(id.rawValue))"
        case .edge(let id, let edgeId, _):
            return "Edge \(edgeId) (\(id.rawValue))"
        case .vertex(let id, let vertexId, _):
            return "Vertex \(vertexId) (\(id.rawValue))"
        }
    }

    public init(selectedSubElement sub: SelectedSubElement) {
        switch sub.elementType {
        case .face:
            self = .face(solidId: sub.solidId, faceId: sub.elementId, deterministicId: sub.deterministicId)
        case .edge:
            self = .edge(solidId: sub.solidId, edgeId: sub.elementId, deterministicId: sub.deterministicId)
        case .vertex:
            self = .vertex(solidId: sub.solidId, vertexId: sub.elementId, deterministicId: sub.deterministicId)
        }
    }
}

/// Extracted geometric properties of a single CAD element.
public struct ElementGeometry: Sendable, Equatable {
    public var centroid: SIMD3<Float>
    public var normal: SIMD3<Float>?
    public var direction: SIMD3<Float>?
    public var area: Double?
    public var length: Double?
    public var radius: Double?
    public var diameter: Double?
    public var isCircular: Bool
    public var isPlanar: Bool

    public init(
        centroid: SIMD3<Float>,
        normal: SIMD3<Float>? = nil,
        direction: SIMD3<Float>? = nil,
        area: Double? = nil,
        length: Double? = nil,
        radius: Double? = nil,
        diameter: Double? = nil,
        isCircular: Bool = false,
        isPlanar: Bool = false
    ) {
        self.centroid = centroid
        self.normal = normal
        self.direction = direction
        self.area = area
        self.length = length
        self.radius = radius
        self.diameter = diameter
        self.isCircular = isCircular
        self.isPlanar = isPlanar
    }
}

/// Measurement output between two elements or a single element.
public struct MeasurementResult: Sendable, Equatable {
    public var elementA: MeasuredElement
    public var elementB: MeasuredElement?
    public var geometryA: ElementGeometry
    public var geometryB: ElementGeometry?
    public var minDistance: Double
    public var centerDistance: Double
    public var normalDistance: Double?
    public var angleDegrees: Double?

    public init(
        elementA: MeasuredElement,
        elementB: MeasuredElement? = nil,
        geometryA: ElementGeometry,
        geometryB: ElementGeometry? = nil,
        minDistance: Double = 0.0,
        centerDistance: Double = 0.0,
        normalDistance: Double? = nil,
        angleDegrees: Double? = nil
    ) {
        self.elementA = elementA
        self.elementB = elementB
        self.geometryA = geometryA
        self.geometryB = geometryB
        self.minDistance = minDistance
        self.centerDistance = centerDistance
        self.normalDistance = normalDistance
        self.angleDegrees = angleDegrees
    }
}

/// Geometric measurement evaluator for CAD elements and candidate meshes.
public struct MeasureTool: Sendable {

    /// Checks if a solid is visible in the document and not hidden.
    @MainActor
    public static func isSolidVisible(_ solidId: SolidId, in document: DocumentModel, hiddenSolidIds: Set<SolidId> = []) -> Bool {
        if hiddenSolidIds.contains(solidId) { return false }
        if let feat = document.feature(for: solidId), !feat.isVisible { return false }
        if let body = document.bodies.first(where: { $0.id.rawValue == solidId.rawValue }), !body.isVisible { return false }
        if let obj = document.objects.first(where: { $0.id == solidId }), !obj.isVisible { return false }
        return true
    }

    /// Evaluates measurements between elementA and optional elementB using document context.
    @MainActor
    public static func measure(
        elementA: MeasuredElement,
        elementB: MeasuredElement? = nil,
        in document: DocumentModel,
        candidateMeshes: [CandidateMesh] = [],
        hiddenSolidIds: Set<SolidId> = []
    ) -> MeasurementResult? {
        guard isSolidVisible(elementA.solidId, in: document, hiddenSolidIds: hiddenSolidIds) else { return nil }
        if let b = elementB {
            guard isSolidVisible(b.solidId, in: document, hiddenSolidIds: hiddenSolidIds) else { return nil }
        }

        let featA = document.features.last(where: { $0.outputSolidId == elementA.solidId }) ?? document.feature(for: elementA.solidId)
        let meshA = resolveMesh(for: elementA.solidId, in: document, candidateMeshes: candidateMeshes, feature: featA)
        guard let geomA = evaluateGeometry(for: elementA, mesh: meshA, feature: featA) else { return nil }

        guard let elementB else {
            return MeasurementResult(
                elementA: elementA,
                elementB: nil,
                geometryA: geomA,
                geometryB: nil,
                minDistance: 0.0,
                centerDistance: 0.0,
                normalDistance: nil,
                angleDegrees: nil
            )
        }

        let featB = document.features.last(where: { $0.outputSolidId == elementB.solidId }) ?? document.feature(for: elementB.solidId)
        let meshB = resolveMesh(for: elementB.solidId, in: document, candidateMeshes: candidateMeshes, feature: featB)
        guard let geomB = evaluateGeometry(for: elementB, mesh: meshB, feature: featB) else { return nil }

        return measure(
            elementA: elementA,
            elementB: elementB,
            geometryA: geomA,
            geometryB: geomB,
            meshA: meshA,
            meshB: meshB
        )
    }

    /// Computes pairwise geometric quantities given geometries and candidate meshes.
    public static func measure(
        elementA: MeasuredElement,
        elementB: MeasuredElement,
        geometryA: ElementGeometry,
        geometryB: ElementGeometry,
        meshA: CandidateMesh? = nil,
        meshB: CandidateMesh? = nil
    ) -> MeasurementResult {
        if elementA == elementB {
            return MeasurementResult(
                elementA: elementA,
                elementB: elementB,
                geometryA: geometryA,
                geometryB: geometryB,
                minDistance: 0.0,
                centerDistance: 0.0,
                normalDistance: 0.0,
                angleDegrees: 0.0
            )
        }

        let centerDist = Double(simd_distance(geometryA.centroid, geometryB.centroid))

        var angleDeg: Double? = nil
        if let normA = geometryA.normal, let normB = geometryB.normal {
            let dot = simd_dot(normA, normB)
            if abs(abs(dot) - 1.0) < 1e-4 {
                angleDeg = 0.0
            } else if abs(dot) < 1e-4 {
                angleDeg = 90.0
            } else {
                let clamped = min(max(abs(dot), 0.0), 1.0)
                angleDeg = Double(acos(clamped) * (180.0 / .pi))
            }
        } else if let dirA = geometryA.direction, let dirB = geometryB.direction {
            let dot = simd_dot(dirA, dirB)
            if abs(abs(dot) - 1.0) < 1e-4 {
                angleDeg = 0.0
            } else if abs(dot) < 1e-4 {
                angleDeg = 90.0
            } else {
                let clamped = min(max(abs(dot), 0.0), 1.0)
                angleDeg = Double(acos(clamped) * (180.0 / .pi))
            }
        }

        var normalDist: Double? = nil
        if let normA = geometryA.normal {
            let disp = geometryB.centroid - geometryA.centroid
            normalDist = Double(abs(simd_dot(disp, normA)))
        } else if let normB = geometryB.normal {
            let disp = geometryA.centroid - geometryB.centroid
            normalDist = Double(abs(simd_dot(disp, normB)))
        }

        let minDist = computeMinimumDistance(
            elementA: elementA,
            elementB: elementB,
            geometryA: geometryA,
            geometryB: geometryB,
            meshA: meshA,
            meshB: meshB,
            normalDist: normalDist,
            angleDeg: angleDeg
        )

        return MeasurementResult(
            elementA: elementA,
            elementB: elementB,
            geometryA: geometryA,
            geometryB: geometryB,
            minDistance: minDist,
            centerDistance: centerDist,
            normalDistance: normalDist,
            angleDegrees: angleDeg
        )
    }

    /// Evaluates the geometric attributes of an element from mesh or feature.
    public static func evaluateGeometry(
        for element: MeasuredElement,
        mesh: CandidateMesh?,
        feature: Feature? = nil
    ) -> ElementGeometry? {
        guard let mesh else {
            return fallbackGeometryFromFeature(element: element, feature: feature)
        }

        switch element {
        case .body:
            var totalArea: Double = 0.0
            for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                if i + 2 < mesh.indices.count {
                    let v0 = mesh.transform.transformPoint(mesh.positions[Int(mesh.indices[i])])
                    let v1 = mesh.transform.transformPoint(mesh.positions[Int(mesh.indices[i + 1])])
                    let v2 = mesh.transform.transformPoint(mesh.positions[Int(mesh.indices[i + 2])])
                    totalArea += Double(0.5 * simd_length(simd_cross(v1 - v0, v2 - v0)))
                }
            }
            let worldPoints = mesh.positions.map { mesh.transform.transformPoint($0) }
            let centroid: SIMD3<Float>
            if !worldPoints.isEmpty {
                centroid = worldPoints.reduce(SIMD3<Float>.zero, +) / Float(worldPoints.count)
            } else {
                centroid = mesh.transform.position
            }
            return ElementGeometry(
                centroid: centroid,
                normal: nil,
                direction: nil,
                area: totalArea > 0 ? totalArea : nil,
                length: nil,
                radius: nil,
                diameter: nil,
                isCircular: false,
                isPlanar: false
            )

        case .face(_, let faceId, let detId):
            let isPlanar = mesh.isFacePlanar(forFaceId: faceId)
            let normal = isPlanar ? mesh.faceNormal(forFaceId: faceId) : nil
            let centroid = mesh.faceCentroid(forFaceId: faceId) ?? mesh.transform.position

            let triRange: Range<Int>?
            if let fr = mesh.faceRanges.first(where: { $0.faceId == faceId }) {
                triRange = fr.triangleRange
            } else if mesh.faceRanges.isEmpty && mesh.indices.count >= 3 {
                triRange = 0..<(mesh.indices.count / 3)
            } else {
                triRange = nil
            }

            var faceArea: Double = 0.0
            if let triRange {
                for t in triRange {
                    let i0 = Int(t * 3)
                    guard i0 + 2 < mesh.indices.count else { continue }
                    let idx0 = Int(mesh.indices[i0])
                    let idx1 = Int(mesh.indices[i0 + 1])
                    let idx2 = Int(mesh.indices[i0 + 2])
                    guard idx0 < mesh.positions.count, idx1 < mesh.positions.count, idx2 < mesh.positions.count else { continue }
                    let v0 = mesh.transform.transformPoint(mesh.positions[idx0])
                    let v1 = mesh.transform.transformPoint(mesh.positions[idx1])
                    let v2 = mesh.transform.transformPoint(mesh.positions[idx2])
                    faceArea += Double(0.5 * simd_length(simd_cross(v1 - v0, v2 - v0)))
                }
            }

            var isCircular = false
            var radius: Double? = nil
            var diameter: Double? = nil

            if let topRef = matchTopologicalReference(deterministicId: detId, label: "face:\(faceId)", feature: feature) {
                if let sig = topRef.disambiguator {
                    if sig.surfaceOrCurveType == "cylinder" {
                        isCircular = true
                        if let feat = feature, case .primitive(.cylinder(let p)) = feat.operation {
                            radius = Double(p.radius)
                            diameter = Double(p.radius * 2.0)
                        } else if let aOrL = sig.areaOrLength, let h = cylinderHeight(from: feature) {
                            radius = aOrL / (2.0 * Double.pi * h)
                            diameter = radius.map { $0 * 2.0 }
                        }
                    }
                }
            } else if let feat = feature, case .primitive(.cylinder(let p)) = feat.operation, faceId == 0 {
                isCircular = true
                radius = Double(p.radius)
                diameter = Double(p.radius * 2.0)
            }

            return ElementGeometry(
                centroid: centroid,
                normal: normal,
                direction: nil,
                area: faceArea > 0 ? faceArea : nil,
                length: nil,
                radius: radius,
                diameter: diameter,
                isCircular: isCircular,
                isPlanar: isPlanar
            )

        case .edge(_, let edgeId, let detId):
            let poly = mesh.edgePolylines.first(where: { $0.edgeId == edgeId })
            let pts: [SIMD3<Float>]
            if let poly, !poly.points.isEmpty {
                pts = poly.points.map { mesh.transform.transformPoint($0) }
            } else if edgeId >= 0 && edgeId < mesh.edges.count {
                let e = mesh.edges[edgeId]
                let i0 = Int(e.v0)
                let i1 = Int(e.v1)
                if i0 < mesh.positions.count && i1 < mesh.positions.count {
                    pts = [mesh.transform.transformPoint(mesh.positions[i0]), mesh.transform.transformPoint(mesh.positions[i1])]
                } else {
                    pts = []
                }
            } else {
                pts = []
            }

            guard !pts.isEmpty else { return nil }

            var edgeLength: Double = 0.0
            for i in 0..<(pts.count - 1) {
                edgeLength += Double(simd_distance(pts[i], pts[i + 1]))
            }

            let isClosedLoop = pts.count > 3 && simd_distance(pts.first!, pts.last!) < 1e-4
            let ptsForCentroid = isClosedLoop ? Array(pts.dropLast()) : pts
            let centroid = ptsForCentroid.reduce(SIMD3<Float>.zero, +) / Float(ptsForCentroid.count)
            let direction: SIMD3<Float>?
            if pts.count == 2 {
                let d = pts[1] - pts[0]
                let l = simd_length(d)
                direction = l > 1e-6 ? (d / l) : nil
            } else {
                direction = nil
            }

            var isCircular = false
            var radius: Double? = nil
            var diameter: Double? = nil

            if let topRef = matchTopologicalReference(deterministicId: detId, label: "edge:\(edgeId)", feature: feature),
               let sig = topRef.disambiguator, sig.surfaceOrCurveType == "circle" {
                isCircular = true
                if let feat = feature, case .primitive(.cylinder(let p)) = feat.operation {
                    radius = Double(p.radius)
                    diameter = Double(p.radius * 2.0)
                } else if let aOrL = sig.areaOrLength {
                    radius = aOrL / (2.0 * Double.pi)
                    diameter = radius.map { $0 * 2.0 }
                }
            } else if let feat = feature, case .primitive(.cylinder(let p)) = feat.operation, (edgeId == 0 || edgeId == 1) {
                isCircular = true
                radius = Double(p.radius)
                diameter = Double(p.radius * 2.0)
            } else if ptsForCentroid.count > 3 {
                let dists = ptsForCentroid.map { simd_distance($0, centroid) }
                let avg = dists.reduce(0.0, +) / Float(dists.count)
                let maxDiff = dists.map { abs($0 - avg) }.max() ?? 0
                if avg > 1e-4 && maxDiff < (avg * 0.03) {
                    isCircular = true
                    radius = Double(avg)
                    diameter = Double(avg * 2.0)
                }
            }

            return ElementGeometry(
                centroid: centroid,
                normal: nil,
                direction: direction,
                area: nil,
                length: edgeLength > 0 ? edgeLength : nil,
                radius: radius,
                diameter: diameter,
                isCircular: isCircular,
                isPlanar: false
            )

        case .vertex(_, let vertexId, _):
            let pt: SIMD3<Float>?
            if let vp = mesh.vertexPoints.first(where: { $0.vertexId == vertexId }) {
                pt = mesh.transform.transformPoint(vp.position)
            } else if vertexId >= 0 && vertexId < mesh.positions.count {
                pt = mesh.transform.transformPoint(mesh.positions[vertexId])
            } else {
                pt = nil
            }
            guard let pos = pt else { return nil }

            return ElementGeometry(
                centroid: pos,
                normal: nil,
                direction: nil,
                area: nil,
                length: nil,
                radius: nil,
                diameter: nil,
                isCircular: false,
                isPlanar: false
            )
        }
    }

    // MARK: - Internal Helpers

    private static func cylinderHeight(from feature: Feature?) -> Double? {
        guard let feat = feature, case .primitive(.cylinder(let p)) = feat.operation else { return nil }
        return Double(p.height)
    }

    private static func matchTopologicalReference(
        deterministicId: UUID?,
        label: String,
        feature: Feature?
    ) -> TopologicalReference? {
        guard let feat = feature else { return nil }
        if let detId = deterministicId, let ref = feat.generatedTopology.values.first(where: { $0.id == detId }) {
            return ref
        }
        if let direct = feat.generatedTopology[label] {
            return direct
        }
        if let mapped = mapTopologyLabel(label, for: feat) {
            if let ref = feat.generatedTopology[mapped] {
                return ref
            }
        }
        return feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == label })
    }

    private static func mapTopologyLabel(_ label: String, for feature: Feature) -> String? {
        switch feature.operation {
        case .primitive(.cylinder):
            switch label {
            case "edge:0": return "edge:top"
            case "edge:1": return "edge:bottom"
            case "edge:2": return "edge:seam"
            case "face:0": return "face:side"
            case "face:1": return "face:top"
            case "face:2": return "face:bottom"
            default: return nil
            }
        case .primitive(.box):
            switch label {
            case "face:0": return "face:top"
            case "face:1": return "face:bottom"
            case "face:2": return "face:right"
            case "face:3": return "face:left"
            case "face:4": return "face:back"
            case "face:5": return "face:front"
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func fallbackGeometryFromFeature(
        element: MeasuredElement,
        feature: Feature?
    ) -> ElementGeometry? {
        guard let feat = feature else { return nil }
        let tr = feat.transform
        switch element {
        case .body:
            return ElementGeometry(
                centroid: tr.position,
                isCircular: false,
                isPlanar: false
            )
        case .face(_, let faceId, let detId):
            if let ref = matchTopologicalReference(deterministicId: detId, label: "face:\(faceId)", feature: feat),
               let sig = ref.disambiguator {
                let centroid = sig.centroid.map { tr.transformPoint($0) } ?? tr.position
                let normal = sig.normal.map { simd_normalize(tr.normalMatrix * $0) }
                let isPlanar = sig.surfaceOrCurveType == "plane"
                let isCyl = sig.surfaceOrCurveType == "cylinder"
                let radius: Double?
                if isCyl, let aOrL = sig.areaOrLength, let h = cylinderHeight(from: feat), h > 0 {
                    radius = aOrL / (2.0 * .pi * h)
                } else {
                    radius = nil
                }
                return ElementGeometry(
                    centroid: centroid,
                    normal: normal,
                    area: sig.areaOrLength,
                    radius: radius,
                    diameter: radius.map { $0 * 2.0 },
                    isCircular: isCyl,
                    isPlanar: isPlanar
                )
            }
            return nil
        case .edge(_, let edgeId, let detId):
            if let ref = matchTopologicalReference(deterministicId: detId, label: "edge:\(edgeId)", feature: feat),
               let sig = ref.disambiguator {
                let centroid = sig.centroid.map { tr.transformPoint($0) } ?? tr.position
                let isCirc = sig.surfaceOrCurveType == "circle"
                let radius = isCirc ? sig.areaOrLength.map { $0 / (2.0 * .pi) } : nil
                return ElementGeometry(
                    centroid: centroid,
                    length: sig.areaOrLength,
                    radius: radius,
                    diameter: radius.map { $0 * 2.0 },
                    isCircular: isCirc,
                    isPlanar: false
                )
            }
            return nil
        case .vertex(_, let vertexId, let detId):
            if let ref = matchTopologicalReference(deterministicId: detId, label: "vertex:\(vertexId)", feature: feat),
               let sig = ref.disambiguator {
                let centroid = sig.centroid.map { tr.transformPoint($0) } ?? tr.position
                return ElementGeometry(
                    centroid: centroid,
                    isCircular: false,
                    isPlanar: false
                )
            }
            return nil
        }
    }

    @MainActor
    static func resolveMesh(
        for solidId: SolidId,
        in document: DocumentModel,
        candidateMeshes: [CandidateMesh],
        feature: Feature? = nil
    ) -> CandidateMesh? {
        if let match = candidateMeshes.first(where: { $0.id == solidId }) {
            return match
        }

        let feat = feature ?? document.features.last(where: { $0.outputSolidId == solidId }) ?? document.feature(for: solidId)
        if let feat {
            switch feat.operation {
            case .primitive(.box(let p)):
                let payload = NativeGeometryGenerator.generateBox(width: p.width, depth: p.depth, height: p.height)
                return CandidateMesh(id: solidId, payload: payload, transform: feat.transform)
            case .primitive(.cylinder(let p)):
                let payload = NativeGeometryGenerator.generateCylinder(radius: p.radius, height: p.height)
                return CandidateMesh(id: solidId, payload: payload, transform: feat.transform)
            case .primitive(.sphere(let p)):
                let payload = NativeGeometryGenerator.generateSphere(radius: p.radius)
                return CandidateMesh(id: solidId, payload: payload, transform: feat.transform)
            case .primitive(.cone(let p)):
                let payload = NativeGeometryGenerator.generateCone(bottomRadius: p.bottomRadius, topRadius: p.topRadius, height: p.height)
                return CandidateMesh(id: solidId, payload: payload, transform: feat.transform)
            case .primitive(.torus(let p)):
                let payload = NativeGeometryGenerator.generateTorus(majorRadius: p.majorRadius, minorRadius: p.minorRadius)
                return CandidateMesh(id: solidId, payload: payload, transform: feat.transform)
            case .primitive(.wedge(let p)):
                let payload = NativeGeometryGenerator.generateWedge(width: p.width, depth: p.depth, height: p.height, topWidth: p.topWidth)
                return CandidateMesh(id: solidId, payload: payload, transform: feat.transform)
            default:
                break
            }
        }

        if let obj = document.objects.first(where: { $0.id == solidId }) {
            switch obj.def {
            case .box(let p):
                let payload = NativeGeometryGenerator.generateBox(width: p.width, depth: p.depth, height: p.height)
                return CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .cylinder(let p):
                let payload = NativeGeometryGenerator.generateCylinder(radius: p.radius, height: p.height)
                return CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .sphere(let p):
                let payload = NativeGeometryGenerator.generateSphere(radius: p.radius)
                return CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .cone(let p):
                let payload = NativeGeometryGenerator.generateCone(bottomRadius: p.bottomRadius, topRadius: p.topRadius, height: p.height)
                return CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .torus(let p):
                let payload = NativeGeometryGenerator.generateTorus(majorRadius: p.majorRadius, minorRadius: p.minorRadius)
                return CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            case .wedge(let p):
                let payload = NativeGeometryGenerator.generateWedge(width: p.width, depth: p.depth, height: p.height, topWidth: p.topWidth)
                return CandidateMesh(id: solidId, payload: payload, transform: obj.transform)
            default:
                break
            }
        }

        return nil
    }

    private static func closestPointOnSegment(p: SIMD3<Float>, a: SIMD3<Float>, b: SIMD3<Float>) -> SIMD3<Float> {
        let ab = b - a
        let abLenSq = simd_dot(ab, ab)
        if abLenSq < 1e-8 { return a }
        let t = min(max(simd_dot(p - a, ab) / abLenSq, 0.0), 1.0)
        return a + t * ab
    }

    private struct ElementPrimitives {
        var points: [SIMD3<Float>] = []
        var segments: [(SIMD3<Float>, SIMD3<Float>)] = []
        var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
    }

    private static func extractPrimitives(for element: MeasuredElement, in mesh: CandidateMesh) -> ElementPrimitives {
        var prims = ElementPrimitives()
        switch element {
        case .vertex(_, let vertexId, _):
            if let vp = mesh.vertexPoints.first(where: { $0.vertexId == vertexId }) {
                prims.points.append(mesh.transform.transformPoint(vp.position))
            } else if vertexId >= 0 && vertexId < mesh.positions.count {
                prims.points.append(mesh.transform.transformPoint(mesh.positions[vertexId]))
            }

        case .edge(_, let edgeId, _):
            if let poly = mesh.edgePolylines.first(where: { $0.edgeId == edgeId }), !poly.points.isEmpty {
                let pts = poly.points.map { mesh.transform.transformPoint($0) }
                for i in 0..<(pts.count - 1) {
                    prims.segments.append((pts[i], pts[i + 1]))
                }
            } else if edgeId >= 0 && edgeId < mesh.edges.count {
                let e = mesh.edges[edgeId]
                let i0 = Int(e.v0)
                let i1 = Int(e.v1)
                if i0 < mesh.positions.count && i1 < mesh.positions.count {
                    prims.segments.append((
                        mesh.transform.transformPoint(mesh.positions[i0]),
                        mesh.transform.transformPoint(mesh.positions[i1])
                    ))
                }
            }

        case .face(_, let faceId, _):
            let triRange: Range<Int>?
            if let fr = mesh.faceRanges.first(where: { $0.faceId == faceId }) {
                triRange = fr.triangleRange
            } else if mesh.faceRanges.isEmpty && mesh.indices.count >= 3 {
                triRange = 0..<(mesh.indices.count / 3)
            } else {
                triRange = nil
            }
            if let triRange {
                for t in triRange {
                    let i0 = Int(t * 3)
                    guard i0 + 2 < mesh.indices.count else { continue }
                    let idx0 = Int(mesh.indices[i0])
                    let idx1 = Int(mesh.indices[i0 + 1])
                    let idx2 = Int(mesh.indices[i0 + 2])
                    guard idx0 < mesh.positions.count, idx1 < mesh.positions.count, idx2 < mesh.positions.count else { continue }
                    prims.triangles.append((
                        mesh.transform.transformPoint(mesh.positions[idx0]),
                        mesh.transform.transformPoint(mesh.positions[idx1]),
                        mesh.transform.transformPoint(mesh.positions[idx2])
                    ))
                }
            }

        case .body:
            for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                if i + 2 < mesh.indices.count {
                    let idx0 = Int(mesh.indices[i])
                    let idx1 = Int(mesh.indices[i + 1])
                    let idx2 = Int(mesh.indices[i + 2])
                    if idx0 < mesh.positions.count && idx1 < mesh.positions.count && idx2 < mesh.positions.count {
                        prims.triangles.append((
                            mesh.transform.transformPoint(mesh.positions[idx0]),
                            mesh.transform.transformPoint(mesh.positions[idx1]),
                            mesh.transform.transformPoint(mesh.positions[idx2])
                        ))
                    }
                }
            }
        }
        return prims
    }

    private static func computeMinimumDistance(
        elementA: MeasuredElement,
        elementB: MeasuredElement,
        geometryA: ElementGeometry,
        geometryB: ElementGeometry,
        meshA: CandidateMesh?,
        meshB: CandidateMesh?,
        normalDist: Double?,
        angleDeg: Double?
    ) -> Double {
        if case .body = elementA, case .body = elementB, let mA = meshA, let mB = meshB {
            return Double(distanceBetweenMeshes(mA, mB))
        }

        guard let meshA, let meshB else {
            if let normalDist, let angleDeg, angleDeg == 0.0 {
                return normalDist
            }
            return Double(simd_distance(geometryA.centroid, geometryB.centroid))
        }

        let primsA = extractPrimitives(for: elementA, in: meshA)
        let primsB = extractPrimitives(for: elementB, in: meshB)

        var minDist = Float.greatestFiniteMagnitude

        // 1. Point to Point
        for pA in primsA.points {
            for pB in primsB.points {
                minDist = min(minDist, simd_distance(pA, pB))
            }
        }

        // 2. Point to Segment
        for p in primsA.points {
            for (s0, s1) in primsB.segments {
                let cp = closestPointOnSegment(p: p, a: s0, b: s1)
                minDist = min(minDist, simd_distance(p, cp))
            }
        }
        for p in primsB.points {
            for (s0, s1) in primsA.segments {
                let cp = closestPointOnSegment(p: p, a: s0, b: s1)
                minDist = min(minDist, simd_distance(p, cp))
            }
        }

        // 3. Point to Triangle
        for p in primsA.points {
            for (t0, t1, t2) in primsB.triangles {
                let cp = closestPointOnTriangle(p: p, a: t0, b: t1, c: t2)
                minDist = min(minDist, simd_distance(p, cp))
            }
        }
        for p in primsB.points {
            for (t0, t1, t2) in primsA.triangles {
                let cp = closestPointOnTriangle(p: p, a: t0, b: t1, c: t2)
                minDist = min(minDist, simd_distance(p, cp))
            }
        }

        // 4. Segment to Segment
        for (a0, a1) in primsA.segments {
            for (b0, b1) in primsB.segments {
                minDist = min(minDist, distanceBetweenSegments(p0: a0, p1: a1, q0: b0, q1: b1))
            }
        }

        // 5. Segment to Triangle
        for (s0, s1) in primsA.segments {
            for (t0, t1, t2) in primsB.triangles {
                let cp0 = closestPointOnTriangle(p: s0, a: t0, b: t1, c: t2)
                let cp1 = closestPointOnTriangle(p: s1, a: t0, b: t1, c: t2)
                minDist = min(minDist, simd_distance(s0, cp0))
                minDist = min(minDist, simd_distance(s1, cp1))
                minDist = min(minDist, distanceBetweenSegments(p0: s0, p1: s1, q0: t0, q1: t1))
                minDist = min(minDist, distanceBetweenSegments(p0: s0, p1: s1, q0: t1, q1: t2))
                minDist = min(minDist, distanceBetweenSegments(p0: s0, p1: s1, q0: t2, q1: t0))
            }
        }
        for (s0, s1) in primsB.segments {
            for (t0, t1, t2) in primsA.triangles {
                let cp0 = closestPointOnTriangle(p: s0, a: t0, b: t1, c: t2)
                let cp1 = closestPointOnTriangle(p: s1, a: t0, b: t1, c: t2)
                minDist = min(minDist, simd_distance(s0, cp0))
                minDist = min(minDist, simd_distance(s1, cp1))
                minDist = min(minDist, distanceBetweenSegments(p0: s0, p1: s1, q0: t0, q1: t1))
                minDist = min(minDist, distanceBetweenSegments(p0: s0, p1: s1, q0: t1, q1: t2))
                minDist = min(minDist, distanceBetweenSegments(p0: s0, p1: s1, q0: t2, q1: t0))
            }
        }

        // 6. Triangle to Triangle
        for (a0, a1, a2) in primsA.triangles {
            for (b0, b1, b2) in primsB.triangles {
                let d = distanceBetweenTriangles(v0: a0, v1: a1, v2: a2, u0: b0, u1: b1, u2: b2)
                if d < minDist {
                    minDist = d
                    if minDist < 1e-5 { return 0.0 }
                }
            }
        }

        if minDist == Float.greatestFiniteMagnitude {
            return Double(simd_distance(geometryA.centroid, geometryB.centroid))
        }

        return Double(minDist)
    }
}
