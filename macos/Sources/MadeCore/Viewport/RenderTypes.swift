import Foundation
import Metal
import simd

public struct RenderUniforms: BitwiseCopyable {
    public var modelMatrix: simd_float4x4
    public var viewMatrix: simd_float4x4
    public var projectionMatrix: simd_float4x4
    public var normalMatrix: simd_float3x3
    public var color: SIMD4<Float>
    
    public init(
        modelMatrix: simd_float4x4 = matrix_identity_float4x4,
        viewMatrix: simd_float4x4 = matrix_identity_float4x4,
        projectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        normalMatrix: simd_float3x3 = matrix_identity_float3x3,
        color: SIMD4<Float> = SIMD4<Float>(0.8, 0.8, 0.85, 1.0)
    ) {
        self.modelMatrix = modelMatrix
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.normalMatrix = normalMatrix
        self.color = color
    }
}

public struct GridUniforms: BitwiseCopyable {
    public var viewProjectionMatrix: simd_float4x4
    
    public init(viewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4) {
        self.viewProjectionMatrix = viewProjectionMatrix
    }
}

public struct BillboardUniforms: BitwiseCopyable {
    public var viewMatrix: simd_float4x4
    public var projectionMatrix: simd_float4x4
    public var labelSize: Float
    private var _padding: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    public init(
        viewMatrix: simd_float4x4 = matrix_identity_float4x4,
        projectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        labelSize: Float = AxesGenerator.defaultLabelSize
    ) {
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.labelSize = labelSize
        self._padding = SIMD3<Float>(0, 0, 0)
    }
}

public struct OutlineUniforms: BitwiseCopyable {
    public var modelMatrix: simd_float4x4
    public var viewMatrix: simd_float4x4
    public var projectionMatrix: simd_float4x4
    public var normalMatrix: simd_float3x3
    public var color: SIMD4<Float>
    public var outlineWidth: Float
    private var _padding: SIMD3<Float> = SIMD3<Float>(0, 0, 0)

    public init(
        modelMatrix: simd_float4x4 = matrix_identity_float4x4,
        viewMatrix: simd_float4x4 = matrix_identity_float4x4,
        projectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        normalMatrix: simd_float3x3 = matrix_identity_float3x3,
        color: SIMD4<Float> = SIMD4<Float>(1.0, 0.65, 0.0, 1.0),
        outlineWidth: Float = 0.008
    ) {
        self.modelMatrix = modelMatrix
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.normalMatrix = normalMatrix
        self.color = color
        self.outlineWidth = outlineWidth
        self._padding = SIMD3<Float>(0, 0, 0)
    }
}

public struct SelectedSubElement: Sendable, Codable, Equatable, Hashable {
    public let solidId: SolidId
    public let elementType: SubelementType
    public let elementId: Int
    public let deterministicId: UUID?

    public init(
        solidId: SolidId,
        elementType: SubelementType,
        elementId: Int,
        deterministicId: UUID? = nil
    ) {
        self.solidId = solidId
        self.elementType = elementType
        self.elementId = elementId
        self.deterministicId = deterministicId
    }
}

public struct EdgeHighlightUniforms: BitwiseCopyable {
    public var modelMatrix: simd_float4x4
    public var viewMatrix: simd_float4x4
    public var projectionMatrix: simd_float4x4
    public var color: SIMD4<Float>
    public var viewportWidth: Float
    public var viewportHeight: Float
    public var lineWidth: Float
    public var targetEdgeId: UInt32
    public var depthBias: Float
    public var _padding: SIMD3<Float>

    public init(
        modelMatrix: simd_float4x4 = matrix_identity_float4x4,
        viewMatrix: simd_float4x4 = matrix_identity_float4x4,
        projectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        color: SIMD4<Float> = SIMD4<Float>(0.0, 0.85, 1.0, 1.0),
        viewportWidth: Float = 0,
        viewportHeight: Float = 0,
        lineWidth: Float = 3.0,
        targetEdgeId: UInt32 = 0,
        depthBias: Float = 0.005
    ) {
        self.modelMatrix = modelMatrix
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.color = color
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.lineWidth = lineWidth
        self.targetEdgeId = targetEdgeId
        self.depthBias = depthBias
        self._padding = SIMD3<Float>(0, 0, 0)
    }
}

public struct PickUniforms: BitwiseCopyable {
    public var modelMatrix: simd_float4x4
    public var viewMatrix: simd_float4x4
    public var projectionMatrix: simd_float4x4
    public var solidIndex: UInt32
    public var subelementType: UInt32 // 1 = face, 2 = edge, 3 = vertex
    public var elementId: UInt32
    public var viewportWidth: Float
    public var viewportHeight: Float
    public var tolerancePx: Float
    public var depthBias: Float
    public var _padding: Float = 0

    public init(
        modelMatrix: simd_float4x4 = matrix_identity_float4x4,
        viewMatrix: simd_float4x4 = matrix_identity_float4x4,
        projectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        solidIndex: UInt32 = 0,
        subelementType: UInt32 = 1,
        elementId: UInt32 = 0,
        viewportWidth: Float = 0,
        viewportHeight: Float = 0,
        tolerancePx: Float = 8.0,
        depthBias: Float = 0.005
    ) {
        self.modelMatrix = modelMatrix
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.solidIndex = solidIndex
        self.subelementType = subelementType
        self.elementId = elementId
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.tolerancePx = tolerancePx
        self.depthBias = depthBias
        self._padding = 0
    }
}

