import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct CalculiXStructuralDeckTests {

    static func makeSimpleMesh() -> VolumeMesh {
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))

        let el = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4])

        let fixSet = VolumeMeshSet(name: "FixFace", nodeIds: [1, 2, 3], elementIds: [])
        let loadSet = VolumeMeshSet(name: "LoadFace", nodeIds: [4], elementIds: [])
        let pressSet = VolumeMeshSet(name: "PressFace", nodeIds: [1, 2, 3], elementIds: [1])

        return VolumeMesh(
            nodes: [n1, n2, n3, n4],
            elements: [el],
            sets: [fixSet, loadSet, pressSet]
        )
    }

    @Test func testStructuralDeckFixedSupportAndForce() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Fixed and Force Test", studyType: .linearStatic)
        study.materials = [
            SimulationMaterialAssignment(materialId: "structural-steel-a36")
        ]
        study.fixtures = [
            SimulationFixture(name: "FixFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "LoadFace", kind: .force, magnitude: 1000.0, direction: SIMD3<Double>(0, -1, 0))
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*HEADING"))
        #expect(text.contains("*STATIC"))
        #expect(text.contains("*MATERIAL, NAME=STRUCTURAL_STEEL_A36"))
        #expect(text.contains("*ELASTIC"))
        #expect(text.contains("200000.0, 0.2600"))
        #expect(text.contains("*DENSITY"))
        #expect(text.contains("*BOUNDARY"))
        #expect(text.contains("1, 1, 3, 0.0"))
        #expect(text.contains("*CLOAD"))
        #expect(text.contains("4, 2, -1000.0000"))
        #expect(text.contains("*NODE FILE\nU"))
        #expect(text.contains("*EL FILE\nS"))
        #expect(text.contains("*END STEP"))
    }

    @Test func testStructuralDeckPrescribedDisplacement() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Prescribed Disp Test", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(
                name: "FixFace",
                kind: .prescribedDisplacement,
                prescribedDisplacement: SIMD3<Double>(1.5, -2.0, 0.5),
                isRestrainedX: true,
                isRestrainedY: true,
                isRestrainedZ: true
            )
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*BOUNDARY"))
        #expect(text.contains("1, 1, 1, 1.5000"))
        #expect(text.contains("1, 2, 2, -2.0000"))
        #expect(text.contains("1, 3, 3, 0.5000"))
    }

    @Test func testStructuralDeckPressureLoad() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Pressure Test", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "FixFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "PressFace", kind: .pressure, magnitude: 2.5)
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*DLOAD"))
        #expect(text.contains("1, P1, 2.5000"))
    }

    @Test func testStructuralDeckGravityLoad() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Gravity Test", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "FixFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "EarthGravity", kind: .gravity, magnitude: 9.81, direction: SIMD3<Double>(0, -1, 0))
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*DLOAD"))
        #expect(text.contains("EALL, GRAV, 9.8100, 0.0000, -1.0000, 0.0000"))
    }
}
