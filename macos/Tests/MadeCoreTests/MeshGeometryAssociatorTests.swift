import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct MeshGeometryAssociatorTests {

    @Test func testMSHParserParsesPhysicalNamesIntoMeshSets() throws {
        let mshContent = """
        $MeshFormat
        2.2 0 8
        $EndMeshFormat
        $PhysicalNames
        2
        2 101 "fixed_bottom"
        3 201 "solid_body"
        $EndPhysicalNames
        $Nodes
        4
        1 0.0 0.0 0.0
        2 10.0 0.0 0.0
        3 0.0 10.0 0.0
        4 0.0 0.0 10.0
        $EndNodes
        $Elements
        2
        1 2 2 101 1 1 2 3
        2 4 2 201 1 1 2 3 4
        $EndElements
        """

        let mesh = try MSHParser.parse(content: mshContent)
        #expect(mesh.sets.count == 2)

        let surfaceSet = mesh.set(named: "fixed_bottom")
        #expect(surfaceSet != nil)
        #expect(surfaceSet?.tag == 101)
        #expect(surfaceSet?.subelementType == .face)
        #expect(surfaceSet?.elementIds == [1])
        #expect(surfaceSet?.nodeIds == [1, 2, 3])

        let bodySet = mesh.set(named: "solid_body")
        #expect(bodySet != nil)
        #expect(bodySet?.tag == 201)
        #expect(bodySet?.subelementType == nil)
        #expect(bodySet?.elementIds == [2])
        #expect(bodySet?.nodeIds == [1, 2, 3, 4])

        // Query helpers
        let nodesInSurface = mesh.nodeSet(named: "fixed_bottom")
        #expect(nodesInSurface.count == 3)
        #expect(nodesInSurface.map { $0.id } == [1, 2, 3])

        let elementsInSurface = mesh.elementSet(named: "fixed_bottom")
        #expect(elementsInSurface.count == 1)
        #expect(elementsInSurface.first?.id == 1)

        let nodesInBody = mesh.nodeSet(named: "solid_body")
        #expect(nodesInBody.count == 4)

        let elementsInBody = mesh.elementSet(named: "solid_body")
        #expect(elementsInBody.count == 1)
        #expect(elementsInBody.first?.id == 2)
    }

    @Test func testAssociatorMapsPlanarFacesToLinearMeshSets() {
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        ]
        let elements = [
            VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 0)
        ]
        // Bottom face at z = 0 with outward normal pointing -Z (nodes 1, 3, 2)
        let surfaceTriangles = [
            VolumeMeshElement(id: 2, order: .linear, nodeIndices: [1, 3, 2], tag: 0)
        ]
        let mesh = VolumeMesh(
            nodes: nodes,
            elements: elements,
            surfaceTriangles: surfaceTriangles
        )

        let fixture = SimulationFixture(
            name: "Bottom Fixed",
            kind: .fixed,
            targetReferences: [
                SimulationGeometryReference(
                    targetId: UUID(),
                    targetName: "face:bottom",
                    subelementType: .face
                )
            ]
        )
        let study = SimulationStudy(fixtures: [fixture])

        let sets = MeshGeometryAssociator.associate(mesh: mesh, study: study)
        let fixtureSet = sets.first { $0.name == "Bottom Fixed" }

        #expect(fixtureSet != nil)
        #expect(fixtureSet?.elementIds == [2])
        #expect(fixtureSet?.nodeIds == [1, 2, 3])
        #expect(fixtureSet?.subelementType == .face)
    }

    @Test func testAssociatorMapsPlanarFacesToQuadraticMeshSets() {
        // C3D10 tetrahedron with 6-node boundary surface triangle on bottom
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10)),
            VolumeMeshNode(id: 5, position: SIMD3<Double>(5, 0, 0)),
            VolumeMeshNode(id: 6, position: SIMD3<Double>(5, 5, 0)),
            VolumeMeshNode(id: 7, position: SIMD3<Double>(0, 5, 0)),
            VolumeMeshNode(id: 8, position: SIMD3<Double>(0, 0, 5)),
            VolumeMeshNode(id: 9, position: SIMD3<Double>(5, 0, 5)),
            VolumeMeshNode(id: 10, position: SIMD3<Double>(0, 5, 5))
        ]
        let elements = [
            VolumeMeshElement(id: 1, order: .quadratic, nodeIndices: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], tag: 0)
        ]
        // 6-node quadratic triangle on bottom z=0 (corners: 1, 3, 2, mid-sides: 7, 6, 5)
        let surfaceTriangles = [
            VolumeMeshElement(id: 2, order: .quadratic, nodeIndices: [1, 3, 2, 7, 6, 5], tag: 0)
        ]
        let mesh = VolumeMesh(
            nodes: nodes,
            elements: elements,
            surfaceTriangles: surfaceTriangles
        )

        let fixture = SimulationFixture(
            name: "Quadratic Base Support",
            kind: .fixed,
            targetReferences: [
                SimulationGeometryReference(
                    targetId: UUID(),
                    targetName: "face:bottom",
                    subelementType: .face
                )
            ]
        )
        let study = SimulationStudy(fixtures: [fixture])

        let sets = MeshGeometryAssociator.associate(mesh: mesh, study: study)
        let fixtureSet = sets.first { $0.name == "Quadratic Base Support" }

        #expect(fixtureSet != nil)
        #expect(fixtureSet?.elementIds == [2])
        // Must contain all 6 nodes: corners 1, 2, 3 and mid-sides 5, 6, 7
        #expect(fixtureSet?.nodeIds.count == 6)
        #expect(fixtureSet?.nodeIds == [1, 2, 3, 5, 6, 7])
    }

    @Test func testAssociatorHandlesEmptyTargetReferencesAsFullBoundary() {
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 1))
        ]
        let surfaceTriangles = [
            VolumeMeshElement(id: 10, order: .linear, nodeIndices: [1, 2, 3], tag: 0),
            VolumeMeshElement(id: 20, order: .linear, nodeIndices: [1, 2, 4], tag: 0)
        ]
        let mesh = VolumeMesh(
            nodes: nodes,
            elements: [VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 0)],
            surfaceTriangles: surfaceTriangles
        )

        let fixture = SimulationFixture(name: "Global Boundary Fixture", targetReferences: [])
        let study = SimulationStudy(fixtures: [fixture])

        let sets = MeshGeometryAssociator.associate(mesh: mesh, study: study)
        let fixtureSet = sets.first { $0.name == "Global Boundary Fixture" }

        #expect(fixtureSet != nil)
        #expect(fixtureSet?.elementIds == [10, 20])
        #expect(fixtureSet?.nodeIds == [1, 2, 3, 4])
        #expect(fixtureSet?.subelementType == .face)
    }

    @Test func testAssociatorHandlesGravityLoadAsFullVolumeMeshSet() {
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 1)),
            VolumeMeshNode(id: 5, position: SIMD3<Double>(1, 1, 1))
        ]
        let elements = [
            VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 0),
            VolumeMeshElement(id: 2, order: .linear, nodeIndices: [2, 3, 4, 5], tag: 0)
        ]
        let mesh = VolumeMesh(nodes: nodes, elements: elements)

        let gravityLoad = SimulationLoad(name: "Self Weight", kind: .gravity, targetReferences: [])
        let study = SimulationStudy(loads: [gravityLoad])

        let sets = MeshGeometryAssociator.associate(mesh: mesh, study: study)
        let loadSet = sets.first { $0.name == "Self Weight" }

        #expect(loadSet != nil)
        #expect(loadSet?.elementIds == [1, 2])
        #expect(loadSet?.nodeIds == [1, 2, 3, 4, 5])
        #expect(loadSet?.subelementType == nil)
    }

    @Test func testAssociatorHandlesNamedGeometryGroups() {
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        ]
        let surfaceTriangles = [
            VolumeMeshElement(id: 2, order: .linear, nodeIndices: [1, 3, 2], tag: 0)
        ]
        let mesh = VolumeMesh(
            nodes: nodes,
            elements: [VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 0)],
            surfaceTriangles: surfaceTriangles
        )

        let group = SimulationGeometryGroup(
            name: "Base Clamping Group",
            targetReferences: [
                SimulationGeometryReference(
                    targetId: UUID(),
                    targetName: "face:bottom",
                    subelementType: .face
                )
            ]
        )
        let fixture = SimulationFixture(
            name: "Fixture Via Group",
            targetReferences: [],
            groupNames: ["Base Clamping Group"]
        )
        let study = SimulationStudy(
            groups: [group],
            fixtures: [fixture]
        )

        let sets = MeshGeometryAssociator.associate(mesh: mesh, study: study)

        let groupSet = sets.first { $0.name == "Base Clamping Group" }
        #expect(groupSet != nil)
        #expect(groupSet?.elementIds == [2])
        #expect(groupSet?.nodeIds == [1, 2, 3])

        let fixtureSet = sets.first { $0.name == "Fixture Via Group" }
        #expect(fixtureSet != nil)
        #expect(fixtureSet?.elementIds == [2])
        #expect(fixtureSet?.nodeIds == [1, 2, 3])
    }

    @Test func testAssociatorToleranceAndUnmatchedReferenceYieldsEmptySet() {
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        ]
        let surfaceTriangles = [
            VolumeMeshElement(id: 2, order: .linear, nodeIndices: [1, 3, 2], tag: 0)
        ]
        let mesh = VolumeMesh(
            nodes: nodes,
            elements: [VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 0)],
            surfaceTriangles: surfaceTriangles
        )

        let fixture = SimulationFixture(
            name: "Unmatched Target Fixture",
            targetReferences: [
                SimulationGeometryReference(
                    targetId: UUID(),
                    targetName: "nonexistent_target_face",
                    subelementType: .face
                )
            ]
        )
        let study = SimulationStudy(fixtures: [fixture])

        let sets = MeshGeometryAssociator.associate(mesh: mesh, study: study)
        let fixtureSet = sets.first { $0.name == "Unmatched Target Fixture" }

        #expect(fixtureSet != nil)
        #expect(fixtureSet?.elementIds.isEmpty == true)
        #expect(fixtureSet?.nodeIds.isEmpty == true)
    }

    @Test func testAssociatorNormalToleranceBoundary() {
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        ]
        // Triangle 10: normal exactly (0, 0, -1) on z = 0
        // Triangle 20: slanted normal on z = 0
        let surfaceTriangles = [
            VolumeMeshElement(id: 10, order: .linear, nodeIndices: [1, 3, 2], tag: 0),
            VolumeMeshElement(id: 20, order: .linear, nodeIndices: [1, 2, 4], tag: 0)
        ]
        let mesh = VolumeMesh(nodes: nodes, surfaceTriangles: surfaceTriangles)

        // Matching normal: (0, 0, -1)
        let matchingRef = SimulationGeometryReference(
            targetId: UUID(),
            targetName: "bottom",
            subelementType: .face,
            topologicalReference: TopologicalReference(
                sourceFeatureId: UUID(),
                elementType: .face,
                disambiguator: GeometricSignature(normal: SIMD3<Float>(0, 0, -1), centroid: SIMD3<Float>(3.33, 3.33, 0))
            )
        )
        let resMatching = MeshGeometryAssociator.associate(reference: matchingRef, mesh: mesh)
        #expect(resMatching.elementIds == [10])

        // Angled normal outside tolerance: (0.5, 0.5, -0.707)
        let angledRef = SimulationGeometryReference(
            targetId: UUID(),
            targetName: "angled",
            subelementType: .face,
            topologicalReference: TopologicalReference(
                sourceFeatureId: UUID(),
                elementType: .face,
                disambiguator: GeometricSignature(normal: SIMD3<Float>(0.5, 0.5, -0.707), centroid: SIMD3<Float>(3.33, 3.33, 0))
            )
        )
        let resAngled = MeshGeometryAssociator.associate(reference: angledRef, mesh: mesh)
        #expect(resAngled.elementIds.isEmpty)
    }

    @Test func testAssociateVertexReferenceWithMeshNodes() {
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        ]
        let mesh = VolumeMesh(nodes: nodes, elements: [VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 0)])

        let matchingVertexRef = SimulationGeometryReference(
            targetId: UUID(),
            targetName: "vertex:corner",
            subelementType: .vertex,
            topologicalReference: TopologicalReference(
                sourceFeatureId: UUID(),
                elementType: .vertex,
                disambiguator: GeometricSignature(centroid: SIMD3<Float>(10, 0, 0))
            )
        )
        let matched = MeshGeometryAssociator.associate(reference: matchingVertexRef, mesh: mesh)
        #expect(matched.nodeIds == [2])
        #expect(matched.elementIds.isEmpty)

        let unmatchedVertexRef = SimulationGeometryReference(
            targetId: UUID(),
            targetName: "vertex:distant",
            subelementType: .vertex,
            topologicalReference: TopologicalReference(
                sourceFeatureId: UUID(),
                elementType: .vertex,
                disambiguator: GeometricSignature(centroid: SIMD3<Float>(100, 100, 100))
            )
        )
        let unmatched = MeshGeometryAssociator.associate(reference: unmatchedVertexRef, mesh: mesh)
        #expect(unmatched.nodeIds.isEmpty)
        #expect(unmatched.elementIds.isEmpty)

        let noCentroidVertexRef = SimulationGeometryReference(
            targetId: UUID(),
            targetName: "vertex:nocentroid",
            subelementType: .vertex
        )
        let noCentroid = MeshGeometryAssociator.associate(reference: noCentroidVertexRef, mesh: mesh)
        #expect(noCentroid.nodeIds.isEmpty)
        #expect(noCentroid.elementIds.isEmpty)
    }
}
