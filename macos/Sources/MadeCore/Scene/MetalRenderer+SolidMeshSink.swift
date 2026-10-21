/// Declared here, not in `Viewport/`, so the viewport names no Scene type (invariant 3).
extension MetalRenderer: @MainActor SolidMeshSink {
    public func candidateMesh(for id: SolidId) -> CandidateMesh? {
        guard let mesh = meshes[id] else { return nil }
        var candidate = mesh.candidateMesh
        candidate.transform = mesh.transform
        return candidate
    }
}
