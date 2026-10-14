import Foundation
import simd

/// Axis-aligned bounding box and dimensions measured from a solid's tessellated mesh.
public struct SolidBoundsMeasurement: Sendable, Codable, Equatable {
    public let min: SIMD3<Float>
    public let max: SIMD3<Float>
    public var size: SIMD3<Float> { max - min }

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    public func toDictionary() -> [String: Any] {
        [
            "min": [Double(min.x), Double(min.y), Double(min.z)],
            "max": [Double(max.x), Double(max.y), Double(max.z)],
            "size": [Double(size.x), Double(size.y), Double(size.z)]
        ]
    }
}

/// Geometric measurements computed from a solid's tessellated mesh.
public struct SolidMeasurements: Sendable, Codable, Equatable {
    public let volume: Double
    public let area: Double
    public let bounds: SolidBoundsMeasurement

    public init(volume: Double, area: Double, bounds: SolidBoundsMeasurement) {
        self.volume = volume
        self.area = area
        self.bounds = bounds
    }

    public func toDictionary() -> [String: Any] {
        [
            "volume": volume,
            "area": area,
            "bounds": bounds.toDictionary()
        ]
    }
}

/// Topological and geometric analysis of a single `MeshPayload`.
public struct MeshVerification: Sendable, Equatable {
    public let closed: Bool
    public let manifold: Bool
    public let positiveVolume: Bool
    public let triangleCount: Int
    public let openEdgeCount: Int
    public let nonManifoldEdgeCount: Int
    public let measurements: SolidMeasurements?

    public var isValidSolid: Bool {
        closed && manifold && positiveVolume
    }
}

/// Comparison result for a scalar metric (`volume` or `area`) against an `expected` block.
public struct ExpectedMetricCheck: Sendable, Codable, Equatable {
    public let passed: Bool
    public let measured: Double
    public let expected: Double
    public let tolerance: Double
    public let delta: Double
    public let allowedDelta: Double

    public func toDictionary() -> [String: Any] {
        [
            "passed": passed,
            "measured": measured,
            "expected": expected,
            "tolerance": tolerance,
            "delta": delta,
            "allowedDelta": allowedDelta
        ]
    }
}

/// Comparison result for axis-aligned bounding box coordinates against an `expected` block.
public struct ExpectedBoundsCheck: Sendable, Codable, Equatable {
    public let passed: Bool
    public let measured: PartExpectedBounds
    public let expected: PartExpectedBounds
    public let tolerance: Double
    public let maxDelta: Double
    public let allowedDelta: Double

    public func toDictionary() -> [String: Any] {
        [
            "passed": passed,
            "measured": [
                "min": [Double(measured.min.x), Double(measured.min.y), Double(measured.min.z)],
                "max": [Double(measured.max.x), Double(measured.max.y), Double(measured.max.z)]
            ],
            "expected": [
                "min": [Double(expected.min.x), Double(expected.min.y), Double(expected.min.z)],
                "max": [Double(expected.max.x), Double(expected.max.y), Double(expected.max.z)]
            ],
            "tolerance": tolerance,
            "maxDelta": maxDelta,
            "allowedDelta": allowedDelta
        ]
    }
}

