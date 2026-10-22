import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct ComponentInstanceTests {

    @Test func testComponentInstanceInitialization() {
        let id = UUID()
        let ref = ComponentReference.internalPart(name: "Arm", bodyId: SolidId("solid-arm"))
        let transform = Transform(
            position: SIMD3<Float>(10, 20, 30),
            rotation: simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 0, 1)),
            scale: SIMD3<Float>(1, 1, 1)
        )
        let instance = ComponentInstance(
            id: id,
            name: "Arm Instance 1",
            reference: ref,
            transform: transform
        )

        #expect(instance.id == id)
        #expect(instance.name == "Arm Instance 1")
        #expect(instance.solidId == SolidId("component-\(id.uuidString)"))
        #expect(instance.isVisible == true)
        #expect(instance.isLocked == false)
        #expect(instance.isGrounded == false)
        #expect(instance.isFixed == false)
        #expect(instance.transform.position == SIMD3<Float>(10, 20, 30))
    }

    @Test func testIsFixedAlias() {
        var instance = ComponentInstance(
            name: "Pin",
            reference: .internalPart(name: "PinPart")
        )
        #expect(instance.isGrounded == false)
        #expect(instance.isFixed == false)

        instance.isFixed = true
        #expect(instance.isGrounded == true)
        #expect(instance.isFixed == true)

        instance.isGrounded = false
        #expect(instance.isFixed == false)
    }

    @Test func testComponentReferenceVariations() {
        let internalRef = ComponentReference.internalPart(name: "Bracket", bodyId: SolidId("box-1"))
        switch internalRef {
        case .internalPart(let name, let bodyId):
            #expect(name == "Bracket")
            #expect(bodyId == SolidId("box-1"))
        case .externalDocument, .subassembly:
            Issue.record("Expected internalPart")
        }

        let fileURL = URL(fileURLWithPath: "/models/bracket.made")
        let externalRef = ComponentReference.externalDocument(url: fileURL, partName: "Base")
        switch externalRef {
        case .externalDocument(let url, let partName):
            #expect(url == fileURL)
            #expect(partName == "Base")
        case .internalPart, .subassembly:
            Issue.record("Expected externalDocument")
        }
    }

    @Test func testEulerAngleConversion() {
        let originalEuler = SIMD3<Float>(30, 45, 60)
        let quat = simd_quatf.fromEulerAngles(degrees: originalEuler)
        let recoveredEuler = quat.eulerAnglesDegrees

        #expect(abs(originalEuler.x - recoveredEuler.x) < 0.1)
        #expect(abs(originalEuler.y - recoveredEuler.y) < 0.1)
        #expect(abs(originalEuler.z - recoveredEuler.z) < 0.1)
    }

    @Test func testComponentInstanceCodableRoundTrip() throws {
        let id = UUID()
        let ref = ComponentReference.externalDocument(
            url: URL(fileURLWithPath: "/Users/test/Documents/part.step"),
            partName: "Flange"
        )
        let transform = Transform(
            position: SIMD3<Float>(15.5, -20.0, 100.25),
            rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(10, 20, 30)),
            scale: SIMD3<Float>(2, 2, 2)
        )
        let original = ComponentInstance(
            id: id,
            name: "Flange Component",
            reference: ref,
            transform: transform,
            isVisible: true,
            isLocked: false,
            isGrounded: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ComponentInstance.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.solidId == original.solidId)
        #expect(decoded.isVisible == original.isVisible)
        #expect(decoded.isLocked == original.isLocked)
        #expect(decoded.isGrounded == true)
        #expect(decoded.isFixed == true)
        #expect(decoded.transform.position == original.transform.position)
        #expect(decoded.transform.scale == original.transform.scale)
        #expect(decoded.reference == original.reference)
    }

    @Test func testLegacyComponentInstanceDecodingWithoutIsGrounded() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789abc",
            "name": "Legacy Part",
            "reference": {
                "type": "internalPart",
                "name": "LegacyBody"
            },
            "isVisible": true,
            "isLocked": false
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ComponentInstance.self, from: data)
        #expect(decoded.name == "LegacyPart" || decoded.name == "Legacy Part")
        #expect(decoded.isGrounded == false)
        #expect(decoded.isFixed == false)
    }

    @Test func testToSceneObjectProjection() {
        let id = UUID()
        let instance = ComponentInstance(
            id: id,
            name: "Motor",
            reference: .internalPart(name: "MotorPart", bodyId: SolidId("motor-body")),
            transform: Transform(position: SIMD3<Float>(5, 10, 15))
        )

        let sceneObject = instance.toSceneObject()
        #expect(sceneObject.id == instance.solidId)
        #expect(sceneObject.name == "Motor")
        #expect(sceneObject.transform.position == SIMD3<Float>(5, 10, 15))
        #expect(sceneObject.isVisible == true)
        #expect(sceneObject.isLocked == false)

        var groundedInstance = instance
        groundedInstance.isGrounded = true
        let groundedSceneObject = groundedInstance.toSceneObject()
        #expect(groundedSceneObject.isLocked == true)

        var lockedInstance = instance
        lockedInstance.isLocked = true
        let lockedSceneObject = lockedInstance.toSceneObject()
        #expect(lockedSceneObject.isLocked == true)
    }

    // MARK: - Subassemblies (BL-ASM-07)

    @Test func testSubassemblyReferenceAndBehavior() {
        let subRef = ComponentReference.subassembly(name: "Gearbox")
        if case .subassembly(let name) = subRef {
            #expect(name == "Gearbox")
        } else {
            Issue.record("Expected .subassembly reference")
        }

        #expect(SubassemblyBehavior.allCases == [.rigid, .flexible])
        #expect(SubassemblyBehavior.rigid.rawValue == "rigid")
        #expect(SubassemblyBehavior.flexible.rawValue == "flexible")
    }

    @Test func testSubassemblyInitializationAndDefaults() {
        let child1 = ComponentInstance(name: "Gear1", reference: .internalPart(name: "Part1"))
        let child2 = ComponentInstance(name: "Gear2", reference: .internalPart(name: "Part2"))
        let mate = AssemblyConstraint(
            kind: .concentric,
            firstFeature: AssemblyFeature(componentInstanceId: child1.id, origin: .zero),
            secondFeature: AssemblyFeature(componentInstanceId: child2.id, origin: .zero)
        )

        let subassembly = ComponentInstance(
            name: "Drive Train",
            reference: .subassembly(name: "Drive Train"),
            subassemblyBehavior: .flexible,
            childInstances: [child1, child2],
            childConstraints: [mate]
        )

        #expect(subassembly.isSubassembly == true)
        #expect(subassembly.subassemblyBehavior == .flexible)
        #expect(subassembly.childInstances.count == 2)
        #expect(subassembly.childConstraints.count == 1)
        #expect(child1.isSubassembly == false)
    }

    @Test func testRecursiveSceneObjectProjection() {
        let child1 = ComponentInstance(
            name: "Child 1",
            reference: .internalPart(name: "Part1"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0))
        )
        let child2 = ComponentInstance(
            name: "Child 2",
            reference: .internalPart(name: "Part2"),
            transform: Transform(position: SIMD3<Float>(0, 20, 0))
        )

        let subassembly = ComponentInstance(
            name: "Subassembly",
            reference: .subassembly(name: "Sub"),
            transform: Transform(position: SIMD3<Float>(5, 5, 0)),
            childInstances: [child1, child2]
        )

        let projected = subassembly.toSceneObjects()
        #expect(projected.count == 2)

        let obj1 = projected.first(where: { $0.id == child1.solidId })
        let obj2 = projected.first(where: { $0.id == child2.solidId })
        #expect(obj1 != nil)
        #expect(obj2 != nil)

        // Child 1 world position: (5, 5, 0) + (10, 0, 0) = (15, 5, 0)
        #expect(abs((obj1?.transform.position.x ?? 0) - 15) < 1e-3)
        #expect(abs((obj1?.transform.position.y ?? 0) - 5) < 1e-3)

        // Child 2 world position: (5, 5, 0) + (0, 20, 0) = (5, 25, 0)
        #expect(abs((obj2?.transform.position.x ?? 0) - 5) < 1e-3)
        #expect(abs((obj2?.transform.position.y ?? 0) - 25) < 1e-3)
    }

    @Test func testRecursiveLookups() {
        let leaf = ComponentInstance(name: "Leaf", reference: .internalPart(name: "LeafPart"))
        let innerSub = ComponentInstance(
            name: "InnerSub",
            reference: .subassembly(name: "Inner"),
            childInstances: [leaf]
        )
        let outerSub = ComponentInstance(
            name: "OuterSub",
            reference: .subassembly(name: "Outer"),
            childInstances: [innerSub]
        )

        let allInstances = outerSub.allComponentInstances(recursive: true, includeSelf: true)
        #expect(allInstances.count == 3)

        let foundLeaf = outerSub.findComponent(id: leaf.id)
        #expect(foundLeaf != nil)
        #expect(foundLeaf?.instance.id == leaf.id)
        #expect(foundLeaf?.parentId == innerSub.id)

        let foundBySolid = outerSub.findComponent(solidId: leaf.solidId)
        #expect(foundBySolid != nil)
        #expect(foundBySolid?.instance.id == leaf.id)
    }

    @Test func testSubassemblyCodableRoundTrip() throws {
        let child = ComponentInstance(
            name: "Motor",
            reference: .internalPart(name: "MotorPart"),
            transform: Transform(position: SIMD3<Float>(1, 2, 3))
        )
        let sub = ComponentInstance(
            name: "Actuator",
            reference: .subassembly(name: "Actuator"),
            subassemblyBehavior: .flexible,
            childInstances: [child]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(sub)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ComponentInstance.self, from: data)

        #expect(decoded.name == "Actuator")
        #expect(decoded.isSubassembly == true)
        #expect(decoded.subassemblyBehavior == .flexible)
        #expect(decoded.childInstances.count == 1)
        #expect(decoded.childInstances.first?.name == "Motor")
        #expect(decoded.childInstances.first?.transform.position == SIMD3<Float>(1, 2, 3))
    }

    @Test func testLegacyComponentInstanceDecodingDefaultsSubassemblyFields() throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "name": "Legacy Part",
            "reference": {
                "type": "internalPart",
                "name": "LegacyBody"
            },
            "isVisible": true,
            "isLocked": false
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ComponentInstance.self, from: data)

        #expect(decoded.subassemblyBehavior == .rigid)
        #expect(decoded.childInstances.isEmpty)
        #expect(decoded.childConstraints.isEmpty)
        #expect(decoded.isSubassembly == false)
    }
}

