import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct MeshQualityCalculatorTests {

    private let equilateralP0 = SIMD3<Double>(-1.0, 0.0, -1.0 / sqrt(2.0))
    private let equilateralP1 = SIMD3<Double>(1.0, 0.0, -1.0 / sqrt(2.0))
    private let equilateralP2 = SIMD3<Double>(0.0, 1.0, 1.0 / sqrt(2.0))
    private let equilateralP3 = SIMD3<Double>(0.0, -1.0, 1.0 / sqrt(2.0))

    @Test func testEquilateralTetrahedronMetrics() {
        let metrics = MeshQualityCalculator.calculateTetrahedronMetrics(
            p0: equilateralP0,
            p1: equilateralP1,
            p2: equilateralP2,
            p3: equilateralP3
        )

        // Equilateral tetrahedron: Aspect Ratio = 1.0, Scaled Jacobian = 1.0, Skewness = 0.0
        #expect(abs(metrics.aspectRatio - 1.0) < 1e-4)
        #expect(abs(metrics.scaledJacobian - 1.0) < 1e-4)
        #expect(abs(metrics.skewness - 0.0) < 1e-4)

        #expect(!MeshQualityMetricKind.aspectRatio.isFailing(value: metrics.aspectRatio))
        #expect(!MeshQualityMetricKind.scaledJacobian.isFailing(value: metrics.scaledJacobian))
        #expect(!MeshQualityMetricKind.skewness.isFailing(value: metrics.skewness))
    }

    @Test func testDistortedSliverTetrahedronFailsAspectRatio() {
        // Highly elongated element along X
        let p0 = SIMD3<Double>(0.0, 0.0, 0.0)
        let p1 = SIMD3<Double>(20.0, 0.0, 0.0)
        let p2 = SIMD3<Double>(0.0, 0.5, 0.0)
        let p3 = SIMD3<Double>(0.0, 0.0, 0.5)

        let metrics = MeshQualityCalculator.calculateTetrahedronMetrics(
            p0: p0,
            p1: p1,
            p2: p2,
            p3: p3
        )

        #expect(metrics.aspectRatio > 3.0)
        #expect(MeshQualityMetricKind.aspectRatio.isFailing(value: metrics.aspectRatio))
    }

    @Test func testInvertedTetrahedronProducesNegativeScaledJacobian() {
        // Swapping two vertices reverses orientation and inverts the Jacobian
        let invMetrics = MeshQualityCalculator.calculateTetrahedronMetrics(
            p0: equilateralP0,
            p1: equilateralP2,
            p2: equilateralP1,
            p3: equilateralP3
        )

        #expect(invMetrics.scaledJacobian < 0.0)
        #expect(MeshQualityMetricKind.scaledJacobian.isFailing(value: invMetrics.scaledJacobian))
    }

    @Test func testDegenerateCoplanarTetrahedron() {
        // All nodes coplanar on Z = 0
        let p0 = SIMD3<Double>(0.0, 0.0, 0.0)
        let p1 = SIMD3<Double>(1.0, 0.0, 0.0)
        let p2 = SIMD3<Double>(0.0, 1.0, 0.0)
        let p3 = SIMD3<Double>(1.0, 1.0, 0.0)

        let metrics = MeshQualityCalculator.calculateTetrahedronMetrics(
            p0: p0,
            p1: p1,
            p2: p2,
            p3: p3
        )

        #expect(metrics.scaledJacobian <= 0.0)
        #expect(MeshQualityMetricKind.scaledJacobian.isFailing(value: metrics.scaledJacobian))
    }

    @Test func testEmptyMeshQualityEvaluation() {
        let report = MeshQualityCalculator.evaluate(nodes: [], elements: [])

        #expect(report.aspectRatioSummary.minValue == 0.0)
        #expect(report.aspectRatioSummary.maxValue == 0.0)
        #expect(report.aspectRatioSummary.failingCount == 0)
        #expect(report.aspectRatioSummary.failingPercentage == 0.0)
        #expect(report.aspectRatioSummary.histogramBins.isEmpty)

        #expect(report.scaledJacobianSummary.failingCount == 0)
        #expect(report.skewnessSummary.failingCount == 0)
    }

    @Test func testSingleElementMeshCreatesSingleActiveHistogramBin() {
        let nodes = [
            VolumeMeshNode(id: 1, position: equilateralP0),
            VolumeMeshNode(id: 2, position: equilateralP1),
            VolumeMeshNode(id: 3, position: equilateralP2),
            VolumeMeshNode(id: 4, position: equilateralP3)
        ]
        let elements = [
            VolumeMeshElement(id: 42, order: .linear, nodeIndices: [1, 2, 3, 4])
        ]

        let report = MeshQualityCalculator.evaluate(nodes: nodes, elements: elements)
        let arSummary = report.aspectRatioSummary

        #expect(arSummary.failingCount == 0)
        #expect(arSummary.failingPercentage == 0.0)
        #expect(arSummary.failingElementIds.isEmpty)
        #expect(arSummary.histogramBins.count == 1)
        #expect(arSummary.histogramBins[0].count == 1)
        #expect(!arSummary.histogramBins[0].isFailing)

        let sjSummary = report.summary(for: .scaledJacobian)
        #expect(sjSummary.histogramBins.count == 1)
        #expect(sjSummary.histogramBins[0].count == 1)
        #expect(!sjSummary.histogramBins[0].isFailing)
    }

    @Test func testQuadraticC3D10ElementEvaluation() {
        var nodes = [
            VolumeMeshNode(id: 1, position: equilateralP0),
            VolumeMeshNode(id: 2, position: equilateralP1),
            VolumeMeshNode(id: 3, position: equilateralP2),
            VolumeMeshNode(id: 4, position: equilateralP3)
        ]
        // Add 6 mid-side nodes
        for i in 5...10 {
            nodes.append(VolumeMeshNode(id: i, position: SIMD3<Double>(0.1 * Double(i), 0, 0)))
        }

        let elements = [
            VolumeMeshElement(id: 101, order: .quadratic, nodeIndices: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        ]

        let report = MeshQualityCalculator.evaluate(nodes: nodes, elements: elements)
        #expect(abs(report.aspectRatioSummary.minValue - 1.0) < 1e-4)
        #expect(abs(report.scaledJacobianSummary.minValue - 1.0) < 1e-4)
        #expect(abs(report.skewnessSummary.minValue - 0.0) < 1e-4)
    }

    @Test func testMultiElementMeshWith10BinHistogramAndFailingIdentification() {
        let nodes = [
            // Element 1: Equilateral (Passing)
            VolumeMeshNode(id: 1, position: equilateralP0),
            VolumeMeshNode(id: 2, position: equilateralP1),
            VolumeMeshNode(id: 3, position: equilateralP2),
            VolumeMeshNode(id: 4, position: equilateralP3),
            // Element 2: Sliver (Failing Aspect Ratio and Scaled Jacobian)
            VolumeMeshNode(id: 5, position: SIMD3<Double>(10.0, 0.0, 0.0)),
            VolumeMeshNode(id: 6, position: SIMD3<Double>(10.0, 10.0, 0.0)),
            VolumeMeshNode(id: 7, position: SIMD3<Double>(10.0, 0.0, 0.1)),
            VolumeMeshNode(id: 8, position: SIMD3<Double>(10.0, 0.05, 0.05))
        ]

        let elements = [
            VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4]),
            VolumeMeshElement(id: 2, order: .linear, nodeIndices: [5, 6, 7, 8])
        ]

        let mesh = VolumeMesh(nodes: nodes, elements: elements)
        let report = MeshQualityCalculator.evaluate(mesh: mesh)

        let arSummary = report.aspectRatioSummary
        #expect(arSummary.failingElementIds.contains(2))
        #expect(!arSummary.failingElementIds.contains(1))
        #expect(arSummary.failingCount == 1)
        #expect(arSummary.failingPercentage == 50.0)
        #expect(arSummary.histogramBins.count == 10)

        let totalBinCount = arSummary.histogramBins.map(\.count).reduce(0, +)
        #expect(totalBinCount == 2)
    }

    @Test func testStandardFailureThresholds() {
        #expect(MeshQualityMetricKind.aspectRatio.standardFailureThreshold == 3.0)
        #expect(MeshQualityMetricKind.scaledJacobian.standardFailureThreshold == 0.2)
        #expect(MeshQualityMetricKind.skewness.standardFailureThreshold == 0.7)

        #expect(MeshQualityMetricKind.aspectRatio.isFailing(value: 3.01))
        #expect(!MeshQualityMetricKind.aspectRatio.isFailing(value: 3.0))
        #expect(!MeshQualityMetricKind.aspectRatio.isFailing(value: 2.99))

        #expect(MeshQualityMetricKind.scaledJacobian.isFailing(value: 0.19))
        #expect(!MeshQualityMetricKind.scaledJacobian.isFailing(value: 0.2))
        #expect(!MeshQualityMetricKind.scaledJacobian.isFailing(value: 0.21))

        #expect(MeshQualityMetricKind.skewness.isFailing(value: 0.71))
        #expect(!MeshQualityMetricKind.skewness.isFailing(value: 0.7))
        #expect(!MeshQualityMetricKind.skewness.isFailing(value: 0.69))
    }
}
