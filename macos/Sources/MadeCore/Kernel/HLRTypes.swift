import Foundation
import simd

/// Fine-grained category for Hidden Line Removal (HLR) edges in 2D drawing projections.
public enum HLREdgeCategory: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case visibleSharp
    case visibleSmooth
    case visibleSewn
    case visibleOutline
    case hiddenSharp
    case hiddenSmooth
    case hiddenSewn
    case hiddenOutline

    public var isVisible: Bool {
        switch self {
        case .visibleSharp, .visibleSmooth, .visibleSewn, .visibleOutline:
            return true
        case .hiddenSharp, .hiddenSmooth, .hiddenSewn, .hiddenOutline:
            return false
        }
    }

    public var isHidden: Bool {
        !isVisible
    }

    public var isSilhouette: Bool {
        self == .visibleOutline || self == .hiddenOutline
    }

    public var isTangent: Bool {
        self == .visibleSmooth || self == .hiddenSmooth
    }

    public var isSharp: Bool {
        self == .visibleSharp || self == .hiddenSharp
    }

    public var isSewn: Bool {
        self == .visibleSewn || self == .hiddenSewn
    }
}


/// 2D axis-aligned bounding box for projected drawing coordinates.
public struct BoundingBox2D: Sendable, Codable, Equatable {
    public var min: SIMD2<Double>
    public var max: SIMD2<Double>

    public init(min: SIMD2<Double>, max: SIMD2<Double>) {
        self.min = min
        self.max = max
    }

    public var width: Double { max.x - min.x }
    public var height: Double { max.y - min.y }
    public var center: SIMD2<Double> { (min + max) * 0.5 }
}

/// A discretized 2D projected edge extracted by the HLR engine.
public struct HLREdge: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let category: HLREdgeCategory
    public let points2D: [SIMD2<Double>]
    public let points3D: [SIMD3<Double>]

    public init(
        id: UUID = UUID(),
        category: HLREdgeCategory,
        points2D: [SIMD2<Double>],
        points3D: [SIMD3<Double>] = []
    ) {
        self.id = id
        self.category = category
        self.points2D = points2D
        self.points3D = points3D
    }

    public var startPoint2D: SIMD2<Double>? { points2D.first }
    public var endPoint2D: SIMD2<Double>? { points2D.last }

    public var bounds2D: BoundingBox2D? {
        guard let first = points2D.first else { return nil }
        var minPt = first
        var maxPt = first
        for pt in points2D.dropFirst() {
            minPt.x = Swift.min(minPt.x, pt.x)
            minPt.y = Swift.min(minPt.y, pt.y)
            maxPt.x = Swift.max(maxPt.x, pt.x)
            maxPt.y = Swift.max(maxPt.y, pt.y)
        }
        return BoundingBox2D(min: minPt, max: maxPt)
    }
}

/// Options controlling HLR tessellation, edge extraction, and 3D curve generation.
public struct HLROptions: Sendable, Codable, Equatable {
    public var deflection: Double
    public var includeHidden: Bool
    public var includeTangent: Bool
    public var includeSilhouette: Bool
    public var compute3D: Bool

    public init(
        deflection: Double = 0.1,
        includeHidden: Bool = true,
        includeTangent: Bool = true,
        includeSilhouette: Bool = true,
        compute3D: Bool = false
    ) {
        self.deflection = deflection
        self.includeHidden = includeHidden
        self.includeTangent = includeTangent
        self.includeSilhouette = includeSilhouette
        self.compute3D = compute3D
    }

    public static let `default` = HLROptions()
}

/// Standard orthographic and isometric viewing directions for 2D drawing projections.
public enum HLRStandardView: String, Sendable, Codable, CaseIterable, Equatable {
    case top
    case bottom
    case front
    case back
    case right
    case left
    case isometric
    case isometricNE
    case isometricNW
    case isometricSE
    case isometricSW

