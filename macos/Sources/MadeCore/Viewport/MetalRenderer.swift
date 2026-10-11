import Foundation
import Metal
import MetalKit
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct RenderUniforms {
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

public struct MetalMesh: @unchecked Sendable {
    public let positionBuffer: MTLBuffer
    public let normalBuffer: MTLBuffer
    public let indexBuffer: MTLBuffer
    public let indexCount: Int
    public let transform: Transform
    public let color: SIMD4<Float>
    
    public init(
        positionBuffer: MTLBuffer,
        normalBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        indexCount: Int,
        transform: Transform = .identity,
        color: SIMD4<Float> = SIMD4<Float>(0.4, 0.6, 0.9, 1.0)
    ) {
        self.positionBuffer = positionBuffer
        self.normalBuffer = normalBuffer
        self.indexBuffer = indexBuffer
        self.indexCount = indexCount
        self.transform = transform
        self.color = color
    }
}

public final class MetalRenderer: NSObject, MTKViewDelegate, SnapshotProvider, @unchecked Sendable {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    
    public var cameraPosition: SIMD3<Float> = Orientation.defaultViewDirection * 150.0
    public var cameraTarget: SIMD3<Float> = SIMD3<Float>(0, 0, 10)
    public var meshes: [SolidId: MetalMesh] = [:]
    public var onDeviceLost: (@Sendable () -> Void)? = nil
    
    public init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        // Load Metal Shaders from source at runtime (no external offline metal toolchain required)
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: MetalShaders.source, options: nil)
        } catch {
            print("Failed to compile Metal shaders: \(error)")
            return nil
        }
        
        guard let vertexFunc = library.makeFunction(name: "cadVertexShader"),
              let fragmentFunc = library.makeFunction(name: "cadFragmentShader") else {
            print("Failed to locate shader entry points")
            return nil
        }
        
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipelineDesc.depthAttachmentPixelFormat = .depth32Float
        
        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            print("Failed to create pipeline state: \(error)")
            return nil
        }
        
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: depthDesc) else { return nil }
        self.depthState = depth
        
        super.init()
    }
    
    /// Converts a MeshPayload into a MetalMesh with zero-copy shared memory allocation on Apple Silicon.
    public func createMesh(from payload: MeshPayload, transform: Transform = .identity, color: SIMD4<Float>) -> MetalMesh? {
        guard !payload.positions.isEmpty, !payload.indices.isEmpty else { return nil }
        
        let posByteLength = payload.positions.count * MemoryLayout<Float>.stride
        guard let posBuffer = device.makeBuffer(
            bytes: payload.positions,
            length: posByteLength,
            options: .storageModeShared
        ) else { return nil }
        
        let normByteLength = payload.normals.count * MemoryLayout<Float>.stride
        guard let normBuffer = device.makeBuffer(
            bytes: payload.normals,
            length: normByteLength,
            options: .storageModeShared
        ) else { return nil }
        
        let indexByteLength = payload.indices.count * MemoryLayout<UInt32>.stride
        guard let idxBuffer = device.makeBuffer(
            bytes: payload.indices,
            length: indexByteLength,
            options: .storageModeShared
        ) else { return nil }
        
        return MetalMesh(
            positionBuffer: posBuffer,
            normalBuffer: normBuffer,
            indexBuffer: idxBuffer,
            indexCount: payload.indices.count,
            transform: transform,
            color: color
        )
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handled dynamically in draw
    }
    
    @discardableResult
    private func renderScene(encoder: MTLRenderCommandEncoder, aspect: Float) -> Int {
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.back)
        
        let viewMatrix = Orientation.makeLookAt(eye: cameraPosition, target: cameraTarget, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
        
        var drawCalls = 0
        for (_, mesh) in meshes {
            var modelMatrix = matrix_identity_float4x4
            modelMatrix.columns.3 = SIMD4<Float>(mesh.transform.position.x, mesh.transform.position.y, mesh.transform.position.z, 1.0)
            
            let normalMatrix = simd_float3x3(
                SIMD3<Float>(modelMatrix.columns.0.x, modelMatrix.columns.0.y, modelMatrix.columns.0.z),
                SIMD3<Float>(modelMatrix.columns.1.x, modelMatrix.columns.1.y, modelMatrix.columns.1.z),
                SIMD3<Float>(modelMatrix.columns.2.x, modelMatrix.columns.2.y, modelMatrix.columns.2.z)
            )
            
            var uniforms = RenderUniforms(
                modelMatrix: modelMatrix,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                normalMatrix: normalMatrix,
                color: mesh.color
            )
            
            encoder.setVertexBuffer(mesh.positionBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(mesh.normalBuffer, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 2)
            
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: mesh.indexCount,
                indexType: .uint32,
                indexBuffer: mesh.indexBuffer,
                indexBufferOffset: 0
            )
            drawCalls += 1
        }
        return drawCalls
    }
    
    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }
        
        let aspect = Float(max(1.0, view.drawableSize.width) / max(1.0, view.drawableSize.height))
        let drawCalls = renderScene(encoder: encoder, aspect: aspect)
        
        encoder.endEncoding()
        
        commandBuffer.addCompletedHandler { [weak self] buffer in
            if buffer.status == .error,
               let error = buffer.error as? NSError,
               error.domain == MTLCommandBufferErrorDomain,
               error.code == MTLCommandBufferError.deviceRemoved.rawValue {
                self?.onDeviceLost?()
            }
        }
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        RenderInstrumentation.shared.recordRender(drawCalls: drawCalls)
    }
    
    public func captureSnapshotPngBase64() async -> String? {
        let width = 800
        let height = 600
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        guard let colorTex = device.makeTexture(descriptor: texDesc) else { return nil }
        
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depthDesc.usage = [.renderTarget]
        guard let depthTex = device.makeTexture(descriptor: depthDesc) else { return nil }
        
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = colorTex
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.depthAttachment.texture = depthTex
        passDesc.depthAttachment.loadAction = .clear
        passDesc.depthAttachment.clearDepth = 1.0
        passDesc.depthAttachment.storeAction = .dontCare
        
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return nil }
        
        renderScene(encoder: encoder, aspect: Float(width) / Float(height))
        encoder.endEncoding()
        cmdBuffer.commit()
        
        await withCheckedContinuation { continuation in
            cmdBuffer.addCompletedHandler { _ in
                continuation.resume()
            }
        }
        
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        colorTex.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            return nil
        }
        
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        
        return (mutableData as Data).base64EncodedString()
    }
}
