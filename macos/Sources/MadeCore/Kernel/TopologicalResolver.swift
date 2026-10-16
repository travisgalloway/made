import Foundation
import simd
public import OCCTSwift

/// Resolves engine-neutral `TopologicalReference` queries into concrete OCCT sub-shapes.
///
/// Implements ADR-D3 topological resolution using lineage history, adjacent face normals,
/// curve/surface types, and fallback geometric signature tie-breakers.
/// Invariant 4: Kept strictly within `MadeCore/Kernel` to prevent OCCT types from leaking into
/// Viewport, Scripting, or Scene layers.
public enum TopologicalResolver {

    // MARK: - Face Resolution

    public static func resolveFace(in shape: Shape, reference: TopologicalReference) throws -> Face {
        guard reference.elementType == .face else {
            throw KernelError(
                code: .topologicalReferenceBroken,
                message: "Reference element type mismatch: expected face but got \(reference.elementType.rawValue)"
            )
        }

        let faces = shape.faces()
        guard !faces.isEmpty else {
            throw KernelError(
                code: .topologicalReferenceBroken,
                message: "Shape contains no faces to resolve reference '\(reference.id)'"
            )
        }

        let label = reference.historyPath.last?.label

        var candidates: [Face] = []

        if let label {
            switch label {
            case "face:top":
                candidates = faces.filter { face in
                    face.isPlanar && matchesNormal(face.normal, SIMD3<Double>(0, 0, 1))
                }
            case "face:bottom":
                candidates = faces.filter { face in
                    face.isPlanar && matchesNormal(face.normal, SIMD3<Double>(0, 0, -1))
                }
            case "face:front":
                candidates = faces.filter { face in
                    face.isPlanar && matchesNormal(face.normal, SIMD3<Double>(0, -1, 0))
                }
            case "face:back":
                candidates = faces.filter { face in
                    face.isPlanar && matchesNormal(face.normal, SIMD3<Double>(0, 1, 0))
                }
            case "face:right":
                candidates = faces.filter { face in
                    face.isPlanar && matchesNormal(face.normal, SIMD3<Double>(1, 0, 0))
                }
            case "face:left":
                candidates = faces.filter { face in
                    face.isPlanar && matchesNormal(face.normal, SIMD3<Double>(-1, 0, 0))
                }
            case "face:side":
                candidates = faces.filter { face in
                    face.surfaceType == .cylinder || face.surfaceType == .cone
                }
            case "face:surface":
                candidates = faces.filter { face in
                    face.surfaceType == .sphere || face.surfaceType == .torus
                }
            case "face:slanted":
                candidates = faces.filter { face in
                    guard face.isPlanar, let n = face.normal else { return false }
                    return !matchesNormal(n, SIMD3(0, 0, 1)) &&
                           !matchesNormal(n, SIMD3(0, 0, -1)) &&
                           !matchesNormal(n, SIMD3(0, -1, 0)) &&
                           !matchesNormal(n, SIMD3(0, 1, 0)) &&
                           !matchesNormal(n, SIMD3(1, 0, 0)) &&
                           !matchesNormal(n, SIMD3(-1, 0, 0))
                }
            default:
                break
            }
        }

        if candidates.isEmpty, let disambiguator = reference.disambiguator {
            candidates = faces.filter { face in
                if let surfaceType = disambiguator.surfaceOrCurveType {
                    if surfaceType == "cylinder" && face.surfaceType != .cylinder { return false }
                    if surfaceType == "cone" && face.surfaceType != .cone { return false }
                    if surfaceType == "sphere" && face.surfaceType != .sphere { return false }
                    if surfaceType == "torus" && face.surfaceType != .torus { return false }
                    if surfaceType == "plane" && !face.isPlanar { return false }
                }
                if let targetNormal = disambiguator.normal {
                    guard matchesNormal(face.normal, SIMD3<Double>(Double(targetNormal.x), Double(targetNormal.y), Double(targetNormal.z))) else {
                        return false
                    }
                }
                return true
            }
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        if candidates.count > 1, let centroid = reference.disambiguator?.centroid {
            let target = SIMD3<Double>(Double(centroid.x), Double(centroid.y), Double(centroid.z))
            if let best = candidates.min(by: { f1, f2 in
                let c1 = f1.surfaceInertia.centerOfMass ?? SIMD3<Double>.zero
                let c2 = f2.surfaceInertia.centerOfMass ?? SIMD3<Double>.zero
                return simd_distance_squared(c1, target) < simd_distance_squared(c2, target)
            }) {
                return best
            }
        }

        throw KernelError(
            code: .topologicalReferenceBroken,
            message: "Topological reference '\(reference.id)' (label: \(label ?? "none")) could not be resolved in shape"
        )
    }

    // MARK: - Edge Resolution

    public static func resolveEdge(in shape: Shape, reference: TopologicalReference) throws -> Edge {
        guard reference.elementType == .edge else {
            throw KernelError(
                code: .topologicalReferenceBroken,
                message: "Reference element type mismatch: expected edge but got \(reference.elementType.rawValue)"
            )
        }

        let edges = shape.edges()
        guard !edges.isEmpty else {
            throw KernelError(
                code: .topologicalReferenceBroken,
                message: "Shape contains no edges to resolve reference '\(reference.id)'"
            )
        }

        let label = reference.historyPath.last?.label

        var candidates: [Edge] = []

        if let label {
            // Box edges: matched by unique unordered pair of adjacent face normals
            let boxEdgeNormals: [String: (SIMD3<Double>, SIMD3<Double>)] = [
                "edge:top-front": (SIMD3(0, 0, 1), SIMD3(0, -1, 0)),
                "edge:top-back": (SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
                "edge:top-left": (SIMD3(0, 0, 1), SIMD3(-1, 0, 0)),
                "edge:top-right": (SIMD3(0, 0, 1), SIMD3(1, 0, 0)),
                "edge:bottom-front": (SIMD3(0, 0, -1), SIMD3(0, -1, 0)),
                "edge:bottom-back": (SIMD3(0, 0, -1), SIMD3(0, 1, 0)),
                "edge:bottom-left": (SIMD3(0, 0, -1), SIMD3(-1, 0, 0)),
                "edge:bottom-right": (SIMD3(0, 0, -1), SIMD3(1, 0, 0)),
                "edge:front-left": (SIMD3(0, -1, 0), SIMD3(-1, 0, 0)),
                "edge:front-right": (SIMD3(0, -1, 0), SIMD3(1, 0, 0)),
                "edge:back-left": (SIMD3(0, 1, 0), SIMD3(-1, 0, 0)),
                "edge:back-right": (SIMD3(0, 1, 0), SIMD3(1, 0, 0))
            ]

            if let (expectedN1, expectedN2) = boxEdgeNormals[label] {
                candidates = edges.filter { edge in
                    guard edge.isLine else { return false }
                    guard let (f1, f2Opt) = edge.adjacentFaces(in: shape), let f2 = f2Opt else {
                        return false
                    }
                    guard let n1 = f1.normal, let n2 = f2.normal else { return false }
                    return (matchesNormal(n1, expectedN1) && matchesNormal(n2, expectedN2))
                        || (matchesNormal(n1, expectedN2) && matchesNormal(n2, expectedN1))
                }
            } else {
                switch label {
                case "edge:top":
                    candidates = edges.filter { edge in
                        guard edge.isCircle else { return false }
                        guard let (f1, f2Opt) = edge.adjacentFaces(in: shape) else { return false }
                        let n1IsTop = matchesNormal(f1.normal, SIMD3(0, 0, 1))
                        let n2IsTop = f2Opt?.normal.map { matchesNormal($0, SIMD3(0, 0, 1)) } ?? false
                        if n1IsTop || n2IsTop { return true }
                        let ep = edge.endpoints
                        return ep.start.z > 0 && ep.end.z > 0
                    }
                case "edge:bottom":
                    candidates = edges.filter { edge in
                        guard edge.isCircle else { return false }
                        guard let (f1, f2Opt) = edge.adjacentFaces(in: shape) else { return false }
                        let n1IsBottom = matchesNormal(f1.normal, SIMD3(0, 0, -1))
                        let n2IsBottom = f2Opt?.normal.map { matchesNormal($0, SIMD3(0, 0, -1)) } ?? false
                        if n1IsBottom || n2IsBottom { return true }
                        let ep = edge.endpoints
                        return ep.start.z < 0 && ep.end.z < 0
                    }
                case "edge:seam":
                    candidates = edges.filter { edge in
                        if edge.isLine {
                            let ep = edge.endpoints
                            return abs(ep.start.x - ep.end.x) < 1e-4 && abs(ep.start.y - ep.end.y) < 1e-4
                        }
                        return edge.isCircle
                    }
                case "edge:major-seam", "edge:minor-seam":
                    candidates = edges.filter { edge in
                        edge.isCircle
                    }
                default:
                    break
                }
            }
        }

        if candidates.isEmpty, let disambiguator = reference.disambiguator {
            candidates = edges.filter { edge in
                if let curveType = disambiguator.surfaceOrCurveType {
                    if curveType == "circle" && !edge.isCircle { return false }
                    if curveType == "line" && !edge.isLine { return false }
                }
                return true
            }
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        if candidates.count > 1, let centroid = reference.disambiguator?.centroid {
            let target = SIMD3<Double>(Double(centroid.x), Double(centroid.y), Double(centroid.z))
            if let best = candidates.min(by: { e1, e2 in
                let p1 = (e1.endpoints.start + e1.endpoints.end) / 2.0
                let p2 = (e2.endpoints.start + e2.endpoints.end) / 2.0
                return simd_distance_squared(p1, target) < simd_distance_squared(p2, target)
            }) {
                return best
            }
        }

        throw KernelError(
            code: .topologicalReferenceBroken,
            message: "Topological reference '\(reference.id)' (label: \(label ?? "none")) could not be resolved in shape"
        )
    }

    // MARK: - Vertex Resolution

    public static func resolveVertex(in shape: Shape, reference: TopologicalReference) throws -> SIMD3<Double> {
        guard reference.elementType == .vertex else {
            throw KernelError(
                code: .topologicalReferenceBroken,
                message: "Reference element type mismatch: expected vertex but got \(reference.elementType.rawValue)"
            )
        }

        let vertices = shape.vertices()
        guard !vertices.isEmpty else {
            throw KernelError(
                code: .topologicalReferenceBroken,
                message: "Shape contains no vertices to resolve reference '\(reference.id)'"
            )
        }

        let label = reference.historyPath.last?.label

        if let label {
            let octantMap: [String: (Bool, Bool, Bool)] = [
                // (isPositiveX, isPositiveY, isPositiveZ)
                "vertex:top-front-left": (false, false, true),
                "vertex:top-front-right": (true, false, true),
                "vertex:top-back-left": (false, true, true),
                "vertex:top-back-right": (true, true, true),
                "vertex:bottom-front-left": (false, false, false),
                "vertex:bottom-front-right": (true, false, false),
                "vertex:bottom-back-left": (false, true, false),
                "vertex:bottom-back-right": (true, true, false)
            ]

            if let (posX, posY, posZ) = octantMap[label] {
                let candidates = vertices.filter { v in
                    (posX ? v.x > 0 : v.x < 0) &&
                    (posY ? v.y > 0 : v.y < 0) &&
                    (posZ ? v.z > 0 : v.z < 0)
                }
                if let first = candidates.first {
                    return first
                }
            } else {
                switch label {
                case "vertex:top-seam":
                    let candidates = vertices.filter { $0.z > 0 }
                    if let first = candidates.first { return first }
                case "vertex:bottom-seam":
                    let candidates = vertices.filter { $0.z < 0 }
                    if let first = candidates.first { return first }
                case "vertex:north-pole":
                    let candidates = vertices.filter { $0.z > 0 && abs($0.x) < 1e-3 && abs($0.y) < 1e-3 }
                    if let first = candidates.first { return first }
                case "vertex:south-pole":
                    let candidates = vertices.filter { $0.z < 0 && abs($0.x) < 1e-3 && abs($0.y) < 1e-3 }
                    if let first = candidates.first { return first }
                case "vertex:apex":
                    let candidates = vertices.filter { $0.z > 0 && abs($0.x) < 1e-3 && abs($0.y) < 1e-3 }
                    if let first = candidates.first { return first }
                default:
                    break
                }
            }
        }

        if let centroid = reference.disambiguator?.centroid {
            let target = SIMD3<Double>(Double(centroid.x), Double(centroid.y), Double(centroid.z))
            if let best = vertices.min(by: { v1, v2 in
                simd_distance_squared(v1, target) < simd_distance_squared(v2, target)
            }) {
                return best
            }
        }

        throw KernelError(
            code: .topologicalReferenceBroken,
            message: "Topological reference '\(reference.id)' (label: \(label ?? "none")) could not be resolved in shape"
        )
    }

    // MARK: - Subshape Resolution

    public static func resolveSubshape(in shape: Shape, reference: TopologicalReference) throws -> Shape {
        switch reference.elementType {
        case .face:
            let face = try resolveFace(in: shape, reference: reference)
            guard let subshape = Shape.fromFace(face) else {
                throw KernelError(
                    code: .topologicalReferenceBroken,
                    message: "Failed to create Shape from resolved Face '\(reference.id)'"
                )
            }
            return subshape
        case .edge:
            let edge = try resolveEdge(in: shape, reference: reference)
            guard let subshape = Shape.fromEdge(edge) else {
                throw KernelError(
                    code: .topologicalReferenceBroken,
                    message: "Failed to create Shape from resolved Edge '\(reference.id)'"
                )
            }
            return subshape
        case .vertex:
            let vertex = try resolveVertex(in: shape, reference: reference)
            guard let subshape = Shape.makeVertex(at: vertex) else {
                throw KernelError(
                    code: .topologicalReferenceBroken,
                    message: "Failed to create Shape from resolved Vertex '\(reference.id)'"
                )
            }
            return subshape
        }
    }

    // MARK: - Private Helpers

    private static func matchesNormal(_ actual: SIMD3<Double>?, _ target: SIMD3<Double>, tolerance: Double = 0.1) -> Bool {
        guard let actual else { return false }
        return simd_dot(actual, target) > (1.0 - tolerance)
    }
}
