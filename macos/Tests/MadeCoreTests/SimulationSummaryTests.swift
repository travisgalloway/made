import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SimulationSummaryTests {

    @Test func testSimulationConstraintReactionInitialization() {
        let id = UUID()
        let rxn = SimulationConstraintReaction(
            id: id,
            fixtureName: "Clamp 1",
            reactionForce: SIMD3<Double>(100.0, -200.0, 50.0),
            reactionMoment: SIMD3<Double>(10.0, 20.0, -30.0),
            referencePoint: SIMD3<Double>(5.0, 10.0, 15.0),
            nodeCount: 4,
            nodalReactionForces: [
                1: SIMD3<Double>(25.0, -50.0, 12.5),
                2: SIMD3<Double>(25.0, -50.0, 12.5),
                3: SIMD3<Double>(25.0, -50.0, 12.5),
                4: SIMD3<Double>(25.0, -50.0, 12.5)
            ]
        )

        #expect(rxn.id == id)
        #expect(rxn.fixtureName == "Clamp 1")
        #expect(rxn.reactionForce == SIMD3<Double>(100.0, -200.0, 50.0))
        #expect(rxn.reactionMoment == SIMD3<Double>(10.0, 20.0, -30.0))
        #expect(rxn.referencePoint == SIMD3<Double>(5.0, 10.0, 15.0))
        #expect(rxn.nodeCount == 4)
        #expect(rxn.nodalReactionForces?.count == 4)
    }

    @Test func testTotalReactionForceAndMoment() {
        var results = SimulationStudyResults()
        #expect(results.totalReactionForce == nil)
        #expect(results.totalReactionMoment == nil)

        let r1 = SimulationConstraintReaction(
            id: UUID(),
            fixtureName: "Fix1",
            reactionForce: SIMD3<Double>(10.0, 20.0, 30.0),
            reactionMoment: SIMD3<Double>(1.0, 2.0, 3.0),
            referencePoint: .zero,
            nodeCount: 1
        )
        let r2 = SimulationConstraintReaction(
            id: UUID(),
            fixtureName: "Fix2",
            reactionForce: SIMD3<Double>(-5.0, 40.0, -10.0),
            reactionMoment: SIMD3<Double>(4.0, -1.0, 2.0),
            referencePoint: .zero,
            nodeCount: 2
        )

        results.constraintReactions = [r1, r2]
        #expect(results.totalReactionForce == SIMD3<Double>(5.0, 60.0, 20.0))
        #expect(results.totalReactionMoment == SIMD3<Double>(5.0, 1.0, 5.0))
    }

    @Test func testSimulationSummaryEvaluatorWithTargets() {
        let node1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let node2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let node3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(20, 0, 0))
        let node4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(30, 0, 0))

        let el1 = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4])
        let el2 = VolumeMeshElement(id: 2, order: .linear, nodeIndices: [2, 3, 4, 1])

        let targetId1 = UUID()
        let targetId2 = UUID()

        let set1 = VolumeMeshSet(name: "BracketBody", nodeIds: [1, 2], elementIds: [1])
        let set2 = VolumeMeshSet(name: "ArmBody", nodeIds: [3, 4], elementIds: [2])

        let mesh = VolumeMesh(
            nodes: [node1, node2, node3, node4],
            elements: [el1, el2],
            sets: [set1, set2]
        )

        var study = SimulationStudy(name: "Multi-Body Study", studyType: .linearStatic)
        study.targets = [
            SimulationGeometryReference(targetId: targetId1, targetName: "BracketBody"),
            SimulationGeometryReference(targetId: targetId2, targetName: "ArmBody")
        ]

        let displacements: [Int: SIMD3<Double>] = [
            1: SIMD3<Double>(0.0, 0.0, 0.0),
            2: SIMD3<Double>(0.1, 0.0, 0.0),
            3: SIMD3<Double>(0.5, 0.0, 0.0),
            4: SIMD3<Double>(1.2, 0.0, 0.0)
        ]
        let stresses: [Int: Double] = [
            1: 50.0,
            2: 120.0,
            3: 200.0,
            4: 310.0
        ]
        let temperatures: [Int: Double] = [
            1: 25.0,
            2: 30.0,
            3: 65.0,
            4: 95.0
        ]
        let fosResult = FactorOfSafetyResult(
            nodalFactorsOfSafety: [
                1: 5.0,
                2: 2.5,
                3: 1.5,
                4: 1.1
            ]
        )

        let summaries = SimulationSummaryEvaluator.evaluateBodySummaries(
            study: study,
            mesh: mesh,
            nodalDisplacements: displacements,
            nodalVonMisesStresses: stresses,
            nodalTemperatures: temperatures,
            factorOfSafety: fosResult
        )

        #expect(summaries.count == 2)

        let b1 = summaries[0]
        #expect(b1.id == targetId1)
        #expect(b1.bodyName == "BracketBody")
        #expect(b1.nodeCount == 2)
        #expect(b1.elementCount == 1)
        #expect(b1.maxVonMisesStress == 120.0)
        #expect(b1.maxDisplacement == 0.1)
        #expect(b1.maxTemperature == 30.0)
        #expect(b1.minFactorOfSafety == 2.5)

        let b2 = summaries[1]
        #expect(b2.id == targetId2)
        #expect(b2.bodyName == "ArmBody")
        #expect(b2.nodeCount == 2)
        #expect(b2.elementCount == 1)
        #expect(b2.maxVonMisesStress == 310.0)
        #expect(b2.maxDisplacement == 1.2)
        #expect(b2.maxTemperature == 95.0)
        #expect(b2.minFactorOfSafety == 1.1)
    }

    @Test func testSimulationSummaryEvaluatorFullModelFallback() {
        let node1 = VolumeMeshNode(id: 1, position: .zero)
        let node2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0))
        let node3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0))
        let node4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 1))
        let el = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4])

        let mesh = VolumeMesh(nodes: [node1, node2, node3, node4], elements: [el])
        let study = SimulationStudy(name: "Single Body", studyType: .linearStatic)

        let summaries = SimulationSummaryEvaluator.evaluateBodySummaries(
            study: study,
            mesh: mesh,
            nodalDisplacements: [1: .zero, 2: SIMD3<Double>(0, 0.5, 0)],
            nodalVonMisesStresses: [1: 10.0, 2: 45.0]
        )

        #expect(summaries.count == 1)
        let body = summaries[0]
        #expect(body.bodyName == "Full Model")
        #expect(body.nodeCount == 4)
        #expect(body.elementCount == 1)
        #expect(body.maxVonMisesStress == 45.0)
        #expect(body.maxDisplacement == 0.5)
        #expect(body.extrema.count == 2)
    }
}
