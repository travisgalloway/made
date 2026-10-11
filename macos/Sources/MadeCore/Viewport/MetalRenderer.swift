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

public struct GridUniforms {
    public var viewProjectionMatrix: simd_float4x4
    
    public init(viewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4) {
        self.viewProjectionMatrix = viewProjectionMatrix
    }
}

public struct BillboardUniforms {
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
    
    // Grid rendering pipeline and resources
    private let gridPipelineState: MTLRenderPipelineState
    private let gridDepthState: MTLDepthStencilState
    private var gridPositionBuffer: MTLBuffer?
    private var gridColorBuffer: MTLBuffer?
    private var gridVertexCount: Int = 0
    
    // Axes line rendering resources
    private let axesDepthState: MTLDepthStencilState
    private var axesPositionBuffer: MTLBuffer?
    private var axesColorBuffer: MTLBuffer?
    private var axesVertexCount: Int = 0
    
    // Axes billboard label rendering resources
    private let billboardPipelineState: MTLRenderPipelineState
    private let billboardDepthState: MTLDepthStencilState
    private let billboardSampler: MTLSamplerState
    private var billboardTexture: MTLTexture?
    private var labelCenterBuffer: MTLBuffer?
    private var labelOffsetBuffer: MTLBuffer?
    private var labelTexCoordBuffer: MTLBuffer?
    private var labelColorBuffer: MTLBuffer?
    private var labelVertexCount: Int = 0
    private var axesLength: Float = AxesGenerator.defaultLength
    private var axesLabelSize: Float = AxesGenerator.defaultLabelSize
    
    public var camera: Camera = Camera()
    public var cameraPosition: SIMD3<Float> {
        get { camera.position }
        set { camera.position = newValue }
    }
    public var cameraTarget: SIMD3<Float> {
        get { camera.target }
        set { camera.target = newValue }
    }
    public var meshes: [SolidId: MetalMesh] = [:]
    public var onDeviceLost: (@Sendable () -> Void)? = nil
    public var onFrameRendered: (@Sendable () -> Void)? = nil
    
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
        
        // Grid pipeline state
        guard let gridVertexFunc = library.makeFunction(name: "gridVertexShader"),
              let gridFragmentFunc = library.makeFunction(name: "gridFragmentShader") else {
            print("Failed to locate grid shader entry points")
            return nil
        }
        
        let gridPipelineDesc = MTLRenderPipelineDescriptor()
        gridPipelineDesc.vertexFunction = gridVertexFunc
        gridPipelineDesc.fragmentFunction = gridFragmentFunc
        gridPipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        gridPipelineDesc.depthAttachmentPixelFormat = .depth32Float
        
        do {
            self.gridPipelineState = try device.makeRenderPipelineState(descriptor: gridPipelineDesc)
        } catch {
            print("Failed to create grid pipeline state: \(error)")
            return nil
        }
        
        let gridDepthDesc = MTLDepthStencilDescriptor()
        gridDepthDesc.depthCompareFunction = .less
        gridDepthDesc.isDepthWriteEnabled = true
        guard let gridDepth = device.makeDepthStencilState(descriptor: gridDepthDesc) else { return nil }
        self.gridDepthState = gridDepth
        
        // Axes depth stencil state: .lessEqual so axes pass depth test when coplanar with Z=0 ground grid
        let axesDepthDesc = MTLDepthStencilDescriptor()
        axesDepthDesc.depthCompareFunction = .lessEqual
        axesDepthDesc.isDepthWriteEnabled = true
        guard let axesDepth = device.makeDepthStencilState(descriptor: axesDepthDesc) else { return nil }
        self.axesDepthState = axesDepth
        
        // Billboard pipeline state
        guard let billboardVertexFunc = library.makeFunction(name: "billboardVertexShader"),
              let billboardFragmentFunc = library.makeFunction(name: "billboardFragmentShader") else {
            print("Failed to locate billboard shader entry points")
            return nil
        }
        
        let billboardPipelineDesc = MTLRenderPipelineDescriptor()
        billboardPipelineDesc.vertexFunction = billboardVertexFunc
        billboardPipelineDesc.fragmentFunction = billboardFragmentFunc
        billboardPipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        billboardPipelineDesc.colorAttachments[0].isBlendingEnabled = true
        billboardPipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        billboardPipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        billboardPipelineDesc.colorAttachments[0].rgbBlendOperation = .add
        billboardPipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        billboardPipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        billboardPipelineDesc.colorAttachments[0].alphaBlendOperation = .add
        billboardPipelineDesc.depthAttachmentPixelFormat = .depth32Float
        
        do {
            self.billboardPipelineState = try device.makeRenderPipelineState(descriptor: billboardPipelineDesc)
        } catch {
            print("Failed to create billboard pipeline state: \(error)")
            return nil
        }
        
        let billboardDepthDesc = MTLDepthStencilDescriptor()
        billboardDepthDesc.depthCompareFunction = .lessEqual
        billboardDepthDesc.isDepthWriteEnabled = false
        guard let billboardDepth = device.makeDepthStencilState(descriptor: billboardDepthDesc) else { return nil }
        self.billboardDepthState = billboardDepth
        
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else { return nil }
        self.billboardSampler = sampler
        self.billboardTexture = AxesGenerator.createAxesLabelAtlas(device: device)
        
        super.init()
        
