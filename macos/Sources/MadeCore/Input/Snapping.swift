import Foundation
import simd

public enum SnapKind: String, Sendable, Equatable, Comparable {
    case vertex
    case edge
    case grid
    
    // Priority order: vertex > edge > grid
    private var priority: Int {
        switch self {
        case .vertex: return 0
        case .edge: return 1
        case .grid: return 2
        }
    }
    
    public static func < (lhs: SnapKind, rhs: SnapKind) -> Bool {
        return lhs.priority < rhs.priority
    }
}

public struct SnapResult: Sendable, Equatable {
    public let kind: SnapKind
    public let point: SIMD3<Float>
    
    public init(kind: SnapKind, point: SIMD3<Float>) {
        self.kind = kind
        self.point = point
    }
}

public struct SnapCandidate: Sendable, Equatable {
    public let kind: SnapKind
    public let point: SIMD3<Float>
    public let screenDistancePx: Float
    
    public init(kind: SnapKind, point: SIMD3<Float>, screenDistancePx: Float) {
        self.kind = kind
        self.point = point
        self.screenDistancePx = screenDistancePx
    }
}

public let defaultGridSpacing: Float = 10.0
public let defaultSnapTolerancePx: Float = 20.0

/// Grid snap: quantizes point's X and Y to the nearest multiple of spacing, leaving Z untouched.
/// Operates on the XY ground plane (Z = 0) per the Z-up convention.
public func snapToGrid(_ point: SIMD3<Float>, spacing: Float = defaultGridSpacing) -> SIMD3<Float> {
    let sx = (point.x / spacing).rounded() * spacing
    let sy = (point.y / spacing).rounded() * spacing
    return SIMD3<Float>(sx, sy, point.z)
}

/// Distance between two 2D screen coordinates.
public func screenPixelDistance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    return simd_distance(a, b)
}

/// Evaluates candidates according to Invariant 9:
/// Priority is strictly vertex > edge > grid. Within the highest-priority kind present,
/// the candidate with the minimum screenDistancePx inside tolerancePx is chosen.
public func resolveSnap(candidates: [SnapCandidate], tolerancePx: Float = defaultSnapTolerancePx) -> SnapResult? {
    let kinds: [SnapKind] = [.vertex, .edge, .grid]
    
    for kind in kinds {
        var best: SnapCandidate? = nil
        for candidate in candidates {
            guard candidate.kind == kind else { continue }
            guard candidate.screenDistancePx <= tolerancePx else { continue }
            
            if let currentBest = best {
                if candidate.screenDistancePx < currentBest.screenDistancePx {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        
        if let winner = best {
            return SnapResult(kind: winner.kind, point: winner.point)
        }
    }
    
    return nil
}
