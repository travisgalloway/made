import Testing
import Foundation
import simd
#if canImport(SwiftUI)
import SwiftUI
#endif
@testable import MadeCore

@Suite struct SimulationContourTests {

    private func makeSingleTetMesh() -> VolumeMesh {
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        let elem = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 1)
        return VolumeMesh(nodes: [n1, n2, n3, n4], elements: [elem])
    }

    private func makeTwoTetMesh() -> VolumeMesh {
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        let n5 = VolumeMeshNode(id: 5, position: SIMD3<Double>(10, 10, 10))
        let elem1 = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 1)
        let elem2 = VolumeMeshElement(id: 2, order: .linear, nodeIndices: [2, 3, 4, 5], tag: 2)
        return VolumeMesh(nodes: [n1, n2, n3, n4, n5], elements: [elem1, elem2])
    }

    // MARK: - Color Map Tests

    @Test func testColorMapEvaluationAcrossPalettes() {
        for kind in SimulationColorMapKind.allCases {
            let c0 = SimulationColorMap.evaluate(t: 0.0, map: kind)
            let cHalf = SimulationColorMap.evaluate(t: 0.5, map: kind)
            let c1 = SimulationColorMap.evaluate(t: 1.0, map: kind)

            #expect(c0.w == 1.0)
            #expect(cHalf.w == 1.0)
            #expect(c1.w == 1.0)

            #expect(c0.x >= 0.0 && c0.x <= 1.0)
            #expect(c0.y >= 0.0 && c0.y <= 1.0)
            #expect(c0.z >= 0.0 && c0.z <= 1.0)

            #expect(c1.x >= 0.0 && c1.x <= 1.0)
            #expect(c1.y >= 0.0 && c1.y <= 1.0)
            #expect(c1.z >= 0.0 && c1.z <= 1.0)
        }
    }

    @Test func testRainbowJetColorStops() {
        let blue = SimulationColorMap.evaluate(t: 0.0, map: .rainbow)
        #expect(blue.x == 0.0)
        #expect(blue.y == 0.0)
        #expect(blue.z == 1.0)

        let green = SimulationColorMap.evaluate(t: 0.5, map: .rainbow)
        #expect(green.x == 0.0)
        #expect(green.y == 1.0)
        #expect(green.z == 0.0)

        let red = SimulationColorMap.evaluate(t: 1.0, map: .rainbow)
        #expect(red.x == 1.0)
        #expect(red.y == 0.0)
        #expect(red.z == 0.0)
    }

    @Test func testGrayscaleRamp() {
        let low = SimulationColorMap.evaluate(t: 0.0, map: .grayscale)
        #expect(abs(low.x - 0.1) < 1e-4)
        #expect(abs(low.y - 0.1) < 1e-4)
        #expect(abs(low.z - 0.1) < 1e-4)

        let high = SimulationColorMap.evaluate(t: 1.0, map: .grayscale)
        #expect(abs(high.x - 0.95) < 1e-4)
        #expect(abs(high.y - 0.95) < 1e-4)
        #expect(abs(high.z - 0.95) < 1e-4)
    }

    @Test func testColorMapClampingAndNaN() {
        let under = SimulationColorMap.evaluate(t: -10.0, map: .turbo)
        let exact0 = SimulationColorMap.evaluate(t: 0.0, map: .turbo)
        #expect(under == exact0)

        let over = SimulationColorMap.evaluate(t: 15.0, map: .turbo)
        let exact1 = SimulationColorMap.evaluate(t: 1.0, map: .turbo)
        #expect(over == exact1)

        let nanColor = SimulationColorMap.evaluate(t: Double.nan, map: .turbo)
        let halfColor = SimulationColorMap.evaluate(t: 0.5, map: .turbo)
        #expect(nanColor == halfColor)
    }

    #if canImport(SwiftUI)
    @Test func testGradientColorsCount() {
        let stops = SimulationColorMap.gradientColors(map: .turbo, sampleCount: 16)
        #expect(stops.count == 16)
    }
    #endif

    // MARK: - Contour Settings Tests

    @Test func testContourSettingsEffectiveRange() {
        let auto = SimulationContourSettings(autoRange: true)
        let range1 = auto.effectiveRange(for: 10.0, actualMax: 200.0)
        #expect(range1.min == 10.0)
        #expect(range1.max == 200.0)

        let custom = SimulationContourSettings(
            autoRange: false,
            customMin: 50.0,
            customMax: 150.0
        )
        let range2 = custom.effectiveRange(for: 0.0, actualMax: 300.0)
        #expect(range2.min == 50.0)
        #expect(range2.max == 150.0)

        // User sets customMin > customMax: automatically normalize bounds
        let inverted = SimulationContourSettings(
            autoRange: false,
            customMin: 200.0,
            customMax: 50.0
        )
        let range3 = inverted.effectiveRange(for: 0.0, actualMax: 300.0)
        #expect(range3.min == 50.0)
        #expect(range3.max == 200.0)
    }

    // MARK: - Contour Generator Tests

    @Test func testEmptyMeshYieldsEmptyPayload() {
        let emptyMesh = VolumeMesh()
        let study = SimulationStudy()
        let (payload, extrema) = SimulationContourGenerator.generatePayload(
            mesh: emptyMesh,
            study: study,
            results: study.results,
            fields: nil,
            settings: study.contourSettings,
            displaySettings: study.meshDisplay
        )

        #expect(payload.isEmpty)
        #expect(payload.colors?.isEmpty ?? true)
        #expect(extrema.actualMin == 0.0)
        #expect(extrema.actualMax == 0.0)
    }

    @Test func testNodalVonMisesContourGeneration() {
        let mesh = makeSingleTetMesh()
        var study = SimulationStudy()
        let fields = SimulationResultFields(
            studyId: study.id,
            nodalVonMisesStresses: [
                1: 10.0,
                2: 50.0,
                3: 100.0,
                4: 200.0
            ]
        )
        study.contourSettings.isVisible = true
        study.contourSettings.field = .vonMisesStress
        study.contourSettings.colorMap = .rainbow

        let (payload, extrema) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: study.contourSettings,
            displaySettings: study.meshDisplay
        )

        #expect(!payload.isEmpty)
        #expect(payload.triangleCount == 4) // 4 faces of a single tet
        guard let colors = payload.colors else {
            #expect(Bool(false), "payload.colors should not be nil")
            return
        }

        // 4 faces * 3 vertices = 12 vertices, 4 floats per vertex = 48 floats
        #expect(colors.count == 12 * 4)

        #expect(extrema.actualMin == 10.0)
        #expect(extrema.actualMax == 200.0)
        #expect(extrema.minNodeId == 1)
        #expect(extrema.maxNodeId == 4)
        #expect(extrema.minPosition == SIMD3<Double>(0, 0, 0))
        #expect(extrema.maxPosition == SIMD3<Double>(0, 0, 10))
    }

    @Test func testZeroRangeFieldMidpointMapping() {
        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()
        let fields = SimulationResultFields(
            studyId: study.id,
            nodalTemperatures: [
                1: 25.0,
                2: 25.0,
                3: 25.0,
                4: 25.0
            ]
        )
        var settings = SimulationContourSettings()
        settings.field = .temperature
        settings.colorMap = .rainbow

        let (payload, extrema) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: settings,
            displaySettings: study.meshDisplay
        )

        #expect(extrema.actualMin == 25.0)
        #expect(extrema.actualMax == 25.0)
        #expect(extrema.effectiveMin == 25.0)
        #expect(extrema.effectiveMax == 25.0)

        guard let colors = payload.colors else {
            #expect(Bool(false), "payload.colors should not be nil")
            return
        }

        // When min == max, all vertices map to t = 0.5 (green in rainbow)
        let expectedGreen = SimulationColorMap.evaluate(t: 0.5, map: .rainbow)
        for i in stride(from: 0, to: colors.count, by: 4) {
            #expect(abs(colors[i] - expectedGreen.x) < 1e-4)
            #expect(abs(colors[i + 1] - expectedGreen.y) < 1e-4)
            #expect(abs(colors[i + 2] - expectedGreen.z) < 1e-4)
        }
    }

    @Test func testDeformedMeshDisplacementScaling() {
        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()
        let fields = SimulationResultFields(
            studyId: study.id,
            nodalDisplacements: [
                1: SIMD3<Double>(0, 0, 0),
                2: SIMD3<Double>(1, 0, 0),
                3: SIMD3<Double>(0, 2, 0),
                4: SIMD3<Double>(0, 0, 3)
            ]
        )
        var settings = SimulationContourSettings()
        settings.field = .displacementMagnitude
        settings.isDeformed = true
        settings.deformationScale = 2.0

        let (payload, extrema) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: settings,
            displaySettings: study.meshDisplay
        )

        #expect(extrema.actualMin == 0.0)
        #expect(abs(extrema.actualMax - 3.0) < 1e-5)
        #expect(extrema.minNodeId == 1)
        #expect(extrema.maxNodeId == 4)

        // Node 4 original pos (0, 0, 10) + scale 2.0 * disp (0, 0, 3) = (0, 0, 16)
        #expect(extrema.maxPosition == SIMD3<Double>(0, 0, 16))

        // First vertex of node 1 at origin
        #expect(!payload.isEmpty)
    }

    @Test func testCustomRangeClamping() {
        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()
        let fields = SimulationResultFields(
            studyId: study.id,
            nodalVonMisesStresses: [
                1: 0.0,
                2: 50.0,
                3: 150.0,
                4: 300.0
            ]
        )
        var settings = SimulationContourSettings()
        settings.field = .vonMisesStress
        settings.autoRange = false
        settings.customMin = 50.0
        settings.customMax = 150.0
        settings.colorMap = .rainbow

        let (_, extrema) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: settings,
            displaySettings: study.meshDisplay
        )

        #expect(extrema.actualMin == 0.0)
        #expect(extrema.actualMax == 300.0)
        #expect(extrema.effectiveMin == 50.0)
        #expect(extrema.effectiveMax == 150.0)
    }

    @Test func testElementVonMisesStressContour() {
        let mesh = makeTwoTetMesh()
        let study = SimulationStudy()
        let fields = SimulationResultFields(
            studyId: study.id,
            elementVonMisesStresses: [
                1: 80.0,
                2: 160.0
            ]
        )
        var settings = SimulationContourSettings()
        settings.field = .elementVonMisesStress
        settings.colorMap = .rainbow

        let (payload, extrema) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: settings,
            displaySettings: study.meshDisplay
        )

        #expect(extrema.actualMin == 80.0)
        #expect(extrema.actualMax == 160.0)
        #expect(extrema.minNodeId == 1) // element 1
        #expect(extrema.maxNodeId == 2) // element 2
        #expect(payload.triangleCount == 8) // 2 tets * 4 faces
    }

    @Test func testMeshWireframeEdgesToggle() {
        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()

        var withEdges = SimulationContourSettings()
        withEdges.showMeshEdges = true
        let (payloadWith, _) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: nil,
            settings: withEdges,
            displaySettings: study.meshDisplay
        )
        #expect(!payloadWith.edgePolylines.isEmpty)

        var withoutEdges = SimulationContourSettings()
        withoutEdges.showMeshEdges = false
        let (payloadWithout, _) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: nil,
            settings: withoutEdges,
            displaySettings: study.meshDisplay
        )
        #expect(payloadWithout.edgePolylines.isEmpty)
    }

    @Test func testPrincipalStressesAndFactorOfSafetyFields() {
        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()
        let tensors: [Int: CauchyStressTensor] = [
            1: CauchyStressTensor(sxx: 100.0, syy: 0.0, szz: 0.0, sxy: 0.0, syz: 0.0, szx: 0.0),
            2: CauchyStressTensor(sxx: 200.0, syy: 50.0, szz: 0.0, sxy: 0.0, syz: 0.0, szx: 0.0),
            3: CauchyStressTensor(sxx: 50.0, syy: 50.0, szz: 50.0, sxy: 0.0, syz: 0.0, szx: 0.0),
            4: CauchyStressTensor(sxx: 0.0, syy: 0.0, szz: 0.0, sxy: 0.0, syz: 0.0, szx: 0.0)
        ]
        let fields = SimulationResultFields(studyId: study.id, nodalCauchyTensors: tensors)

        // Major principal stress
        var s1Settings = SimulationContourSettings()
        s1Settings.field = .majorPrincipalStress
        let (_, s1Extrema) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: s1Settings,
            displaySettings: study.meshDisplay
        )
        #expect(s1Extrema.actualMax >= 200.0)

        // Factor of safety
        var fosSettings = SimulationContourSettings()
        fosSettings.field = .factorOfSafety
        let (_, fosExtrema) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: fosSettings,
            displaySettings: study.meshDisplay
        )
        #expect(fosExtrema.actualMin > 0.0)
    }

    // MARK: - Animation & Deformed Shape Tests (BL-RES-03, #324)

    @Test func testAnimationModeWaveforms() {
        // Harmonic: sin(2 * pi * phase)
        #expect(abs(SimulationAnimationMode.factor(for: .harmonic, phase: 0.0)) < 1e-6)
        #expect(abs(SimulationAnimationMode.factor(for: .harmonic, phase: 0.25) - 1.0) < 1e-6)
        #expect(abs(SimulationAnimationMode.factor(for: .harmonic, phase: 0.5)) < 1e-6)
        #expect(abs(SimulationAnimationMode.factor(for: .harmonic, phase: 0.75) - (-1.0)) < 1e-6)
        #expect(abs(SimulationAnimationMode.factor(for: .harmonic, phase: 1.0)) < 1e-6)

        // Half Cycle: sin(pi * phase)
        #expect(abs(SimulationAnimationMode.factor(for: .halfCycle, phase: 0.0)) < 1e-6)
        #expect(abs(SimulationAnimationMode.factor(for: .halfCycle, phase: 0.5) - 1.0) < 1e-6)
        #expect(abs(SimulationAnimationMode.factor(for: .halfCycle, phase: 1.0)) < 1e-6)

        // Linear Ramp: phase
        #expect(SimulationAnimationMode.factor(for: .linearRamp, phase: 0.0) == 0.0)
        #expect(SimulationAnimationMode.factor(for: .linearRamp, phase: 0.5) == 0.5)
        #expect(SimulationAnimationMode.factor(for: .linearRamp, phase: 1.0) == 1.0)

        // Ping-Pong: triangular 0 -> 1 -> 0
        #expect(SimulationAnimationMode.factor(for: .pingPong, phase: 0.0) == 0.0)
        #expect(abs(SimulationAnimationMode.factor(for: .pingPong, phase: 0.25) - 0.5) < 1e-6)
        #expect(SimulationAnimationMode.factor(for: .pingPong, phase: 0.5) == 1.0)
        #expect(abs(SimulationAnimationMode.factor(for: .pingPong, phase: 0.75) - 0.5) < 1e-6)
        #expect(SimulationAnimationMode.factor(for: .pingPong, phase: 1.0) == 0.0)

        // Phase clamping
        #expect(SimulationAnimationMode.factor(for: .linearRamp, phase: -0.5) == 0.0)
        #expect(SimulationAnimationMode.factor(for: .linearRamp, phase: 1.5) == 1.0)
    }

    @Test func testDeformationMultiplierScaling() {
        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()
        let fields = SimulationResultFields(
            studyId: study.id,
            nodalDisplacements: [
                1: SIMD3<Double>(0, 0, 0),
                2: SIMD3<Double>(1, 0, 0),
                3: SIMD3<Double>(0, 2, 0),
                4: SIMD3<Double>(0, 0, 10)
            ]
        )
        var settings = SimulationContourSettings()
        settings.field = .displacementMagnitude
        settings.isDeformed = true
        settings.deformationScale = 2.0

        // Multiplier = 0.5: node 4 pos (0, 0, 10) + 2.0 * 0.5 * (0, 0, 10) = (0, 0, 20)
        let (_, extHalf) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: settings,
            displaySettings: study.meshDisplay,
            deformationMultiplier: 0.5
        )
        #expect(extHalf.maxPosition == SIMD3<Double>(0, 0, 20))

        // Multiplier = 0.0: node 4 pos (0, 0, 10) + 0 = (0, 0, 10)
        let (_, extZero) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: settings,
            displaySettings: study.meshDisplay,
            deformationMultiplier: 0.0
        )
        #expect(extZero.maxPosition == SIMD3<Double>(0, 0, 10))

        // Multiplier = -1.0: node 4 pos (0, 0, 10) + 2.0 * (-1.0) * (0, 0, 10) = (0, 0, -10)
        let (_, extNeg) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: fields,
            settings: settings,
            displaySettings: study.meshDisplay,
            deformationMultiplier: -1.0
        )
        #expect(extNeg.maxPosition == SIMD3<Double>(0, 0, -10))
    }

    @Test func testDisplacementsOverride() {
        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()
        let originalFields = SimulationResultFields(
            studyId: study.id,
            nodalDisplacements: [
                1: .zero,
                2: SIMD3<Double>(1, 0, 0),
                3: SIMD3<Double>(0, 1, 0),
                4: SIMD3<Double>(0, 0, 1)
            ]
        )
        let overrideDisplacements: [Int: SIMD3<Double>] = [
            1: .zero,
            2: SIMD3<Double>(1, 0, 0),
            3: SIMD3<Double>(0, 2, 0),
            4: SIMD3<Double>(0, 0, 5)
        ]
        var settings = SimulationContourSettings()
        settings.field = .displacementMagnitude
        settings.isDeformed = true
        settings.deformationScale = 1.0

        let (_, ext) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: originalFields,
            settings: settings,
            displaySettings: study.meshDisplay,
            deformationMultiplier: 1.0,
            displacementsOverride: overrideDisplacements
        )
        // Node 4: pos (0, 0, 10) + 1.0 * (0, 0, 5) = (0, 0, 15)
        #expect(ext.maxPosition == SIMD3<Double>(0, 0, 15))
    }

    @Test func testUndeformedWireframePayloadGeneration() {
        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()

        let wireframe = SimulationContourGenerator.generateUndeformedWireframePayload(
            mesh: mesh,
            displaySettings: study.meshDisplay
        )
        #expect(wireframe.positions.isEmpty)
        #expect(wireframe.normals.isEmpty)
        #expect(wireframe.indices.isEmpty)
        #expect(wireframe.colors?.isEmpty ?? true)
        #expect(wireframe.edgePolylines.count == 6) // Single tet has 6 edges

        let emptyMesh = VolumeMesh()
        let emptyWireframe = SimulationContourGenerator.generateUndeformedWireframePayload(
            mesh: emptyMesh,
            displaySettings: study.meshDisplay
        )
        #expect(emptyWireframe.edgePolylines.isEmpty)
    }

    @Test func testZeroDisplacementKeepsGeometryStationary() {
        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()
        let zeroDisplacements: [Int: SIMD3<Double>] = [
            1: .zero,
            2: .zero,
            3: .zero,
            4: .zero
        ]
        var settings = SimulationContourSettings()
        settings.field = .displacementMagnitude
        settings.isDeformed = true
        settings.deformationScale = 50.0

        let (payload, ext) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: nil,
            settings: settings,
            displaySettings: study.meshDisplay,
            displacementsOverride: zeroDisplacements
        )

        var undeformedSettings = settings
        undeformedSettings.isDeformed = false
        let (undeformedPayload, _) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: nil,
            settings: undeformedSettings,
            displaySettings: study.meshDisplay
        )

        #expect(!payload.isEmpty)
        #expect(payload.positions == undeformedPayload.positions)
        #expect(payload.positions.allSatisfy { !$0.isNaN })
        #expect(ext.actualMin == 0.0)
        #expect(ext.actualMax == 0.0)
    }

    @Test func testNonPositiveDeformationScaleClamping() {
        let settings = SimulationContourSettings(field: .displacementMagnitude, isDeformed: true, deformationScale: -5.0)
        #expect(settings.deformationScale == 0.0)

        let mesh = makeSingleTetMesh()
        let study = SimulationStudy()
        let disp: [Int: SIMD3<Double>] = [
            1: .zero,
            2: SIMD3<Double>(1, 0, 0),
            3: SIMD3<Double>(0, 2, 0),
            4: SIMD3<Double>(0, 0, 10)
        ]
        let (_, ext) = SimulationContourGenerator.generatePayload(
            mesh: mesh,
            study: study,
            results: study.results,
            fields: nil,
            settings: settings,
            displaySettings: study.meshDisplay,
            displacementsOverride: disp
        )
        // With scale clamped to 0.0, node 4 remains at undeformed (0, 0, 10)
        #expect(ext.maxPosition == SIMD3<Double>(0, 0, 10))
    }
}