/// Structured verification report for a single solid produced by `cad_verify` (#428).
public struct SolidVerificationReport: Sendable, Equatable {
    public let id: SolidId
    public let name: String
    public let kind: String
    public let file: String?
    public let valid: Bool
    public let closed: Bool
    public let manifold: Bool
    public let positiveVolume: Bool
    public let triangleCount: Int
    public let measured: SolidMeasurements?
    public let expected: PartExpected?
    public let volumeCheck: ExpectedMetricCheck?
    public let areaCheck: ExpectedMetricCheck?
    public let boundsCheck: ExpectedBoundsCheck?
    public let diagnostic: PartDiagnostic?
    public let failures: [String]

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.rawValue,
            "name": name,
            "kind": kind,
            "valid": valid,
            "closed": closed,
            "manifold": manifold,
            "positiveVolume": positiveVolume,
            "triangleCount": triangleCount,
            "failures": failures
        ]
        if let file {
            dict["file"] = file
        }
        if let measured {
            dict["measured"] = measured.toDictionary()
        }
        if let expected {
            var expDict: [String: Any] = [:]
            if let v = expected.volume { expDict["volume"] = v }
            if let a = expected.area { expDict["area"] = a }
            if let b = expected.bounds {
                expDict["bounds"] = [
                    "min": [Double(b.min.x), Double(b.min.y), Double(b.min.z)],
                    "max": [Double(b.max.x), Double(b.max.y), Double(b.max.z)]
                ]
            }
            if let t = expected.tolerance { expDict["tolerance"] = t }
            dict["expected"] = expDict
        }
        var checks: [String: Any] = [
            "closed": closed,
            "manifold": manifold,
            "positiveVolume": positiveVolume
        ]
        if let volumeCheck {
            checks["volume"] = volumeCheck.toDictionary()
        }
        if let areaCheck {
            checks["area"] = areaCheck.toDictionary()
        }
        if let boundsCheck {
            checks["bounds"] = boundsCheck.toDictionary()
        }
        dict["checks"] = checks
        if let diagnostic {
            dict["diagnostic"] = [
                "file": diagnostic.file,
                "line": diagnostic.line,
                "column": diagnostic.column,
                "message": diagnostic.message
            ]
        }
        return dict
    }
}

/// Evaluates topological validity (closed, manifold, positive volume) and intent checks (`expected` block) for CAD solids (#428).
public enum SolidVerifier {
    public static let defaultTolerance: Double = 0.01

    private struct QuantizedPoint: Hashable {
        let x: Int64
        let y: Int64
        let z: Int64

        init(_ p: SIMD3<Double>, scale: Double = 1000.0) {
            self.x = Int64((p.x * scale).rounded())
            self.y = Int64((p.y * scale).rounded())
            self.z = Int64((p.z * scale).rounded())
        }

        func toDouble(scale: Double = 1000.0) -> SIMD3<Double> {
            SIMD3<Double>(Double(x) / scale, Double(y) / scale, Double(z) / scale)
        }
    }

    private struct UndirectedEdge: Hashable {
        let a: QuantizedPoint
        let b: QuantizedPoint

        init(_ u: QuantizedPoint, _ v: QuantizedPoint) {
            if Self.lessThan(u, v) {
                self.a = u
                self.b = v
            } else {
                self.a = v
                self.b = u
            }
        }

        static func lessThan(_ lhs: QuantizedPoint, _ rhs: QuantizedPoint) -> Bool {
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.z < rhs.z
        }
    }

    private struct EdgeCounts {
        var forward: Int = 0
        var backward: Int = 0
    }