    public var direction: SIMD3<Double> {
        let invSqrt3 = 1.0 / sqrt(3.0)
        switch self {
        case .top:
            return SIMD3<Double>(0, 0, 1)
        case .bottom:
            return SIMD3<Double>(0, 0, -1)
        case .front:
            return SIMD3<Double>(0, 1, 0)
        case .back:
            return SIMD3<Double>(0, -1, 0)
        case .right:
            return SIMD3<Double>(1, 0, 0)
        case .left:
            return SIMD3<Double>(-1, 0, 0)
        case .isometric, .isometricNE:
            return SIMD3<Double>(invSqrt3, invSqrt3, invSqrt3)
        case .isometricNW:
            return SIMD3<Double>(-invSqrt3, invSqrt3, invSqrt3)
        case .isometricSE:
            return SIMD3<Double>(invSqrt3, -invSqrt3, invSqrt3)
        case .isometricSW:
            return SIMD3<Double>(-invSqrt3, -invSqrt3, invSqrt3)
        }
    }
}

/// A request to compute HLR edges from a single solid or multi-body scene objects.
public struct HLRRequest: Sendable, Codable, Equatable {
    public var jobId: JobId
    public var solidId: SolidId?
    public var objects: [SceneObject]?
    public var direction: SIMD3<Double>
    public var options: HLROptions

    public init(
        jobId: JobId = JobId(UUID().uuidString),
        solidId: SolidId? = nil,
        objects: [SceneObject]? = nil,
        direction: SIMD3<Double>,
        options: HLROptions = .default
    ) {
        self.jobId = jobId
        self.solidId = solidId
        self.objects = objects
        self.direction = direction
        self.options = options
    }

    public init(
        jobId: JobId = JobId(UUID().uuidString),
        solidId: SolidId? = nil,
        objects: [SceneObject]? = nil,
        view: HLRStandardView,
        options: HLROptions = .default
    ) {
        self.init(
            jobId: jobId,
            solidId: solidId,
            objects: objects,
            direction: view.direction,
            options: options
        )
    }
}

/// The result of an HLR projection containing categorized 2D edges and bounding box.
public struct HLRResult: Sendable, Codable, Equatable {
    public let edges: [HLREdge]
    public let viewDirection: SIMD3<Double>

    public init(edges: [HLREdge], viewDirection: SIMD3<Double>) {
        self.edges = edges
        self.viewDirection = viewDirection
    }

    public var visibleEdges: [HLREdge] {
        edges.filter { $0.category.isVisible }
    }

    public var hiddenEdges: [HLREdge] {
        edges.filter { $0.category.isHidden }
    }

    public var silhouetteEdges: [HLREdge] {
        edges.filter { $0.category.isSilhouette }
    }

    public var tangentEdges: [HLREdge] {
        edges.filter { $0.category.isTangent }
    }

    public var visibleSharpEdges: [HLREdge] {
        edges.filter { $0.category == .visibleSharp }
    }

    public var hiddenSharpEdges: [HLREdge] {
        edges.filter { $0.category == .hiddenSharp }
    }

    public var visibleSewnEdges: [HLREdge] {
        edges.filter { $0.category == .visibleSewn }
    }

    public var hiddenSewnEdges: [HLREdge] {
        edges.filter { $0.category == .hiddenSewn }
    }

    public var visibleSilhouetteEdges: [HLREdge] {
        edges.filter { $0.category == .visibleOutline }
    }

    public var hiddenSilhouetteEdges: [HLREdge] {
        edges.filter { $0.category == .hiddenOutline }
    }

    public var visibleTangentEdges: [HLREdge] {
        edges.filter { $0.category == .visibleSmooth }
    }

    public var hiddenTangentEdges: [HLREdge] {
        edges.filter { $0.category == .hiddenSmooth }
    }

    public var bounds2D: BoundingBox2D? {
        var minX: Double = .infinity
        var minY: Double = .infinity
        var maxX: Double = -.infinity
        var maxY: Double = -.infinity
        var hasPoint = false

        for edge in edges {
            for pt in edge.points2D {
                hasPoint = true
                minX = Swift.min(minX, pt.x)
                minY = Swift.min(minY, pt.y)
                maxX = Swift.max(maxX, pt.x)
                maxY = Swift.max(maxY, pt.y)
            }
        }
        guard hasPoint else { return nil }
        return BoundingBox2D(min: SIMD2(minX, minY), max: SIMD2(maxX, maxY))
    }
}
