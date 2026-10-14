import Foundation
import Metal

/// Serves `cad_capture_snapshot` in `--mcp-stdio` mode, where no window renderer holds the document's meshes.
/// Each capture tessellates the document into an offscreen target, then renders it.
@MainActor
public final class HeadlessSnapshotProvider: SnapshotProvider {
    private let document: DocumentModel
    private let kernelClient: any KernelClientProtocol
    private let target: any HeadlessSnapshotTarget

    public init(document: DocumentModel, kernelClient: any KernelClientProtocol, target: any HeadlessSnapshotTarget) {
        self.document = document
        self.kernelClient = kernelClient
        self.target = target
    }

    /// Returns nil when no Metal 4 device can build a renderer, so the tool reports the snapshot as unavailable.
    public static func make(
        document: DocumentModel,
        kernelClient: any KernelClientProtocol,
        device: MTLDevice? = MTLCreateSystemDefaultDevice()
    ) -> HeadlessSnapshotProvider? {
        guard let device, let renderer = MetalRenderer(device: device) else { return nil }
        return HeadlessSnapshotProvider(document: document, kernelClient: kernelClient, target: renderer)
    }

    public func captureSnapshotPngBase64() async -> String? {
        await captureSnapshotPngBase64(view: nil)
    }

    public func captureSnapshotPngBase64(view: ViewportPerspective?) async -> String? {
        // The frame shows the document as it was when the capture was requested.
        let objects = document.objects
        target.removeMeshes(notIn: Set(objects.map(\.id)))

        // Each solid gets a second request with a fresh job ID, used only if the first is conflated.
        let pairs = objects.compactMap { object -> (KernelRequest, KernelRequest)? in
            guard let first = KernelRegeneration.request(for: object, jobId: Self.jobId()),
                  let retry = KernelRegeneration.request(for: object, jobId: Self.jobId()) else { return nil }
            return (first, retry)
        }
        let client = kernelClient
        let results = await withTaskGroup(of: (SolidId, KernelResult<MeshPayload>).self) { group in
            for (first, retry) in pairs {
                group.addTask { (first.solidId, await Self.request(first, retry: retry, client: client)) }
            }
            var collected: [(SolidId, KernelResult<MeshPayload>)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        for (id, result) in results {
            // A failed solid keeps its previous mesh, as the window viewport does.
            _ = SolidMeshApplier.apply(result, to: id, document: document, sink: target)
        }
        return await target.captureSnapshotPngBase64(view: view)
    }

    /// A concurrent edit to the same solid conflates this request into `.cancelled`; one resubmission recovers a mesh.
    private nonisolated static func request(
        _ first: KernelRequest,
        retry: KernelRequest,
        client: any KernelClientProtocol
    ) async -> KernelResult<MeshPayload> {
        let result = await client.request(first)
        guard case .failure(_, let error) = result, error.code == .cancelled else { return result }
        return await client.request(retry)
    }

    private nonisolated static func jobId() -> JobId {
        JobId("snapshot-\(UUID().uuidString)")
    }
}
