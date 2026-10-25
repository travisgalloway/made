import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SimulationProbeTests {

    private func makeSampleMesh() -> VolumeMesh {
        // Simple tetrahedral mesh:
        // Node 1: (0, 0, 0)
        // Node 2: (10, 0, 0)
        // Node 3: (0, 10, 0)
        // Node 4: (0, 0, 10)
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))

        let elem = VolumeMeshElement(id: 101, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 1)
        // Surface triangles: (1, 2, 3), (1, 3, 4), (1, 4, 2), (2, 4, 3)
        let st1 = VolumeMeshElement(id: 201, order: .linear, nodeIndices: [1, 2, 3])
        let st2 = VolumeMeshElement(id: 202, order: .linear, nodeIndices: [1, 3, 4])
        let st3 = VolumeMeshElement(id: 203, order: .linear, nodeIndices: [1, 4, 2])
        let st4 = VolumeMeshElement(id: 204, order: .linear, nodeIndices: [2, 4, 3])

        return VolumeMesh(
            nodes: [n1, n2, n3, n4],
            elements: [elem],
            surfaceTriangles: [st1, st2, st3, st4],
            statistics: SimulationMeshStatistics(nodeCount: 4, elementCount: 1),
            sets: []
        )
    }

    private func makeSampleStudy(isDeformed: Bool = false, deformationScale: Double = 1.0) -> (SimulationStudy, SimulationStudyResults) {
        var study = SimulationStudy(name: "Sample Study")
        study.contourSettings.field = .vonMisesStress
        study.contourSettings.isDeformed = isDeformed
        study.contourSettings.deformationScale = deformationScale

        var results = SimulationStudyResults(status: .completed)
        results.nodalVonMisesStresses = [
            1: 100.0,
            2: 200.0,
            3: 300.0,
            4: 400.0
        ]
        results.nodalDisplacements = [
            1: SIMD3<Double>(0, 0, 0),
            2: SIMD3<Double>(1.0, 0, 0),
            3: SIMD3<Double>(0, 1.0, 0),
            4: SIMD3<Double>(0, 0, 1.0)
        ]
        results.elementVonMisesStresses = [
            101: 250.0
        ]

        return (study, results)
    }

    @Test func testSimulationProbePointInitialization() {
        let id = UUID()
        let pt = SimulationProbePoint(
            id: id,
            name: "Test Point",
            kind: .point,
            position: SIMD3<Double>(1, 2, 3),
            distanceAlongPath: 5.5,
            nodeId: 42,
            elementId: 108,
            fieldValues: [.vonMisesStress: 150.0],
            isSelected: true
        )

        #expect(pt.id == id)
        #expect(pt.name == "Test Point")
        #expect(pt.kind == .point)
        #expect(pt.position == SIMD3<Double>(1, 2, 3))
        #expect(pt.distanceAlongPath == 5.5)
        #expect(pt.nodeId == 42)
        #expect(pt.elementId == 108)
        #expect(pt.fieldValues[.vonMisesStress] == 150.0)
        #expect(pt.isSelected == true)
    }

    @Test func testSimulationProbeTableCSVExportSingleField() {
        let p1 = SimulationProbePoint(
            name: "P1",
            kind: .point,
            position: SIMD3<Double>(0, 0, 0),
            nodeId: 1,
            elementId: 10,
            fieldValues: [.vonMisesStress: 123.4567]
        )
        let p2 = SimulationProbePoint(
            name: "P2",
            kind: .pathSample,
            position: SIMD3<Double>(5, 0, 0),
            distanceAlongPath: 5.0,
            nodeId: 2,
            elementId: 10,
            fieldValues: [.vonMisesStress: 234.5678]
        )

        let table = SimulationProbeTable(probes: [p1, p2])
        let csv = table.toCSV(field: .vonMisesStress)

        #expect(csv.hasSuffix("\r\n"))
        #expect(csv.contains("Index,Name,Kind,X [mm],Y [mm],Z [mm],Distance [mm],Node ID,Element ID,Value [MPa]\r\n"))
        #expect(csv.contains("1,P1,Point,0.0000,0.0000,0.0000,,1,10,123.4567\r\n"))
        #expect(csv.contains("2,P2,Path Sample,5.0000,0.0000,0.0000,5.0000,2,10,234.5678\r\n"))
    }

    @Test func testSimulationProbeTableCSVExportAllFields() {
        let p = SimulationProbePoint(
            name: "Root",
            kind: .point,
            position: SIMD3<Double>(1, 2, 3),
            nodeId: 5,
            fieldValues: [
                .vonMisesStress: 50.0,
                .temperature: 25.0
            ]
        )
        let table = SimulationProbeTable(probes: [p])
        let csv = table.toCSV(field: nil)

        #expect(csv.contains("Index,Name,Kind,X [mm],Y [mm],Z [mm],Distance [mm],Node ID,Element ID"))
        #expect(csv.contains("von Mises Stress [MPa]"))
        #expect(csv.contains("Temperature [°C]"))
        #expect(csv.contains("Factor of Safety"))
        #expect(csv.contains("1,Root,Point,1.0000,2.0000,3.0000,,5,"))
    }

    @Test func testSimulationProbeTableCSVExportEscaping() {
        let trickyName = "Probe, with \"Quotes\" and \n Newline"
        let p = SimulationProbePoint(
            name: trickyName,
            kind: .point,
            position: SIMD3<Double>(0, 0, 0),
            nodeId: 1,
            fieldValues: [.vonMisesStress: 10.0]
        )
        let table = SimulationProbeTable(probes: [p])
        let csv = table.toCSV(field: .vonMisesStress)

        // RFC 4180 expects quotes to be escaped with double quotes and entire field enclosed in quotes
        #expect(csv.contains("\"Probe, with \"\"Quotes\"\" and \n Newline\""))
    }

    @Test func testSimulationProbeEvaluatorNodalPointProbe() {
        let mesh = makeSampleMesh()
        let (study, results) = makeSampleStudy()

        // Probe close to node 2 (10, 0, 0)
        let probe = SimulationProbeEvaluator.evaluateProbe(
            at: SIMD3<Double>(9.9, 0.1, 0),
            mesh: mesh,
            study: study,
            results: results,
            fields: nil,
            name: "Near Node 2"
        )

        #expect(probe.name == "Near Node 2")
        #expect(probe.kind == .point)
        #expect(probe.nodeId == 2)
        #expect(probe.elementId == 101)
        #expect(probe.fieldValues[.vonMisesStress] == 200.0)
    }

    @Test func testSimulationProbeEvaluatorElementPointProbe() {
        let mesh = makeSampleMesh()
        let (study, results) = makeSampleStudy()

        // Centroid of nodes (0,0,0), (10,0,0), (0,10,0), (0,0,10) is (2.5, 2.5, 2.5)
        let probe = SimulationProbeEvaluator.evaluateProbe(
            at: SIMD3<Double>(2.5, 2.5, 2.5),
            mesh: mesh,
            study: study,
            results: results,
            fields: nil
        )

        #expect(probe.elementId == 101)
        #expect(probe.fieldValues[.elementVonMisesStress] == 250.0)
    }

    @Test func testSimulationProbeEvaluatorDeformedMeshSampling() {
        let mesh = makeSampleMesh()
        // Node 2 original: (10, 0, 0). With disp (1, 0, 0) and scale 5.0 -> deformed position is (15, 0, 0)
        let (study, results) = makeSampleStudy(isDeformed: true, deformationScale: 5.0)

        // Probe at (14.9, 0, 0): should snap to deformed node 2
        let probe = SimulationProbeEvaluator.evaluateProbe(
            at: SIMD3<Double>(14.9, 0, 0),
            mesh: mesh,
            study: study,
            results: results,
            fields: nil
        )

        #expect(probe.nodeId == 2)
    }

    @Test func testSimulationProbeEvaluatorLinearPathSampling() {
        let mesh = makeSampleMesh()
        let (study, results) = makeSampleStudy()

        let start = SIMD3<Double>(0, 0, 0)
        let end = SIMD3<Double>(10, 0, 0)
        let samples = SimulationProbeEvaluator.evaluatePath(
            start: start,
            end: end,
            sampleCount: 5,
            pathName: "Centerline",
            mesh: mesh,
            study: study,
            results: results,
            fields: nil
        )

        #expect(samples.count == 5)
        #expect(samples[0].name == "Centerline [1]")
        #expect(samples[0].distanceAlongPath == 0.0)
        #expect(samples[0].nodeId == 1)

        #expect(samples[4].name == "Centerline [5]")
        #expect(samples[4].distanceAlongPath == 10.0)
        #expect(samples[4].nodeId == 2)

        for s in samples {
            #expect(s.kind == .pathSample)
        }
    }

    @Test func testSimulationProbeEvaluatorZeroLengthPathEdgeCase() {
        let mesh = makeSampleMesh()
        let (study, results) = makeSampleStudy()

        let pt = SIMD3<Double>(3, 4, 5)
        let samples = SimulationProbeEvaluator.evaluatePath(
            start: pt,
            end: pt,
            sampleCount: 4,
            pathName: "ZeroPath",
            mesh: mesh,
            study: study,
            results: results,
            fields: nil
        )

        #expect(samples.count == 4)
        for s in samples {
            #expect(s.position == pt)
            #expect(s.distanceAlongPath == 0.0)
        }
    }

    @Test func testSimulationProbeEvaluatorSampleCountClamping() {
        let mesh = makeSampleMesh()
        let (study, results) = makeSampleStudy()

        let samples = SimulationProbeEvaluator.evaluatePath(
            start: .zero,
            end: SIMD3<Double>(10, 0, 0),
            sampleCount: 1, // should be clamped to >= 2
            mesh: mesh,
            study: study,
            results: results,
            fields: nil
        )

        #expect(samples.count == 2)
    }

    @Test func testSimulationProbeEvaluatorEmptyMeshAndUncomputedResults() {
        let emptyMesh = VolumeMesh()
        let study = SimulationStudy(name: "Empty")
        let results = SimulationStudyResults(status: .notRun)

        let probe = SimulationProbeEvaluator.evaluateProbe(
            at: SIMD3<Double>(1, 2, 3),
            mesh: emptyMesh,
            study: study,
            results: results,
            fields: nil
        )

        #expect(probe.nodeId == nil)
        #expect(probe.elementId == nil)
        #expect(probe.fieldValues.isEmpty)
    }

    @Test func testSimulationProbeEvaluatorRaycastVolumeMesh() {
        let mesh = makeSampleMesh()

        // Ray from (2, 2, 10) pointing straight down -Z towards inclined surface triangle (2, 4, 3) at Z=6
        let topRay = Ray3D(origin: SIMD3<Float>(2, 2, 10), direction: SIMD3<Float>(0, 0, -1))
        let topHit = SimulationProbeEvaluator.raycastVolumeMesh(ray: topRay, mesh: mesh)

        #expect(topHit != nil)
        if let topHit {
            #expect(abs(topHit.x - 2.0) < 1e-4)
            #expect(abs(topHit.y - 2.0) < 1e-4)
            #expect(abs(topHit.z - 6.0) < 1e-4)
        }

        // Ray from (2, 2, -10) pointing straight up +Z towards bottom triangle (1, 2, 3) at Z=0
        let bottomRay = Ray3D(origin: SIMD3<Float>(2, 2, -10), direction: SIMD3<Float>(0, 0, 1))
        let bottomHit = SimulationProbeEvaluator.raycastVolumeMesh(ray: bottomRay, mesh: mesh)

        #expect(bottomHit != nil)
        if let bottomHit {
            #expect(abs(bottomHit.x - 2.0) < 1e-4)
            #expect(abs(bottomHit.y - 2.0) < 1e-4)
            #expect(abs(bottomHit.z - 0.0) < 1e-4)
        }

        // Ray pointing away from mesh
        let missRay = Ray3D(origin: SIMD3<Float>(100, 100, 100), direction: SIMD3<Float>(1, 1, 1))
        let missHit = SimulationProbeEvaluator.raycastVolumeMesh(ray: missRay, mesh: mesh)
        #expect(missHit == nil)
    }
}
