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

    @Test func testStructuralDeckPinnedSupport() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Pinned Deck Test", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(name: "FixFace", kind: .pinned)
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*BOUNDARY"))
        #expect(text.contains("1, 1, 3, 0.0"))
    }

    @Test func testStructuralDeckRollerSlider() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Roller Deck Test", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(
                name: "FixFace",
                kind: .rollerSlider,
                isRestrainedX: false,
                isRestrainedY: true,
                isRestrainedZ: false
            )
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*BOUNDARY"))
        #expect(text.contains("1, 2, 2, 0.0"))
        #expect(!text.contains("1, 1, 1, 0.0"))
    }

    @Test func testStructuralDeckSymmetrySupport() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Symmetry Deck Test", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(
                name: "FixFace",
                kind: .symmetry,
                isRestrainedX: true,
                isRestrainedY: false,
                isRestrainedZ: false
            )
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*BOUNDARY"))
        #expect(text.contains("1, 1, 1, 0.0"))
        #expect(!text.contains("1, 2, 2, 0.0"))
    }

    @Test func testStructuralDeckElasticSupport() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Elastic Deck Test", studyType: .linearStatic)
        study.fixtures = [
            SimulationFixture(
                name: "FixFace",
                kind: .elasticSupport,
                isRestrainedX: true,
                isRestrainedY: false,
                isRestrainedZ: false,
                elasticStiffness: SIMD3<Double>(3e6, 0, 0)
            )
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*ELEMENT, TYPE=SPRING1, ELSET=ESPRING_"))
        #expect(text.contains("*SPRING, ELSET=ESPRING_"))
        // 3e6 N/m distributed across 3 nodes = 1e6 N/m per node = 1000 N/mm
        #expect(text.contains("1000.0000"))
        #expect(!text.contains("*BOUNDARY"))
    }

    // MARK: - BL-FEA-03 Structural Load Deck Tests (#221)

    @Test func testStructuralDeckMomentLoad() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Moment Deck Test", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "FixFace", kind: .fixed)]
        study.loads = [
            SimulationLoad(name: "PressFace", kind: .moment, magnitude: 50.0, direction: SIMD3<Double>(0, 0, 1))
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*CLOAD"))
    }

    @Test func testStructuralDeckRemoteLoad() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Remote Load Deck Test", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "FixFace", kind: .fixed)]
        study.loads = [
            SimulationLoad(
                name: "PressFace",
                kind: .remoteLoad,
                magnitude: 1200.0,
                direction: SIMD3<Double>(0, -1, 0),
                remotePoint: SIMD3<Double>(0, 50, 0)
            )
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*CLOAD"))
    }

    @Test func testStructuralDeckBearingLoad() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Bearing Deck Test", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "FixFace", kind: .fixed)]
        study.loads = [
            SimulationLoad(name: "PressFace", kind: .bearing, magnitude: 3000.0, direction: SIMD3<Double>(0, 1, 0))
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*CLOAD"))
    }

    @Test func testStructuralDeckCentrifugalLoad() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Centrifugal Deck Test", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "FixFace", kind: .fixed)]
        study.loads = [
            SimulationLoad(
                name: "SpinLoad",
                kind: .centrifugal,
                magnitude: 100.0, // rad/s
                direction: SIMD3<Double>(0, 0, 1),
                axisOrigin: SIMD3<Double>(5.0, 5.0, 0.0)
            )
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*DLOAD"))
        // omega^2 = 10000.0000, axis from (5,5,0) to (5,5,1)
        #expect(text.contains("EALL, CENTRIF, 10000.0000, 5.0000, 5.0000, 0.0000, 5.0000, 5.0000, 1.0000"))
    }

    @Test func testStructuralDeckThermalExpansionLoad() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Thermal Structural Deck Test", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "FixFace", kind: .fixed)]
        study.loads = [
            SimulationLoad(
                name: "LoadFace",
                kind: .thermalLoad,
                magnitude: 150.0,
                referenceTemperature: 25.0
            )
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*EXPANSION"))
        #expect(text.contains("*INITIAL CONDITIONS, TYPE=TEMPERATURE"))
        #expect(text.contains("NALL, 25.0000"))
        #expect(text.contains("*STATIC"))
        #expect(text.contains("*TEMPERATURE"))
        #expect(text.contains("4, 150.0000"))
    }

    @Test func testStructuralDeckLinearBuckling() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Buckling Test", studyType: .linearBuckling)
        study.materials = [
            SimulationMaterialAssignment(materialId: "structural-steel-a36")
        ]
        study.solver.bucklingModesCount = 3
        study.fixtures = [
            SimulationFixture(name: "FixFace", kind: .fixed)
        ]
        study.loads = [
            SimulationLoad(name: "LoadFace", kind: .force, magnitude: 5000.0, direction: SIMD3<Double>(0, 0, -1))
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*HEADING"))
        #expect(text.contains("*STEP"))
        #expect(text.contains("*BUCKLE"))
        #expect(text.contains("3"))
        #expect(!text.contains("*STATIC"))
        #expect(text.contains("*BOUNDARY"))
        #expect(text.contains("*CLOAD"))
        #expect(text.contains("*NODE FILE\nU"))
        #expect(!text.contains("*EL FILE\nS"))
        #expect(text.contains("*END STEP"))
    }

    @Test func testStructuralDeckBondedConnection() {
        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(10, 0, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(20, 0, 0))

        let el1 = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 2, 2])
        let el2 = VolumeMeshElement(id: 2, order: .linear, nodeIndices: [3, 4, 4, 4])

        let sourceSet = VolumeMeshSet(name: "SourceFace", nodeIds: [2], elementIds: [])
        let targetSet = VolumeMeshSet(name: "TargetFace", nodeIds: [3], elementIds: [])
        let fixSet = VolumeMeshSet(name: "FixFace", nodeIds: [1], elementIds: [])
        let loadSet = VolumeMeshSet(name: "LoadFace", nodeIds: [4], elementIds: [])

        let mesh = VolumeMesh(
            nodes: [n1, n2, n3, n4],
            elements: [el1, el2],
            sets: [fixSet, loadSet, sourceSet, targetSet]
        )

        var study = SimulationStudy(name: "Bonded Contact Test", studyType: .linearStatic)
        study.fixtures = [SimulationFixture(name: "FixFace", kind: .fixed)]
        study.loads = [SimulationLoad(name: "LoadFace", kind: .force, magnitude: 500.0, direction: SIMD3<Double>(1, 0, 0))]
        study.connections = [
            SimulationConnection(
                name: "Bonded Connection",
                kind: .bonded,
                sourceReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "SourceFace")],
                targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "TargetFace")],
                searchTolerance: 0.05
            )
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*NSET, NSET=BONDED_CONNECTION_SOURCE\n2"))
        #expect(text.contains("*NSET, NSET=BONDED_CONNECTION_TARGET\n3"))
        #expect(text.contains("*SURFACE, NAME=SURF_BONDED_CONNECTION_SOURCE, TYPE=NODE\nBONDED_CONNECTION_SOURCE"))
        #expect(text.contains("*SURFACE, NAME=SURF_BONDED_CONNECTION_TARGET, TYPE=NODE\nBONDED_CONNECTION_TARGET"))
        #expect(text.contains("*TIE, NAME=BONDED_CONNECTION_TIE, POSITION TOLERANCE=0.0500\nSURF_BONDED_CONNECTION_SOURCE, SURF_BONDED_CONNECTION_TARGET"))

        let tieRange = text.range(of: "*TIE")
        let stepRange = text.range(of: "*STEP")
        #expect(tieRange != nil)
        #expect(stepRange != nil)
        if let tieRange, let stepRange {
            #expect(tieRange.lowerBound < stepRange.lowerBound)
        }
    }

    @Test func testModalFrequencyDeckSingleStep() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Modal Analysis Test", studyType: .modalFrequency)
        study.solver.modeCount = 5
        study.fixtures = [SimulationFixture(name: "FixFace", kind: .fixed)]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*FREQUENCY\n5"))
        #expect(text.contains("*DENSITY"))
        #expect(text.contains("*BOUNDARY"))
        #expect(text.contains("*NODE FILE\nU"))
        #expect(!text.contains("*STATIC"))
        #expect(!text.contains("*EL FILE"))
    }

    @Test func testModalFrequencyDeckPrestressedTwoStep() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Prestressed Modal Analysis Test", studyType: .modalFrequency)
        study.solver.modeCount = 6
        study.solver.isPrestressEnabled = true
        study.fixtures = [SimulationFixture(name: "FixFace", kind: .fixed)]
        study.loads = [
            SimulationLoad(name: "LoadFace", kind: .force, magnitude: 1000.0, direction: SIMD3<Double>(0, -1, 0))
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh)
        let text = deck.deckContent

        #expect(text.contains("*STATIC"))
        #expect(text.contains("*CLOAD"))
        #expect(text.contains("*STEP, PERTURBATION\n*FREQUENCY\n6"))
        #expect(text.contains("*NODE FILE\nU"))
        #expect(text.contains("*DENSITY"))
    }

    @Test func testThermalCoupledDeckPerNodeTemperatures() {
        let mesh = Self.makeSimpleMesh()
        var study = SimulationStudy(name: "Thermal Coupled Deck Test", studyType: .linearStatic)
        study.thermalStudyId = UUID()
        study.thermalReferenceTemperature = 22.5
        study.fixtures = [SimulationFixture(name: "FixFace", kind: .fixed)]

        let nodalTemps: [Int: Double] = [
            1: 22.5,
            2: 45.0,
            3: 70.0,
            4: 100.0
        ]

        let deck = CalculiXDeckBuilder.buildDeck(study: study, mesh: mesh, nodalTemperatures: nodalTemps)
        let text = deck.deckContent

        #expect(text.contains("*INITIAL CONDITIONS, TYPE=TEMPERATURE\nNALL, 22.5000"))
        #expect(text.contains("*TEMPERATURE"))
        #expect(text.contains("1, 22.5000"))
        #expect(text.contains("2, 45.0000"))
        #expect(text.contains("3, 70.0000"))
        #expect(text.contains("4, 100.0000"))
    }
}
