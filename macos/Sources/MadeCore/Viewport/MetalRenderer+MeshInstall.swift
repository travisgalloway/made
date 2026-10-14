import Foundation
import simd

extension MetalRenderer {
    /// Installs a finished mesh. The Scene directory declares the protocol conformance this method witnesses (invariant 3).
    @MainActor
    public func installMesh(_ payload: MeshPayload, for id: SolidId, transform: Transform, color: SIMD4<Float>, isHidden: Bool) -> Bool {
        guard let mesh = createMesh(from: payload, solidId: id, transform: transform, color: color) else { return false }
        meshes[id] = mesh
        if isHidden {
            hiddenSolidIds.insert(id)
        } else {
            hiddenSolidIds.remove(id)
        }
        return true
    }

    /// Updates an installed mesh's transform in place without rebuilding GPU buffers.
    @MainActor
    public func updateTransform(_ transform: Transform, for id: SolidId) -> Bool {
        guard var mesh = meshes[id] else { return false }
        mesh.transform = transform
        mesh.candidateMesh.transform = transform
        meshes[id] = mesh
        return true
    }

    /// Removes the mesh and hidden flag for `id`.
    @MainActor
    public func removeMesh(for id: SolidId) -> Bool {
        hiddenSolidIds.remove(id)
        return meshes.removeValue(forKey: id) != nil
    }
}
