import Foundation
import simd

/// Categories of geometric quality metrics evaluated on tetrahedral mesh elements (BL-MSH-04, #277).
public enum MeshQualityMetricKind: String, Sendable, Codable, Equatable, Hashable, CaseIterable, Identifiable {
    case aspectRatio = "aspectRatio"
    case scaledJacobian = "scaledJacobian"
    case skewness = "skewness"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aspectRatio:
            return "Aspect Ratio"
        case .scaledJacobian:
            return "Scaled Jacobian"
        case .skewness:
            return "Equiangular Skewness"
        }
    }

    /// Standard failure threshold for this metric kind.
    public var standardFailureThreshold: Double {
        switch self {
        case .aspectRatio:
            return 3.0
        case .scaledJacobian:
            return 0.2
        case .skewness:
            return 0.7
        }
    }

    /// Evaluates whether a metric value violates the acceptable quality threshold.
    public func isFailing(value: Double, threshold: Double? = nil) -> Bool {
        let t = threshold ?? standardFailureThreshold
        switch self {
        case .aspectRatio:
            return value > t
        case .scaledJacobian:
            return value < t
        case .skewness:
            return value > t
        }
    }
}

/// A single interval bucket within a mesh quality distribution histogram.
public struct MeshQualityHistogramBin: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var rangeMin: Double
    public var rangeMax: Double
    public var count: Int
    public var isFailing: Bool

    public init(
        index: Int,
        rangeMin: Double,
        rangeMax: Double,
        count: Int,
        isFailing: Bool
    ) {
        self.index = index
        self.rangeMin = rangeMin
        self.rangeMax = rangeMax
        self.count = count
        self.isFailing = isFailing
    }
}

/// Statistical summary and histogram distribution for a specific mesh quality metric kind.
public struct MeshQualityMetricSummary: Sendable, Codable, Equatable, Hashable {
    public var kind: MeshQualityMetricKind
    public var minValue: Double
    public var maxValue: Double
    public var averageValue: Double
    public var failureThreshold: Double
    public var failingCount: Int
    public var failingPercentage: Double
    public var failingElementIds: [Int]
    public var histogramBins: [MeshQualityHistogramBin]

    public init(
        kind: MeshQualityMetricKind,
        minValue: Double = 0.0,
        maxValue: Double = 0.0,
        averageValue: Double = 0.0,
        failureThreshold: Double? = nil,
        failingCount: Int = 0,
        failingPercentage: Double = 0.0,
        failingElementIds: [Int] = [],
        histogramBins: [MeshQualityHistogramBin] = []
    ) {
        self.kind = kind
        self.minValue = minValue
        self.maxValue = maxValue
        self.averageValue = averageValue
        self.failureThreshold = failureThreshold ?? kind.standardFailureThreshold
        self.failingCount = failingCount
        self.failingPercentage = failingPercentage
        self.failingElementIds = failingElementIds
        self.histogramBins = histogramBins
    }
}

/// Complete quality evaluation report across aspect ratio, scaled Jacobian, and equiangular skewness.
public struct MeshQualityReport: Sendable, Codable, Equatable, Hashable {
    public var aspectRatioSummary: MeshQualityMetricSummary
    public var scaledJacobianSummary: MeshQualityMetricSummary
    public var skewnessSummary: MeshQualityMetricSummary

    public init(
        aspectRatioSummary: MeshQualityMetricSummary = MeshQualityMetricSummary(kind: .aspectRatio),
        scaledJacobianSummary: MeshQualityMetricSummary = MeshQualityMetricSummary(kind: .scaledJacobian),
        skewnessSummary: MeshQualityMetricSummary = MeshQualityMetricSummary(kind: .skewness)
    ) {
        self.aspectRatioSummary = aspectRatioSummary
        self.scaledJacobianSummary = scaledJacobianSummary
        self.skewnessSummary = skewnessSummary
    }

    /// Accesses the metric summary for the specified quality metric kind.
    public func summary(for kind: MeshQualityMetricKind) -> MeshQualityMetricSummary {
        switch kind {
        case .aspectRatio:
            return aspectRatioSummary
        case .scaledJacobian:
            return scaledJacobianSummary
        case .skewness:
            return skewnessSummary
        }
    }
}

/// Pure Swift geometric evaluator for tetrahedral finite element mesh quality (BL-MSH-04, #277).
public enum MeshQualityCalculator {

