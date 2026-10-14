import Foundation

/// A renderer the headless snapshot provider can fill with meshes, prune, and capture.
@MainActor
public protocol HeadlessSnapshotTarget: SolidMeshSink {
    /// Drops every mesh whose solid is not in `ids`, so solids removed from the document leave the frame.
    func removeMeshes(notIn ids: Set<SolidId>)
    func captureSnapshotPngBase64() async -> String?
    func captureSnapshotPngBase64(view: ViewportPerspective?) async -> String?
}

public extension HeadlessSnapshotTarget {
    func captureSnapshotPngBase64(view: ViewportPerspective?) async -> String? {
        await captureSnapshotPngBase64()
    }
}

/// Declared here, not in `Viewport/`, so the viewport names no Agent type (invariant 3).
extension MetalRenderer: @MainActor HeadlessSnapshotTarget {
    @MainActor
    public func removeMeshes(notIn ids: Set<SolidId>) {
        meshes = meshes.filter { ids.contains($0.key) }
        hiddenSolidIds.formIntersection(ids)
    }
}