    /// Computes topological validity (`closed`, `manifold`, `positiveVolume`) and geometric metrics (`volume`, `area`, `bounds`) from `payload`.
    public static func analyzeMesh(
        _ payload: MeshPayload,
        transform: Transform = .identity
    ) -> MeshVerification {
        let posCount = payload.positions.count
        let idxCount = payload.indices.count
        let triCount = idxCount / 3

        guard triCount >= 4,
              posCount >= 12,
              posCount % 3 == 0,
              idxCount == triCount * 3,
              transform.position.x.isFinite,
              transform.position.y.isFinite,
              transform.position.z.isFinite else {
            return MeshVerification(
                closed: false,
                manifold: false,
                positiveVolume: false,
                triangleCount: triCount,
                openEdgeCount: max(1, triCount),
                nonManifoldEdgeCount: 0,
                measurements: nil
            )
        }

        let vertexCount = posCount / 3
        let offset = SIMD3<Double>(
            Double(transform.position.x),
            Double(transform.position.y),
            Double(transform.position.z)
        )

        var minBounds = SIMD3<Double>(repeating: .infinity)
        var maxBounds = SIMD3<Double>(repeating: -.infinity)
        var vertices: [SIMD3<Double>] = []
        vertices.reserveCapacity(vertexCount)

        for v in 0..<vertexCount {
            let base = v * 3
            let px = Double(payload.positions[base])
            let py = Double(payload.positions[base + 1])
            let pz = Double(payload.positions[base + 2])
            guard px.isFinite, py.isFinite, pz.isFinite else {
                return MeshVerification(
                    closed: false,
                    manifold: false,
                    positiveVolume: false,
                    triangleCount: triCount,
                    openEdgeCount: 1,
                    nonManifoldEdgeCount: 1,
                    measurements: nil
                )
            }
            let worldPt = SIMD3<Double>(px, py, pz) + offset
            minBounds = simd_min(minBounds, worldPt)
            maxBounds = simd_max(maxBounds, worldPt)
            vertices.append(worldPt)
        }

        let ref = vertices[0]
        var totalArea: Double = 0
        var signedVolume: Double = 0
        var edgeTable: [UndirectedEdge: EdgeCounts] = [:]
        edgeTable.reserveCapacity(triCount * 2)
        var nonDegenerateTriangles = 0

        for t in 0..<triCount {
            let i0 = Int(payload.indices[t * 3])
            let i1 = Int(payload.indices[t * 3 + 1])
            let i2 = Int(payload.indices[t * 3 + 2])
            guard i0 >= 0, i0 < vertexCount,
                  i1 >= 0, i1 < vertexCount,
                  i2 >= 0, i2 < vertexCount else {
                return MeshVerification(
                    closed: false,
                    manifold: false,
                    positiveVolume: false,
                    triangleCount: triCount,
                    openEdgeCount: 1,
                    nonManifoldEdgeCount: 1,
                    measurements: nil
                )
            }

            let p0 = vertices[i0]
            let p1 = vertices[i1]
            let p2 = vertices[i2]

            let cross = simd_cross(p1 - p0, p2 - p0)
            let doubleArea = simd_length(cross)
            totalArea += 0.5 * doubleArea
            signedVolume += simd_dot(p0 - ref, simd_cross(p1 - ref, p2 - ref)) / 6.0

            let q0 = QuantizedPoint(p0)
            let q1 = QuantizedPoint(p1)
            let q2 = QuantizedPoint(p2)
            guard doubleArea > 1e-9, q0 != q1, q1 != q2, q2 != q0 else {
                continue
            }
            nonDegenerateTriangles += 1

            for (u, v) in [(q0, q1), (q1, q2), (q2, q0)] {
                let edge = UndirectedEdge(u, v)
                if UndirectedEdge.lessThan(u, v) {
                    edgeTable[edge, default: EdgeCounts()].forward += 1
                } else {
                    edgeTable[edge, default: EdgeCounts()].backward += 1
                }
            }
        }

        // First check direct edge pairing; if residual edges exist due to colinear CSG T-junction splits,
        // split residual edges at intermediate colinear vertices and re-evaluate.
        let resolvedTable = resolveColinearTJunctionsIfNeeded(edgeTable)

        var openEdges = 0
        var nonManifoldEdges = 0
        for counts in resolvedTable.values {
            let total = counts.forward + counts.backward
            if total < 2 || counts.forward != counts.backward {
                if total == 1 {
                    openEdges += 1
                } else if counts.forward != counts.backward {
                    // Unbalanced edge: either a boundary gap (1 vs 0) or inconsistent winding / fin (2 vs 0, 2 vs 1, etc.)
                    if counts.forward == 0 || counts.backward == 0 {
                        openEdges += 1
                    }
                    nonManifoldEdges += 1
                }
            } else if total > 2 {
                nonManifoldEdges += 1
            }
        }

        let isClosed = nonDegenerateTriangles >= 4 && openEdges == 0
        let isManifold = isClosed && nonManifoldEdges == 0
        let hasPositiveVolume = signedVolume > 1e-6

        let bounds = SolidBoundsMeasurement(
            min: SIMD3<Float>(Float(minBounds.x), Float(minBounds.y), Float(minBounds.z)),
            max: SIMD3<Float>(Float(maxBounds.x), Float(maxBounds.y), Float(maxBounds.z))
        )
        let measurements = SolidMeasurements(
            volume: signedVolume,
            area: totalArea,
            bounds: bounds
        )

        return MeshVerification(
            closed: isClosed,
            manifold: isManifold,
            positiveVolume: hasPositiveVolume,
            triangleCount: triCount,
            openEdgeCount: openEdges,
            nonManifoldEdgeCount: nonManifoldEdges,
            measurements: measurements
        )
    }

