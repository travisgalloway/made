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

    @Test func testTangentMateCylinderToPlane() {
        let base = ComponentInstance(name: "Base Plane", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let cyl = ComponentInstance(
            name: "Cylinder",
            reference: .internalPart(name: "Cyl"),
            transform: Transform(
                position: SIMD3<Float>(0, 0, 25),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(0, 10, 0))
            )
        )

        // Cylinder axis along +X, plane normal along +Z at z=0, radius offset 10mm
        let fPlane = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fCyl = AssemblyFeature(componentInstanceId: cyl.id, origin: .zero, axis: SIMD3<Float>(1, 0, 0))
        let mate = AssemblyConstraint(kind: .tangent, firstFeature: fCyl, secondFeature: fPlane, value: 10.0)

        let system = AssemblyConstraintSystem(instances: [base, cyl], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 4) // 2 constraints, leaves 4 DOF
        #expect(result.instanceDOF[cyl.id] == 4)

        guard let solvedPos = result.solvedTransforms[cyl.id]?.position,
              let solvedRot = result.solvedTransforms[cyl.id]?.rotation else {
            Issue.record("Missing solved transform")
            return
        }
        #expect(abs(solvedPos.z - 10.0) < 1e-3)
        let cylAxis = solvedRot.act(SIMD3<Float>(1, 0, 0))
        #expect(abs(simd_dot(cylAxis, SIMD3<Float>(0, 0, 1))) < 1e-3)
    }

    @Test func testTangentMateSphereToPlane() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let sphere = ComponentInstance(name: "Sphere", reference: .internalPart(name: "Sphere"), transform: Transform(position: SIMD3<Float>(10, 20, 50)))

        // Plane normal along +Z, sphere origin-only feature, radius offset 15mm
        let fPlane = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fSphere = AssemblyFeature(componentInstanceId: sphere.id, origin: .zero)
        let mate = AssemblyConstraint(kind: .tangent, firstFeature: fSphere, secondFeature: fPlane, value: 15.0)

        let system = AssemblyConstraintSystem(instances: [base, sphere], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 5) // 1 constraint, leaves 5 DOF
        #expect(result.instanceDOF[sphere.id] == 5)

        guard let solvedPos = result.solvedTransforms[sphere.id]?.position else {
            Issue.record("Missing solved transform")
            return
        }
        #expect(abs(solvedPos.z - 15.0) < 1e-3)
    }

    @Test func testRevoluteJoint() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let arm = ComponentInstance(
            name: "Arm",
            reference: .internalPart(name: "Arm"),
            transform: Transform(
                position: SIMD3<Float>(20, 30, 40),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(15, -20, 30))
            )
        )

        // Rotation around +Z axis at (0, 0, 0)
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fArm = AssemblyFeature(componentInstanceId: arm.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let joint = AssemblyConstraint(kind: .revolute, firstFeature: fBase, secondFeature: fArm)

        let system = AssemblyConstraintSystem(instances: [base, arm], constraints: [joint])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 1) // 5 constraints, leaves 1 rotational DOF
        #expect(result.instanceDOF[arm.id] == 1)

        guard let solvedTransform = result.solvedTransforms[arm.id] else {
            Issue.record("Missing solved transform")
            return
        }
        #expect(abs(solvedTransform.position.x) < 1e-3)
        #expect(abs(solvedTransform.position.y) < 1e-3)
        #expect(abs(solvedTransform.position.z) < 1e-3)

        let armAxis = solvedTransform.rotation.act(SIMD3<Float>(0, 0, 1))
        #expect(abs(armAxis.x) < 1e-3)
        #expect(abs(armAxis.y) < 1e-3)
        #expect(abs(armAxis.z - 1.0) < 1e-3)
    }

    @Test func testSliderJoint() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let carriage = ComponentInstance(
            name: "Carriage",
            reference: .internalPart(name: "Carriage"),
            transform: Transform(
                position: SIMD3<Float>(10, 25, -30),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(10, -15, 20))
            )
        )

        // Prismatic slider along +X axis
        let fBase = AssemblyFeature(
            componentInstanceId: base.id,
            localOrigin: .zero,
            localAxis: SIMD3<Float>(1, 0, 0),
            localSecondaryAxis: SIMD3<Float>(0, 1, 0)
        )
        let fCarriage = AssemblyFeature(
            componentInstanceId: carriage.id,
            localOrigin: .zero,
            localAxis: SIMD3<Float>(1, 0, 0),
            localSecondaryAxis: SIMD3<Float>(0, 1, 0)
        )
        let joint = AssemblyConstraint(kind: .slider, firstFeature: fBase, secondFeature: fCarriage)

        let system = AssemblyConstraintSystem(instances: [base, carriage], constraints: [joint])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 1) // 5 constraints, leaves 1 translational DOF along X
        #expect(result.instanceDOF[carriage.id] == 1)

        guard let solvedTransform = result.solvedTransforms[carriage.id] else {
            Issue.record("Missing solved transform")
            return
        }
        // Lateral displacement on Y and Z must be zero
        #expect(abs(solvedTransform.position.y) < 1e-3)
        #expect(abs(solvedTransform.position.z) < 1e-3)

        // Rotation must align with base frame
        let axisX = solvedTransform.rotation.act(SIMD3<Float>(1, 0, 0))
        let axisY = solvedTransform.rotation.act(SIMD3<Float>(0, 1, 0))
        #expect(abs(axisX.x - 1.0) < 1e-3)
        #expect(abs(axisY.y - 1.0) < 1e-3)
    }

    @Test func testCylindricalJoint() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let shaft = ComponentInstance(
            name: "Shaft",
            reference: .internalPart(name: "Shaft"),
            transform: Transform(
                position: SIMD3<Float>(30, 40, 50),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(20, 10, -15))
            )
        )

        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fShaft = AssemblyFeature(componentInstanceId: shaft.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let joint = AssemblyConstraint(kind: .cylindrical, firstFeature: fBase, secondFeature: fShaft)

        let system = AssemblyConstraintSystem(instances: [base, shaft], constraints: [joint])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 2) // 4 constraints, leaves 1 axial translation + 1 axial rotation
        #expect(result.instanceDOF[shaft.id] == 2)

        guard let solvedTransform = result.solvedTransforms[shaft.id] else {
            Issue.record("Missing solved transform")
            return
        }
        #expect(abs(solvedTransform.position.x) < 1e-3)
        #expect(abs(solvedTransform.position.y) < 1e-3)
        let shaftAxis = solvedTransform.rotation.act(SIMD3<Float>(0, 0, 1))
        #expect(abs(shaftAxis.z - 1.0) < 1e-3)
    }

    @Test func testPinSlotJoint() {
        let plate = ComponentInstance(name: "Plate", reference: .internalPart(name: "Plate"), transform: .identity, isGrounded: true)
        let pin = ComponentInstance(
            name: "Pin",
            reference: .internalPart(name: "Pin"),
            transform: Transform(
                position: SIMD3<Float>(15, 30, 20),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(10, -20, 15))
            )
        )

        // Slot plane normal +Z, slot length along +X
        let fSlot = AssemblyFeature(
            componentInstanceId: plate.id,
            localOrigin: .zero,
            localAxis: SIMD3<Float>(0, 0, 1),
            localSecondaryAxis: SIMD3<Float>(1, 0, 0)
        )
        // Pin axis along +Z
        let fPin = AssemblyFeature(
            componentInstanceId: pin.id,
            localOrigin: .zero,
            localAxis: SIMD3<Float>(0, 0, 1),
            localSecondaryAxis: SIMD3<Float>(1, 0, 0)
        )
        let joint = AssemblyConstraint(kind: .pinSlot, firstFeature: fSlot, secondFeature: fPin)

        let system = AssemblyConstraintSystem(instances: [plate, pin], constraints: [joint])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 2) // 4 constraints, leaves 1 slot translation (X) + 1 pin rotation (Z)
        #expect(result.instanceDOF[pin.id] == 2)

        guard let solvedTransform = result.solvedTransforms[pin.id] else {
            Issue.record("Missing solved transform")
            return
        }
        // Pin center must be in slot midline: Y = 0 (transverse width), Z = 0 (normal out of plane)
        #expect(abs(solvedTransform.position.y) < 1e-3)
        #expect(abs(solvedTransform.position.z) < 1e-3)
        // Pin axis aligns with slot normal
        let pinAxis = solvedTransform.rotation.act(SIMD3<Float>(0, 0, 1))
        #expect(abs(pinAxis.z - 1.0) < 1e-3)
    }

    @Test func testPlanarJoint() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let puck = ComponentInstance(
            name: "Puck",
            reference: .internalPart(name: "Puck"),
            transform: Transform(
                position: SIMD3<Float>(10, 20, 50),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(15, 25, 0))
            )
        )

        // Planar mate with 5mm offset along +Z
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fPuck = AssemblyFeature(componentInstanceId: puck.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let joint = AssemblyConstraint(kind: .planar, firstFeature: fBase, secondFeature: fPuck, value: 5.0)

        let system = AssemblyConstraintSystem(instances: [base, puck], constraints: [joint])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 3) // 3 constraints, leaves 2 planar translations + 1 normal rotation
        #expect(result.instanceDOF[puck.id] == 3)

        guard let solvedTransform = result.solvedTransforms[puck.id] else {
            Issue.record("Missing solved transform")
            return
        }
        #expect(abs(solvedTransform.position.z - 5.0) < 1e-3)
        let puckAxis = solvedTransform.rotation.act(SIMD3<Float>(0, 0, 1))
        #expect(abs(puckAxis.z - 1.0) < 1e-3)
    }

    @Test func testBallJoint() {
        let socket = ComponentInstance(name: "Socket", reference: .internalPart(name: "Socket"), transform: .identity, isGrounded: true)
        let ball = ComponentInstance(
            name: "Ball",
            reference: .internalPart(name: "Ball"),
            transform: Transform(
                position: SIMD3<Float>(40, -50, 60),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(30, 45, 60))
            )
        )

        let targetPos = SIMD3<Float>(10, 20, 30)
        let fSocket = AssemblyFeature(componentInstanceId: socket.id, origin: targetPos)
        let fBall = AssemblyFeature(componentInstanceId: ball.id, origin: .zero)
        let joint = AssemblyConstraint(kind: .ball, firstFeature: fSocket, secondFeature: fBall)

        let system = AssemblyConstraintSystem(instances: [socket, ball], constraints: [joint])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 3) // 3 translation constraints, leaves 3 rotational DOFs
        #expect(result.instanceDOF[ball.id] == 3)

        guard let solvedPos = result.solvedTransforms[ball.id]?.position else {
            Issue.record("Missing solved transform")
            return
        }
        #expect(abs(solvedPos.x - targetPos.x) < 1e-3)
        #expect(abs(solvedPos.y - targetPos.y) < 1e-3)
        #expect(abs(solvedPos.z - targetPos.z) < 1e-3)
    }

    @Test func testKinematicChainWithMixedJoints() {
        // Ground -> Revolute -> Link1 -> Slider -> Link2
        let ground = ComponentInstance(name: "Ground", reference: .internalPart(name: "G"), transform: .identity, isGrounded: true)
        let link1 = ComponentInstance(name: "Link1", reference: .internalPart(name: "L1"), transform: Transform(position: SIMD3<Float>(5, 5, 5)))
        let link2 = ComponentInstance(name: "Link2", reference: .internalPart(name: "L2"), transform: Transform(position: SIMD3<Float>(20, 20, 20)))

        // Joint 1: Revolute around +Z at (10, 0, 0)
        let j1 = AssemblyConstraint(
            kind: .revolute,
            firstFeature: AssemblyFeature(componentInstanceId: ground.id, origin: SIMD3<Float>(10, 0, 0), axis: SIMD3<Float>(0, 0, 1)),
            secondFeature: AssemblyFeature(componentInstanceId: link1.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        )
        // Joint 2: Slider along +X relative to Link1
        let j2 = AssemblyConstraint(
            kind: .slider,
            firstFeature: AssemblyFeature(
                componentInstanceId: link1.id,
                localOrigin: SIMD3<Float>(20, 0, 0),
                localAxis: SIMD3<Float>(1, 0, 0),
                localSecondaryAxis: SIMD3<Float>(0, 1, 0)
            ),
            secondFeature: AssemblyFeature(
                componentInstanceId: link2.id,
                localOrigin: .zero,
                localAxis: SIMD3<Float>(1, 0, 0),
                localSecondaryAxis: SIMD3<Float>(0, 1, 0)
            )
        )

        let system = AssemblyConstraintSystem(instances: [ground, link1, link2], constraints: [j1, j2])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        // Link1 has 1 rotational DOF, Link2 has 1 translational DOF along link1 axis -> total DOF = 2
        #expect(result.totalDOF == 2)
        #expect(result.instanceDOF[link1.id] == 1)
        #expect(result.instanceDOF[link2.id] == 2)
    }

    @Test func testZeroLengthAndUnnormalizedFeatureAxesHandledSafely() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let arm = ComponentInstance(name: "Arm", reference: .internalPart(name: "Arm"), transform: Transform(position: SIMD3<Float>(5, 0, 0)))

        // Zero-length axis and huge unnormalized axis
        let fZero = AssemblyFeature(componentInstanceId: base.id, localOrigin: .zero, localAxis: SIMD3<Float>(0, 0, 0), localSecondaryAxis: .zero)
        let fUnnorm = AssemblyFeature(componentInstanceId: arm.id, localOrigin: .zero, localAxis: SIMD3<Float>(0, 0, 50), localSecondaryAxis: SIMD3<Float>(100, 0, 0))
        let mate = AssemblyConstraint(kind: .parallel, firstFeature: fZero, secondFeature: fUnnorm)

        let system = AssemblyConstraintSystem(instances: [base, arm], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(!result.solvedTransforms.isEmpty)
    }

    // MARK: - Under-Constrained Drag Solver Tests (BL-ASM-06)

    @Test func testDragTargetRespectsPlanarMate() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let slider = ComponentInstance(
            name: "Slider",
            reference: .internalPart(name: "Slider"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        // Planar joint constraining Z to 0 (normal along +Z)
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fSlider = AssemblyFeature(componentInstanceId: slider.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let joint = AssemblyConstraint(kind: .planar, firstFeature: fBase, secondFeature: fSlider, value: 0.0)

        // Drag target wants to move to (25, 40, 100) - an out-of-plane deviation of 100 on Z
        let dragTarget = AssemblyDragTarget(
            instanceId: slider.id,
            targetPosition: SIMD3<Float>(25, 40, 100),
            weight: 1.0
        )
        let system = AssemblyConstraintSystem(instances: [base, slider], constraints: [joint])
        let result = AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)

        #expect(result.status.isConverged)
        guard let solved = result.solvedTransforms[slider.id] else {
            Issue.record("Missing solved transform")
            return
        }
        // In-plane translations (X and Y) follow the drag target
        #expect(abs(solved.position.x - 25) < 1.0)
        #expect(abs(solved.position.y - 40) < 1.0)
        // Out-of-plane translation Z is strictly constrained to 0
        #expect(abs(solved.position.z) < 1e-3)
    }

    @Test func testDragTargetRespectsRevoluteJoint() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let arm = ComponentInstance(
            name: "Arm",
            reference: .internalPart(name: "Arm"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        // Revolute joint at origin around +Z axis
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let fArm = AssemblyFeature(componentInstanceId: arm.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        let joint = AssemblyConstraint(kind: .revolute, firstFeature: fBase, secondFeature: fArm)

        // Drag target wants to rotate 45 degrees around Z, but also shift position to (50, 50, 50)
        let targetRot = simd_quatf(angle: Float.pi / 4.0, axis: SIMD3<Float>(0, 0, 1))
        let dragTarget = AssemblyDragTarget(
            instanceId: arm.id,
            targetPosition: SIMD3<Float>(50, 50, 50),
            targetRotation: targetRot,
            weight: 1.0
        )
        let system = AssemblyConstraintSystem(instances: [base, arm], constraints: [joint])
        let result = AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)

        #expect(result.status.isConverged)
        guard let solved = result.solvedTransforms[arm.id] else {
            Issue.record("Missing solved transform")
            return
        }
        // Origin remains pinned at (0, 0, 0)
        #expect(abs(solved.position.x) < 1e-3)
        #expect(abs(solved.position.y) < 1e-3)
        #expect(abs(solved.position.z) < 1e-3)

        // Rotation around Z rotated toward target
        let armX = solved.rotation.act(SIMD3<Float>(1, 0, 0))
        let expectedX = targetRot.act(SIMD3<Float>(1, 0, 0))
        #expect(abs(armX.x - expectedX.x) < 1e-2)
        #expect(abs(armX.y - expectedX.y) < 1e-2)
    }

    @Test func testDragTargetArticulatesKinematicChain() {
        // Multi-link chain: Ground -> Link1 (revolute at (0,0,0) around Z) -> Link2 (revolute at (10,0,0) on Link1 around Z)
        let ground = ComponentInstance(name: "Ground", reference: .internalPart(name: "G"), transform: .identity, isGrounded: true)
        let link1 = ComponentInstance(name: "Link1", reference: .internalPart(name: "L1"), transform: .identity)
        let link2 = ComponentInstance(name: "Link2", reference: .internalPart(name: "L2"), transform: Transform(position: SIMD3<Float>(10, 0, 0)))

        let j1 = AssemblyConstraint(
            kind: .revolute,
            firstFeature: AssemblyFeature(componentInstanceId: ground.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1)),
            secondFeature: AssemblyFeature(componentInstanceId: link1.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1))
        )
        let j2 = AssemblyConstraint(
            kind: .revolute,
            firstFeature: AssemblyFeature(componentInstanceId: link1.id, localOrigin: SIMD3<Float>(10, 0, 0), localAxis: SIMD3<Float>(0, 0, 1)),
            secondFeature: AssemblyFeature(componentInstanceId: link2.id, localOrigin: .zero, localAxis: SIMD3<Float>(0, 0, 1))
        )

        // Drag end-effector Link2 towards (0, 10, 0) - requires Link1 to rotate by 90 degrees
        let dragTarget = AssemblyDragTarget(
            instanceId: link2.id,
            targetPosition: SIMD3<Float>(0, 10, 0),
            weight: 1.0
        )
        let system = AssemblyConstraintSystem(instances: [ground, link1, link2], constraints: [j1, j2])
        let result = AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)

        #expect(result.status.isConverged)
        guard let solvedL1 = result.solvedTransforms[link1.id],
              let solvedL2 = result.solvedTransforms[link2.id] else {
            Issue.record("Missing solved transforms")
            return
        }
        // Link1 articulated around Z
        let l1Rot = solvedL1.rotation.eulerAnglesDegrees
        #expect(abs(l1Rot.z) > 1.0)
        // Joint 2 origin remains connected: solvedL2 position matches link1 tip
        let expectedL2Origin = solvedL1.rotation.act(SIMD3<Float>(10, 0, 0)) + solvedL1.position
        #expect(abs(solvedL2.position.x - expectedL2Origin.x) < 1e-3)
        #expect(abs(solvedL2.position.y - expectedL2Origin.y) < 1e-3)
        #expect(abs(solvedL2.position.z - expectedL2Origin.z) < 1e-3)
    }

    @Test func testDragTargetOnGroundedComponentIgnored() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let dragTarget = AssemblyDragTarget(
            instanceId: base.id,
            targetPosition: SIMD3<Float>(100, 200, 300),
            weight: 1.0
        )
        let system = AssemblyConstraintSystem(instances: [base], constraints: [])
        let result = AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)

        #expect(result.status.isConverged)
        #expect(result.solvedTransforms[base.id]?.position == SIMD3<Float>(0, 0, 0))
    }

    @Test func testDragTargetOnFullyConstrainedComponentMaintainsMates() {
        let base = ComponentInstance(name: "Base", reference: .internalPart(name: "Base"), transform: .identity, isGrounded: true)
        let part = ComponentInstance(name: "Part", reference: .internalPart(name: "Part"), transform: Transform(position: SIMD3<Float>(10, 0, 0)))

        // Fastened mate locks all 6 DOFs relative to base
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: SIMD3<Float>(10, 0, 0))
        let fPart = AssemblyFeature(componentInstanceId: part.id, origin: .zero)
        let mate = AssemblyConstraint(kind: .fastened, firstFeature: fBase, secondFeature: fPart)

        // Attempting to drag locked component away to (100, 200, 300)
        let dragTarget = AssemblyDragTarget(
            instanceId: part.id,
            targetPosition: SIMD3<Float>(100, 200, 300),
            weight: 1.0
        )
        let system = AssemblyConstraintSystem(instances: [base, part], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 0)
        guard let solvedPos = result.solvedTransforms[part.id]?.position else {
            Issue.record("Missing solved transform")
            return
        }
        // Part remains locked at (10, 0, 0)
        #expect(abs(solvedPos.x - 10) < 1e-3)
        #expect(abs(solvedPos.y) < 1e-3)
        #expect(abs(solvedPos.z) < 1e-3)
    }

    @Test func testDragTargetWithZeroConstraintsMovesFreeInstance() {
        let free = ComponentInstance(name: "Free", reference: .internalPart(name: "Part"), transform: .identity)
        let targetPos = SIMD3<Float>(15, -25, 35)
        let targetRot = simd_quatf(angle: Float.pi / 3.0, axis: SIMD3<Float>(0, 1, 0))
        let dragTarget = AssemblyDragTarget(
            instanceId: free.id,
            targetPosition: targetPos,
            targetRotation: targetRot
        )
        let system = AssemblyConstraintSystem(instances: [free], constraints: [])
        let result = AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)

        #expect(result.status.isConverged)
        #expect(result.totalDOF == 6)
        guard let solved = result.solvedTransforms[free.id] else {
            Issue.record("Missing solved transform")
            return
        }
        #expect(abs(solved.position.x - targetPos.x) < 1e-3)
        #expect(abs(solved.position.y - targetPos.y) < 1e-3)
        #expect(abs(solved.position.z - targetPos.z) < 1e-3)
        #expect(abs(solved.rotation.real - targetRot.real) < 1e-3)
    }

    // MARK: - Subassemblies (BL-ASM-07)

    @Test func testRigidSubassemblySolvesAsSingleRigidBody() {
        let base = ComponentInstance(
            name: "Base",
            reference: .internalPart(name: "BasePart"),
            transform: .identity,
            isGrounded: true
        )

        // Subassembly contains Child1 at (0, 0, 0) and Child2 at (10, 0, 0) relative to subassembly
        let child1 = ComponentInstance(
            name: "Child 1",
            reference: .internalPart(name: "Child1Part"),
            transform: .identity
        )
        let child2 = ComponentInstance(
            name: "Child 2",
            reference: .internalPart(name: "Child2Part"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0))
        )
        let sub = ComponentInstance(
            name: "RigidSub",
            reference: .subassembly(name: "RigidSub"),
            transform: Transform(position: SIMD3<Float>(50, 50, 0)),
            subassemblyBehavior: .rigid,
            childInstances: [child1, child2]
        )

        // Mate in parent assembly: Child1 coincident with Base at (5, 5, 5)
        let targetPos = SIMD3<Float>(5, 5, 5)
        let fBase = AssemblyFeature(componentInstanceId: base.id, origin: targetPos)
        let fChild1 = AssemblyFeature(componentInstanceId: child1.id, origin: .zero)
        let mate = AssemblyConstraint(
            kind: .coincident,
            firstFeature: fBase,
            secondFeature: fChild1
        )

        let system = AssemblyConstraintSystem(instances: [base, sub], constraints: [mate])
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        #expect(result.instanceDOF[sub.id] == 3) // 3 translational constraints satisfied, leaves 3 rotational DOFs

        guard let solvedSub = result.solvedTransforms[sub.id],
              let solvedChild1 = result.solvedTransforms[child1.id],
              let solvedChild2 = result.solvedTransforms[child2.id] else {
            Issue.record("Missing solved transforms for subassembly or children")
            return
        }

        // Child1 origin was at local (0, 0, 0), so subassembly origin should now be at targetPos (5, 5, 5)
        #expect(abs(solvedSub.position.x - targetPos.x) < 1e-3)
        #expect(abs(solvedSub.position.y - targetPos.y) < 1e-3)
        #expect(abs(solvedSub.position.z - targetPos.z) < 1e-3)

        // Child1 world position should match targetPos
        #expect(abs(solvedChild1.position.x - targetPos.x) < 1e-3)
        #expect(abs(solvedChild1.position.y - targetPos.y) < 1e-3)
        #expect(abs(solvedChild1.position.z - targetPos.z) < 1e-3)

        // Child2 world position should maintain relative offset of (10, 0, 0)
        #expect(abs(solvedChild2.position.x - (targetPos.x + 10)) < 1e-3)
        #expect(abs(solvedChild2.position.y - targetPos.y) < 1e-3)
        #expect(abs(solvedChild2.position.z - targetPos.z) < 1e-3)
    }

    @Test func testFlexibleSubassemblyArticulatesInternalJoint() {
        // Link1 is grounded at origin
        let link1 = ComponentInstance(
            name: "Link1",
            reference: .internalPart(name: "Link1Part"),
            transform: .identity,
            isGrounded: true
        )
        // Link2 initially at (10, 0, 0)
        let link2 = ComponentInstance(
            name: "Link2",
            reference: .internalPart(name: "Link2Part"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0))
        )
        // Internal slider joint along X axis between Link1 and Link2
        let fLink1 = AssemblyFeature(componentInstanceId: link1.id, origin: .zero, axis: SIMD3<Float>(1, 0, 0))
        let fLink2 = AssemblyFeature(componentInstanceId: link2.id, origin: .zero, axis: SIMD3<Float>(1, 0, 0))
        let internalSlider = AssemblyConstraint(
            name: "Internal Slider",
            kind: .slider,
            firstFeature: fLink1,
            secondFeature: fLink2,
            value: 0.0
        )

        let flexibleSub = ComponentInstance(
            name: "FlexibleActuator",
            reference: .subassembly(name: "FlexibleActuator"),
            transform: .identity,
            subassemblyBehavior: .flexible,
            childInstances: [link1, link2],
            childConstraints: [internalSlider]
        )

        // Parent constraint: Target block at (25, 0, 0), coincident with Link2
        let targetPos = SIMD3<Float>(25, 0, 0)
        let parentBase = ComponentInstance(
            name: "ParentBase",
            reference: .internalPart(name: "ParentBase"),
            transform: .identity,
            isGrounded: true
        )
        let fParent = AssemblyFeature(componentInstanceId: parentBase.id, origin: targetPos)
        let fChild2 = AssemblyFeature(componentInstanceId: link2.id, origin: .zero)
        let parentMate = AssemblyConstraint(
            kind: .coincident,
            firstFeature: fParent,
            secondFeature: fChild2
        )

        let system = AssemblyConstraintSystem(
            instances: [parentBase, flexibleSub],
            constraints: [parentMate]
        )
        let result = AssemblyConstraintSolver.solve(system: system)

        #expect(result.status.isConverged)
        guard let solvedLink2 = result.solvedTransforms[link2.id] else {
            Issue.record("Missing solved transform for Link2")
            return
        }

        // Link2 slid along the slider axis to satisfy the parent constraint at (25, 0, 0)
        #expect(abs(solvedLink2.position.x - targetPos.x) < 1e-2)
        #expect(abs(solvedLink2.position.y - targetPos.y) < 1e-2)
        #expect(abs(solvedLink2.position.z - targetPos.z) < 1e-2)
    }

    @Test func testDragTargetOnChildOfRigidSubassemblyMovesEntireSubassembly() {
        let child1 = ComponentInstance(
            name: "Child 1",
            reference: .internalPart(name: "P1"),
            transform: .identity
        )
        let child2 = ComponentInstance(
            name: "Child 2",
            reference: .internalPart(name: "P2"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0))
        )
        let sub = ComponentInstance(
            name: "RigidSub",
            reference: .subassembly(name: "RigidSub"),
            transform: .identity,
            subassemblyBehavior: .rigid,
            childInstances: [child1, child2]
        )

        // Drag child2 to (50, 60, 70)
        let dragTarget = AssemblyDragTarget(
            instanceId: child2.id,
            targetPosition: SIMD3<Float>(50, 60, 70)
        )

        let system = AssemblyConstraintSystem(instances: [sub], constraints: [])
        let result = AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)

        #expect(result.status.isConverged)
        guard let solvedSub = result.solvedTransforms[sub.id],
              let solvedChild1 = result.solvedTransforms[child1.id],
              let solvedChild2 = result.solvedTransforms[child2.id] else {
            Issue.record("Missing solved transforms")
            return
        }

        // Child2 was at local (10, 0, 0). When dragged to (50, 60, 70), subassembly origin moves to (40, 60, 70)
        #expect(abs(solvedSub.position.x - 40) < 1e-2)
        #expect(abs(solvedSub.position.y - 60) < 1e-2)
        #expect(abs(solvedSub.position.z - 70) < 1e-2)

        // Child1 should be at subassembly origin (40, 60, 70)
        #expect(abs(solvedChild1.position.x - 40) < 1e-2)
        #expect(abs(solvedChild1.position.y - 60) < 1e-2)
        #expect(abs(solvedChild1.position.z - 70) < 1e-2)

        // Child2 should be at target (50, 60, 70)
        #expect(abs(solvedChild2.position.x - 50) < 1e-2)
        #expect(abs(solvedChild2.position.y - 60) < 1e-2)
        #expect(abs(solvedChild2.position.z - 70) < 1e-2)
    }

    @Test func testNestedSubassemblyTransforms() {
        let leaf = ComponentInstance(
            name: "Leaf",
            reference: .internalPart(name: "LeafPart"),
            transform: Transform(position: SIMD3<Float>(1, 2, 3))
        )
        let innerSub = ComponentInstance(
            name: "InnerSub",
            reference: .subassembly(name: "Inner"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0)),
            subassemblyBehavior: .rigid,
            childInstances: [leaf]
        )
        let outerSub = ComponentInstance(
            name: "OuterSub",
            reference: .subassembly(name: "Outer"),
            transform: Transform(position: SIMD3<Float>(0, 20, 0)),
            subassemblyBehavior: .rigid,
            childInstances: [innerSub]
        )

        // Outer sub dragged to (100, 200, 300)
        let dragTarget = AssemblyDragTarget(
            instanceId: outerSub.id,
            targetPosition: SIMD3<Float>(100, 200, 300)
        )
        let system = AssemblyConstraintSystem(instances: [outerSub], constraints: [])
        let result = AssemblyConstraintSolver.solve(system: system, dragTarget: dragTarget)

        #expect(result.status.isConverged)
        guard let solvedOuter = result.solvedTransforms[outerSub.id],
              let solvedInner = result.solvedTransforms[innerSub.id],
              let solvedLeaf = result.solvedTransforms[leaf.id] else {
            Issue.record("Missing solved transforms in nested hierarchy")
            return
        }

        #expect(abs(solvedOuter.position.x - 100) < 1e-2)
        #expect(abs(solvedOuter.position.y - 200) < 1e-2)
        #expect(abs(solvedOuter.position.z - 300) < 1e-2)

        // Inner: Outer (100, 200, 300) + Inner (10, 0, 0) = (110, 200, 300)
        #expect(abs(solvedInner.position.x - 110) < 1e-2)
        #expect(abs(solvedInner.position.y - 200) < 1e-2)
        #expect(abs(solvedInner.position.z - 300) < 1e-2)

        // Leaf: Inner (110, 200, 300) + Leaf (1, 2, 3) = (111, 202, 303)
        #expect(abs(solvedLeaf.position.x - 111) < 1e-2)
        #expect(abs(solvedLeaf.position.y - 202) < 1e-2)
        #expect(abs(solvedLeaf.position.z - 303) < 1e-2)
    }
}

