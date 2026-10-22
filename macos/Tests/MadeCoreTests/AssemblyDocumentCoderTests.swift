import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct AssemblyDocumentCoderTests {

    @Test func testManifestDocumentTypeRoundTrip() throws {
        var manifest = MadeManifest(documentType: .assembly)
        #expect(manifest.documentType == .assembly)

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(MadeManifest.self, from: data)
        #expect(decoded.documentType == .assembly)

        manifest.documentType = .part
        let partData = try JSONEncoder().encode(manifest)
        let decodedPart = try JSONDecoder().decode(MadeManifest.self, from: partData)
        #expect(decodedPart.documentType == .part)
    }

    @Test func testManifestBackwardCompatibilityDefaultsToPart() throws {
        let legacyManifestJSON = """
        {
          "formatVersion": 2,
          "appVersion": "1.0.0",
          "createdAt": "2026-01-01T00:00:00Z",
          "modifiedAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MadeManifest.self, from: legacyManifestJSON)
        #expect(decoded.documentType == .part)
    }

    @Test func testDocumentDataAssemblyRoundTrip() throws {
        let instance = ComponentInstance(
            name: "Mount Bracket",
            reference: .internalPart(name: "BracketPart"),
            transform: Transform(
                position: SIMD3<Float>(12.5, -45.0, 78.0),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(15, 30, 45)),
                scale: SIMD3<Float>(1, 1, 1)
            )
        )

        let doc = DocumentModel(
            documentType: .assembly,
            componentInstances: [instance]
        )

        let encoded = try DocumentModelCoder.encode(document: doc)
        let decoded = try DocumentModelCoder.decode(from: encoded)

        #expect(decoded.documentType == DocumentType.assembly)
        #expect(decoded.componentInstances?.count == 1)
        #expect(decoded.componentInstances?.first?.name == "Mount Bracket")
        #expect(decoded.componentInstances?.first?.transform.position == SIMD3<Float>(12.5, -45.0, 78.0))
    }

    @Test func testDecodeIntoDocumentModelRestoresAssembly() throws {
        let instance = ComponentInstance(
            name: "Coupling",
            reference: .externalDocument(url: URL(fileURLWithPath: "/parts/coupling.made")),
            transform: Transform(position: SIMD3<Float>(0, 10, 20))
        )

        let sourceDoc = DocumentModel(
            documentType: .assembly,
            componentInstances: [instance]
        )

        let encoded = try DocumentModelCoder.encode(document: sourceDoc)

        let targetDoc = DocumentModel()
        #expect(targetDoc.documentType == .part)
        #expect(targetDoc.componentInstances.isEmpty)

        try DocumentModelCoder.decode(into: targetDoc, from: encoded)

        #expect(targetDoc.documentType == .assembly)
        #expect(targetDoc.componentInstances.count == 1)
        #expect(targetDoc.componentInstances.first?.name == "Coupling")
        #expect(targetDoc.objects.contains(where: { $0.id == instance.solidId }))
    }

    @Test func testLegacyDocumentDataWithoutDocumentTypeDefaultsToPart() throws {
        let legacyDocJSON = """
        {
          "schemaVersion": 2,
          "objects": []
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyDocJSON)
        #expect(decoded.documentType == nil || decoded.documentType == .part)
        #expect(decoded.componentInstances == nil || decoded.componentInstances?.isEmpty == true)

        let targetDoc = DocumentModel()
        try DocumentModelCoder.decode(into: targetDoc, from: legacyDocJSON)
        #expect(targetDoc.documentType == .part)
        #expect(targetDoc.componentInstances.isEmpty)
    }

    @Test func testMadePackageAssemblyFileWrapperRoundTrip() throws {
        let instance = ComponentInstance(
            name: "Rotor",
            reference: .internalPart(name: "RotorPart"),
            transform: Transform(position: SIMD3<Float>(5, 15, 25))
        )

        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            objects: [instance.toSceneObject()],
            documentType: .assembly,
            componentInstances: [instance]
        )

        let manifest = MadeManifest(documentType: .assembly)
        let package = MadePackage(manifest: manifest, documentData: docData)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AssemblyPackage-\(UUID().uuidString).made")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileWrapper = try package.makeFileWrapper()
        try fileWrapper.write(to: tempDir, options: .atomic, originalContentsURL: nil)

        let reopened = try MadePackage(directoryURL: tempDir)
        #expect(reopened.manifest.documentType == .assembly)

        let reopenedDoc = DocumentModel()
        let encodedData = try DocumentModelCoder.encode(reopened.documentData)
        try DocumentModelCoder.decode(into: reopenedDoc, from: encodedData)

        #expect(reopenedDoc.documentType == .assembly)
        #expect(reopenedDoc.componentInstances.count == 1)
        #expect(reopenedDoc.componentInstances.first?.name == "Rotor")
        #expect(reopenedDoc.componentInstances.first?.transform.position == SIMD3<Float>(5, 15, 25))
        #expect(reopenedDoc.objects.contains(where: { $0.id == instance.solidId }))
    }

    @Test func testAssemblyConstraintsDocumentDataRoundTrip() throws {
        let instanceA = ComponentInstance(name: "A", reference: .internalPart(name: "PartA"))
        let instanceB = ComponentInstance(name: "B", reference: .internalPart(name: "PartB"))

        let mate1 = AssemblyConstraint(
            kind: .coincident,
            firstFeature: AssemblyFeature(componentInstanceId: instanceA.id, origin: .zero),
            secondFeature: AssemblyFeature(componentInstanceId: instanceB.id, origin: .zero)
        )
        let mate2 = AssemblyConstraint(
            kind: .distance,
            firstFeature: AssemblyFeature(componentInstanceId: instanceA.id, origin: SIMD3<Float>(10, 0, 0)),
            secondFeature: AssemblyFeature(componentInstanceId: instanceB.id, origin: .zero),
            value: 20.0
        )

        let sourceDoc = DocumentModel(
            documentType: .assembly,
            componentInstances: [instanceA, instanceB],
            assemblyConstraints: [mate1, mate2]
        )

        let data = try DocumentModelCoder.encode(document: sourceDoc)
        let decodedData = try DocumentModelCoder.decode(from: data)

        #expect(decodedData.assemblyConstraints?.count == 2)
        #expect(decodedData.assemblyConstraints?.first?.kind == .coincident)
        #expect(decodedData.assemblyConstraints?.last?.value == 20.0)

        let targetDoc = DocumentModel()
        try DocumentModelCoder.decode(into: targetDoc, from: data)

        #expect(targetDoc.documentType == .assembly)
        #expect(targetDoc.assemblyConstraints.count == 2)
        #expect(targetDoc.assemblyConstraints.first?.id == mate1.id)
        #expect(targetDoc.assemblyConstraints.last?.id == mate2.id)
    }

    @Test func testLegacyDocumentWithoutAssemblyConstraintsDecodesEmpty() throws {
        let legacyDocJSON = """
        {
          "schemaVersion": 2,
          "documentType": "assembly",
          "objects": []
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyDocJSON)
        #expect(decoded.assemblyConstraints == nil || decoded.assemblyConstraints?.isEmpty == true)

        let targetDoc = DocumentModel()
        try DocumentModelCoder.decode(into: targetDoc, from: legacyDocJSON)
        #expect(targetDoc.assemblyConstraints.isEmpty)
    }

    @Test func testAllConstraintAndJointKindsRoundTrip() throws {
        let instanceA = ComponentInstance(name: "A", reference: .internalPart(name: "PartA"))
        let instanceB = ComponentInstance(name: "B", reference: .internalPart(name: "PartB"))

        let allConstraints = AssemblyConstraintKind.allCases.map { kind in
            AssemblyConstraint(
                name: kind.displayName,
                kind: kind,
                firstFeature: AssemblyFeature(componentInstanceId: instanceA.id, origin: .zero, axis: SIMD3<Float>(0, 0, 1)),
                secondFeature: AssemblyFeature(componentInstanceId: instanceB.id, origin: SIMD3<Float>(0, 0, 10), axis: SIMD3<Float>(0, 0, 1)),
                value: kind.isJoint ? 5.0 : 10.0
            )
        }

        #expect(allConstraints.count == 14)

        let doc = DocumentModel(
            documentType: .assembly,
            componentInstances: [instanceA, instanceB],
            assemblyConstraints: allConstraints
        )

        let data = try DocumentModelCoder.encode(document: doc)
        let decodedDoc = DocumentModel()
        try DocumentModelCoder.decode(into: decodedDoc, from: data)

        #expect(decodedDoc.assemblyConstraints.count == 14)
        for (original, decoded) in zip(allConstraints, decodedDoc.assemblyConstraints) {
            #expect(decoded.kind == original.kind)
            #expect(decoded.name == original.name)
            #expect(decoded.value == original.value)
            #expect(decoded.firstFeature.componentInstanceId == original.firstFeature.componentInstanceId)
            #expect(decoded.secondFeature.componentInstanceId == original.secondFeature.componentInstanceId)
        }
    }

    @Test func testLegacyAndAliasJointKindDecoding() throws {
        let legacyJSON = """
        [
            {
                "id": "11111111-1111-1111-1111-111111111111",
                "name": "Pin Slot Joint",
                "kind": "pin_slot",
                "firstFeature": { "localOrigin": [0, 0, 0], "localAxis": [0, 0, 1], "localSecondaryAxis": [1, 0, 0], "hasExplicitAxis": true },
                "secondFeature": { "localOrigin": [0, 0, 0], "localAxis": [0, 0, 1], "localSecondaryAxis": [1, 0, 0], "hasExplicitAxis": true },
                "isSuppressed": false
            },
            {
                "id": "22222222-2222-2222-2222-222222222222",
                "name": "Pin Slot Hyphen",
                "kind": "pin-slot",
                "firstFeature": { "localOrigin": [0, 0, 0], "localAxis": [0, 0, 1], "localSecondaryAxis": [1, 0, 0], "hasExplicitAxis": true },
                "secondFeature": { "localOrigin": [0, 0, 0], "localAxis": [0, 0, 1], "localSecondaryAxis": [1, 0, 0], "hasExplicitAxis": true },
                "isSuppressed": false
            },
            {
                "id": "33333333-3333-3333-3333-333333333333",
                "name": "Rigid Joint",
                "kind": "rigid",
                "firstFeature": { "localOrigin": [0, 0, 0], "localAxis": [0, 0, 1], "localSecondaryAxis": [1, 0, 0], "hasExplicitAxis": true },
                "secondFeature": { "localOrigin": [0, 0, 0], "localAxis": [0, 0, 1], "localSecondaryAxis": [1, 0, 0], "hasExplicitAxis": true },
                "isSuppressed": false
            }
        ]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([AssemblyConstraint].self, from: legacyJSON)
        #expect(decoded.count == 3)
        #expect(decoded[0].kind == .pinSlot)
        #expect(decoded[1].kind == .pinSlot)
        #expect(decoded[2].kind == .fastened)
    }

    // MARK: - Subassemblies (BL-ASM-07)

    @Test func testNestedSubassemblyDocumentCoderRoundTrip() throws {
        let childA = ComponentInstance(name: "A", reference: .internalPart(name: "PartA"), transform: Transform(position: SIMD3<Float>(10, 0, 0)))
        let childB = ComponentInstance(name: "B", reference: .internalPart(name: "PartB"), transform: Transform(position: SIMD3<Float>(20, 0, 0)))
        let internalMate = AssemblyConstraint(
            name: "Mate AB",
            kind: .coincident,
            firstFeature: AssemblyFeature(componentInstanceId: childA.id, origin: .zero),
            secondFeature: AssemblyFeature(componentInstanceId: childB.id, origin: .zero)
        )
        let subassembly = ComponentInstance(
            name: "Subassembly AB",
            reference: .subassembly(name: "Subassembly AB"),
            transform: Transform(position: SIMD3<Float>(5, 10, 15)),
            subassemblyBehavior: .flexible,
            childInstances: [childA, childB],
            childConstraints: [internalMate]
        )

        let sourceDoc = DocumentModel(
            documentType: .assembly,
            componentInstances: [subassembly]
        )

        let data = try DocumentModelCoder.encode(document: sourceDoc)
        let decodedDoc = DocumentModel()
        try DocumentModelCoder.decode(into: decodedDoc, from: data)

        #expect(decodedDoc.documentType == .assembly)
        #expect(decodedDoc.componentInstances.count == 1)

        guard let decodedSub = decodedDoc.componentInstances.first else {
            Issue.record("Missing decoded subassembly")
            return
        }

        #expect(decodedSub.name == "Subassembly AB")
        #expect(decodedSub.isSubassembly == true)
        #expect(decodedSub.subassemblyBehavior == .flexible)
        #expect(decodedSub.transform.position == SIMD3<Float>(5, 10, 15))
        #expect(decodedSub.childInstances.count == 2)
        #expect(decodedSub.childConstraints.count == 1)
        #expect(decodedSub.childConstraints.first?.name == "Mate AB")

        // Ensure child scene objects are projected into decodedDoc.objects
        #expect(decodedDoc.objects.contains(where: { $0.id == childA.solidId }))
        #expect(decodedDoc.objects.contains(where: { $0.id == childB.solidId }))
    }

    @Test func testSubassemblyPackageRoundTrip() throws {
        let child = ComponentInstance(name: "Link", reference: .internalPart(name: "LinkPart"))
        let sub = ComponentInstance(
            name: "ArmSub",
            reference: .subassembly(name: "ArmSub"),
            subassemblyBehavior: .rigid,
            childInstances: [child]
        )

        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            objects: sub.toSceneObjects(),
            documentType: .assembly,
            componentInstances: [sub]
        )

        let package = MadePackage(manifest: MadeManifest(documentType: .assembly), documentData: docData)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SubPackage-\(UUID().uuidString).made")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wrapper = try package.makeFileWrapper()
        try wrapper.write(to: tempDir, options: .atomic, originalContentsURL: nil)

        let reopened = try MadePackage(directoryURL: tempDir)
        let targetDoc = DocumentModel()
        let encodedData = try DocumentModelCoder.encode(reopened.documentData)
        try DocumentModelCoder.decode(into: targetDoc, from: encodedData)

        #expect(targetDoc.documentType == .assembly)
        #expect(targetDoc.componentInstances.count == 1)
        #expect(targetDoc.componentInstances.first?.isSubassembly == true)
        #expect(targetDoc.componentInstances.first?.childInstances.count == 1)
        #expect(targetDoc.objects.contains(where: { $0.id == child.solidId }))
    }

    // MARK: - Component Patterns & Mirrors Serialization Tests (BL-ASM-08, #169)

    @Test func testDocumentPatternsAndMirrorsSerializationRoundTrip() throws {
        let sourceInstance = ComponentInstance(
            name: "Flange Bolt",
            reference: .internalPart(name: "Bolt"),
            transform: Transform(position: SIMD3<Float>(10, 0, 0))
        )
        let replica1 = ComponentInstance(
            name: "Flange Bolt (Pattern 2)",
            reference: .internalPart(name: "Bolt"),
            transform: Transform(position: SIMD3<Float>(0, 10, 0))
        )
        let replica2 = ComponentInstance(
            name: "Flange Bolt (Mirrored)",
            reference: .internalPart(name: "Bolt"),
            transform: Transform(position: SIMD3<Float>(-10, 0, 0))
        )

        let pattern = ComponentPattern(
            name: "Circular Flange Pattern",
            sourceInstanceId: sourceInstance.id,
            replicaInstanceIds: [replica1.id],
            params: AssemblyPatternParams(
                sourceInstanceId: sourceInstance.id,
                patternType: .circular,
                count: 2,
                totalAngle: 180.0
            )
        )
        let mirror = ComponentMirror(
            name: "Flange Mirror",
            sourceInstanceId: sourceInstance.id,
            replicaInstanceIds: [replica2.id],
            params: AssemblyMirrorParams(
                sourceInstanceId: sourceInstance.id,
                planeNormal: SIMD3<Float>(1, 0, 0),
                planeOrigin: .zero
            )
        )

        let doc = DocumentModel(
            documentType: .assembly,
            componentInstances: [sourceInstance, replica1, replica2],
            componentPatterns: [pattern],
            componentMirrors: [mirror]
        )

        let encoded = try DocumentModelCoder.encode(document: doc)
        let decoded = try DocumentModelCoder.decode(from: encoded)

        #expect(decoded.componentPatterns?.count == 1)
        #expect(decoded.componentPatterns?.first?.name == "Circular Flange Pattern")
        #expect(decoded.componentPatterns?.first?.replicaInstanceIds == [replica1.id])
        #expect(decoded.componentMirrors?.count == 1)
        #expect(decoded.componentMirrors?.first?.name == "Flange Mirror")
        #expect(decoded.componentMirrors?.first?.replicaInstanceIds == [replica2.id])
    }

    @Test func testDecodeIntoDocumentModelRestoresPatternsAndMirrors() throws {
        let sourceInstance = ComponentInstance(
            name: "Column",
            reference: .internalPart(name: "ColumnPart")
        )
        let pattern = ComponentPattern(
            name: "Linear Column Pattern",
            sourceInstanceId: sourceInstance.id,
            replicaInstanceIds: [],
            params: AssemblyPatternParams(
                sourceInstanceId: sourceInstance.id,
                count: 1
            )
        )

        let sourceDoc = DocumentModel(
            documentType: .assembly,
            componentInstances: [sourceInstance],
            componentPatterns: [pattern]
        )

        let encoded = try DocumentModelCoder.encode(document: sourceDoc)

        let targetDoc = DocumentModel()
        try DocumentModelCoder.decode(into: targetDoc, from: encoded)

        #expect(targetDoc.documentType == .assembly)
        #expect(targetDoc.componentPatterns.count == 1)
        #expect(targetDoc.componentPatterns.first?.name == "Linear Column Pattern")
        #expect(targetDoc.componentMirrors.isEmpty)
    }

    @Test func testLegacyDocumentWithoutPatternsDecodesSafely() throws {
        let legacyAssemblyJSON = """
        {
          "schemaVersion": 2,
          "documentType": "assembly",
          "componentInstances": [
            {
              "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
              "name": "LegacyPart",
              "reference": {
                "type": "internalPart",
                "name": "PartA"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyAssemblyJSON)
        #expect(decoded.componentPatterns == nil)
        #expect(decoded.componentMirrors == nil)

        let targetDoc = DocumentModel()
        try DocumentModelCoder.decode(into: targetDoc, from: legacyAssemblyJSON)
        #expect(targetDoc.componentPatterns.isEmpty)
        #expect(targetDoc.componentMirrors.isEmpty)
        #expect(targetDoc.componentInstances.first?.patternId == nil)
        #expect(targetDoc.componentInstances.first?.mirrorId == nil)
    }

    // MARK: - Exploded Views (BL-ASM-12)

    @Test func testExplodedViewsDocumentDataRoundTrip() throws {
        let instance = ComponentInstance(
            name: "Plate",
            reference: .internalPart(name: "PlatePart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )
        let step = ExplodeStep(
            name: "Step 1",
            targetInstanceIds: [instance.id],
            direction: SIMD3<Float>(0, 1, 0),
            distance: 45.0,
            hasTrail: true
        )
        let view = ExplodedView(
            name: "Exploded 1",
            steps: [step],
            isCollapsed: false
        )

        let sourceDoc = DocumentModel(
            documentType: .assembly,
            componentInstances: [instance],
            explodedViews: [view],
            activeExplodedViewId: view.id
        )

        let encoded = try DocumentModelCoder.encode(document: sourceDoc)
        let decodedData = try DocumentModelCoder.decode(from: encoded)

        #expect(decodedData.explodedViews?.count == 1)
        #expect(decodedData.explodedViews?.first?.name == "Exploded 1")
        #expect(decodedData.explodedViews?.first?.steps.count == 1)
        #expect(decodedData.explodedViews?.first?.steps.first?.distance == 45.0)
        #expect(decodedData.explodedViews?.first?.steps.first?.hasTrail == true)
        #expect(decodedData.activeExplodedViewId == view.id)

        let targetDoc = DocumentModel()
        try DocumentModelCoder.decode(into: targetDoc, from: encoded)

        #expect(targetDoc.documentType == .assembly)
        #expect(targetDoc.explodedViews.count == 1)
        #expect(targetDoc.explodedViews.first?.id == view.id)
        #expect(targetDoc.explodedViews.first?.name == "Exploded 1")
        #expect(targetDoc.activeExplodedViewId == view.id)
        #expect(targetDoc.explodedViews.first?.steps.count == 1)
        #expect(targetDoc.explodedViews.first?.steps.first?.targetInstanceIds == [instance.id])

        // Verify scene object projected transform incorporates exploded displacement
        let projected = targetDoc.objects.first(where: { $0.id == instance.solidId })
        #expect(projected?.transform.position == SIMD3<Float>(0, 45, 0))
    }

    @Test func testLegacyDocumentWithoutExplodedViewsDecodesEmpty() throws {
        let legacyAssemblyJSON = """
        {
          "schemaVersion": 2,
          "documentType": "assembly",
          "componentInstances": []
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyAssemblyJSON)
        #expect(decoded.explodedViews == nil)
        #expect(decoded.activeExplodedViewId == nil)

        let targetDoc = DocumentModel()
        try DocumentModelCoder.decode(into: targetDoc, from: legacyAssemblyJSON)
        #expect(targetDoc.explodedViews.isEmpty)
        #expect(targetDoc.activeExplodedViewId == nil)
    }
}