    /// Splits any unmatched directed edges at colinear intermediate vertices produced by CSG T-junctions.
    private static func resolveColinearTJunctionsIfNeeded(
        _ edgeTable: [UndirectedEdge: EdgeCounts]
    ) -> [UndirectedEdge: EdgeCounts] {
        var residualDirected: [(from: QuantizedPoint, to: QuantizedPoint, count: Int)] = []
        var balancedTable: [UndirectedEdge: EdgeCounts] = [:]
        balancedTable.reserveCapacity(edgeTable.count)

        for (edge, counts) in edgeTable {
            let matched = min(counts.forward, counts.backward)
            let remFwd = counts.forward - matched
            let remBwd = counts.backward - matched
            if matched > 0 {
                balancedTable[edge] = EdgeCounts(forward: matched, backward: matched)
            }
            if remFwd > 0 {
                residualDirected.append((from: edge.a, to: edge.b, count: remFwd))
            }
            if remBwd > 0 {
                residualDirected.append((from: edge.b, to: edge.a, count: remBwd))
            }
        }

        guard !residualDirected.isEmpty else {
            return edgeTable
        }

        // Collect all unique vertices participating in residual edges.
        var residualVerticesSet: Set<QuantizedPoint> = []
        for item in residualDirected {
            residualVerticesSet.insert(item.from)
            residualVerticesSet.insert(item.to)
        }
        let residualVertices = residualVerticesSet.map { (q: $0, pos: $0.toDouble()) }

        var anySplit = false
        for item in residualDirected {
            let aPos = item.from.toDouble()
            let bPos = item.to.toDouble()
            let ab = bPos - aPos
            let abLenSq = simd_length_squared(ab)
            guard abLenSq > 1e-9 else { continue }

            // Find all residual vertices lying strictly between A and B on segment AB.
            var intermediates: [(t: Double, q: QuantizedPoint)] = []
            for candidate in residualVertices {
                guard candidate.q != item.from, candidate.q != item.to else { continue }
                let ap = candidate.pos - aPos
                let t = simd_dot(ap, ab) / abLenSq
                guard t > 1e-5, t < 1.0 - 1e-5 else { continue }
                let closest = aPos + t * ab
                let distSq = simd_length_squared(candidate.pos - closest)
                if distSq <= 4e-6 { // within 0.002 mm of segment AB
                    intermediates.append((t: t, q: candidate.q))
                }
            }

            if intermediates.isEmpty {
                let edge = UndirectedEdge(item.from, item.to)
                if UndirectedEdge.lessThan(item.from, item.to) {
                    balancedTable[edge, default: EdgeCounts()].forward += item.count
                } else {
                    balancedTable[edge, default: EdgeCounts()].backward += item.count
                }
            } else {
                anySplit = true
                intermediates.sort { $0.t < $1.t }
                var chain: [QuantizedPoint] = [item.from]
                for mid in intermediates where chain.last != mid.q {
                    chain.append(mid.q)
                }
                if chain.last != item.to {
                    chain.append(item.to)
                }
                for idx in 0..<(chain.count - 1) {
                    let u = chain[idx]
                    let v = chain[idx + 1]
                    guard u != v else { continue }
                    let subEdge = UndirectedEdge(u, v)
                    if UndirectedEdge.lessThan(u, v) {
                        balancedTable[subEdge, default: EdgeCounts()].forward += item.count
                    } else {
                        balancedTable[subEdge, default: EdgeCounts()].backward += item.count
                    }
                }
            }
        }

        guard anySplit else {
            return edgeTable
        }

        // Normalize split sub-edges where opposing T-junction segments cancelled each other.
        var normalizedTable: [UndirectedEdge: EdgeCounts] = [:]
        normalizedTable.reserveCapacity(balancedTable.count)
        for (edge, counts) in balancedTable {
            if counts.forward > 0 && counts.forward == counts.backward {
                normalizedTable[edge] = EdgeCounts(forward: 1, backward: 1)
            } else {
                normalizedTable[edge] = counts
            }
        }
        return normalizedTable
    }

