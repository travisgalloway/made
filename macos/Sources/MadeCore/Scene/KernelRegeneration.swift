import Foundation

/// Rebuilds kernel requests from the document, so a restarted kernel service can be repopulated.
@MainActor
public enum KernelRegeneration {
    /// The request that recomputes `object`, or nil for objects the kernel cannot build from parameters.
    public static func request(for object: SceneObject, jobId: JobId) -> KernelRequest? {
        switch object.def {
        case .box(let params): return .makeBox(jobId: jobId, solidId: object.id, params: params)
        case .cylinder(let params): return .makeCylinder(jobId: jobId, solidId: object.id, params: params)
        case .imported: return nil
        }
    }
    
    /// Resubmits every buildable object except `excluded`, the solid whose job stopped the service.
    public static func regenerate(document: DocumentModel, client: any KernelClientProtocol, excluding excluded: SolidId?) async {
        let requests = document.objects
            .filter { $0.id != excluded }
            .compactMap { request(for: $0, jobId: JobId("regen-\(UUID().uuidString)")) }
        await withTaskGroup(of: Void.self) { group in
            for request in requests {
                group.addTask { _ = await client.request(request) }
            }
        }
    }
}
