import Foundation

/// Rebuilds kernel requests from the document, so a restarted kernel service can be repopulated.
@MainActor
public enum KernelRegeneration {
    /// The request that recomputes `object`, or nil for objects the kernel cannot build from parameters.
    public static func request(for object: SceneObject, jobId: JobId) -> KernelRequest? {
        switch object.def {
        case .box(let params): return .makeBox(jobId: jobId, solidId: object.id, params: params)
        case .cylinder(let params): return .makeCylinder(jobId: jobId, solidId: object.id, params: params)
        case .part(_, let shape):
            guard let shape else { return nil }
            return .evaluateShape(jobId: jobId, solidId: object.id, shape: shape)
        case .boolean(let op, let solidA, let solidB):
            return .booleanOperation(jobId: jobId, solidId: object.id, op: op, solidA: solidA, solidB: solidB)
        case .imported: return nil
        }
    }
    
    /// Resubmits every buildable object except `excluded`, the solid whose job stopped the service.
    /// Base solids are submitted concurrently, followed by boolean operations in topological order.
    public static func regenerate(document: DocumentModel, client: any KernelClientProtocol, excluding excluded: SolidId?) async {
        let candidateObjects = document.objects.filter { $0.id != excluded }
        var baseRequests: [KernelRequest] = []
        var booleanRequests: [KernelRequest] = []
        for obj in candidateObjects {
            guard let req = request(for: obj, jobId: JobId("regen-\(UUID().uuidString)")) else { continue }
            if case .booleanOperation = req {
                booleanRequests.append(req)
            } else {
                baseRequests.append(req)
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for req in baseRequests {
                group.addTask { _ = await client.request(req) }
            }
        }
        for req in booleanRequests {
            _ = await client.request(req)
        }
    }
}

