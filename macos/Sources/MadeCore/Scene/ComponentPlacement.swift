import Foundation
import simd

/// A component instance pending interactive viewport placement.
public struct PendingComponentPlacement: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var reference: ComponentReference
    public var material: MaterialAttributes?

    public init(
        id: UUID = UUID(),
        name: String,
        reference: ComponentReference,
        material: MaterialAttributes? = nil
    ) {
        self.id = id
        self.name = name
        self.reference = reference
        self.material = material
    }
}

/// Solves 3D placement coordinates for interactive component insertion.
public enum ComponentPlacementSolver {
    /// Resolves target placement point in 3D world space.
    /// 1. Surface hit point under cursor from visible candidate geometry (`pickSolid`).
    /// 2. Ground plane intersection (`Ray3D.intersectPlaneZZero()`).
    /// 3. Fallback position (defaulting to origin `(0, 0, 0)`).
    public static func resolvePlacementPoint(
        ray: Ray3D?,
        candidateMeshes: [CandidateMesh],
        fallback: SIMD3<Float> = .zero
    ) -> SIMD3<Float> {
        if let ray, let hit = pickSolid(ray: ray, candidateMeshes: candidateMeshes) {
            return hit.hitPoint
        }
        if let ray, let groundHit = ray.intersectPlaneZZero() {
            return groundHit
        }
        return fallback
    }
}
