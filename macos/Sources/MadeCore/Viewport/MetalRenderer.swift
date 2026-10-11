import Foundation
import Metal
import MetalKit
import QuartzCore
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os

/// Metal 4 renderer for the CAD viewport (invariant 5). Draws on demand only (invariant 2).
public final class MetalRenderer: NSObject, MTKViewDelegate, SnapshotProvider, @unchecked Sendable {
    public let device: MTLDevice
    public let commandQueue: MTL4CommandQueue

    private static let log = Logger(subsystem: "com.made.app", category: "Renderer")
    private static let signposter = OSSignposter(subsystem: "com.made.app", category: "Renderer")
    private static let framesInFlight = 3
    private static let colorFormat: MTLPixelFormat = .bgra8Unorm_srgb
    private static let depthFormat: MTLPixelFormat = .depth32Float
    /// The M1 (G13) driver crashes when several threads build Metal 4 pipelines at once, even on separate compilers.
    private static let pipelineBuildLock = NSLock()

    // Pipelines and fixed-function state
    private let solidPipeline: MTLRenderPipelineState
    private let linePipeline: MTLRenderPipelineState
    private let billboardPipeline: MTLRenderPipelineState
    private let solidDepthState: MTLDepthStencilState
    private let gridDepthState: MTLDepthStencilState
    private let axesDepthState: MTLDepthStencilState
    private let billboardDepthState: MTLDepthStencilState
    private let snapDepthState: MTLDepthStencilState
    private let billboardSampler: MTLSamplerState
    private let billboardTexture: MTLTexture?

    // Frame pacing: one allocator, arena, and argument table per frame in flight
    private let frameAllocators: [MTL4CommandAllocator]
    private var frameArenas: [UniformArena]
    private let frameTable: MTL4ArgumentTable
    private let frameEvent: MTLSharedEvent
    private var frameNumber: UInt64 = 0
    private var hasLayerResidency = false

    // Snapshots encode off the main thread, so they own separate encoding resources
    private let snapshotAllocator: MTL4CommandAllocator
    private let snapshotTable: MTL4ArgumentTable
    private let snapshotLock = NSLock()

    /// Every buffer and texture the renderer binds; Metal 4 requires explicit residency.
    private let residencySet: MTLResidencySet

    // Static geometry
    private var gridPositionBuffer: MTLBuffer?
    private var gridColorBuffer: MTLBuffer?
    private var gridVertexCount = 0
    private var axesPositionBuffer: MTLBuffer?
    private var axesColorBuffer: MTLBuffer?
    private var axesVertexCount = 0
    private var labelCenterBuffer: MTLBuffer?
    private var labelOffsetBuffer: MTLBuffer?
    private var labelTexCoordBuffer: MTLBuffer?
    private var labelColorBuffer: MTLBuffer?
    private var labelVertexCount = 0
    private var axesLabelSize: Float = AxesGenerator.defaultLabelSize
    private var snapPositionBuffer: MTLBuffer?
    private var snapNormalBuffer: MTLBuffer?
    private var snapIndexBuffer: MTLBuffer?
    private var snapIndexCount = 0

    public var activeSnap: SnapResult? = nil
    public var camera: Camera = Camera()
    public var cameraPosition: SIMD3<Float> {
        get { camera.position }
        set { camera.position = newValue }
    }
    public var cameraTarget: SIMD3<Float> {
        get { camera.target }
        set { camera.target = newValue }
    }
    public var meshes: [SolidId: MetalMesh] = [:] {
        didSet { updateResidency() }
    }
    public var projectionMode: CameraProjection = .perspective
    public var hiddenSolidIds: Set<SolidId> = []
    public var onDeviceLost: (@Sendable () -> Void)? = nil
    public var onFrameRendered: (@Sendable () -> Void)? = nil

