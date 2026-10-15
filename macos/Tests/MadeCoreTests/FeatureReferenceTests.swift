import Testing
import Foundation
@testable import MadeCore

@MainActor
@Suite struct FeatureReferenceTests {

    // MARK: - Target Types & Factory Helpers

    @Test func testReferenceTargetTypes() {
        let featId = UUID()
        let entId = UUID()
        let solidId = SolidId("body-1")

        let faceRef = TopologicalReference(
            sourceFeatureId: featId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")]
        )
        let edgeRef = TopologicalReference(
            sourceFeatureId: featId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:front")]
        )
        let vertRef = TopologicalReference(
            sourceFeatureId: featId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:corner")]
        )

        // 1. Feature reference
        let ref1 = Reference.feature(featId, role: "parent")
        #expect(ref1.role == "parent")
        #expect(ref1.target == .feature(featId))
        #expect(ref1.referencedFeatureId == featId)

        // 2. Sketch entity reference
        let ref2 = Reference.sketchEntity(featureId: featId, entityId: entId, role: "profile")
        #expect(ref2.role == "profile")
        #expect(ref2.target == .sketchEntity(featureId: featId, entityId: entId))
        #expect(ref2.referencedFeatureId == featId)

        // 3. Body reference
        let ref3 = Reference.body(solidId, role: "targetSolid")
        #expect(ref3.role == "targetSolid")
        #expect(ref3.target == .body(solidId))
        #expect(ref3.referencedFeatureId == nil)

        // 4. Face reference
        let ref4 = Reference.face(faceRef, role: "plane")
        #expect(ref4.role == "plane")
        #expect(ref4.target == .face(faceRef))
        #expect(ref4.referencedFeatureId == featId)

        // 5. Edge reference
        let ref5 = Reference.edge(edgeRef, role: "filletEdge")
        #expect(ref5.role == "filletEdge")
        #expect(ref5.target == .edge(edgeRef))
        #expect(ref5.referencedFeatureId == featId)

        // 6. Vertex reference
        let ref6 = Reference.vertex(vertRef, role: "corner")
        #expect(ref6.role == "corner")
        #expect(ref6.target == .vertex(vertRef))
        #expect(ref6.referencedFeatureId == featId)
    }

    // MARK: - Serialization & Round Trip

    @Test func testFeatureReferenceSerializationRoundTrip() throws {
        let parentFeatureId = UUID()
        let sketchEntityId = UUID()
        let faceRef = TopologicalReference(
            sourceFeatureId: parentFeatureId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")]
        )

        let references: [Reference] = [
            .feature(parentFeatureId, role: "base"),
            .sketchEntity(featureId: parentFeatureId, entityId: sketchEntityId, role: "boundary"),
            .body(SolidId("box-1"), role: "tool"),
            .face(faceRef, role: "support")
        ]

        let feature = Feature(
            name: "Extrude 1",
            operation: .extrude(ExtrudeFeatureData(sketchFeatureId: parentFeatureId, distance: 25.0)),
            references: references
        )

        #expect(feature.reference(forRole: "base")?.referencedFeatureId == parentFeatureId)
        #expect(feature.reference(forRole: "tool")?.target == .body(SolidId("box-1")))
        #expect(feature.reference(forRole: "missing") == nil)
        #expect(feature.inputReferences["base"] != nil)
        #expect(feature.inputReferences["tool"] != nil)
        #expect(feature.inputReferences.count == 4)

        // JSON round trip of Feature
        let encoder = DocumentModelCoder.makeJSONEncoder()
        let decoder = DocumentModelCoder.makeJSONDecoder()

        let data = try encoder.encode(feature)
        let decoded = try decoder.decode(Feature.self, from: data)

        #expect(decoded.id == feature.id)
        #expect(decoded.name == feature.name)
        #expect(decoded.references.count == feature.references.count)
        #expect(decoded.references == feature.references)
        #expect(decoded.reference(forRole: "base") == feature.reference(forRole: "base"))
        #expect(decoded.reference(forRole: "tool") == feature.reference(forRole: "tool"))

        // DocumentModelCoder full document round trip
        let doc = DocumentModel()
        let f1 = Feature.makeBox(params: BoxParams(width: 10, depth: 10, height: 10))
        let f2 = Feature(
            name: "Dependent",
            operation: .extrude(ExtrudeFeatureData(distance: 5.0)),
            references: [.feature(f1.id, role: "parent")]
        )
        _ = doc.insertFeature(f1, at: 0)
        _ = doc.insertFeature(f2, at: 1)

        let encodedDoc = try DocumentModelCoder.encode(document: doc)
        let decodedDocData = try DocumentModelCoder.decode(from: encodedDoc)

        let decodedFeatures = try #require(decodedDocData.features)
        #expect(decodedFeatures.count == 4) // default 2 + added 2
        let matched = decodedFeatures.first(where: { $0.id == f2.id })
        #expect(matched?.references.count == 1)
        #expect(matched?.reference(forRole: "parent")?.referencedFeatureId == f1.id)
    }

