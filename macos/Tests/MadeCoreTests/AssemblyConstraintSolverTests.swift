import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct AssemblyConstraintSolverTests {

    @Test func testUnconstrainedInstanceHasSixDOF() {
        let freeInstance = ComponentInstance(
            name: "Free Body",
            reference: .internalPart(name: "Cube"),
            transform: Transform(position: SIMD3<Float>(10, 20, 30))
        )
        let system = AssemblyConstraintSystem(instances: [freeInstance], constraints: [])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 6)
        #expect(result.instanceDOF[freeInstance.id] == 6)
        #expect(result.solvedTransforms[freeInstance.id]?.position == SIMD3<Float>(10, 20, 30))
    }

    @Test func testGroundedInstanceHasZeroDOF() {
        let groundedInstance = ComponentInstance(
            name: "Grounded Base",
            reference: .internalPart(name: "Base"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0)),
            isGrounded: true
        )
        let system = AssemblyConstraintSystem(instances: [groundedInstance], constraints: [])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 0)
        #expect(result.instanceDOF[groundedInstance.id] == 0)
    }

    @Test func testCoincidentMate() {
        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        let part = ComponentInstance(
            name: "Part",
            reference: .internalPart(name: "Part"),
            transform: Transform(position: SIMD3<Float>(15, -20, 35))
        )

        let targetWorldPos = SIMD3<Float>(5, 10, 15)
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: targetWorldPos)
        let fPart = AssemblyFeature(componentInstanceId: part.id, origin: .zero)
        let mate = AssemblyConstraint(
            kind: .coincident,
            firstFeature: fBase,
            secondFeature: fPart
        )

        let system = AssemblyConstraintSystem(instances: [base, part], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 3) // 3 translational constraints, leaves 3 rotational DOF
        #expect(result.instanceDOF[part.id] == 3)
        #expect(result.instanceDOF[base.id] == 0)

        guard let solvedPos = result.solvedTransforms[part.id]?.position else {
            Issue.record("Missing solved transform")
            return
        }
        #expect(abs(solvedPos.x - targetWorldPos.x) < 1e-3)
        #expect(abs(solvedPos.y - targetWorldPos.y) < 1e-3)
        #expect(abs(solvedPos.z - targetWorldPos.z) < 1e-3)
    }

    @Test func testConcentricMate() {
        let base = ComponentInstance(
            name: "Base Cylinder",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        let shaft = ComponentInstance(
            name: "Shaft",
            reference: .internalPart(name: "Shaft"),
            transform: Transform(
                position: SIMD3<Float>(20, 30, 40),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(10, -15, 20))
            )
        )

        // Base axis along +Z at (0, 0, 0)
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fShaft = AssemblyFeature(componentInstanceId: shaft.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let mate = AssemblyConstraint(
            kind: .concentric,
            firstFeature: fBase,
            secondFeature: fShaft
        )

        let system = AssemblyConstraintSystem(instances: [base, shaft], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 2) // Leaves 1 axial translation and 1 axial rotation
        #expect(result.instanceDOF[shaft.id] == 2)

        guard let solvedTransform = result.solvedTransforms[shaft.id] else {
            Issue.record("Missing solved transform")
            return
        }
        // Lateral position should be centered on base axis (x = 0, y = 0)
        #expect(abs(solvedTransform.position.x) < 1e-3)
        #expect(abs(solvedTransform.position.y) < 1e-3)

        // Solved axis should be parallel to Z axis
        let shaftAxis = solvedTransform.rotation.act(SIMD3<Float>(0, 0, 1))
        #expect(abs(shaftAxis.x) < 1e-3)
        #expect(abs(shaftAxis.y) < 1e-3)
        #expect(abs(abs(shaftAxis.z) - 1.0) < 1e-3)
    }

    @Test func testDistanceMate() {
        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        let block = ComponentInstance(
            name: "Block",
            reference: .internalPart(name: "Block"),
            transform: Transform(position: SIMD3<Float>(5, 0, 0))
        )

        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero)
        let fBlock = AssemblyFeature(componentInstanceId: block.id, origin: .zero)
        let mate = AssemblyConstraint(
            kind: .distance,
            firstFeature: fBase,
            secondFeature: fBlock,
            value: 25.0
        )

        let system = AssemblyConstraintSystem(instances: [base, block], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 5) // 1 distance constraint, leaves 5 DOF
        #expect(result.instanceDOF[block.id] == 5)

        guard let pos = result.solvedTransforms[block.id]?.position else {
            Issue.record("Missing solved transform")
            return
        }
        let dist = simd_length(pos)
        #expect(abs(dist - 25.0) < 1e-3)
    }

    @Test func testParallelMate() {
        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        let block = ComponentInstance(
            name: "Block",
            reference: .internalPart(name: "Block"),
            transform: Transform(
                position: .zero,
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(30, 45, 0))
            )
        )

        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 1, 0))
        let fBlock = AssemblyFeature(componentInstanceId: block.id, origin: .zero, axis: SIMD3<Float>(0, 1, 0))
        let mate = AssemblyConstraint(
            kind: .parallel,
            firstFeature: fBase,
            secondFeature: fBlock
        )

        let system = AssemblyConstraintSystem(instances: [base, block], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 4) // 2 angular constraints, leaves 3 translation + 1 rotation = 4 DOF
        #expect(result.instanceDOF[block.id] == 4)

        guard let rot = result.solvedTransforms[block.id]?.rotation else {
            Issue.record("Missing solved transform")
            return
        }
        let blockAxis = rot.act(SIMD3<Float>(0, 1, 0))
        #expect(abs(blockAxis.x) < 1e-3)
        #expect(abs(blockAxis.z) < 1e-3)
        #expect(abs(abs(blockAxis.y) - 1.0) < 1e-3)
    }

    @Test func testPerpendicularMate() {
        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        let arm = ComponentInstance(
            name: "Arm",
            reference: .internalPart(name: "Arm"),
            transform: Transform(
                position: .zero,
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(10, 20, 0))
            )
        )

        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fArm = AssemblyFeature(componentInstanceId: arm.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let mate = AssemblyConstraint(
            kind: .perpendicular,
            firstFeature: fBase,
            secondFeature: fArm
        )

        let system = AssemblyConstraintSystem(instances: [base, arm], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 5) // 1 angular constraint, leaves 5 DOF
        #expect(result.instanceDOF[arm.id] == 5)

        guard let rot = result.solvedTransforms[arm.id]?.rotation else {
            Issue.record("Missing solved transform")
            return
        }
        let armAxis = rot.act(SIMD3<Float>(0, 0, 1))
        let dot = simd_dot(armAxis, SIMD3<Float>(0, 0, 1))
        #expect(abs(dot) < 1e-3)
    }

    @Test func testAngleMate() {
        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        let arm = ComponentInstance(
            name: "Arm",
            reference: .internalPart(name: "Arm"),
            transform: Transform(
                position: .zero,
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(0, 15, 0))
            )
        )

        let targetAngle = Double.pi / 4.0 // 45 degrees
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(1, 0, 0))
        let fArm = AssemblyFeature(componentInstanceId: arm.id, origin: .zero, axis: SIMD3<Float>(1, 0, 0))
        let mate = AssemblyConstraint(
            kind: .angle,
            firstFeature: fBase,
            secondFeature: fArm,
            value: targetAngle
        )

        let system = AssemblyConstraintSystem(instances: [base, arm], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 5)
        #expect(result.instanceDOF[arm.id] == 5)

        guard let rot = result.solvedTransforms[arm.id]?.rotation else {
            Issue.record("Missing solved transform")
            return
        }
        let armAxis = rot.act(SIMD3<Float>(1, 0, 0))
        let dot = simd_dot(armAxis, SIMD3<Float>(1, 0, 0))
        let expectedDot = Float(cos(targetAngle))
        #expect(abs(dot - expectedDot) < 1e-3)
    }

    @Test func testFastenedMate() {
        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        let bracket = ComponentInstance(
            name: "Bracket",
            reference: .internalPart(name: "Bracket"),
            transform: Transform(
                position: SIMD3<Float>(30, -40, 50),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(25, -35, 45))
            )
        )

        let offset = SIMD3<Float>(100, 200, 300)
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: offset)
        let fBracket = AssemblyFeature(componentInstanceId: bracket.id, origin: .zero)
        let mate = AssemblyConstraint(
            kind: .fastened,
            firstFeature: fBase,
            secondFeature: fBracket
        )

        let system = AssemblyConstraintSystem(instances: [base, bracket], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 0) // Fully constrained, 0 DOF
        #expect(result.instanceDOF[bracket.id] == 0)
        #expect(result.instanceDOF[base.id] == 0)

        guard let solvedTransform = result.solvedTransforms[bracket.id] else {
            Issue.record("Missing solved transform")
            return
        }
        #expect(abs(solvedTransform.position.x - offset.x) < 1e-3)
        #expect(abs(solvedTransform.position.y - offset.y) < 1e-3)
        #expect(abs(solvedTransform.position.z - offset.z) < 1e-3)
    }

    @Test func testRedundantConstraintsDetected() {
        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        let arm = ComponentInstance(
            name: "Arm",
            reference: .internalPart(name: "Arm"),
            transform: Transform(position: SIMD3<Float>(5, 0, 0))
        )

        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fArm = AssemblyFeature(componentInstanceId: arm.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))

        let mate1 = AssemblyConstraint(kind: .parallel, firstFeature: fBase, secondFeature: fArm)
        let mate2 = AssemblyConstraint(kind: .parallel, firstFeature: fBase, secondFeature: fArm)

        let system = AssemblyConstraintSystem(instances: [base, arm], constraints: [mate1, mate2])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        if case .redundant(let redundantIds) = result.status {
            #expect(!redundantIds.isEmpty)
            #expect(redundantIds.contains(mate1.id) || redundantIds.contains(mate2.id))
        } else {
            Issue.record("Expected .redundant status, got: \(result.status)")
        }
    }

    @Test func testConflictingConstraintsDiagnosed() {
        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "Base"),
            transform: .identity,
            isGrounded: true
        )
        let block = ComponentInstance(
            name: "Block",
            reference: .internalPart(name: "Block"),
            transform: Transform(position: SIMD3<Float>(5, 0, 0))
        )

        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero)
        let fBlock = AssemblyFeature(componentInstanceId: block.id, origin: .zero)

        let mate1 = AssemblyConstraint(kind: .distance, firstFeature: fBase, secondFeature: fBlock, value: 10.0)
        let mate2 = AssemblyConstraint(kind: .distance, firstFeature: fBase, secondFeature: fBlock, value: 30.0)

        let system = AssemblyConstraintSystem(instances: [base, block], constraints: [mate1, mate2])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(!result.status.isConverged)
        if case .overConstrained(let conflictingIds) = result.status {
            #expect(!conflictingIds.isEmpty)
            #expect(conflictingIds.contains(mate1.id) || conflictingIds.contains(mate2.id))
        } else {
            Issue.record("Expected .overConstrained status, got: \(result.status)")
        }
    }

    @Test func testMultiBodyKinematicChain() {
        let ground = ComponentInstance(name: "Ground", reference: .internalPart(name: "P0"), transform: .identity, isGrounded: true)
        let link1 = ComponentInstance(name: "Link1", reference: .internalPart(name: "P1"), transform: Transform(position: SIMD3<Float>(5, 0, 0)))
        let link2 = ComponentInstance(name: "Link2", reference: .internalPart(name: "P2"), transform: Transform(position: SIMD3<Float>(12, 0, 0)))

        // Joint 1: Ground to Link1 fastened at (10, 0, 0)
        let j1 = AssemblyConstraint(
            kind: .fastened,
            firstFeature: AssemblyFeature(componentInstanceId: ground.id, origin: SIMD3<Float>(10, 0, 0)),
            secondFeature: AssemblyFeature(componentInstanceId: link1.id, origin: .zero)
        )
        // Joint 2: Link1 to Link2 fastened at (20, 0, 0) relative to Link1
        let j2 = AssemblyConstraint(
            kind: .fastened,
            firstFeature: AssemblyFeature(componentInstanceId: link1.id, origin: SIMD3<Float>(20, 0, 0)),
            secondFeature: AssemblyFeature(componentInstanceId: link2.id, origin: .zero)
        )

        let system = AssemblyConstraintSystem(instances: [ground, link1, link2], constraints: [j1, j2])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 0)
        #expect(result.instanceDOF[link1.id] == 0)
        #expect(result.instanceDOF[link2.id] == 0)

        guard let p1 = result.solvedTransforms[link1.id]?.position,
              let p2 = result.solvedTransforms[link2.id]?.position else {
            Issue.record("Missing solved transforms")
            return
        }
        #expect(abs(p1.x - 10.0) < 1e-3)
        #expect(abs(p2.x - 30.0) < 1e-3)
    }

    @Test func testAssemblyConstraintSolverActor() async {
        let actor = AssemblyConstraintSolverActor()

        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let part = ComponentInstance(name: "Part", reference: .internalPart(name: "Part"), transform: Transform(position: SIMD3<Float>(10, 10, 10)))
        let mate = AssemblyConstraint(
            kind: .coincident,
            firstFeature: AssemblyFeature(componentInstanceId: base.id, origin: .zero),
            secondFeature: AssemblyFeature(componentInstanceId: part.id, origin: .zero)
        )

        let system = AssemblyConstraintSystem(instances: [base, part], constraints: [mate])
        let result = await actor.solve(system: system)
        #expect(result.status.isConverged)
        #expect(result.totalDOF == 3)

        let dof = await actor.computeSystemDOF(system: system)
        #expect(dof.totalDOF == 3)
        #expect(dof.instanceDOF[part.id] == 3)
    }
}
