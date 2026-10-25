import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SimulationCouplingMapperTests {

    @Test func testIdenticalMeshesFastPath() {
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        ]
        let mesh = VolumeMesh(nodes: nodes, elements: [])
        let sourceTemps = [1: 20.0, 2: 100.0, 3: 50.0]

        let mapped = SimulationCouplingMapper.mapNodalTemperatures(
            sourceTemperatures: sourceTemps,
            sourceMesh: mesh,
            targetMesh: mesh,
            fallbackTemperature: 20.0
        )

        #expect(mapped.count == 3)
        #expect(mapped[1] == 20.0)
        #expect(mapped[2] == 100.0)
        #expect(mapped[3] == 50.0)
    }

    @Test func testReindexedNodesSpatialFallback() {
        let sourceNodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        ]
        let sourceMesh = VolumeMesh(nodes: sourceNodes, elements: [])
        let sourceTemps = [1: 25.0, 2: 125.0, 3: 75.0]

        let targetNodes = [
            VolumeMeshNode(id: 101, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 102, position: SIMD3<Double>(1, 0, 0)),
            VolumeMeshNode(id: 103, position: SIMD3<Double>(0, 1, 0))
        ]
        let targetMesh = VolumeMesh(nodes: targetNodes, elements: [])

        let mapped = SimulationCouplingMapper.mapNodalTemperatures(
            sourceTemperatures: sourceTemps,
            sourceMesh: sourceMesh,
            targetMesh: targetMesh,
            fallbackTemperature: 20.0
        )

        #expect(mapped.count == 3)
        #expect(mapped[101] == 25.0)
        #expect(mapped[102] == 125.0)
        #expect(mapped[103] == 75.0)
    }

    @Test func testSpatialDistanceFallback() {
        let sourceNodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        ]
        let sourceMesh = VolumeMesh(nodes: sourceNodes, elements: [])
        let sourceTemps = [1: 30.0, 2: 150.0]

        // Target nodes at x=1 (closer to node 1) and x=9 (closer to node 2)
        let targetNodes = [
            VolumeMeshNode(id: 50, position: SIMD3<Double>(1.0, 0, 0)),
            VolumeMeshNode(id: 51, position: SIMD3<Double>(9.0, 0, 0))
        ]
        let targetMesh = VolumeMesh(nodes: targetNodes, elements: [])

        let mapped = SimulationCouplingMapper.mapNodalTemperatures(
            sourceTemperatures: sourceTemps,
            sourceMesh: sourceMesh,
            targetMesh: targetMesh,
            fallbackTemperature: 20.0
        )

        #expect(mapped[50] == 30.0)
        #expect(mapped[51] == 150.0)
    }

    @Test func testEmptySourceTemperaturesFallback() {
        let targetNodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        ]
        let targetMesh = VolumeMesh(nodes: targetNodes, elements: [])

        let mapped = SimulationCouplingMapper.mapNodalTemperatures(
            sourceTemperatures: [:],
            sourceMesh: nil,
            targetMesh: targetMesh,
            fallbackTemperature: 22.5
        )

        #expect(mapped.count == 2)
        #expect(mapped[1] == 22.5)
        #expect(mapped[2] == 22.5)
    }

    @Test func testEmptyTargetMeshReturnsEmpty() {
        let emptyTarget = VolumeMesh(nodes: [], elements: [])
        let mapped = SimulationCouplingMapper.mapNodalTemperatures(
            sourceTemperatures: [1: 100.0],
            sourceMesh: nil,
            targetMesh: emptyTarget,
            fallbackTemperature: 20.0
        )
        #expect(mapped.isEmpty)
    }

    @Test func testNilSourceMeshWithMissingNodesUsesFallback() {
        let targetNodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        ]
        let targetMesh = VolumeMesh(nodes: targetNodes, elements: [])
        let sourceTemps = [1: 55.0] // Node 2 missing

        let mapped = SimulationCouplingMapper.mapNodalTemperatures(
            sourceTemperatures: sourceTemps,
            sourceMesh: nil,
            targetMesh: targetMesh,
            fallbackTemperature: 21.0
        )

        #expect(mapped[1] == 55.0)
        #expect(mapped[2] == 21.0)
    }
}
