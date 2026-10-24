import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct MeshDisplayGeneratorTests {

    private func makeSingleTetMesh(order: MeshElementOrder = .linear) -> VolumeMesh {
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 1))

        var nodes = [n1, n2, n3, n4]
        var nodeIndices = [1, 2, 3, 4]

        if order == .quadratic {
            let n5 = VolumeMeshNode(id: 5, position: SIMD3<Double>(0.5, 0, 0))
            let n6 = VolumeMeshNode(id: 6, position: SIMD3<Double>(0.5, 0.5, 0))
            let n7 = VolumeMeshNode(id: 7, position: SIMD3<Double>(0, 0.5, 0))
            let n8 = VolumeMeshNode(id: 8, position: SIMD3<Double>(0, 0, 0.5))
            let n9 = VolumeMeshNode(id: 9, position: SIMD3<Double>(0.5, 0, 0.5))
            let n10 = VolumeMeshNode(id: 10, position: SIMD3<Double>(0, 0.5, 0.5))
            nodes.append(contentsOf: [n5, n6, n7, n8, n9, n10])
            nodeIndices.append(contentsOf: [5, 6, 7, 8, 9, 10])
        }

        let element = VolumeMeshElement(id: 1, order: order, nodeIndices: nodeIndices, tag: 10)
        return VolumeMesh(nodes: nodes, elements: [element])
    }

    private func makeTwoAdjacentTetsMesh() -> VolumeMesh {
        // Tet 1: (0,0,0), (1,0,0), (0,1,0), (0,0,1)
        // Tet 2 shares face (1,0,0)-(0,1,0)-(0,0,1) with opposite node (1,1,1)
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 1))
        let n5 = VolumeMeshNode(id: 5, position: SIMD3<Double>(1, 1, 1))

        let elem1 = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4])
        let elem2 = VolumeMeshElement(id: 2, order: .linear, nodeIndices: [2, 3, 4, 5])

        return VolumeMesh(nodes: [n1, n2, n3, n4, n5], elements: [elem1, elem2])
    }

    @Test func testEmptyMeshProducesEmptyPayload() {
        let emptyMesh = VolumeMesh()
        let settings = SimulationMeshDisplaySettings()
        let payload = MeshDisplayGenerator.generatePayload(mesh: emptyMesh, settings: settings)

        #expect(payload.isEmpty)
        #expect(payload.triangleCount == 0)
        #expect(payload.edgePolylines.isEmpty)
    }

    @Test func testLinearC3D4MeshPayloadGeneration() {
        let mesh = makeSingleTetMesh(order: .linear)
        let settings = SimulationMeshDisplaySettings()
        let payload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: settings)

        #expect(!payload.isEmpty)
        #expect(payload.triangleCount == 4)
        #expect(payload.edgePolylines.count == 6)

        // Verify all coordinates and normals are finite
        for p in payload.positions {
            #expect(!p.isNaN && !p.isInfinite)
        }
        for n in payload.normals {
            #expect(!n.isNaN && !n.isInfinite)
        }
    }

    @Test func testQuadraticC3D10MeshPayloadGeneration() {
        let mesh = makeSingleTetMesh(order: .quadratic)
        let settings = SimulationMeshDisplaySettings()
        let payload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: settings)

        #expect(!payload.isEmpty)
        #expect(payload.triangleCount == 4)
        #expect(payload.edgePolylines.count == 6)
    }

    @Test func testElementShrinkGeometry() {
        let mesh = makeTwoAdjacentTetsMesh()

        // At shrink = 0, shared edges are deduplicated
        let unshrinkSettings = SimulationMeshDisplaySettings(elementShrink: 0.0)
        let unshrinkPayload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: unshrinkSettings)
        // 2 tets sharing 3 edges: 6 + 6 - 3 = 9 unique edges
        #expect(unshrinkPayload.edgePolylines.count == 9)

        // At shrink = 0.5, each tetrahedron gets its own 6 shrunk edges: 6 * 2 = 12 edges
        let shrinkSettings = SimulationMeshDisplaySettings(elementShrink: 0.5)
        let shrinkPayload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: shrinkSettings)
        #expect(shrinkPayload.edgePolylines.count == 12)

        // Verify that vertices moved toward the centroid
        // Tet 1 original centroid is (0.25, 0.25, 0.25).
        // Original node 1 is at (0, 0, 0), distance to centroid is sqrt(3 * 0.25^2) ≈ 0.4330.
        // At shrink = 0.5, distance should be 0.5 * 0.4330 ≈ 0.2165.
        let centroid = SIMD3<Float>(0.25, 0.25, 0.25)
        var minDistanceToCentroid: Float = .greatestFiniteMagnitude
        for i in stride(from: 0, to: shrinkPayload.positions.count, by: 3) {
            let pt = SIMD3<Float>(shrinkPayload.positions[i], shrinkPayload.positions[i + 1], shrinkPayload.positions[i + 2])
            let d = simd_distance(pt, centroid)
            minDistanceToCentroid = min(minDistanceToCentroid, d)
        }
        #expect(minDistanceToCentroid > 0.15 && minDistanceToCentroid < 0.3)
    }

    @Test func testSlicingPlaneFilteringAcrossAxes() {
        // Create 2 separated tetrahedra: one at negative origin, one shifted along +X, +Y, +Z
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 1))

        let n5 = VolumeMeshNode(id: 5, position: SIMD3<Double>(10, 10, 10))
        let n6 = VolumeMeshNode(id: 6, position: SIMD3<Double>(11, 10, 10))
        let n7 = VolumeMeshNode(id: 7, position: SIMD3<Double>(10, 11, 10))
        let n8 = VolumeMeshNode(id: 8, position: SIMD3<Double>(10, 10, 11))

        let elem1 = VolumeMeshElement(id: 1, nodeIndices: [1, 2, 3, 4])
        let elem2 = VolumeMeshElement(id: 2, nodeIndices: [5, 6, 7, 8])

        let mesh = VolumeMesh(nodes: [n1, n2, n3, n4, n5, n6, n7, n8], elements: [elem1, elem2])

        for axis in MeshSliceAxis.allCases {
            let sliceSettings = SimulationMeshDisplaySettings(
                isSliceEnabled: true,
                sliceAxis: axis,
                slicePosition: 0.5,
                isSliceInverted: false
            )
            let payload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: sliceSettings)
            // Kept only elem1 (4 triangles)
            #expect(payload.triangleCount == 4)
        }
    }

    @Test func testSliceInversionToggle() {
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 1))

        let n5 = VolumeMeshNode(id: 5, position: SIMD3<Double>(10, 0, 0))
        let n6 = VolumeMeshNode(id: 6, position: SIMD3<Double>(11, 0, 0))
        let n7 = VolumeMeshNode(id: 7, position: SIMD3<Double>(10, 1, 0))
        let n8 = VolumeMeshNode(id: 8, position: SIMD3<Double>(10, 0, 1))

        let elem1 = VolumeMeshElement(id: 1, nodeIndices: [1, 2, 3, 4])
        let elem2 = VolumeMeshElement(id: 2, nodeIndices: [5, 6, 7, 8])

        let mesh = VolumeMesh(nodes: [n1, n2, n3, n4, n5, n6, n7, n8], elements: [elem1, elem2])

        let invertedSettings = SimulationMeshDisplaySettings(
            isSliceEnabled: true,
            sliceAxis: .x,
            slicePosition: 0.5,
            isSliceInverted: true
        )
        let payload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: invertedSettings)
        // Kept only elem2 (4 triangles)
        #expect(payload.triangleCount == 4)
    }

    @Test func testSliceZeroExtentAxisKeepsAllElements() {
        // Mesh with zero extent on Z axis (all z = 0)
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0.5, 0.5, 0))
        let elem = VolumeMeshElement(id: 1, nodeIndices: [1, 2, 3, 4])
        let mesh = VolumeMesh(nodes: [n1, n2, n3, n4], elements: [elem])

        let settings = SimulationMeshDisplaySettings(
            isSliceEnabled: true,
            sliceAxis: .z,
            slicePosition: 0.5
        )
        let payload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: settings)
        #expect(payload.triangleCount == 4)
    }

    @Test func testDegenerateAndFlatTetrahedronHandling() {
        // All four nodes coplanar (flat)
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(1, 1, 0))
        let elem = VolumeMeshElement(id: 1, nodeIndices: [1, 2, 3, 4])
        let mesh = VolumeMesh(nodes: [n1, n2, n3, n4], elements: [elem])

        let payload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: SimulationMeshDisplaySettings())
        #expect(payload.triangleCount == 4)

        for n in payload.normals {
            #expect(!n.isNaN && !n.isInfinite)
        }
    }

    @Test func testElementFilterGeneratesHighlightedSubmesh() {
        let mesh = makeTwoAdjacentTetsMesh()
        let settings = SimulationMeshDisplaySettings()
        let filteredPayload = MeshDisplayGenerator.generatePayload(
            mesh: mesh,
            settings: settings,
            elementFilter: [2]
        )

        // Exactly 1 tetrahedron generated
        #expect(filteredPayload.triangleCount == 4)
        #expect(filteredPayload.edgePolylines.count == 6)
    }

    @Test func testShowFacesAndShowEdgesToggles() {
        let mesh = makeSingleTetMesh()

        let edgesOnlySettings = SimulationMeshDisplaySettings(showEdges: true, showFaces: false)
        let edgesPayload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: edgesOnlySettings)
        #expect(edgesPayload.triangleCount == 0)
        #expect(edgesPayload.edgePolylines.count == 6)

        let facesOnlySettings = SimulationMeshDisplaySettings(showEdges: false, showFaces: true)
        let facesPayload = MeshDisplayGenerator.generatePayload(mesh: mesh, settings: facesOnlySettings)
        #expect(facesPayload.triangleCount == 4)
        #expect(facesPayload.edgePolylines.isEmpty)
    }
}
