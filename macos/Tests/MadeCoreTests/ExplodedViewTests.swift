import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct ExplodedViewTests {

    @Test func testDefaultValuesAndInitialization() {
        let defaultStep = ExplodeStep()
        #expect(defaultStep.name == "Explode Step")
        #expect(defaultStep.targetInstanceIds.isEmpty)
        #expect(defaultStep.direction == SIMD3<Float>(0, 0, 1))
        #expect(defaultStep.distance == 50.0)
        #expect(defaultStep.hasTrail == true)
        #expect(defaultStep.translation == SIMD3<Float>(0, 0, 50.0))

        let trailId = UUID()
        let stepId = UUID()
        let instanceId = UUID()
        let trail = ExplodeTrail(
            id: trailId,
            stepId: stepId,
            instanceId: instanceId,
            startPoint: SIMD3<Float>(1, 2, 3),
            endPoint: SIMD3<Float>(4, 5, 6),
            isVisible: true
        )
        #expect(trail.id == trailId)
        #expect(trail.stepId == stepId)
        #expect(trail.instanceId == instanceId)
        #expect(trail.startPoint == SIMD3<Float>(1, 2, 3))
        #expect(trail.endPoint == SIMD3<Float>(4, 5, 6))
        #expect(trail.isVisible == true)

        let defaultView = ExplodedView()
        #expect(defaultView.name == "Exploded View")
        #expect(defaultView.steps.isEmpty)
        #expect(!defaultView.isCollapsed)
    }

    @Test func testTranslationCalculationFromDirectionAndDistance() {
        let stepX = ExplodeStep(
            direction: SIMD3<Float>(10, 0, 0),
            distance: 75.0
        )
        #expect(abs(stepX.translation.x - 75.0) < 1e-5)
        #expect(abs(stepX.translation.y) < 1e-5)
        #expect(abs(stepX.translation.z) < 1e-5)

        let stepDiag = ExplodeStep(
            direction: SIMD3<Float>(1, 1, 0),
            distance: 100.0
        )
        let expectedDiag = Float(100.0 / sqrt(2.0))
        #expect(abs(stepDiag.translation.x - expectedDiag) < 1e-4)
        #expect(abs(stepDiag.translation.y - expectedDiag) < 1e-4)
        #expect(abs(stepDiag.translation.z) < 1e-4)
    }

    @Test func testZeroLengthDirectionHandling() {
        let stepZero = ExplodeStep(
            direction: SIMD3<Float>(0, 0, 0),
            distance: 100.0
        )
        #expect(stepZero.translation == .zero)

        let stepNearZero = ExplodeStep(
            direction: SIMD3<Float>(1e-8, 1e-8, 1e-8),
            distance: 100.0
        )
        #expect(stepNearZero.translation == .zero)
    }

    @Test func testCumulativeDisplacementsAcrossSteps() {
        let comp1 = UUID()
        let comp2 = UUID()

        let step1 = ExplodeStep(
            targetInstanceIds: [comp1],
            direction: SIMD3<Float>(1, 0, 0),
            distance: 20.0
        )
        let step2 = ExplodeStep(
            targetInstanceIds: [comp1, comp2],
            direction: SIMD3<Float>(0, 1, 0),
            distance: 30.0
        )
        let step3 = ExplodeStep(
            targetInstanceIds: [comp2],
            direction: SIMD3<Float>(0, 0, 1),
            distance: 40.0
        )

        let view = ExplodedView(
            name: "Test Exploded View",
            steps: [step1, step2, step3]
        )

        let displacements = view.cumulativeDisplacements()
        #expect(displacements.count == 2)

        let disp1 = displacements[comp1] ?? .zero
        #expect(abs(disp1.x - 20.0) < 1e-5)
        #expect(abs(disp1.y - 30.0) < 1e-5)
        #expect(abs(disp1.z) < 1e-5)

        let disp2 = displacements[comp2] ?? .zero
        #expect(abs(disp2.x) < 1e-5)
        #expect(abs(disp2.y - 30.0) < 1e-5)
        #expect(abs(disp2.z - 40.0) < 1e-5)
    }

    @Test func testTransformedPosition() {
        let compId = UUID()
        let step = ExplodeStep(
            targetInstanceIds: [compId],
            direction: SIMD3<Float>(0, 0, 1),
            distance: 45.0
        )
        let view = ExplodedView(steps: [step])

        let baseTransform = Transform(position: SIMD3<Float>(10, 20, 30))
        let transformed = view.transformedPosition(for: compId, baseTransform: baseTransform)
        #expect(transformed.position == SIMD3<Float>(10, 20, 75))

        let otherId = UUID()
        let untargeted = view.transformedPosition(for: otherId, baseTransform: baseTransform)
        #expect(untargeted.position == SIMD3<Float>(10, 20, 30))
    }

    @Test func testComputeTrails() {
        let comp1Id = UUID()
        let comp2Id = UUID()

        let inst1 = ComponentInstance(
            id: comp1Id,
            name: "Part 1",
            reference: .internalPart(name: "P1"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        let inst2 = ComponentInstance(
            id: comp2Id,
            name: "Part 2",
            reference: .internalPart(name: "P2"),
            transform: Transform(position: SIMD3<Float>(50, 0, 0))
        )

        let step1 = ExplodeStep(
            targetInstanceIds: [comp1Id],
            direction: SIMD3<Float>(0, 0, 1),
            distance: 100.0,
            hasTrail: true
        )
        let step2 = ExplodeStep(
            targetInstanceIds: [comp1Id],
            direction: SIMD3<Float>(0, 1, 0),
            distance: 50.0,
            hasTrail: true
        )
        let step3 = ExplodeStep(
            targetInstanceIds: [comp2Id],
            direction: SIMD3<Float>(1, 0, 0),
            distance: 30.0,
            hasTrail: false
        )
        let step4 = ExplodeStep(
            targetInstanceIds: [comp2Id],
            direction: SIMD3<Float>(0, 0, 1),
            distance: 25.0,
            hasTrail: true
        )

        let view = ExplodedView(steps: [step1, step2, step3, step4])
        let trails = view.computeTrails(instances: [inst1, inst2])

        // step3 has hasTrail == false, so 3 trails expected: step1(comp1), step2(comp1), step4(comp2)
        #expect(trails.count == 3)

        // Trail 1: comp1 from (0, 0, 0) to (0, 0, 100)
        #expect(trails[0].instanceId == comp1Id)
        #expect(trails[0].stepId == step1.id)
        #expect(trails[0].startPoint == SIMD3<Float>(0, 0, 0))
        #expect(trails[0].endPoint == SIMD3<Float>(0, 0, 100))

        // Trail 2: comp1 from (0, 0, 100) to (0, 50, 100)
        #expect(trails[1].instanceId == comp1Id)
        #expect(trails[1].stepId == step2.id)
        #expect(trails[1].startPoint == SIMD3<Float>(0, 0, 100))
        #expect(trails[1].endPoint == SIMD3<Float>(0, 50, 100))

        // Trail 3: comp2 from (80, 0, 0) to (80, 0, 25) because step3 displaced it by 30 in X
        #expect(trails[2].instanceId == comp2Id)
        #expect(trails[2].stepId == step4.id)
        #expect(abs(trails[2].startPoint.x - 80.0) < 1e-5)
        #expect(abs(trails[2].startPoint.y) < 1e-5)
        #expect(abs(trails[2].startPoint.z) < 1e-5)
        #expect(abs(trails[2].endPoint.x - 80.0) < 1e-5)
        #expect(abs(trails[2].endPoint.y) < 1e-5)
        #expect(abs(trails[2].endPoint.z - 25.0) < 1e-5)
    }

    @Test func testCodableRoundTrip() throws {
        let step = ExplodeStep(
            name: "Pull Out",
            targetInstanceIds: [UUID(), UUID()],
            direction: SIMD3<Float>(0, 1, 0),
            distance: 60.0,
            hasTrail: true
        )
        let original = ExplodedView(
            name: "Main Explode",
            steps: [step],
            isCollapsed: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExplodedView.self, from: data)

        #expect(decoded == original)
    }
}