    @Test func testLegacyFeatureJSONCompatibility() throws {
        let box = Feature.makeBox(params: BoxParams(width: 10, depth: 20, height: 30))
        let encoder = DocumentModelCoder.makeJSONEncoder()
        let encodedData = try encoder.encode(box)

        // Remove "references" key to simulate legacy JSON missing references
        var jsonObject = try #require(try JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        jsonObject.removeValue(forKey: "references")
        let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)

        let decoder = DocumentModelCoder.makeJSONDecoder()
        let decoded = try decoder.decode(Feature.self, from: legacyData)

        #expect(decoded.id == box.id)
        #expect(decoded.references.isEmpty)
        #expect(decoded.name == box.name)
        #expect(decoded.inputReferences.isEmpty)
        #expect(decoded.reference(forRole: "any") == nil)
    }

    // MARK: - Resolution Happy Path

    @Test func testResolutionHappyPath() {
        let doc = DocumentModel()
        let boxFeature = doc.features[0] // box-1

        let sketchEntityId = UUID()
        let sketchData = SketchFeatureData(
            planeName: "XY",
            planeReference: boxFeature.generatedTopology["face:top"],
            entities: [
                SketchEntity(id: sketchEntityId, kind: "circle", data: ["radius": 5.0])
            ]
        )
        let sketchFeature = Feature(
            name: "Sketch 1",
            operation: .sketch(sketchData),
            references: [
                .face(boxFeature.generatedTopology["face:top"]!, role: "sketchPlane")
            ]
        )
        _ = doc.insertFeature(sketchFeature, at: 1)

        let topFaceRef = boxFeature.generatedTopology["face:top"]!
        let topFrontEdgeRef = boxFeature.generatedTopology["edge:top-front"]!
        let cornerVertRef = boxFeature.generatedTopology["vertex:top-front-left"]!

        let extrudeFeature = Feature(
            name: "Extrude 1",
            operation: .extrude(ExtrudeFeatureData(distance: 20.0)),
            references: [
                .feature(sketchFeature.id, role: "sketch"),
                .sketchEntity(featureId: sketchFeature.id, entityId: sketchEntityId, role: "profile"),
                .body(boxFeature.outputSolidId!, role: "baseBody"),
                .face(topFaceRef, role: "capFace"),
                .edge(topFrontEdgeRef, role: "guideEdge"),
                .vertex(cornerVertRef, role: "anchorVertex")
            ]
        )
        _ = doc.insertFeature(extrudeFeature, at: 2)

        // Resolve each reference individually
        for ref in extrudeFeature.references {
            let res = doc.resolve(reference: ref, for: extrudeFeature)
            switch res {
            case .success(let resolved):
                #expect(resolved.reference == ref)
            case .failure(let err):
                Issue.record("Expected success for reference role '\(ref.role ?? "")' but got: \(err)")
            }
        }

        // Validate all references
        let validationError = ReferenceResolver.validateReferences(for: extrudeFeature, in: doc)
        #expect(validationError == nil)

        // ResolveAll returns 6 successes
        let allResults = ReferenceResolver.resolveAll(for: extrudeFeature, in: doc)
        #expect(allResults.count == 6)
        for (ref, res) in allResults {
            #expect(res.isSuccess, "Failed to resolve \(ref)")
        }

        // Dependent features lookup
        let dependentsOfSketch = doc.dependentFeatures(referencing: sketchFeature.id)
        #expect(dependentsOfSketch.contains(where: { $0.id == extrudeFeature.id }))

        let dependentsOfBox = doc.dependentFeatures(referencing: boxFeature.id)
        #expect(dependentsOfBox.contains(where: { $0.id == sketchFeature.id }))
        #expect(dependentsOfBox.contains(where: { $0.id == extrudeFeature.id }))
    }

    // MARK: - Resolution Failure Modes

    @Test func testResolutionFailureModes() {
        let doc = DocumentModel()
        let boxFeature = doc.features[0] // index 0
        let cylFeature = doc.features[1] // index 1

        // 1. Self reference
        let selfRef = Reference.feature(boxFeature.id)
        let resSelf = doc.resolve(reference: selfRef, for: boxFeature)
        #expect(resSelf == .failure(.selfReference(boxFeature.id)))

        // 2. Forward reference (feature at index 0 referencing feature at index 1)
        let fwdRef = Reference.feature(cylFeature.id)
        let resFwd = doc.resolve(reference: fwdRef, for: boxFeature)
        #expect(resFwd == .failure(.forwardReference(referencedFeatureId: cylFeature.id, currentFeatureId: boxFeature.id)))

        // 3. Target feature not found
        let missingId = UUID()
        let missingRef = Reference.feature(missingId)
        let resMissing = doc.resolve(reference: missingRef, for: cylFeature)
        #expect(resMissing == .failure(.targetFeatureNotFound(missingId)))

        // 4. Target feature suppressed
        _ = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: true)
        let suppressedRef = Reference.feature(boxFeature.id)
        let resSuppressed = doc.resolve(reference: suppressedRef, for: cylFeature)
        #expect(resSuppressed == .failure(.targetFeatureSuppressed(boxFeature.id)))
        _ = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: false)

        // 5. Target not a sketch
        let fakeEntityId = UUID()
        let notSketchRef = Reference.sketchEntity(featureId: boxFeature.id, entityId: fakeEntityId)
        let resNotSketch = doc.resolve(reference: notSketchRef, for: cylFeature)
        #expect(resNotSketch == .failure(.targetNotASketch(boxFeature.id)))

        // 6. Sketch entity not found
        let sketchFeature = Feature(
            name: "Empty Sketch",
            operation: .sketch(SketchFeatureData(entities: []))
        )
        _ = doc.insertFeature(sketchFeature, at: 1)
        let missingEntityRef = Reference.sketchEntity(featureId: sketchFeature.id, entityId: fakeEntityId)
        let resMissingEntity = doc.resolve(reference: missingEntityRef, for: cylFeature)
        #expect(resMissingEntity == .failure(.sketchEntityNotFound(featureId: sketchFeature.id, entityId: fakeEntityId)))

        // 7. Body not found
        let missingSolid = SolidId("unknown-solid")
        let missingBodyRef = Reference.body(missingSolid)
        let resMissingBody = doc.resolve(reference: missingBodyRef, for: cylFeature)
        #expect(resMissingBody == .failure(.bodyNotFound(missingSolid)))

        // 8. Topological source feature not found
        let randomFeatId = UUID()
        let missingTopRef = TopologicalReference(sourceFeatureId: randomFeatId, elementType: .face)
        let resMissingTopSource = doc.resolve(reference: .face(missingTopRef), for: cylFeature)
        #expect(resMissingTopSource == .failure(.topologicalSourceFeatureNotFound(randomFeatId)))

        // 9. Topological source feature suppressed
        _ = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: true)
        let faceRef = boxFeature.generatedTopology["face:top"]!
        let resSuppressedTop = doc.resolve(reference: .face(faceRef), for: cylFeature)
        #expect(resSuppressedTop == .failure(.topologicalSourceFeatureSuppressed(boxFeature.id)))
        _ = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: false)

        // 10. Type mismatch: face reference wrapping edge topological reference
        let edgeRef = boxFeature.generatedTopology["edge:top-front"]!
        let mismatchedFaceRef = Reference.face(edgeRef)
        let resMismatch = doc.resolve(reference: mismatchedFaceRef, for: cylFeature)
        #expect(resMismatch == .failure(.typeMismatch(expected: "face", actual: "edge")))

        // 11. Topological element missing from source feature topology
        let ghostTopRef = TopologicalReference(
            id: UUID(),
            sourceFeatureId: boxFeature.id,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:nonexistent")]
        )
        let resGhost = doc.resolve(reference: .face(ghostTopRef), for: cylFeature)
        #expect(resGhost == .failure(.topologicalElementMissing(ghostTopRef)))
    }

    // MARK: - Kernel Regeneration Integration

    @Test func testRegenerationRecordsBrokenReferenceError() async {
        let doc = DocumentModel()
        let boxFeature = doc.features[0]

        // Create a dependent feature downstream of boxFeature
        let dependentFeature = Feature(
            name: "Box Dependent",
            operation: .primitive(.box(BoxParams(width: 15, depth: 15, height: 15))),
            references: [.feature(boxFeature.id, role: "parentBox")],
            outputSolidId: SolidId("dep-1")
        )
        _ = doc.insertFeature(dependentFeature, at: 1)

        let client = RecordingKernelClient()

        // 1. Initial regeneration succeeds for all features
        await KernelRegeneration.regenerate(document: doc, client: client, excluding: nil)
        #expect(doc.features[1].errorState == nil)
        #expect(client.requestedSolids.contains(SolidId("dep-1")))

        // 2. Suppress the upstream feature
        _ = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: true)
        client.requestedSolids.removeAll()

        await KernelRegeneration.regenerate(document: doc, client: client, excluding: nil)

        // Dependent feature references suppressed box, so it gets reference-broken error and is NOT dispatched
        let depFeatureAfterSuppression = doc.features[1]
        #expect(depFeatureAfterSuppression.errorState?.code == "reference-broken")
        #expect(!client.requestedSolids.contains(SolidId("dep-1")))

        // 3. Unsuppress the upstream feature and re-regenerate
        _ = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: false)
        client.requestedSolids.removeAll()

        await KernelRegeneration.regenerate(document: doc, client: client, excluding: nil)

        // Error is cleared and kernel request dispatched
        let depFeatureRestored = doc.features[1]
        #expect(depFeatureRestored.errorState == nil)
        #expect(client.requestedSolids.contains(SolidId("dep-1")))
    }

    // MARK: - Transitive Dependency Resolution (BL-FND-03)

    @Test func testTransitiveDependentFeaturesLookup() {
        let doc = DocumentModel(features: [])

        let featA = Feature.makeBox(solidId: SolidId("a"), params: BoxParams(width: 10, depth: 10, height: 10))
        _ = doc.addFeature(featA)

        let featB = Feature(
            name: "B",
            operation: .primitive(.cylinder(CylinderParams(radius: 5, height: 10))),
            references: [.feature(featA.id)],
            outputSolidId: SolidId("b")
        )
        _ = doc.addFeature(featB)

        let featD = Feature(
            name: "D",
            operation: .primitive(.box(BoxParams(width: 5, depth: 5, height: 5))),
            references: [.feature(featA.id)],
            outputSolidId: SolidId("d")
        )
        _ = doc.addFeature(featD)

        let featC = Feature(
            name: "C",
            operation: .primitive(.cylinder(CylinderParams(radius: 2, height: 4))),
            references: [.feature(featB.id)],
            outputSolidId: SolidId("c")
        )
        _ = doc.addFeature(featC)

        let featE = Feature.makeBox(solidId: SolidId("e"), params: BoxParams(width: 8, depth: 8, height: 8))
        _ = doc.addFeature(featE)

        // Dependents of A in topological timeline order: B, D, C (E is independent)
        let depsA = doc.dependentFeatures(referencing: featA.id)
        #expect(depsA.map(\.id) == [featB.id, featD.id, featC.id])

        // Dependents of B: C
        let depsB = doc.dependentFeatures(referencing: featB.id)
        #expect(depsB.map(\.id) == [featC.id])

        // Dependents of D: empty
        let depsD = doc.dependentFeatures(referencing: featD.id)
        #expect(depsD.isEmpty)

        // Dependents of C: empty
        let depsC = doc.dependentFeatures(referencing: featC.id)
        #expect(depsC.isEmpty)

        // Dependents of non-existent UUID: empty
        #expect(doc.dependentFeatures(referencing: UUID()).isEmpty)

        // Direct dependent features of A: [B, D] (not transitive C)
        let directDepsA = doc.directDependentFeatures(referencing: featA.id)
        #expect(directDepsA.map(\.id) == [featB.id, featD.id])
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
