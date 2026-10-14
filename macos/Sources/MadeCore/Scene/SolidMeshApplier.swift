import Foundation
import simd

/// Receives a finished solid mesh; MetalRenderer is the production sink.
@MainActor
public protocol SolidMeshSink: AnyObject {
    /// Returns false when the mesh could not be built (buffer allocation failed).
    func installMesh(_ payload: MeshPayload, for id: SolidId, transform: Transform, color: SIMD4<Float>, isHidden: Bool) -> Bool
    /// Updates an installed mesh's transform in place. Returns false when no mesh is installed for `id`.
    func updateTransform(_ transform: Transform, for id: SolidId) -> Bool
    /// Removes the mesh for `id`, if any. Returns true when a mesh was present.
    func removeMesh(for id: SolidId) -> Bool
}

extension SolidMeshSink {
    public func updateTransform(_ transform: Transform, for id: SolidId) -> Bool { false }
    public func removeMesh(for id: SolidId) -> Bool { false }
}

@MainActor
public enum SolidMeshApplier {
    /// Installs a kernel result using the document's state at this moment, not at request time.
    /// Returns true when a mesh was installed and the viewport needs a redraw.
    public static func apply(
        _ result: KernelResult<MeshPayload>,
        to id: SolidId,
        document: DocumentModel,
        sink: SolidMeshSink
    ) -> Bool {
        guard case .success(_, let payload) = result else { return false }
        // A solid removed during the recompute must stay removed.
        guard let object = document.objects.first(where: { $0.id == id }) else { return false }
        return sink.installMesh(
            payload,
            for: id,
            transform: displayTransform(for: id, object.transform),
            color: object.material.color,
            isHidden: !object.isVisible
        )
    }

    /// Updates an installed mesh's transform from the document's live state.
    /// Returns true when the mesh was updated and the viewport needs a redraw.
    public static func applyTransform(
        to id: SolidId,
        document: DocumentModel,
        sink: SolidMeshSink
    ) -> Bool {
        guard let object = document.objects.first(where: { $0.id == id }) else { return false }
        return sink.updateTransform(displayTransform(for: id, object.transform), for: id)
    }

    /// Drops an installed mesh for a removed solid. Returns true when a mesh was removed.
    public static func remove(id: SolidId, from sink: SolidMeshSink) -> Bool {
        sink.removeMesh(for: id)
    }

    static func displayTransform(for id: SolidId, _ transform: Transform) -> Transform {
        var transform = transform
        if transform.position == .zero {
            // Spreads the two demo solids apart until the document stores real positions.
            transform.position = id == boxSolidId ? SIMD3<Float>(-25, 0, 0) : SIMD3<Float>(25, 0, 0)
        }
        return transform
    }
}
