import Foundation
import simd
import CryptoKit

public struct SolidId: Hashable, Equatable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }

    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let str = try? container.decode(String.self) {
            self.rawValue = str
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rawValue = try container.decode(String.self, forKey: .rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct JobId: Hashable, Equatable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public var description: String { rawValue }

    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let str = try? container.decode(String.self) {
            self.rawValue = str
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rawValue = try container.decode(String.self, forKey: .rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct BoxParams: Hashable, Equatable, Sendable, Codable {
    public var width: Float
    public var depth: Float
    public var height: Float
    
    public init(width: Float, depth: Float, height: Float) {
        self.width = width
        self.depth = depth
        self.height = height
    }
}

public struct CylinderParams: Hashable, Equatable, Sendable, Codable {
    public var radius: Float
    public var height: Float
    
    public init(radius: Float, height: Float) {
        self.radius = radius
        self.height = height
    }
}

public struct SphereParams: Hashable, Equatable, Sendable, Codable {
    public var radius: Float
    
    public init(radius: Float) {
        self.radius = radius
    }
}

public struct ConeParams: Hashable, Equatable, Sendable, Codable {
    public var bottomRadius: Float
    public var topRadius: Float
    public var height: Float
    
    public init(bottomRadius: Float, topRadius: Float = 0, height: Float) {
        self.bottomRadius = bottomRadius
        self.topRadius = topRadius
        self.height = height
    }
}

public struct TorusParams: Hashable, Equatable, Sendable, Codable {
    public var majorRadius: Float
    public var minorRadius: Float

    public init(majorRadius: Float, minorRadius: Float) {
        self.majorRadius = majorRadius
        self.minorRadius = minorRadius
    }
}

public struct WedgeParams: Hashable, Equatable, Sendable, Codable {
    public var width: Float
    public var depth: Float
    public var height: Float
    public var topWidth: Float

    public init(width: Float, depth: Float, height: Float, topWidth: Float = 0) {
        self.width = width
        self.depth = depth
        self.height = height
        self.topWidth = topWidth
    }
}

/// Topological triangle range mapped back to source B-Rep face ID.
public struct FaceTriangleRange: Sendable, Codable, Equatable {
    public let faceId: Int
    public let triangleRange: Range<Int>
    public let deterministicId: UUID?

    public init(faceId: Int, triangleRange: Range<Int>, deterministicId: UUID? = nil) {
        self.faceId = faceId
        self.triangleRange = triangleRange
        self.deterministicId = deterministicId
    }
}

/// Discretized edge segment range mapped to edge ID.
public struct EdgeSegmentRange: Sendable, Codable, Equatable {
    public let edgeId: Int
    public let segmentRange: Range<Int>
    public let deterministicId: UUID?

    public init(edgeId: Int, segmentRange: Range<Int>, deterministicId: UUID? = nil) {
        self.edgeId = edgeId
        self.segmentRange = segmentRange
        self.deterministicId = deterministicId
    }
}

/// Discretized 3D polyline for a B-Rep edge.
public struct EdgePolyline: Sendable, Codable, Equatable {
    public let edgeId: Int
    public let points: [SIMD3<Float>]
    public let segmentRange: Range<Int>
    public let deterministicId: UUID?

    public init(edgeId: Int, points: [SIMD3<Float>], segmentRange: Range<Int>, deterministicId: UUID? = nil) {
        self.edgeId = edgeId
        self.points = points
        self.segmentRange = segmentRange
        self.deterministicId = deterministicId
    }
}

/// Discrete 3D vertex position mapped to vertex ID.
public struct VertexPoint: Sendable, Codable, Equatable {
    public let vertexId: Int
    public let position: SIMD3<Float>
    public let deterministicId: UUID?

    public init(vertexId: Int, position: SIMD3<Float>, deterministicId: UUID? = nil) {
        self.vertexId = vertexId
        self.position = position
        self.deterministicId = deterministicId
    }
}

/// A triangle mesh held in one page-aligned shared-memory region, so it can cross XPC without a copy (invariant 6).
public struct MeshPayload: Sendable {
    public let storage: MeshStorage
    public let faceRanges: [FaceTriangleRange]
    public let edgePolylines: [EdgePolyline]
    public let edgeSegmentRanges: [EdgeSegmentRange]
    public let vertexPoints: [VertexPoint]

    public var positions: MeshComponent<Float> { storage.positions }
    public var normals: MeshComponent<Float> { storage.normals }
    public var indices: MeshComponent<UInt32> { storage.indices }
    public var triangleCount: Int { storage.indexCount / 3 }
    public var isEmpty: Bool { triangleCount == 0 }
    
    public init(
        storage: MeshStorage,
        faceRanges: [FaceTriangleRange] = [],
        edgePolylines: [EdgePolyline] = [],
        edgeSegmentRanges: [EdgeSegmentRange] = [],
        vertexPoints: [VertexPoint] = []
    ) {
        self.storage = storage
        self.faceRanges = faceRanges
        self.edgePolylines = edgePolylines
        self.edgeSegmentRanges = edgeSegmentRanges
        self.vertexPoints = vertexPoints
    }
    
    public init(
        positions: [Float],
        normals: [Float],
        indices: [UInt32],
        faceRanges: [FaceTriangleRange] = [],
        edgePolylines: [EdgePolyline] = [],
        edgeSegmentRanges: [EdgeSegmentRange] = [],
        vertexPoints: [VertexPoint] = []
    ) {
        self.storage = MeshStorage(positionCount: positions.count, normalCount: normals.count, indexCount: indices.count) { p, n, i in
            _ = p.initialize(from: positions)
            _ = n.initialize(from: normals)
            _ = i.initialize(from: indices)
        }
        self.faceRanges = faceRanges
        self.edgePolylines = edgePolylines
        self.edgeSegmentRanges = edgeSegmentRanges
        self.vertexPoints = vertexPoints
    }

    /// Returns the vertex point for the given vertex ID.
    public func vertexPoint(forVertex vertexId: Int) -> VertexPoint? {
        vertexPoints.first(where: { $0.vertexId == vertexId })
    }

    /// Resolves the source B-Rep face ID for a triangle index in this mesh, or nil if unmapped or out of bounds.
    public func faceId(atTriangle triangleIndex: Int) -> Int? {
        guard triangleIndex >= 0 && triangleIndex < triangleCount else { return nil }
        for item in faceRanges {
            if item.triangleRange.contains(triangleIndex) {
                return item.faceId
            }
        }
        return nil
    }

    /// Returns all triangle ranges associated with the given face ID.
    public func triangleRanges(forFace faceId: Int) -> [Range<Int>] {
        faceRanges.compactMap { $0.faceId == faceId ? $0.triangleRange : nil }
    }

    /// Resolves the source B-Rep edge ID for an edge segment index, or nil if unmapped or out of bounds.
    public func edgeId(atSegment segmentIndex: Int) -> Int? {
        guard segmentIndex >= 0 else { return nil }
        for item in edgeSegmentRanges {
            if item.segmentRange.contains(segmentIndex) {
                return item.edgeId
            }
        }
        return nil
    }

    /// Returns the segment range associated with the given edge ID.
    public func segmentRange(forEdge edgeId: Int) -> Range<Int>? {
        edgeSegmentRanges.first(where: { $0.edgeId == edgeId })?.segmentRange
    }

    /// Returns the discretized polyline for the given edge ID.
    public func polyline(forEdge edgeId: Int) -> EdgePolyline? {
        edgePolylines.first(where: { $0.edgeId == edgeId })
    }

    /// The total count of discretized line segments across all edge polylines.
    public var totalEdgeSegments: Int {
        edgeSegmentRanges.last?.segmentRange.upperBound ?? 0
    }

    /// Flat line segment endpoints (2 endpoints per segment) suitable for GPU line rendering or ray picking.
    public var edgeSegments: [SIMD3<Float>] {
        var segments: [SIMD3<Float>] = []
        segments.reserveCapacity(totalEdgeSegments * 2)
        for polyline in edgePolylines {
            let pts = polyline.points
            guard pts.count >= 2 else { continue }
            for i in 0..<(pts.count - 1) {
                segments.append(pts[i])
                segments.append(pts[i + 1])
            }
        }
        return segments
    }
}

public enum KernelErrorCode: String, Sendable, Codable, CaseIterable {
    case kernelInitFailed = "kernel-init-failed"
    case invalidParams = "invalid-params"
    case geometryFailed = "geometry-failed"
    case unknownSolid = "unknown-solid"
    case cancelled = "cancelled"
    case workerCrashed = "worker-crashed"
    case topologicalReferenceBroken = "topological-reference-broken"
}

public struct KernelError: Error, Equatable, Sendable, Codable {
    public let code: KernelErrorCode
    public let message: String
    
    public init(code: KernelErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum KernelResult<T: Sendable>: Sendable {
    case success(jobId: JobId, value: T)
    case failure(jobId: JobId, error: KernelError)
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    public var jobId: JobId {
        switch self {
        case .success(let id, _): return id
        case .failure(let id, _): return id
        }
    }
    
    public var value: T? {
        if case .success(_, let v) = self { return v }
        return nil
    }
    
    public var error: KernelError? {
        if case .failure(_, let e) = self { return e }
        return nil
    }
}

public enum ChamferMode: String, Sendable, Codable, Equatable, CaseIterable {
    case equalDistance = "equalDistance"
    case twoDistances = "twoDistances"
    case distanceAngle = "distanceAngle"

    public var label: String {
        switch self {
        case .equalDistance: return "Equal Distance"
        case .twoDistances: return "Two Distances"
        case .distanceAngle: return "Distance-Angle"
        }
    }
}

public struct ChamferParams: Hashable, Equatable, Sendable, Codable {
    public var targetSolidId: SolidId
    public var mode: ChamferMode
    public var distance: Double
    public var distance2: Double
    public var angle: Double
    public var edgeReferences: [TopologicalReference]

    public init(
        targetSolidId: SolidId,
        mode: ChamferMode = .equalDistance,
        distance: Double = 1.0,
        distance2: Double = 1.0,
        angle: Double = 45.0,
        edgeReferences: [TopologicalReference] = []
    ) {
        self.targetSolidId = targetSolidId
        self.mode = mode
        self.distance = distance
        self.distance2 = distance2
        self.angle = angle
        self.edgeReferences = edgeReferences
    }
}

public struct FaceThicknessOverride: Hashable, Equatable, Sendable, Codable {
    public var faceReference: TopologicalReference
    public var thickness: Double

    public init(faceReference: TopologicalReference, thickness: Double) {
        self.faceReference = faceReference
        self.thickness = thickness
    }
}

public struct ShellParams: Hashable, Equatable, Sendable, Codable {
    public var targetSolidId: SolidId
    public var thickness: Double
    public var removedFaceReferences: [TopologicalReference]
    public var perFaceOverrides: [FaceThicknessOverride]

    public init(
        targetSolidId: SolidId,
        thickness: Double = 1.0,
        removedFaceReferences: [TopologicalReference] = [],
        perFaceOverrides: [FaceThicknessOverride] = []
    ) {
        self.targetSolidId = targetSolidId
        self.thickness = thickness
        self.removedFaceReferences = removedFaceReferences
        self.perFaceOverrides = perFaceOverrides
    }
}

public struct HoleParams: Hashable, Equatable, Sendable, Codable {
    public var targetSolidId: SolidId
    public var faceReference: TopologicalReference
    public var sketchFeatureId: UUID?
    public var points: [SIMD2<Double>]
    public var holeType: HoleType
    public var standard: HoleStandard
    public var sizeDesignation: String?
    public var diameter: Double
    public var depth: Double
    public var isThrough: Bool
    public var counterboreDiameter: Double
    public var counterboreDepth: Double
    public var countersinkDiameter: Double
    public var countersinkAngle: Double
    public var drillTipAngle: Double?
    public var threadMetadata: ThreadMetadata?

    public init(
        targetSolidId: SolidId,
        faceReference: TopologicalReference,
        sketchFeatureId: UUID? = nil,
        points: [SIMD2<Double>] = [],
        holeType: HoleType = .simple,
        standard: HoleStandard = .custom,
        sizeDesignation: String? = nil,
        diameter: Double = 5.0,
        depth: Double = 10.0,
        isThrough: Bool = true,
        counterboreDiameter: Double = 0.0,
        counterboreDepth: Double = 0.0,
        countersinkDiameter: Double = 0.0,
        countersinkAngle: Double = 90.0,
        drillTipAngle: Double? = nil,
        threadMetadata: ThreadMetadata? = nil
    ) {
        self.targetSolidId = targetSolidId
        self.faceReference = faceReference
        self.sketchFeatureId = sketchFeatureId
        self.points = points
        self.holeType = holeType
        self.standard = standard
        self.sizeDesignation = sizeDesignation
        self.diameter = diameter
        self.depth = depth
        self.isThrough = isThrough
        self.counterboreDiameter = counterboreDiameter
        self.counterboreDepth = counterboreDepth
        self.countersinkDiameter = countersinkDiameter
        self.countersinkAngle = countersinkAngle
        self.drillTipAngle = drillTipAngle
        self.threadMetadata = threadMetadata
    }
}

public typealias HoleFeatureData = HoleParams

public enum BooleanOp: String, Sendable, Codable {
    case subtract
    case union
    case intersect
}

public enum KernelRequest: Sendable, Codable, Equatable {
    case makeBox(jobId: JobId, solidId: SolidId, params: BoxParams)
    case makeCylinder(jobId: JobId, solidId: SolidId, params: CylinderParams)
    case makeSphere(jobId: JobId, solidId: SolidId, params: SphereParams)
    case makeCone(jobId: JobId, solidId: SolidId, params: ConeParams)
    case makeTorus(jobId: JobId, solidId: SolidId, params: TorusParams)
    case makeWedge(jobId: JobId, solidId: SolidId, params: WedgeParams)
    case tessellate(jobId: JobId, solidId: SolidId, tolerances: KernelTolerances?)
    case importStep(jobId: JobId, solidId: SolidId, data: Data)
    case booleanOperation(jobId: JobId, solidId: SolidId, op: BooleanOp, solidA: SolidId, solidB: SolidId)
    case evaluateShape(jobId: JobId, solidId: SolidId, shape: ShapeNode)
    case fillet(jobId: JobId, solidId: SolidId, edgeReference: TopologicalReference, radius: Double)
    case chamfer(jobId: JobId, solidId: SolidId, targetSolidId: SolidId, edgeReferences: [TopologicalReference], mode: ChamferMode, distance: Double, distance2: Double, angle: Double)
    case shell(jobId: JobId, solidId: SolidId, targetSolidId: SolidId, thickness: Double, removedFaceReferences: [TopologicalReference], perFaceOverrides: [FaceThicknessOverride])
    case hole(jobId: JobId, solidId: SolidId, targetSolidId: SolidId, faceReference: TopologicalReference, holeData: HoleFeatureData)
    
    public static func tessellate(jobId: JobId, solidId: SolidId) -> KernelRequest {
        .tessellate(jobId: jobId, solidId: solidId, tolerances: nil)
    }

    public var jobId: JobId {
        switch self {
        case .makeBox(let j, _, _),
             .makeCylinder(let j, _, _),
             .makeSphere(let j, _, _),
             .makeCone(let j, _, _),
             .makeTorus(let j, _, _),
             .makeWedge(let j, _, _),
             .tessellate(let j, _, _),
             .importStep(let j, _, _),
             .booleanOperation(let j, _, _, _, _),
             .evaluateShape(let j, _, _),
             .fillet(let j, _, _, _):
            return j
        case .chamfer(let j, _, _, _, _, _, _, _):
            return j
        case .shell(let j, _, _, _, _, _):
            return j
        case .hole(let j, _, _, _, _):
            return j
        }
    }
    
    public var solidId: SolidId {
        switch self {
        case .makeBox(_, let s, _),
             .makeCylinder(_, let s, _),
             .makeSphere(_, let s, _),
             .makeCone(_, let s, _),
             .makeTorus(_, let s, _),
             .makeWedge(_, let s, _),
             .tessellate(_, let s, _),
             .importStep(_, let s, _),
             .booleanOperation(_, let s, _, _, _),
             .evaluateShape(_, let s, _),
             .fillet(_, let s, _, _):
            return s
        case .chamfer(_, let s, _, _, _, _, _, _):
            return s
        case .shell(_, let s, _, _, _, _):
            return s
        case .hole(_, let s, _, _, _):
            return s
        }
    }
}

// MARK: - Topological Query Types (ADR-D3)

public enum SubelementType: String, Sendable, Codable, Equatable, Hashable {
    case face
    case edge
    case vertex
}

public enum HistoryStepKind: String, Sendable, Codable, Equatable, Hashable {
    case generated
    case modified
    case deleted
}

public struct HistoryStep: Sendable, Codable, Equatable, Hashable {
    public var kind: HistoryStepKind
    public var label: String
    public var sourceIndex: Int?

    public init(kind: HistoryStepKind, label: String, sourceIndex: Int? = nil) {
        self.kind = kind
        self.label = label
        self.sourceIndex = sourceIndex
    }
}

public struct GeometricSignature: Sendable, Codable, Equatable, Hashable {
    public var surfaceOrCurveType: String?
    public var normal: SIMD3<Float>?
    public var centroid: SIMD3<Float>?
    public var areaOrLength: Double?

    public init(
        surfaceOrCurveType: String? = nil,
        normal: SIMD3<Float>? = nil,
        centroid: SIMD3<Float>? = nil,
        areaOrLength: Double? = nil
    ) {
        self.surfaceOrCurveType = surfaceOrCurveType
        self.normal = normal
        self.centroid = centroid
        self.areaOrLength = areaOrLength
    }
}

public struct TopologicalReference: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var sourceFeatureId: UUID
    public var elementType: SubelementType
    public var historyPath: [HistoryStep]
    public var disambiguator: GeometricSignature?

    public static func deterministicId(
        sourceFeatureId: UUID,
        historyPath: [HistoryStep],
        elementType: SubelementType
    ) -> UUID {
        var hasher = SHA256()
        hasher.update(data: Data(sourceFeatureId.uuidString.utf8))
        hasher.update(data: Data(elementType.rawValue.utf8))
        for step in historyPath {
            hasher.update(data: Data(step.kind.rawValue.utf8))
            hasher.update(data: Data(step.label.utf8))
            if let index = step.sourceIndex {
                var idx = Int64(index)
                withUnsafeBytes(of: &idx) { hasher.update(bufferPointer: $0) }
            }
        }
        let digest = hasher.finalize()
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public init(
        id: UUID? = nil,
        sourceFeatureId: UUID,
        elementType: SubelementType,
        historyPath: [HistoryStep] = [],
        disambiguator: GeometricSignature? = nil
    ) {
        self.id = id ?? Self.deterministicId(
            sourceFeatureId: sourceFeatureId,
            historyPath: historyPath,
            elementType: elementType
        )
        self.sourceFeatureId = sourceFeatureId
        self.elementType = elementType
        self.historyPath = historyPath
        self.disambiguator = disambiguator
    }
}