    /// Verifies a scene object's mesh topology and compares its measurements against an optional `PartExpected` block.
    public static func verify(
        object: SceneObject,
        payload: MeshPayload?,
        expected: PartExpected? = nil,
        diagnostic: PartDiagnostic? = nil,
        toleranceOverride: Double? = nil
    ) -> SolidVerificationReport {
        let filePath: String?
        if case .part(let url, _) = object.def {
            filePath = url.path
        } else {
            filePath = nil
        }

        var failures: [String] = []
        if let diagnostic {
            failures.append("Evaluation error at \(diagnostic.description)")
        }

        guard let payload else {
            if failures.isEmpty {
                failures.append("Solid '\(object.id.rawValue)' has no evaluated mesh")
            }
            return SolidVerificationReport(
                id: object.id,
                name: object.name,
                kind: object.def.kind,
                file: filePath,
                valid: false,
                closed: false,
                manifold: false,
                positiveVolume: false,
                triangleCount: 0,
                measured: nil,
                expected: expected,
                volumeCheck: nil,
                areaCheck: nil,
                boundsCheck: nil,
                diagnostic: diagnostic,
                failures: failures
            )
        }

        let meshCheck = analyzeMesh(payload, transform: object.transform)
        if !meshCheck.closed {
            failures.append("Solid '\(object.id.rawValue)' is not closed (open boundary edges: \(meshCheck.openEdgeCount))")
        }
        if !meshCheck.manifold {
            failures.append("Solid '\(object.id.rawValue)' is not manifold (non-manifold edges: \(meshCheck.nonManifoldEdgeCount))")
        }
        if !meshCheck.positiveVolume {
            let volStr = String(format: "%.4f", meshCheck.measurements?.volume ?? 0)
            failures.append("Solid '\(object.id.rawValue)' does not have positive volume (measured: \(volStr) mm^3)")
        }

        var volumeCheck: ExpectedMetricCheck? = nil
        var areaCheck: ExpectedMetricCheck? = nil
        var boundsCheck: ExpectedBoundsCheck? = nil

        if let expected, let measured = meshCheck.measurements {
            let tol = max(0, toleranceOverride ?? expected.tolerance ?? defaultTolerance)

            if let expVolume = expected.volume {
                let delta = abs(measured.volume - expVolume)
                let allowed = max(abs(expVolume) * tol, tol, 1e-4)
                let passed = delta <= allowed
                volumeCheck = ExpectedMetricCheck(
                    passed: passed,
                    measured: measured.volume,
                    expected: expVolume,
                    tolerance: tol,
                    delta: delta,
                    allowedDelta: allowed
                )
                if !passed {
                    failures.append(
                        String(
                            format: "volume mismatch on '%@': measured %.4f, expected %.4f (delta %.4f > allowed %.4f, tolerance %.4f)",
                            object.id.rawValue,
                            measured.volume,
                            expVolume,
                            delta,
                            allowed,
                            tol
                        )
                    )
                }
            }

            if let expArea = expected.area {
                let delta = abs(measured.area - expArea)
                let allowed = max(abs(expArea) * tol, tol, 1e-4)
                let passed = delta <= allowed
                areaCheck = ExpectedMetricCheck(
                    passed: passed,
                    measured: measured.area,
                    expected: expArea,
                    tolerance: tol,
                    delta: delta,
                    allowedDelta: allowed
                )
                if !passed {
                    failures.append(
                        String(
                            format: "area mismatch on '%@': measured %.4f, expected %.4f (delta %.4f > allowed %.4f, tolerance %.4f)",
                            object.id.rawValue,
                            measured.area,
                            expArea,
                            delta,
                            allowed,
                            tol
                        )
                    )
                }
            }

            if let expBounds = expected.bounds {
                let measBounds = PartExpectedBounds(min: measured.bounds.min, max: measured.bounds.max)
                let minDiff = simd_abs(measBounds.min - expBounds.min)
                let maxDiff = simd_abs(measBounds.max - expBounds.max)
                let worstDelta = Double(
                    Swift.max(
                        Swift.max(minDiff.x, minDiff.y, minDiff.z),
                        Swift.max(maxDiff.x, maxDiff.y, maxDiff.z)
                    )
                )
                let expSpan = simd_abs(expBounds.max - expBounds.min)
                let characteristicScale = Double(
                    Swift.max(
                        Swift.max(expSpan.x, expSpan.y, expSpan.z),
                        Swift.max(
                            Swift.max(abs(expBounds.min.x), abs(expBounds.min.y), abs(expBounds.min.z)),
                            Swift.max(abs(expBounds.max.x), abs(expBounds.max.y), abs(expBounds.max.z))
                        ),
                        1.0
                    )
                )
                let allowed = max(characteristicScale * tol, tol, 1e-4)
                let passed = worstDelta <= allowed
                boundsCheck = ExpectedBoundsCheck(
                    passed: passed,
                    measured: measBounds,
                    expected: expBounds,
                    tolerance: tol,
                    maxDelta: worstDelta,
                    allowedDelta: allowed
                )
                if !passed {
                    failures.append(
                        String(
                            format: "bounds mismatch on '%@': measured min [%.3f, %.3f, %.3f] max [%.3f, %.3f, %.3f], expected min [%.3f, %.3f, %.3f] max [%.3f, %.3f, %.3f] (maxDelta %.4f > allowed %.4f, tolerance %.4f)",
                            object.id.rawValue,
                            measBounds.min.x, measBounds.min.y, measBounds.min.z,
                            measBounds.max.x, measBounds.max.y, measBounds.max.z,
                            expBounds.min.x, expBounds.min.y, expBounds.min.z,
                            expBounds.max.x, expBounds.max.y, expBounds.max.z,
                            worstDelta,
                            allowed,
                            tol
                        )
                    )
                }
            }
        }

        let isValid = diagnostic == nil
            && meshCheck.isValidSolid
            && (volumeCheck?.passed ?? true)
            && (areaCheck?.passed ?? true)
            && (boundsCheck?.passed ?? true)

        return SolidVerificationReport(
            id: object.id,
            name: object.name,
            kind: object.def.kind,
            file: filePath,
            valid: isValid,
            closed: meshCheck.closed,
            manifold: meshCheck.manifold,
            positiveVolume: meshCheck.positiveVolume,
            triangleCount: meshCheck.triangleCount,
            measured: meshCheck.measurements,
            expected: expected,
            volumeCheck: volumeCheck,
            areaCheck: areaCheck,
            boundsCheck: boundsCheck,
            diagnostic: diagnostic,
            failures: failures
        )
    }
}