    public init?(device: MTLDevice) {
        guard device.supportsFamily(.metal4) else {
            Self.log.error("Device \(device.name, privacy: .public) does not support Metal 4")
            return nil
        }
        self.device = device

        guard let queue = device.makeMTL4CommandQueue(),
              let residency = try? device.makeResidencySet(descriptor: MTLResidencySetDescriptor()),
              let event = device.makeSharedEvent(),
              let snapshotAllocator = device.makeCommandAllocator() else { return nil }
        self.commandQueue = queue
        self.residencySet = residency
        self.frameEvent = event
        self.snapshotAllocator = snapshotAllocator

        var allocators: [MTL4CommandAllocator] = []
        var arenas: [UniformArena] = []
        let initialCapacity = UniformArena.capacity(forDraws: 64, blockSize: MemoryLayout<RenderUniforms>.stride)
        for _ in 0..<Self.framesInFlight {
            guard let allocator = device.makeCommandAllocator(),
                  let arena = UniformArena(device: device, capacity: initialCapacity) else { return nil }
            allocators.append(allocator)
            arenas.append(arena)
        }
        self.frameAllocators = allocators
        self.frameArenas = arenas

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 5
        tableDescriptor.maxTextureBindCount = 1
        tableDescriptor.maxSamplerStateBindCount = 1
        guard let frameTable = try? device.makeArgumentTable(descriptor: tableDescriptor),
              let snapshotTable = try? device.makeArgumentTable(descriptor: tableDescriptor) else { return nil }
        self.frameTable = frameTable
        self.snapshotTable = snapshotTable

        // Shaders are compiled at build time into the MadeCore bundle's default library.
        do {
            Self.pipelineBuildLock.lock()
            defer { Self.pipelineBuildLock.unlock() }
            let library = try device.makeDefaultLibrary(bundle: .module)
            let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
            self.solidPipeline = try Self.makePipeline(compiler, library, vertex: "cadVertexShader", fragment: "cadFragmentShader")
            self.linePipeline = try Self.makePipeline(compiler, library, vertex: "gridVertexShader", fragment: "gridFragmentShader")
            self.billboardPipeline = try Self.makePipeline(compiler, library, vertex: "billboardVertexShader", fragment: "billboardFragmentShader", alphaBlend: true)
        } catch {
            Self.log.error("Failed to build Metal 4 pipelines: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let solidDepth = Self.makeDepthState(device, .less, write: true),
              let gridDepth = Self.makeDepthState(device, .less, write: true),
              // .lessEqual so the axes pass the depth test where they are coplanar with the Z = 0 grid
              let axesDepth = Self.makeDepthState(device, .lessEqual, write: true),
              let billboardDepth = Self.makeDepthState(device, .lessEqual, write: false),
              let snapDepth = Self.makeDepthState(device, .always, write: false) else { return nil }
        self.solidDepthState = solidDepth
        self.gridDepthState = gridDepth
        self.axesDepthState = axesDepth
        self.billboardDepthState = billboardDepth
        self.snapDepthState = snapDepth

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.supportArgumentBuffers = true  // required for gpuResourceID binding
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }
        self.billboardSampler = sampler
        self.billboardTexture = AxesGenerator.createAxesLabelAtlas(device: device)

        super.init()

        setupGrid()
        setupAxes()
        setupSnapMarker()
        queue.addResidencySet(residency)
    }

    private static func makePipeline(
        _ compiler: MTL4Compiler,
        _ library: MTLLibrary,
        vertex: String,
        fragment: String,
        alphaBlend: Bool = false
    ) throws -> MTLRenderPipelineState {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.name = vertex
        vertexFunction.library = library
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.name = fragment
        fragmentFunction.library = library

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = vertex
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = colorFormat
        if alphaBlend {
            color.blendingState = .enabled
            color.sourceRGBBlendFactor = .sourceAlpha
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.rgbBlendOperation = .add
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            color.alphaBlendOperation = .add
        }
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeDepthState(_ device: MTLDevice, _ compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = compare
        descriptor.isDepthWriteEnabled = write
        return device.makeDepthStencilState(descriptor: descriptor)
    }

    // MARK: - Static geometry

    private func makeBuffer<T: BitwiseCopyable>(_ values: [T], label: String) -> MTLBuffer? {
        guard !values.isEmpty else { return nil }
        let buffer = values.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
        buffer?.label = label
        return buffer
    }

    private func setupGrid(size: Float = GridGenerator.defaultSize, spacing: Float = defaultGridSpacing) {
        let grid = GridGenerator.generateGrid(size: size, spacing: spacing)
        gridVertexCount = grid.vertexCount
        gridPositionBuffer = makeBuffer(grid.positions, label: "Grid Positions")
        gridColorBuffer = makeBuffer(grid.colors, label: "Grid Colors")
        updateResidency()
    }

    /// Updates the ground grid dimensions or spacing.
    public func updateGrid(size: Float = GridGenerator.defaultSize, spacing: Float = defaultGridSpacing) {
        setupGrid(size: size, spacing: spacing)
    }

    private func setupAxes(length: Float = AxesGenerator.defaultLength, labelSize: Float = AxesGenerator.defaultLabelSize) {
        axesLabelSize = labelSize
        let axes = AxesGenerator.generateAxes(length: length, labelSize: labelSize)
        axesVertexCount = axes.lineVertexCount
        labelVertexCount = axes.labelVertexCount
        axesPositionBuffer = makeBuffer(axes.linePositions, label: "Axes Positions")
        axesColorBuffer = makeBuffer(axes.lineColors, label: "Axes Colors")
        labelCenterBuffer = makeBuffer(axes.labelCenters, label: "Label Centers")
        labelOffsetBuffer = makeBuffer(axes.labelOffsets, label: "Label Offsets")
        labelTexCoordBuffer = makeBuffer(axes.labelTexCoords, label: "Label UVs")
        labelColorBuffer = makeBuffer(axes.labelColors, label: "Label Colors")
        updateResidency()
    }

    /// Updates the axes indicator dimensions.
    public func updateAxes(length: Float = AxesGenerator.defaultLength, labelSize: Float = AxesGenerator.defaultLabelSize) {
        setupAxes(length: length, labelSize: labelSize)
    }

    private func setupSnapMarker(radius: Float = 2.5) {
        let r = radius
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(0, 0, r), SIMD3(r, 0, 0), SIMD3(0, -r, 0)),
            (SIMD3(0, 0, r), SIMD3(0, -r, 0), SIMD3(-r, 0, 0)),
            (SIMD3(0, 0, r), SIMD3(-r, 0, 0), SIMD3(0, r, 0)),
            (SIMD3(0, 0, r), SIMD3(0, r, 0), SIMD3(r, 0, 0)),
            (SIMD3(0, 0, -r), SIMD3(0, -r, 0), SIMD3(r, 0, 0)),
            (SIMD3(0, 0, -r), SIMD3(-r, 0, 0), SIMD3(0, -r, 0)),
            (SIMD3(0, 0, -r), SIMD3(0, r, 0), SIMD3(-r, 0, 0)),
            (SIMD3(0, 0, -r), SIMD3(r, 0, 0), SIMD3(0, r, 0))
        ]
        var positions: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []
        for (v0, v1, v2) in faces {
            let n = simd_normalize(simd_cross(v1 - v0, v2 - v0))
            let base = UInt32(positions.count / 3)
            for v in [v0, v1, v2] {
                positions.append(contentsOf: [v.x, v.y, v.z])
                normals.append(contentsOf: [n.x, n.y, n.z])
            }
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
        snapIndexCount = indices.count
        snapPositionBuffer = makeBuffer(positions, label: "Snap Positions")
        snapNormalBuffer = makeBuffer(normals, label: "Snap Normals")
        snapIndexBuffer = makeBuffer(indices, label: "Snap Indices")
        updateResidency()
    }

    /// Converts a MeshPayload into a MetalMesh in shared, unified memory (invariant 6).
    public func createMesh(
        from payload: MeshPayload,
        solidId: SolidId = SolidId("solid"),
        transform: Transform = .identity,
        color: SIMD4<Float>
    ) -> MetalMesh? {
        guard let positions = makeBuffer(payload.positions, label: "\(solidId) Positions"),
              let normals = makeBuffer(payload.normals, label: "\(solidId) Normals"),
              let indices = makeBuffer(payload.indices, label: "\(solidId) Indices") else { return nil }
        return MetalMesh(
            positionBuffer: positions,
            normalBuffer: normals,
            indexBuffer: indices,
            indexCount: payload.indices.count,
            transform: transform,
            color: color,
            candidateMesh: CandidateMesh(id: solidId, payload: payload, transform: transform)
        )
    }

    /// Returns the scene's current candidate meshes for snapping.
    public func candidateMeshes() -> [CandidateMesh] {
        meshes.compactMap { id, mesh in
            guard !hiddenSolidIds.contains(id) else { return nil }
            var candidate = mesh.candidateMesh
            candidate.transform = mesh.transform
            return candidate
        }
    }

    // MARK: - Residency

    private func updateResidency() {
        residencySet.removeAllAllocations()
        var allocations: [MTLAllocation] = frameArenas.map(\.buffer)
        let statics: [MTLBuffer?] = [
            gridPositionBuffer, gridColorBuffer, axesPositionBuffer, axesColorBuffer,
            labelCenterBuffer, labelOffsetBuffer, labelTexCoordBuffer, labelColorBuffer,
            snapPositionBuffer, snapNormalBuffer, snapIndexBuffer
        ]
        allocations += statics.compactMap { $0 }
        if let billboardTexture { allocations.append(billboardTexture) }
        for mesh in meshes.values {
            allocations += [mesh.positionBuffer, mesh.normalBuffer, mesh.indexBuffer]
        }
        residencySet.addAllocations(allocations)
        residencySet.commit()
    }

    // MARK: - Encoding

    private struct EncodeContext {
        let encoder: MTL4RenderCommandEncoder
        let table: MTL4ArgumentTable
        let arena: UniformArena

        func bind(_ buffer: MTLBuffer, at index: Int) {
            table.setAddress(buffer.gpuAddress, index: index)
        }

        /// Returns false when the arena is full, so the caller skips the draw.
        func bindUniforms<T: BitwiseCopyable>(_ value: T, at index: Int) -> Bool {
            guard let address = arena.push(value) else { return false }
            table.setAddress(address, index: index)
            return true
        }
    }

    private func requiredArenaCapacity() -> Int {
        // One block per visible solid, plus grid, axes, labels, and snap marker.
        UniformArena.capacity(forDraws: meshes.count + 4, blockSize: MemoryLayout<RenderUniforms>.stride)
    }

    @discardableResult
    private func renderScene(_ ctx: EncodeContext, aspect: Float) -> Int {
        let encoder = ctx.encoder
        encoder.setArgumentTable(ctx.table, stages: [.vertex, .fragment])
        encoder.setRenderPipelineState(solidPipeline)
        encoder.setDepthStencilState(solidDepthState)
        // Euclid emits counter-clockwise triangles; Metal assumes clockwise unless told otherwise.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)

        let viewMatrix = Orientation.makeLookAt(eye: cameraPosition, target: cameraTarget, up: Orientation.worldUp)
        let projMatrix: simd_float4x4
        if projectionMode == .orthographic {
            let dist = max(10.0, simd_length(cameraPosition - cameraTarget))
            let halfH = dist * 0.4
            let halfW = halfH * aspect
            projMatrix = Orientation.makeOrthographic(left: -halfW, right: halfW, bottom: -halfH, top: halfH, nearZ: 0.1, farZ: 1000.0)
        } else {
            projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
        }

        var drawCalls = 0
        for (id, mesh) in meshes where !hiddenSolidIds.contains(id) {
            var modelMatrix = matrix_identity_float4x4
            modelMatrix.columns.3 = SIMD4<Float>(mesh.transform.position, 1.0)
            let uniforms = RenderUniforms(
                modelMatrix: modelMatrix,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                normalMatrix: matrix_identity_float3x3,  // translation-only model matrix
                color: mesh.color
            )
            guard ctx.bindUniforms(uniforms, at: 2) else { break }
            ctx.bind(mesh.positionBuffer, at: 0)
            ctx.bind(mesh.normalBuffer, at: 1)
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: mesh.indexCount,
                indexType: .uint32,
                indexBuffer: mesh.indexBuffer.gpuAddress,
                indexBufferLength: mesh.indexBuffer.length
            )
            drawCalls += 1
        }

        let lineUniforms = GridUniforms(viewProjectionMatrix: projMatrix * viewMatrix)

        // Ground grid on Z = 0
        if let positions = gridPositionBuffer, let colors = gridColorBuffer, gridVertexCount > 0,
           ctx.bindUniforms(lineUniforms, at: 2) {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setDepthStencilState(gridDepthState)
            encoder.setCullMode(.none)
            ctx.bind(positions, at: 0)
            ctx.bind(colors, at: 1)
            encoder.drawPrimitives(primitiveType: .line, vertexStart: 0, vertexCount: gridVertexCount)
            drawCalls += 1
        }

        // Axes indicator lines at the origin
        if let positions = axesPositionBuffer, let colors = axesColorBuffer, axesVertexCount > 0,
           ctx.bindUniforms(lineUniforms, at: 2) {
            encoder.setRenderPipelineState(linePipeline)
            encoder.setDepthStencilState(axesDepthState)
            encoder.setCullMode(.none)
            ctx.bind(positions, at: 0)
            ctx.bind(colors, at: 1)
            encoder.drawPrimitives(primitiveType: .line, vertexStart: 0, vertexCount: axesVertexCount)
            drawCalls += 1
        }

        // Axes billboard labels
        if let centers = labelCenterBuffer, let offsets = labelOffsetBuffer, let uvs = labelTexCoordBuffer,
           let colors = labelColorBuffer, let texture = billboardTexture, labelVertexCount > 0,
           ctx.bindUniforms(BillboardUniforms(viewMatrix: viewMatrix, projectionMatrix: projMatrix, labelSize: axesLabelSize), at: 4) {
            encoder.setRenderPipelineState(billboardPipeline)
            encoder.setDepthStencilState(billboardDepthState)
            encoder.setCullMode(.none)
            ctx.bind(centers, at: 0)
            ctx.bind(offsets, at: 1)
            ctx.bind(uvs, at: 2)
            ctx.bind(colors, at: 3)
            ctx.table.setTexture(texture.gpuResourceID, index: 0)
            ctx.table.setSamplerState(billboardSampler.gpuResourceID, index: 0)
            encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: labelVertexCount)
            drawCalls += 1
        }

