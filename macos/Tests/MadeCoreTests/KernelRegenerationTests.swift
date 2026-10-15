import Testing
import Foundation
@testable import MadeCore

@MainActor
@Suite struct KernelRegenerationTests {
    @Test func testRequestForEachKind() {
        let box = BoxParams(width: 1, depth: 2, height: 3)
        let cylinder = CylinderParams(radius: 4, height: 5)
        let jobId = JobId("j")
        let id = SolidId("s")
        #expect(KernelRegeneration.request(for: object(id, .box(box)), jobId: jobId) == .makeBox(jobId: jobId, solidId: id, params: box))
        #expect(KernelRegeneration.request(for: object(id, .cylinder(cylinder)), jobId: jobId)
                == .makeCylinder(jobId: jobId, solidId: id, params: cylinder))
    }
    
    @Test func testImportedObjectsAreSkipped() {
        #expect(KernelRegeneration.request(for: object(SolidId("i"), .imported(name: "part.step")), jobId: JobId("j")) == nil)
    }

    @Test func testImportedObjectWithDataProducesImportStepRequest() {
        let data = Data([1, 2, 3])
        let id = SolidId("imported-with-data")
        let jobId = JobId("j")
        #expect(KernelRegeneration.request(for: object(id, .imported(name: "box.step", data: data)), jobId: jobId)
                == .importStep(jobId: jobId, solidId: id, data: data))
    }

    @Test func testImportedObjectWithSourceURLProducesImportStepRequest() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".step")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let sampleData = Data([4, 5, 6])
        try sampleData.write(to: tempURL)
        
        let id = SolidId("imported-with-url")
        let jobId = JobId("j")
        #expect(KernelRegeneration.request(for: object(id, .imported(name: "box.step", sourceURL: tempURL)), jobId: jobId)
                == .importStep(jobId: jobId, solidId: id, data: sampleData))
    }
    
    @Test func testBooleanObjectsProduceBooleanOperationRequest() {
        let def = ObjectDef.boolean(op: .subtract, solidA: boxSolidId, solidB: cylinderSolidId)
        let jobId = JobId("j")
        let id = SolidId("boolean-3")
        #expect(KernelRegeneration.request(for: object(id, def), jobId: jobId)
                == .booleanOperation(jobId: jobId, solidId: id, op: .subtract, solidA: boxSolidId, solidB: cylinderSolidId))
    }
    
    @Test func testRegenerateExcludesSolidAndRepopulatesCache() async {
        let document = DocumentModel()
        let kept = document.addObject(def: .cylinder(CylinderParams(radius: 3, height: 4)))
        let boolSolid = document.addObject(def: .boolean(op: .subtract, solidA: boxSolidId, solidB: cylinderSolidId))
        let culprit = document.addObject(def: .box(BoxParams(width: 1, depth: 1, height: 1)))
        let imported = document.addObject(def: .imported(name: "part.step"))
        // A fresh client stands in for a restarted service: it holds no solids.
        let client = KernelClient(debounceDuration: .milliseconds(5))
        
        await KernelRegeneration.regenerate(document: document, client: client, excluding: culprit)
        
        for id in document.objects.map(\.id) where id != culprit && id != imported {
            #expect(await client.request(.tessellate(jobId: JobId("t-\(id)"), solidId: id)).isSuccess)
        }
        #expect(await client.request(.tessellate(jobId: JobId("t-kept"), solidId: kept)).isSuccess)
        #expect(await client.request(.tessellate(jobId: JobId("t-bool"), solidId: boolSolid)).isSuccess)
        #expect(await client.request(.tessellate(jobId: JobId("t-culprit"), solidId: culprit)).error?.code == .unknownSolid)
        #expect(await client.request(.tessellate(jobId: JobId("t-imported"), solidId: imported)).error?.code == .unknownSolid)
    }
    
    @Test func testSequentialFeatureRegenerationWalksInOrder() async {
        let document = DocumentModel()
        _ = document.addObject(def: .boolean(op: .subtract, solidA: boxSolidId, solidB: cylinderSolidId))

        let client = RecordingKernelClient()
        await KernelRegeneration.regenerate(document: document, client: client, excluding: nil)

        #expect(client.requestedSolids.count == 3)
        #expect(client.requestedSolids[0] == boxSolidId)
        #expect(client.requestedSolids[1] == cylinderSolidId)
        #expect(client.requestedSolids[2] == SolidId("boolean-2"))
    }

    @Test func testRegenerationSkipsSuppressedFeatures() async {
        let document = DocumentModel()
        let boxFeature = document.features[0]
        _ = document.setFeatureSuppressed(id: boxFeature.id, isSuppressed: true)

        let client = RecordingKernelClient()
        await KernelRegeneration.regenerate(document: document, client: client, excluding: nil)

        #expect(!client.requestedSolids.contains(boxSolidId))
        #expect(client.requestedSolids == [cylinderSolidId])
    }

    @Test func testRegenerationRecordsFeatureErrorOnFailure() async {
        let document = DocumentModel()
        let client = RecordingKernelClient()
        client.failureCode = .geometryFailed

        await KernelRegeneration.regenerate(document: document, client: client, excluding: nil)

        #expect(document.features[0].errorState?.code == "geometry-failed")
        #expect(document.features[1].errorState?.code == "geometry-failed")

        // Clearing error on successful subsequent regeneration
        client.failureCode = nil
        await KernelRegeneration.regenerate(document: document, client: client, excluding: nil)

        #expect(document.features[0].errorState == nil)
        #expect(document.features[1].errorState == nil)
    }

    @Test func testRequestForFeatureOperations() {
        let boxFeature = Feature.makeBox(solidId: SolidId("b"), params: BoxParams(width: 10, depth: 20, height: 30))
        let cylinderFeature = Feature.makeCylinder(solidId: SolidId("c"), params: CylinderParams(radius: 5, height: 15))
        let boolFeature = Feature(
            name: "Bool",
            operation: .boolean(BooleanFeatureData(op: .union, targetSolidId: SolidId("b"), toolSolidId: SolidId("c"))),
            outputSolidId: SolidId("u")
        )
        let partFeature = Feature(
            name: "Part",
            operation: .part(PartFeatureData(url: URL(fileURLWithPath: "/tmp/part.ts"), shape: .box(BoxParams(width: 1, depth: 1, height: 1)))),
            outputSolidId: SolidId("p")
        )
        let importedFeature = Feature(
            name: "Imp",
            operation: .imported(ImportedFeatureData(name: "x.step", data: Data([1, 2]))),
            outputSolidId: SolidId("i")
        )
        let unmeshedSketch = Feature(
            name: "Sketch",
            operation: .sketch(SketchFeatureData())
        )

        let j = JobId("j")
        #expect(KernelRegeneration.request(for: boxFeature, jobId: j) == .makeBox(jobId: j, solidId: SolidId("b"), params: BoxParams(width: 10, depth: 20, height: 30)))
        #expect(KernelRegeneration.request(for: cylinderFeature, jobId: j) == .makeCylinder(jobId: j, solidId: SolidId("c"), params: CylinderParams(radius: 5, height: 15)))
        #expect(KernelRegeneration.request(for: boolFeature, jobId: j) == .booleanOperation(jobId: j, solidId: SolidId("u"), op: .union, solidA: SolidId("b"), solidB: SolidId("c")))
        #expect(KernelRegeneration.request(for: partFeature, jobId: j) == .evaluateShape(jobId: j, solidId: SolidId("p"), shape: .box(BoxParams(width: 1, depth: 1, height: 1))))
        #expect(KernelRegeneration.request(for: importedFeature, jobId: j) == .importStep(jobId: j, solidId: SolidId("i"), data: Data([1, 2])))
        #expect(KernelRegeneration.request(for: unmeshedSketch, jobId: j) == nil)
    }

    // MARK: - Incremental Regeneration Tests (BL-FND-03)

    @Test func testIncrementalRegenerationOnlyDispatchesRootAndDependents() async {
        let document = DocumentModel()
        let boxFeature = document.features[0]

        // Add an independent cylinder solid
        let independentId = document.addObject(def: .cylinder(CylinderParams(radius: 10, height: 20)))

        // Add a boolean feature combining box-1 and cylinder-1
        let boolId = document.reserveId(for: .boolean(op: .subtract, solidA: boxSolidId, solidB: cylinderSolidId))
        let boolFeature = Feature(
            name: "Cut",
            operation: .boolean(BooleanFeatureData(op: .subtract, targetSolidId: boxSolidId, toolSolidId: cylinderSolidId)),
            outputSolidId: boolId
        )
        _ = document.addFeature(boolFeature)

        let client = RecordingKernelClient()
        // Regenerate incrementally from boxFeature
        await KernelRegeneration.regenerateIncremental(from: boxFeature.id, in: document, client: client)

        // boxFeature and its dependent boolFeature should be dispatched
        #expect(client.requestedSolids.contains(boxSolidId))
        #expect(client.requestedSolids.contains(boolId))

        // cylinder-1 and independent solid must be untouched (0 kernel requests)
        #expect(!client.requestedSolids.contains(cylinderSolidId))
        #expect(!client.requestedSolids.contains(independentId))
        #expect(client.requestedSolids.count == 2)
    }

    @Test func testIncrementalRegenerationDiamondDependencyDeduplication() async {
        let document = DocumentModel(features: [])

        // Feature A (root)
        let solidA = SolidId("solid-a")
        let featureA = Feature.makeBox(solidId: solidA, params: BoxParams(width: 10, depth: 10, height: 10))
        _ = document.addFeature(featureA)

        // Feature B (depends on A)
        let solidB = SolidId("solid-b")
        let featureB = Feature(
            name: "Feature B",
            operation: .primitive(.box(BoxParams(width: 12, depth: 12, height: 12))),
            references: [.feature(featureA.id)],
            outputSolidId: solidB
        )
        _ = document.addFeature(featureB)

        // Feature C (depends on A)
        let solidC = SolidId("solid-c")
        let featureC = Feature(
            name: "Feature C",
            operation: .primitive(.box(BoxParams(width: 14, depth: 14, height: 14))),
            references: [.feature(featureA.id)],
            outputSolidId: solidC
        )
        _ = document.addFeature(featureC)

        // Feature D (depends on B and C - diamond join)
        let solidD = SolidId("solid-d")
        let featureD = Feature(
            name: "Feature D",
            operation: .boolean(BooleanFeatureData(op: .union, targetSolidId: solidB, toolSolidId: solidC)),
            references: [.feature(featureB.id), .feature(featureC.id)],
            outputSolidId: solidD
        )
        _ = document.addFeature(featureD)

        // Feature E (independent)
        let solidE = SolidId("solid-e")
        let featureE = Feature.makeCylinder(solidId: solidE, params: CylinderParams(radius: 5, height: 10))
        _ = document.addFeature(featureE)

        let client = RecordingKernelClient()
        await KernelRegeneration.regenerateIncremental(from: featureA.id, in: document, client: client)

        // Evaluated in topological order: A first, B and C, then D
        #expect(client.requestedSolids.count == 4)
        #expect(client.requestedSolids[0] == solidA)
        #expect(client.requestedSolids[1] == solidB)
        #expect(client.requestedSolids[2] == solidC)
        #expect(client.requestedSolids[3] == solidD)

        // D evaluates exactly once
        #expect(client.requestedSolids.filter { $0 == solidD }.count == 1)

        // Independent E issues 0 requests
        #expect(!client.requestedSolids.contains(solidE))
    }

    @Test func testIncrementalRegenerationNonSolidSketchPropagatesToExtrusion() async {
        let document = DocumentModel()
        // Has box-1 and cylinder-1 by default

        let sketchEntityId = UUID()
        let sketchFeature = Feature(
            name: "Sketch 1",
            operation: .sketch(SketchFeatureData(
                planeName: "XY",
                entities: [SketchEntity(id: sketchEntityId, kind: "circle", data: ["radius": 5.0])]
            ))
        )
        _ = document.addFeature(sketchFeature)

        let extrudeSolidId = SolidId("extrude-1")
        let extrudeFeature = Feature(
            name: "Extrude 1",
            operation: .primitive(.box(BoxParams(width: 10, depth: 10, height: 20))),
            references: [.feature(sketchFeature.id, role: "sketchProfile")],
            outputSolidId: extrudeSolidId
        )
        _ = document.addFeature(extrudeFeature)

        let client = RecordingKernelClient()
        await KernelRegeneration.regenerateIncremental(from: sketchFeature.id, in: document, client: client)

        // Sketch has no solid output / request, so issues 0 requests
        // Extrusion produces solid, so recomputes
        #expect(client.requestedSolids == [extrudeSolidId])
        #expect(!client.requestedSolids.contains(boxSolidId))
        #expect(!client.requestedSolids.contains(cylinderSolidId))
    }

    @Test func testIncrementalRegenerationSuppressedUpstreamRecordsBrokenReference() async {
        let document = DocumentModel()
        let boxFeature = document.features[0]

        let depSolidId = SolidId("dep-solid")
        let depFeature = Feature(
            name: "Dependent",
            operation: .primitive(.box(BoxParams(width: 5, depth: 5, height: 5))),
            references: [.feature(boxFeature.id, role: "parent")],
            outputSolidId: depSolidId
        )
        _ = document.addFeature(depFeature)

        // Suppress upstream boxFeature
        _ = document.setFeatureSuppressed(id: boxFeature.id, isSuppressed: true)

        let client = RecordingKernelClient()
        await KernelRegeneration.regenerateIncremental(from: boxFeature.id, in: document, client: client)

        // Dependent feature records reference-broken error and is not dispatched
        let depFeatureAfter = document.feature(for: depFeature.id)
        #expect(depFeatureAfter?.errorState?.code == "reference-broken")
        #expect(!client.requestedSolids.contains(depSolidId))
        #expect(!client.requestedSolids.contains(boxSolidId))
        #expect(client.requestedSolids.isEmpty)
    }

    @Test func testIncrementalRegenerationUnknownFeatureIdIsNoOp() async {
        let document = DocumentModel()
        let client = RecordingKernelClient()

        let unknownId = UUID()
        await KernelRegeneration.regenerateIncremental(from: unknownId, in: document, client: client)

        #expect(client.requestedSolids.isEmpty)
    }

    private func object(_ id: SolidId, _ def: ObjectDef) -> SceneObject {
        SceneObject(id: id, name: id.rawValue, def: def)
    }
}

final class RecordingKernelClient: KernelClientProtocol, @unchecked Sendable {
    var requestedSolids: [SolidId] = []
    var failureCode: KernelErrorCode?

    func request(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        requestedSolids.append(request.solidId)
        if let failureCode {
            return .failure(jobId: request.jobId, error: KernelError(code: failureCode, message: "Simulated kernel failure"))
        }
        return .success(jobId: request.jobId, value: MeshPayload(positions: [], normals: [], indices: []))
    }

    func cancel(jobId: JobId) async {}
    func dispose(solidId: SolidId) async {}
    func getStats() async -> KernelStats { KernelStats() }
}

