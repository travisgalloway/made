import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct CalculiXThermalDeckTests {

    static func makeSimpleMesh() -> VolumeMesh {
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        let el = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4])
        let tri1 = VolumeMeshElement(id: 2, order: .linear, nodeIndices: [1, 2, 3])
        let tri2 = VolumeMeshElement(id: 3, order: .linear, nodeIndices: [1, 2, 4])

        let set1 = VolumeMeshSet(name: "HotFace", nodeIds: [1, 2, 3], elementIds: [2])
        let set2 = VolumeMeshSet(name: "ColdFace", nodeIds: [1, 2, 4], elementIds: [3])

        return VolumeMesh(
            nodes: [n1, n2, n3, n4],
            elements: [el],
            surfaceTriangles: [tri1, tri2],
            statistics: SimulationMeshStatistics(nodeCount: 4, elementCount: 1),
            sets: [set1, set2]
        )
    }

    @Test func testThermalDeckHeaderMaterialAndStep() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Thermal Bracket", studyType: .thermalConduction)
        study.materials = [SimulationMaterialAssignment(name: "Steel Assignment", materialId: "structural-steel")]
        study.loads = [
            SimulationLoad(name: "HotFace", kind: .temperature, magnitude: 120.0)
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*HEADING"))
        #expect(text.contains("CalculiX FEA Simulation Study - Thermal Bracket"))
        #expect(text.contains("*NODE, NSET=NALL"))
        #expect(text.contains("*ELEMENT, TYPE=C3D4, ELSET=EALL"))
        #expect(text.contains("*MATERIAL, NAME=STRUCTURAL_STEEL"))
        #expect(text.contains("*CONDUCTIVITY"))
        #expect(text.contains("50.0"))
        #expect(text.contains("*SOLID SECTION, ELSET=EALL, MATERIAL=STRUCTURAL_STEEL"))
        #expect(text.contains("*STEP"))
        #expect(text.contains("*HEAT TRANSFER, STEADY STATE"))
        #expect(text.contains("*NODE FILE\nNT"))
        #expect(text.contains("*EL FILE\nHFL"))
        #expect(text.contains("*END STEP"))
    }

    @Test func testThermalDeckBoundaryDOF11() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Dirichlet Test", studyType: .thermalConduction)
        study.loads = [
            SimulationLoad(name: "HotFace", kind: .temperature, magnitude: 85.5)
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*BOUNDARY"))
        #expect(text.contains("1, 11, 11, 85.5000"))
        #expect(text.contains("2, 11, 11, 85.5000"))
        #expect(text.contains("3, 11, 11, 85.5000"))
    }

    @Test func testThermalDeckConvectionFilm() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Convection Test", studyType: .thermalConduction)
        study.loads = [
            SimulationLoad(name: "ColdFace", kind: .convection, magnitude: 25.0, ambientTemperature: 18.0)
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*FILM"))
        #expect(text.contains("1, 11, 18.0000, 25.0000"))
    }

    @Test func testThermalDeckSurfaceHeatFlux() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Flux Test", studyType: .thermalConduction)
        study.loads = [
            SimulationLoad(name: "HotFace", kind: .thermalFlux, magnitude: 5000.0)
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*DFLUX"))
        #expect(text.contains("2, S1, 5000.0000"))
    }

    @Test func testThermalDeckHeatPower() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Power Test", studyType: .thermalConduction)
        study.loads = [
            SimulationLoad(name: "HotFace", kind: .heatPower, magnitude: 30.0)
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*CFLUX"))
        // HotFace has 3 nodes: 30 W / 3 = 10 W per node
        #expect(text.contains("1, 11, 10.0000"))
        #expect(text.contains("2, 11, 10.0000"))
        #expect(text.contains("3, 11, 10.0000"))
    }

    @Test func testStructuralDeckFallback() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Structural Test", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "ColdFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "HotFace", kind: .force, magnitude: 1500.0, direction: SIMD3<Double>(0, 0, -1))
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*MATERIAL, NAME=STEEL"))
        #expect(text.contains("*ELASTIC"))
        #expect(text.contains("210000.0, 0.3"))
        #expect(text.contains("*STEP"))
        #expect(text.contains("*STATIC"))
        #expect(text.contains("*BOUNDARY"))
        #expect(text.contains("1, 1, 3, 0.0"))
        #expect(text.contains("*CLOAD"))
        #expect(text.contains("*NODE FILE\nU"))
        #expect(text.contains("*EL FILE\nS"))
        #expect(text.contains("*END STEP"))
    }
}
