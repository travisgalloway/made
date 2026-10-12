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
}