    /// Evaluates mesh quality across all tetrahedral elements and generates a complete quality report.
    public static func evaluate(nodes: [VolumeMeshNode], elements: [VolumeMeshElement]) -> MeshQualityReport {
        var nodeMap: [Int: SIMD3<Double>] = [:]
        nodeMap.reserveCapacity(nodes.count)
        for n in nodes {
            nodeMap[n.id] = n.position
        }

        var aspectRatios: [(id: Int, value: Double)] = []
        var jacobians: [(id: Int, value: Double)] = []
        var skewnesses: [(id: Int, value: Double)] = []

        let tetElements = elements.filter { $0.nodeIndices.count >= 4 }
        aspectRatios.reserveCapacity(tetElements.count)
        jacobians.reserveCapacity(tetElements.count)
        skewnesses.reserveCapacity(tetElements.count)

        for elem in tetElements {
            guard let p0 = nodeMap[elem.nodeIndices[0]],
                  let p1 = nodeMap[elem.nodeIndices[1]],
                  let p2 = nodeMap[elem.nodeIndices[2]],
                  let p3 = nodeMap[elem.nodeIndices[3]] else {
                aspectRatios.append((id: elem.id, value: 1000.0))
                jacobians.append((id: elem.id, value: 0.0))
                skewnesses.append((id: elem.id, value: 1.0))
                continue
            }

            let metrics = calculateTetrahedronMetrics(p0: p0, p1: p1, p2: p2, p3: p3)
            aspectRatios.append((id: elem.id, value: metrics.aspectRatio))
            jacobians.append((id: elem.id, value: metrics.scaledJacobian))
            skewnesses.append((id: elem.id, value: metrics.skewness))
        }

        let arSummary = makeMetricSummary(kind: .aspectRatio, entries: aspectRatios)
        let sjSummary = makeMetricSummary(kind: .scaledJacobian, entries: jacobians)
        let skSummary = makeMetricSummary(kind: .skewness, entries: skewnesses)

        return MeshQualityReport(
            aspectRatioSummary: arSummary,
            scaledJacobianSummary: sjSummary,
            skewnessSummary: skSummary
        )
    }

    /// Evaluates volume mesh quality using the mesh nodes and elements.
    public static func evaluate(mesh: VolumeMesh) -> MeshQualityReport {
        evaluate(nodes: mesh.nodes, elements: mesh.elements)
    }

    /// Calculates aspect ratio, scaled Jacobian determinant, and equiangular skewness for a single tetrahedron.
    public static func calculateTetrahedronMetrics(
        p0: SIMD3<Double>,
        p1: SIMD3<Double>,
        p2: SIMD3<Double>,
        p3: SIMD3<Double>
    ) -> (aspectRatio: Double, scaledJacobian: Double, skewness: Double) {
        // 1. Aspect Ratio: L_max / L_min
        let l01 = simd_distance(p0, p1)
        let l02 = simd_distance(p0, p2)
        let l03 = simd_distance(p0, p3)
        let l12 = simd_distance(p1, p2)
        let l13 = simd_distance(p1, p3)
        let l23 = simd_distance(p2, p3)

        let minL = min(l01, l02, l03, l12, l13, l23)
        let maxL = max(l01, l02, l03, l12, l13, l23)
        let aspectRatio: Double = (minL <= 1e-12) ? 1000.0 : (maxL / minL)

        // 2. Scaled Jacobian: min_k (sqrt(2) * det(J_k) / prod(||e_k||))
        // Corner 0: (p1-p0), (p2-p0), (p3-p0)
        let v01 = p1 - p0
        let v02 = p2 - p0
        let v03 = p3 - p0
        let det0 = simd_dot(v01, simd_cross(v02, v03))
        let d0 = l01 * l02 * l03
        let j0 = (d0 > 1e-18) ? (sqrt(2.0) * det0 / d0) : (det0 < 0 ? -1.0 : 0.0)

        // Corner 1: (p2-p1), (p0-p1), (p3-p1)
        let v12 = p2 - p1
        let v10 = p0 - p1
        let v13 = p3 - p1
        let det1 = simd_dot(v12, simd_cross(v10, v13))
        let d1 = l12 * l01 * l13
        let j1 = (d1 > 1e-18) ? (sqrt(2.0) * det1 / d1) : (det1 < 0 ? -1.0 : 0.0)

        // Corner 2: (p0-p2), (p1-p2), (p3-p2)
        let v20 = p0 - p2
        let v21 = p1 - p2
        let v23 = p3 - p2
        let det2 = simd_dot(v20, simd_cross(v21, v23))
        let d2 = l02 * l12 * l23
        let j2 = (d2 > 1e-18) ? (sqrt(2.0) * det2 / d2) : (det2 < 0 ? -1.0 : 0.0)

        // Corner 3: (p2-p3), (p1-p3), (p0-p3)
        let v32 = p2 - p3
        let v31 = p1 - p3
        let v30 = p0 - p3
        let det3 = simd_dot(v32, simd_cross(v31, v30))
        let d3 = l23 * l13 * l03
        let j3 = (d3 > 1e-18) ? (sqrt(2.0) * det3 / d3) : (det3 < 0 ? -1.0 : 0.0)

        let minJ = min(j0, j1, j2, j3)
        let scaledJacobian = min(1.0, max(-1.0, minJ))

        // 3. Equiangular Skewness: max over 4 faces of max((theta_max - 60)/120, (60 - theta_min)/60)
        let sk0 = calculateFaceSkewness(a: p0, b: p1, c: p2)
        let sk1 = calculateFaceSkewness(a: p0, b: p1, c: p3)
        let sk2 = calculateFaceSkewness(a: p0, b: p2, c: p3)
        let sk3 = calculateFaceSkewness(a: p1, b: p2, c: p3)
        let skewness = max(sk0, sk1, sk2, sk3)

        return (aspectRatio: aspectRatio, scaledJacobian: scaledJacobian, skewness: skewness)
    }