        // Snap marker
        if let snap = activeSnap, let positions = snapPositionBuffer, let normals = snapNormalBuffer,
           let indices = snapIndexBuffer, snapIndexCount > 0 {
            var modelMatrix = matrix_identity_float4x4
            modelMatrix.columns.3 = SIMD4<Float>(snap.point, 1.0)
            let color: SIMD4<Float>
            switch snap.kind {
            case .vertex: color = SIMD4(1.0, 0.65, 0.0, 1.0)  // amber
            case .edge: color = SIMD4(0.0, 0.85, 1.0, 1.0)    // cyan
            case .grid: color = SIMD4(0.2, 0.9, 0.2, 1.0)     // green
            }
            let uniforms = RenderUniforms(
                modelMatrix: modelMatrix,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                normalMatrix: matrix_identity_float3x3,
                color: color
            )
            if ctx.bindUniforms(uniforms, at: 2) {
                encoder.setRenderPipelineState(solidPipeline)
                encoder.setDepthStencilState(snapDepthState)
                encoder.setCullMode(.none)
                ctx.bind(positions, at: 0)
                ctx.bind(normals, at: 1)
                encoder.drawIndexedPrimitives(
                    primitiveType: .triangle,
                    indexCount: snapIndexCount,
                    indexType: .uint32,
                    indexBuffer: indices.gpuAddress,
                    indexBufferLength: indices.length
                )
                drawCalls += 1
            }
        }

