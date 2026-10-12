import Foundation
import simd

/// Receives a finished solid mesh; MetalRenderer is the production sink.
@MainActor
public protocol SolidMeshSink: AnyObject {
    /// Returns false when the mesh could not be built (buffer allocation failed).
    func installMesh(_ payload: MeshPayload, for id: SolidId, transform: Transform, color: SIMD4<Float>, isHidden: Bool) -> Bool
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

    static func displayTransform(for id: SolidId, _ transform: Transform) -> Transform {
        var transform = transform
        if transform.position == .zero {
            // Spreads the two demo solids apart until the document stores real positions.
            transform.position = id == boxSolidId ? SIMD3<Float>(-25, 0, 0) : SIMD3<Float>(25, 0, 0)
        }
        return transform
    }
}