    /// Evaluates equiangular skewness for a single triangular face [0.0, 1.0].
    private static func calculateFaceSkewness(a: SIMD3<Double>, b: SIMD3<Double>, c: SIMD3<Double>) -> Double {
        let sideA = simd_distance(b, c)
        let sideB = simd_distance(a, c)
        let sideC = simd_distance(a, b)

        guard sideA > 1e-12, sideB > 1e-12, sideC > 1e-12 else {
            return 1.0
        }

        let cosA = min(1.0, max(-1.0, (sideB * sideB + sideC * sideC - sideA * sideA) / (2.0 * sideB * sideC)))
        let cosB = min(1.0, max(-1.0, (sideA * sideA + sideC * sideC - sideB * sideB) / (2.0 * sideA * sideC)))
        let cosC = min(1.0, max(-1.0, (sideA * sideA + sideB * sideB - sideC * sideC) / (2.0 * sideA * sideB)))

        let thetaA = acos(cosA) * 180.0 / .pi
        let thetaB = acos(cosB) * 180.0 / .pi
        let thetaC = acos(cosC) * 180.0 / .pi

        let thetaMax = max(thetaA, thetaB, thetaC)
        let thetaMin = min(thetaA, thetaB, thetaC)

        let skew = max((thetaMax - 60.0) / 120.0, (60.0 - thetaMin) / 60.0)
        return min(1.0, max(0.0, skew))
    }

    /// Builds statistical summary and 10-bin histogram for a metric series.
    private static func makeMetricSummary(
        kind: MeshQualityMetricKind,
        entries: [(id: Int, value: Double)],
        threshold: Double? = nil
    ) -> MeshQualityMetricSummary {
        let failureThreshold = threshold ?? kind.standardFailureThreshold

        guard !entries.isEmpty else {
            return MeshQualityMetricSummary(
                kind: kind,
                minValue: 0.0,
                maxValue: 0.0,
                averageValue: 0.0,
                failureThreshold: failureThreshold,
                failingCount: 0,
                failingPercentage: 0.0,
                failingElementIds: [],
                histogramBins: []
            )
        }

        let values = entries.map(\.value)
        let minVal = values.min() ?? 0.0
        let maxVal = values.max() ?? 0.0
        let avgVal = values.reduce(0.0, +) / Double(values.count)

        var failingElementIds: [Int] = []
        for entry in entries {
            if kind.isFailing(value: entry.value, threshold: failureThreshold) {
                failingElementIds.append(entry.id)
            }
        }

        let failingCount = failingElementIds.count
        let failingPercentage = (Double(failingCount) / Double(entries.count)) * 100.0

        var histogramBins: [MeshQualityHistogramBin] = []
        if abs(maxVal - minVal) <= 1e-12 {
            let isFailing = kind.isFailing(value: minVal, threshold: failureThreshold)
            let singleBin = MeshQualityHistogramBin(
                index: 0,
                rangeMin: minVal,
                rangeMax: maxVal,
                count: entries.count,
                isFailing: isFailing
            )
            histogramBins = [singleBin]
        } else {
            let delta = (maxVal - minVal) / 10.0
            var binCounts = Array(repeating: 0, count: 10)
            var binHasFailing = Array(repeating: false, count: 10)

            for entry in entries {
                let rawIdx = Int((entry.value - minVal) / delta)
                let binIdx = min(9, max(0, rawIdx))
                binCounts[binIdx] += 1
                if kind.isFailing(value: entry.value, threshold: failureThreshold) {
                    binHasFailing[binIdx] = true
                }
            }

            for i in 0..<10 {
                let rMin = minVal + Double(i) * delta
                let rMax = (i == 9) ? maxVal : (minVal + Double(i + 1) * delta)
                let mid = (rMin + rMax) / 2.0
                let isFailing = binHasFailing[i] || kind.isFailing(value: mid, threshold: failureThreshold)
                histogramBins.append(MeshQualityHistogramBin(
                    index: i,
                    rangeMin: rMin,
                    rangeMax: rMax,
                    count: binCounts[i],
                    isFailing: isFailing
                ))
            }
        }

        return MeshQualityMetricSummary(
            kind: kind,
            minValue: minVal,
            maxValue: maxVal,
            averageValue: avgVal,
            failureThreshold: failureThreshold,
            failingCount: failingCount,
            failingPercentage: failingPercentage,
            failingElementIds: failingElementIds,
            histogramBins: histogramBins
        )
    }
}