public struct EdgeSegmentData: BitwiseCopyable {
    public var startX: Float
    public var startY: Float
    public var startZ: Float
    public var endX: Float
    public var endY: Float
    public var endZ: Float
    public var edgeId: UInt32
    public var _padding: UInt32 = 0

    public init(start: SIMD3<Float>, end: SIMD3<Float>, edgeId: UInt32) {
        self.startX = start.x
        self.startY = start.y
        self.startZ = start.z
        self.endX = end.x
        self.endY = end.y
        self.endZ = end.z
        self.edgeId = edgeId
        self._padding = 0
    }
}

public struct VertexData: BitwiseCopyable {
    public var posX: Float
    public var posY: Float
    public var posZ: Float
    public var vertexId: UInt32

    public init(position: SIMD3<Float>, vertexId: UInt32) {
        self.posX = position.x
        self.posY = position.y
        self.posZ = position.z
        self.vertexId = vertexId
    }
}

public struct MetalMesh: @unchecked Sendable {
    public let positionBuffer: MTLBuffer
    public let normalBuffer: MTLBuffer
    public let indexBuffer: MTLBuffer
    public let indexCount: Int
    public var transform: Transform
    public var color: SIMD4<Float>
    public var candidateMesh: CandidateMesh
    public var faceRanges: [FaceTriangleRange]
    public var edgePolylines: [EdgePolyline]
    public var vertexPoints: [VertexPoint]
    public var triangleFaceIdBuffer: MTLBuffer?
    public var edgeSegmentBuffer: MTLBuffer?
    public var edgeSegmentCount: Int
    public var vertexBuffer: MTLBuffer?
    public var vertexCount: Int
    
    public init(
        positionBuffer: MTLBuffer,
        normalBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        indexCount: Int,
        transform: Transform = .identity,
        color: SIMD4<Float> = SIMD4<Float>(0.4, 0.6, 0.9, 1.0),
        candidateMesh: CandidateMesh? = nil,
        faceRanges: [FaceTriangleRange] = [],
        edgePolylines: [EdgePolyline] = [],
        vertexPoints: [VertexPoint] = [],
        triangleFaceIdBuffer: MTLBuffer? = nil,
        edgeSegmentBuffer: MTLBuffer? = nil,
        edgeSegmentCount: Int = 0,
        vertexBuffer: MTLBuffer? = nil,
        vertexCount: Int = 0
    ) {
        self.positionBuffer = positionBuffer
        self.normalBuffer = normalBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.transform = transform
        self.color = color
        self.candidateMesh = candidateMesh ?? CandidateMesh(id: SolidId("mesh"), positions: [], edges: [], transform: transform)
        self.faceRanges = faceRanges
        self.edgePolylines = edgePolylines
        self.vertexPoints = vertexPoints
        self.triangleFaceIdBuffer = triangleFaceIdBuffer
        self.edgeSegmentBuffer = edgeSegmentBuffer
        self.edgeSegmentCount = edgeSegmentCount
        self.vertexBuffer = vertexBuffer
        self.vertexCount = vertexCount
    }
    
    public func faceNormal(forFaceId faceId: Int) -> SIMD3<Float>? {
        var mesh = candidateMesh
        mesh.transform = self.transform
        return mesh.faceNormal(forFaceId: faceId)
    }
    
    public func faceCentroid(forFaceId faceId: Int) -> SIMD3<Float>? {
        var mesh = candidateMesh
        mesh.transform = self.transform
        return mesh.faceCentroid(forFaceId: faceId)
    }
}

/// An immutable point-in-time capture of viewport scene state for off-main encoding passes.
public struct SceneSnapshot: Sendable {
    public let meshes: [SolidId: MetalMesh]
    public let hiddenSolidIds: Set<SolidId>
    public let camera: Camera
    public let selectedId: SolidId?
    public let selectedSubElement: SelectedSubElement?
    public let preselectedSubElement: SelectedSubElement?
    public let activeSnap: SnapResult?
    public let activeGizmoHandle: GizmoHandle?

    public init(
        meshes: [SolidId: MetalMesh] = [:],
        hiddenSolidIds: Set<SolidId> = [],
        camera: Camera = Camera(),
        selectedId: SolidId? = nil,
        selectedSubElement: SelectedSubElement? = nil,
        preselectedSubElement: SelectedSubElement? = nil,
        activeSnap: SnapResult? = nil,
        activeGizmoHandle: GizmoHandle? = nil
    ) {
        self.meshes = meshes
        self.hiddenSolidIds = hiddenSolidIds
        self.camera = camera
        self.selectedId = selectedId
        self.selectedSubElement = selectedSubElement
        self.preselectedSubElement = preselectedSubElement
        self.activeSnap = activeSnap
        self.activeGizmoHandle = activeGizmoHandle
    }
}