        return drawCalls
    }

    private func makeCommitOptions(onComplete: (@Sendable (Error?) -> Void)? = nil) -> MTL4CommitOptions {
        let options = MTL4CommitOptions()
        options.addFeedbackHandler { [weak self] feedback in
            if let error = feedback.error as NSError?,
               error.domain == MTLCommandBufferErrorDomain,
               error.code == MTLCommandBufferError.deviceRemoved.rawValue {
                self?.onDeviceLost?()
            }
            onComplete?(feedback.error)
        }
        return options
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The aspect ratio is read from drawableSize on each draw.
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentMTL4RenderPassDescriptor,
              let commandBuffer = device.makeCommandBuffer() else { return }

        if !hasLayerResidency, let layer = view.layer as? CAMetalLayer {
            commandQueue.addResidencySet(layer.residencySet)
            hasLayerResidency = true
        }

        let interval = Self.signposter.beginInterval("Frame")
        defer { Self.signposter.endInterval("Frame", interval) }

        frameNumber += 1
        let slot = Int(frameNumber % UInt64(Self.framesInFlight))
        if frameNumber > UInt64(Self.framesInFlight) {
            // Waits for the GPU to release this slot's allocator and arena.
            _ = frameEvent.wait(untilSignaledValue: frameNumber - UInt64(Self.framesInFlight), timeoutMS: 1000)
        }
        let required = requiredArenaCapacity()
        if frameArenas[slot].capacity < required, let grown = UniformArena(device: device, capacity: required * 2) {
            frameArenas[slot] = grown
            updateResidency()
        }
        let allocator = frameAllocators[slot]
        let arena = frameArenas[slot]
        allocator.reset()
        arena.reset()

        commandBuffer.beginCommandBuffer(allocator: allocator)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            commandBuffer.endCommandBuffer()
            return
        }
        let aspect = Float(max(1.0, view.drawableSize.width) / max(1.0, view.drawableSize.height))
        let drawCalls = renderScene(EncodeContext(encoder: encoder, table: frameTable, arena: arena), aspect: aspect)
        encoder.endEncoding()
        commandBuffer.endCommandBuffer()

        commandQueue.waitForDrawable(drawable)
        commandQueue.commit([commandBuffer], options: makeCommitOptions())
        commandQueue.signalDrawable(drawable)
        commandQueue.signalEvent(frameEvent, value: frameNumber)
        drawable.present()

        RenderInstrumentation.shared.recordRender(drawCalls: drawCalls)
        onFrameRendered?()
    }

    // MARK: - Snapshot

    public func captureSnapshotPngBase64() async -> String? {
        let width = 800
        let height = 600
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.colorFormat, width: width, height: height, mipmapped: false)
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .shared
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.depthFormat, width: width, height: height, mipmapped: false)
        depthDescriptor.usage = [.renderTarget]
        depthDescriptor.storageMode = .private
        guard let colorTexture = device.makeTexture(descriptor: colorDescriptor),
              let depthTexture = device.makeTexture(descriptor: depthDescriptor),
              let arena = UniformArena(device: device, capacity: requiredArenaCapacity()),
              let snapshotResidency = try? device.makeResidencySet(descriptor: MTLResidencySetDescriptor()),
              let commandBuffer = device.makeCommandBuffer() else { return nil }
        snapshotResidency.addAllocations([colorTexture, depthTexture, arena.buffer])
        snapshotResidency.commit()

        let pass = MTL4RenderPassDescriptor()
        pass.colorAttachments[0].texture = colorTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depthTexture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .dontCare

        let encoded: Bool = snapshotLock.withLock {
            snapshotAllocator.reset()
            commandBuffer.beginCommandBuffer(allocator: snapshotAllocator)
            commandBuffer.useResidencySet(snapshotResidency)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                commandBuffer.endCommandBuffer()
                return false
            }
            renderScene(EncodeContext(encoder: encoder, table: snapshotTable, arena: arena), aspect: Float(width) / Float(height))
            encoder.endEncoding()
            commandBuffer.endCommandBuffer()
            return true
        }
        guard encoded else { return nil }

        let error: Error? = await withCheckedContinuation { continuation in
            commandQueue.commit([commandBuffer], options: makeCommitOptions { continuation.resume(returning: $0) })
        }
        if let error {
            Self.log.error("Snapshot render failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        colorTexture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return Self.pngBase64(bgra: bytes, width: width, height: height)
    }

    private static func pngBase64(bgra bytes: [UInt8], width: Int, height: Int) -> String? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
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
              ) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data).base64EncodedString()
    }
}
