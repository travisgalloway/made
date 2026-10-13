import Testing
import Foundation
import Metal
import simd
import ImageIO
@testable import MadeCore

@MainActor
private final class StubTarget: HeadlessSnapshotTarget {
    var installed: [SolidId] = []
    var meshes: Set<SolidId> = []
    var removalCalls = 0
    var snapshot: String? = "c3R1Yg=="

    func installMesh(_ payload: MeshPayload, for id: SolidId, transform: Transform, color: SIMD4<Float>, isHidden: Bool) -> Bool {
        installed.append(id)
        meshes.insert(id)
        return true
    }

    func removeMeshes(notIn ids: Set<SolidId>) {
        removalCalls += 1
        meshes.formIntersection(ids)
    }

    func captureSnapshotPngBase64() async -> String? { snapshot }
}

/// Answers each solid's first request with the `.cancelled` result `KernelClient` gives a conflated job.
private actor ConflatesFirstRequestClient: KernelClientProtocol {
    private let inner = KernelClient(debounceDuration: .milliseconds(5))
    private var seen: Set<SolidId> = []
    private(set) var requestCount = 0

    func request(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        requestCount += 1
        guard seen.insert(request.solidId).inserted else { return await inner.request(request) }
        return .failure(jobId: request.jobId, error: KernelError(code: .cancelled, message: "Conflated by newer request"))
    }

    func cancel(jobId: JobId) async { await inner.cancel(jobId: jobId) }
    func dispose(solidId: SolidId) async { await inner.dispose(solidId: solidId) }
    func getStats() async -> KernelStats { await inner.getStats() }
}

@MainActor
@Suite struct HeadlessSnapshotProviderTests {
    private func makeFixture() -> (DocumentModel, KernelClient, StubTarget, HeadlessSnapshotProvider, CADToolRegistry) {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let target = StubTarget()
        let provider = HeadlessSnapshotProvider(document: doc, kernelClient: kernel, target: target)
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: provider)
        return (doc, kernel, target, provider, registry)
    }

    @Test func testEmptyDocumentCapturesWithoutInstalling() async {
        let (doc, _, target, provider, _) = makeFixture()
        for object in doc.objects { doc.removeObject(id: object.id) }

        let snapshot = await provider.captureSnapshotPngBase64()

        #expect(snapshot == target.snapshot)
        #expect(target.installed.isEmpty)
    }

    @Test func testSolidAddedOverMCPIsInstalledBeforeCapture() async throws {
        let (doc, _, target, provider, registry) = makeFixture()
        let added = await registry.callTool(name: "cad_add_solid", arguments: ["type": .string("box")])
        #expect(added.isError == false)
        let newId = try #require(doc.objects.last?.id)

        _ = await provider.captureSnapshotPngBase64()

        #expect(Set(target.installed) == Set(doc.objects.map(\.id)))
        #expect(target.meshes.contains(newId))
    }

    @Test func testSolidRemovedOverMCPIsPrunedOnNextCapture() async {
        let (_, _, target, provider, registry) = makeFixture()
        _ = await provider.captureSnapshotPngBase64()
        #expect(target.meshes.contains(cylinderSolidId))

        let removed = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string(cylinderSolidId.rawValue)])
        #expect(removed.isError == false)
        _ = await provider.captureSnapshotPngBase64()

        #expect(!target.meshes.contains(cylinderSolidId))
        #expect(target.meshes.contains(boxSolidId))
    }

    @Test func testCaptureDuringPendingRecomputeStillInstallsMesh() async {
        let (_, kernel, target, provider, _) = makeFixture()
        let edit = KernelRequest.makeBox(jobId: JobId("edit"), solidId: boxSolidId, params: BoxParams(width: 50, depth: 30, height: 20))

        // Interleave a recompute with the capture's requests so one of them is conflated into `.cancelled`.
        async let editResult = kernel.request(edit)
        let snapshot = await provider.captureSnapshotPngBase64()
        _ = await editResult

        #expect(snapshot == target.snapshot)
        #expect(target.meshes.contains(boxSolidId))
        #expect(target.meshes.contains(cylinderSolidId))
    }

    @Test func testConflatedRequestIsRetriedOnce() async {
        let doc = DocumentModel()
        let kernel = ConflatesFirstRequestClient()
        let target = StubTarget()
        let provider = HeadlessSnapshotProvider(document: doc, kernelClient: kernel, target: target)

        _ = await provider.captureSnapshotPngBase64()

        #expect(target.meshes == Set(doc.objects.map(\.id)))
        #expect(await kernel.requestCount == doc.objects.count * 2)
    }

    @Test func testMakeWithoutDeviceReturnsNil() {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        #expect(HeadlessSnapshotProvider.make(document: doc, kernelClient: kernel, device: nil) == nil)
    }

    @Test func testRegistryReturnsPngImageFromProvider() async {
        let (_, _, _, provider, registry) = makeFixture()
        let result = await registry.callTool(name: "cad_capture_snapshot", arguments: [:])
        withExtendedLifetime(provider) {}
        #expect(result.isError == false)
        #expect(result.content.first?.type == "image")
        #expect(result.content.first?.mimeType == "image/png")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testRealRendererCapturesAddedSolid() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let provider = try #require(HeadlessSnapshotProvider.make(document: doc, kernelClient: kernel, device: device))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: provider)

        _ = await registry.callTool(name: "cad_add_solid", arguments: ["type": .string("box"), "posZ": .double(40)])
        let result = await registry.callTool(name: "cad_capture_snapshot", arguments: [:])

        #expect(result.isError == false)
        let base64 = try #require(result.content.first?.data)
        let data = try #require(Data(base64Encoded: base64))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 800)
        #expect(image.height == 600)
        withExtendedLifetime(provider) {}
    }
}
