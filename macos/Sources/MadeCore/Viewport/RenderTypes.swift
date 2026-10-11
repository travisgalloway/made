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

public struct MetalMesh: @unchecked Sendable {
    public let positionBuffer: MTLBuffer
    public let normalBuffer: MTLBuffer
    public let indexBuffer: MTLBuffer
    public let indexCount: Int
    public var transform: Transform
    public let color: SIMD4<Float>
    public var candidateMesh: CandidateMesh
    
    public init(
        positionBuffer: MTLBuffer,
        normalBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        indexCount: Int,
        transform: Transform = .identity,
        color: SIMD4<Float> = SIMD4<Float>(0.4, 0.6, 0.9, 1.0),
        candidateMesh: CandidateMesh? = nil
    ) {
        self.positionBuffer = positionBuffer
        self.normalBuffer = normalBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.transform = transform
        self.color = color
        self.candidateMesh = candidateMesh ?? CandidateMesh(id: SolidId("mesh"), positions: [], edges: [], transform: transform)
    }
}
