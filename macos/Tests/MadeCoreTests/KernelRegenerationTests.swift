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