        setupGrid()
        setupAxes()
    }
    
    private func setupGrid(size: Float = GridGenerator.defaultSize, spacing: Float = defaultGridSpacing) {
        let grid = GridGenerator.generateGrid(size: size, spacing: spacing)
        self.gridVertexCount = grid.vertexCount
        
        guard !grid.positions.isEmpty else {
            self.gridPositionBuffer = nil
            self.gridColorBuffer = nil
            return
        }
        
        let posByteLength = grid.positions.count * MemoryLayout<Float>.stride
        self.gridPositionBuffer = device.makeBuffer(
            bytes: grid.positions,
            length: posByteLength,
            options: .storageModeShared
        )
        
        let colByteLength = grid.colors.count * MemoryLayout<Float>.stride
        self.gridColorBuffer = device.makeBuffer(
            bytes: grid.colors,
            length: colByteLength,
            options: .storageModeShared
        )
    }
    
    /// Updates the ground grid dimensions or spacing.
    public func updateGrid(size: Float = GridGenerator.defaultSize, spacing: Float = defaultGridSpacing) {
        setupGrid(size: size, spacing: spacing)
    }
    
    private func setupAxes(length: Float = AxesGenerator.defaultLength, labelSize: Float = AxesGenerator.defaultLabelSize) {
        self.axesLength = length
        self.axesLabelSize = labelSize
        let axes = AxesGenerator.generateAxes(length: length, labelSize: labelSize)
        self.axesVertexCount = axes.lineVertexCount
        self.labelVertexCount = axes.labelVertexCount
        
        guard !axes.linePositions.isEmpty else {
            self.axesPositionBuffer = nil
            self.axesColorBuffer = nil
            self.labelCenterBuffer = nil
            self.labelOffsetBuffer = nil
            self.labelTexCoordBuffer = nil
            self.labelColorBuffer = nil
            return
        }
        
        self.axesPositionBuffer = device.makeBuffer(
            bytes: axes.linePositions,
            length: axes.linePositions.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        self.axesColorBuffer = device.makeBuffer(
            bytes: axes.lineColors,
            length: axes.lineColors.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        self.labelCenterBuffer = device.makeBuffer(
            bytes: axes.labelCenters,
            length: axes.labelCenters.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        self.labelOffsetBuffer = device.makeBuffer(
            bytes: axes.labelOffsets,
            length: axes.labelOffsets.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        self.labelTexCoordBuffer = device.makeBuffer(
            bytes: axes.labelTexCoords,
            length: axes.labelTexCoords.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        self.labelColorBuffer = device.makeBuffer(
            bytes: axes.labelColors,
            length: axes.labelColors.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }
    
    /// Updates the axes indicator dimensions.
    public func updateAxes(length: Float = AxesGenerator.defaultLength, labelSize: Float = AxesGenerator.defaultLabelSize) {
        setupAxes(length: length, labelSize: labelSize)
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
        
        // Draw ground grid on Z = 0
        if let gridPos = gridPositionBuffer, let gridCol = gridColorBuffer, gridVertexCount > 0 {
            encoder.setRenderPipelineState(gridPipelineState)
            encoder.setDepthStencilState(gridDepthState)
            encoder.setCullMode(.none)
            
            var gridUniforms = GridUniforms(viewProjectionMatrix: projMatrix * viewMatrix)
            encoder.setVertexBuffer(gridPos, offset: 0, index: 0)
            encoder.setVertexBuffer(gridCol, offset: 0, index: 1)
            encoder.setVertexBytes(&gridUniforms, length: MemoryLayout<GridUniforms>.stride, index: 2)
            
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridVertexCount)
            drawCalls += 1
        }
        
        // Draw axes indicator lines at origin
        if let axesPos = axesPositionBuffer, let axesCol = axesColorBuffer, axesVertexCount > 0 {
            encoder.setRenderPipelineState(gridPipelineState)
            encoder.setDepthStencilState(axesDepthState)
            encoder.setCullMode(.none)
            
            var gridUniforms = GridUniforms(viewProjectionMatrix: projMatrix * viewMatrix)
            encoder.setVertexBuffer(axesPos, offset: 0, index: 0)
            encoder.setVertexBuffer(axesCol, offset: 0, index: 1)
            encoder.setVertexBytes(&gridUniforms, length: MemoryLayout<GridUniforms>.stride, index: 2)
            
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: axesVertexCount)
            drawCalls += 1
        }
        
        // Draw axes billboard labels
        if let labelPos = labelCenterBuffer,
           let labelOff = labelOffsetBuffer,
           let labelUV = labelTexCoordBuffer,
           let labelCol = labelColorBuffer,
           let labelTex = billboardTexture,
           labelVertexCount > 0 {
            encoder.setRenderPipelineState(billboardPipelineState)
            encoder.setDepthStencilState(billboardDepthState)
            encoder.setCullMode(.none)
            
            var uniforms = BillboardUniforms(
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                labelSize: axesLabelSize
            )
            encoder.setVertexBuffer(labelPos, offset: 0, index: 0)
            encoder.setVertexBuffer(labelOff, offset: 0, index: 1)
            encoder.setVertexBuffer(labelUV, offset: 0, index: 2)
            encoder.setVertexBuffer(labelCol, offset: 0, index: 3)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<BillboardUniforms>.stride, index: 4)
            encoder.setFragmentTexture(labelTex, index: 0)
            encoder.setFragmentSamplerState(billboardSampler, index: 0)
            
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: labelVertexCount)
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
        onFrameRendered?()
    }
    
    public func captureSnapshotPngBase64() async -> String? {
        let width = 800
        let height = 600
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
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
        
        await withCheckedContinuation { continuation in
            cmdBuffer.addCompletedHandler { _ in
                continuation.resume()
            }
            cmdBuffer.commit()
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
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
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
