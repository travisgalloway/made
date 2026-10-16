import Foundation
import Metal
import MetalKit
import QuartzCore
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os

struct GizmoGeometryBuffers: @unchecked Sendable {
    let positionBuffer: MTLBuffer
    let defaultColorBuffer: MTLBuffer
    let activeColorBuffer: MTLBuffer
    let vertexCount: Int
}

/// Metal 4 renderer for the CAD viewport (invariant 5). Draws on demand only (invariant 2).
///
/// Marked `@unchecked Sendable` because it coordinates GPU pipeline objects (`MTLDevice`, `MTL4CommandQueue`,
/// `MTLResidencySet`) that lack system Sendable annotations. Mutable scene state (`meshes`, `camera`,
/// `hiddenSolidIds`, `selectedId`, `activeSnap`, `activeGizmoHandle`) is strictly mutated on `@MainActor`.
/// Off-main snapshot routines (`captureSnapshotPngBase64`) capture an immutable `SceneSnapshot` on `@MainActor`
/// before encoding, preventing data races during concurrent scene edits. GPU command encoding for snapshots
/// is synchronized via `snapshotLock`, `snapshotAllocator`, and `snapshotTable`.
public final class MetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
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
    private let cadEdgePipeline: MTLRenderPipelineState
    let linePipeline: MTLRenderPipelineState
    private let billboardPipeline: MTLRenderPipelineState
    private let outlinePipeline: MTLRenderPipelineState
    private let overlayPipeline: MTLRenderPipelineState
    private let edgeHighlightPipeline: MTLRenderPipelineState
    private let pickFacePipeline: MTLRenderPipelineState
    private let pickEdgePipeline: MTLRenderPipelineState
    private let pickVertexPipeline: MTLRenderPipelineState
    private let solidDepthState: MTLDepthStencilState
    private let cadEdgeDepthState: MTLDepthStencilState
    private let gridDepthState: MTLDepthStencilState
    private let axesDepthState: MTLDepthStencilState
    private let billboardDepthState: MTLDepthStencilState
    let snapDepthState: MTLDepthStencilState
    private let outlineDepthState: MTLDepthStencilState
    private let overlayDepthState: MTLDepthStencilState
    private let edgeHighlightDepthState: MTLDepthStencilState
    private let pickFaceDepthState: MTLDepthStencilState
    private let pickEdgeDepthState: MTLDepthStencilState
    private let pickVertexDepthState: MTLDepthStencilState
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

    // GPU picking resources (BL-SEL-02)
    private let pickAllocator: MTL4CommandAllocator
    private let pickTable: MTL4ArgumentTable
    private let pickLock = NSLock()
    private var pickColorTexture: MTLTexture?
    private var pickDepthTexture: MTLTexture?

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
    public var selectedId: SolidId? = nil
    public var selectedSubElement: SelectedSubElement? = nil
    public var preselectedSubElement: SelectedSubElement? = nil
    public var activeGizmoHandle: GizmoHandle? = nil
    public var showsGrid: Bool = true
    public var showsAxes: Bool = true
    public var showsGizmo: Bool = true
    public var showsEdges: Bool = true
    var gizmoGeometry: [GizmoHandle: GizmoGeometryBuffers] = [:]
    public private(set) var lastDrawCalls: Int = 0
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
    public var projectionMode: CameraProjection {
        get { camera.projection }
        set { camera.projection = newValue }
    }
    public var hiddenSolidIds: Set<SolidId> = []
    public var onDeviceLost: (@Sendable () -> Void)? = nil
    public var onFrameRendered: (@Sendable () -> Void)? = nil

    @MainActor
    public func snapshotSceneState() -> SceneSnapshot {
        SceneSnapshot(
            meshes: meshes,
            hiddenSolidIds: hiddenSolidIds,
            camera: camera,
            selectedId: selectedId,
            selectedSubElement: selectedSubElement,
            preselectedSubElement: preselectedSubElement,
            activeSnap: activeSnap,
            activeGizmoHandle: activeGizmoHandle,
            showsEdges: showsEdges
        )
    }

    public init?(device: MTLDevice) {
        guard device.supportsFamily(.metal4) else {
            Self.log.error("Device \(device.name, privacy: .public) does not support Metal 4")
            return nil
        }
        self.device = device

        guard let queue = device.makeMTL4CommandQueue(),
              let residency = try? device.makeResidencySet(descriptor: MTLResidencySetDescriptor()),
              let event = device.makeSharedEvent(),
              let snapshotAllocator = device.makeCommandAllocator(),
              let pickAllocator = device.makeCommandAllocator() else { return nil }
        self.commandQueue = queue
        self.residencySet = residency
        self.frameEvent = event
        self.snapshotAllocator = snapshotAllocator
        self.pickAllocator = pickAllocator

        var allocators: [MTL4CommandAllocator] = []
        var arenas: [UniformArena] = []
        let initialCapacity = UniformArena.capacity(forDraws: 64, blockSize: MemoryLayout<OutlineUniforms>.stride)
        for _ in 0..<Self.framesInFlight {
            guard let allocator = device.makeCommandAllocator(),
                  let arena = UniformArena(device: device, capacity: initialCapacity) else { return nil }
            allocators.append(allocator)
            arenas.append(arena)
        }
        self.frameAllocators = allocators
        self.frameArenas = arenas

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 8
        tableDescriptor.maxTextureBindCount = 1
        tableDescriptor.maxSamplerStateBindCount = 1
        guard let frameTable = try? device.makeArgumentTable(descriptor: tableDescriptor),
              let snapshotTable = try? device.makeArgumentTable(descriptor: tableDescriptor),
              let pickTable = try? device.makeArgumentTable(descriptor: tableDescriptor) else { return nil }
        self.frameTable = frameTable
        self.snapshotTable = snapshotTable
        self.pickTable = pickTable

        // Shaders are compiled at build time into the MadeCore bundle's default library.
        do {
            Self.pipelineBuildLock.lock()
            defer { Self.pipelineBuildLock.unlock() }
            let library = try Self.makeShaderLibrary(device: device)
            let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
            self.solidPipeline = try Self.makePipeline(compiler, library, vertex: "cadVertexShader", fragment: "cadFragmentShader")
            self.cadEdgePipeline = try Self.makePipeline(compiler, library, vertex: "cadEdgeVertexShader", fragment: "cadEdgeFragmentShader", alphaBlend: true)
            self.linePipeline = try Self.makePipeline(compiler, library, vertex: "gridVertexShader", fragment: "gridFragmentShader")
            self.billboardPipeline = try Self.makePipeline(compiler, library, vertex: "billboardVertexShader", fragment: "billboardFragmentShader", alphaBlend: true)
            self.outlinePipeline = try Self.makePipeline(compiler, library, vertex: "outlineVertexShader", fragment: "outlineFragmentShader")
            self.overlayPipeline = try Self.makePipeline(compiler, library, vertex: "cadVertexShader", fragment: "cadFragmentShader", alphaBlend: true)
            self.edgeHighlightPipeline = try Self.makePipeline(compiler, library, vertex: "edgeHighlightVertexShader", fragment: "edgeHighlightFragmentShader", alphaBlend: true)
            self.pickFacePipeline = try Self.makePickPipeline(compiler, library, vertex: "pickFaceVertexShader", fragment: "pickFaceFragmentShader")
            self.pickEdgePipeline = try Self.makePickPipeline(compiler, library, vertex: "pickEdgeVertexShader", fragment: "pickEdgeFragmentShader")
            self.pickVertexPipeline = try Self.makePickPipeline(compiler, library, vertex: "pickVertexVertexShader", fragment: "pickVertexFragmentShader")
        } catch {
            Self.log.error("Failed to build Metal 4 pipelines: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let solidDepth = Self.makeDepthState(device, .less, write: true),
              let cadEdgeDepth = Self.makeDepthState(device, .lessEqual, write: false),
              let gridDepth = Self.makeDepthState(device, .less, write: true),
              // .lessEqual so the axes pass the depth test where they are coplanar with the Z = 0 grid
              let axesDepth = Self.makeDepthState(device, .lessEqual, write: true),
              let billboardDepth = Self.makeDepthState(device, .lessEqual, write: false),
              let snapDepth = Self.makeDepthState(device, .always, write: false),
              let outlineDepth = Self.makeDepthState(device, .lessEqual, write: false),
              let overlayDepth = Self.makeDepthState(device, .lessEqual, write: false),
              let edgeHighlightDepth = Self.makeDepthState(device, .lessEqual, write: false),
              let pickFaceDepth = Self.makeDepthState(device, .less, write: true),
              let pickEdgeDepth = Self.makeDepthState(device, .lessEqual, write: true),
              let pickVertexDepth = Self.makeDepthState(device, .lessEqual, write: true) else { return nil }
        self.solidDepthState = solidDepth
        self.cadEdgeDepthState = cadEdgeDepth
        self.gridDepthState = gridDepth
        self.axesDepthState = axesDepth
        self.billboardDepthState = billboardDepth
        self.snapDepthState = snapDepth
        self.outlineDepthState = outlineDepth
        self.overlayDepthState = overlayDepth
        self.edgeHighlightDepthState = edgeHighlightDepth
        self.pickFaceDepthState = pickFaceDepth
        self.pickEdgeDepthState = pickEdgeDepth
        self.pickVertexDepthState = pickVertexDepth

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
        setupGizmo()
        queue.addResidencySet(residency)
    }

    /// Shader entry points the renderer links; tests check the bundled library against this list.
    public static let shaderFunctionNames = [
        "cadVertexShader", "cadFragmentShader",
        "cadEdgeVertexShader", "cadEdgeFragmentShader",
        "gridVertexShader", "gridFragmentShader",
        "billboardVertexShader", "billboardFragmentShader",
        "outlineVertexShader", "outlineFragmentShader",
        "pickFaceVertexShader", "pickFaceFragmentShader",
        "pickEdgeVertexShader", "pickEdgeFragmentShader",
        "pickVertexVertexShader", "pickVertexFragmentShader",
        "edgeHighlightVertexShader", "edgeHighlightFragmentShader"
    ]

    /// Loads the build-time `default.metallib` from the MadeCore resource bundle. Works on any Metal device.
    public static func makeShaderLibrary(device: MTLDevice) throws -> MTLLibrary {
        try device.makeDefaultLibrary(bundle: .module)
    }

    private static func makePickPipeline(
        _ compiler: MTL4Compiler,
        _ library: MTLLibrary,
        vertex: String,
        fragment: String
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
        color.pixelFormat = .rgba32Uint
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
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

    func makeBuffer<T: BitwiseCopyable>(_ values: [T], label: String) -> MTLBuffer? {
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
    /// The one app-side copy of a kernel mesh: from the mapped shared region into a shared Metal buffer (invariant 6).
    private func makeBuffer<T>(_ component: MeshComponent<T>, label: String) -> MTLBuffer? {
        let buffer = component.withUnsafeBytes { bytes -> MTLBuffer? in
            guard let base = bytes.baseAddress, bytes.count > 0 else { return nil }
            return device.makeBuffer(bytes: base, length: bytes.count, options: .storageModeShared)
        }
        buffer?.label = label
        return buffer
    }

    public func createMesh(
        from payload: MeshPayload,
        solidId: SolidId = SolidId("solid"),
        transform: Transform = .identity,
        color: SIMD4<Float>
    ) -> MetalMesh? {
        guard let positions = makeBuffer(payload.positions, label: "\(solidId) Positions"),
              let normals = makeBuffer(payload.normals, label: "\(solidId) Normals"),
              let indices = makeBuffer(payload.indices, label: "\(solidId) Indices") else { return nil }

        // Build triangleFaceIdBuffer
        let triangleCount = payload.triangleCount
        let faceIdBuffer: MTLBuffer?
        if triangleCount > 0 {
            var faceIds = [UInt32](repeating: 0, count: triangleCount)
            for range in payload.faceRanges {
                for tri in range.triangleRange {
                    if tri >= 0 && tri < triangleCount {
                        faceIds[tri] = UInt32(range.faceId)
                    }
                }
            }
            faceIdBuffer = device.makeBuffer(bytes: faceIds, length: faceIds.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
            faceIdBuffer?.label = "\(solidId) FaceIds"
        } else {
            faceIdBuffer = nil
        }

        // Build edgeSegmentBuffer
        var edgeSegments: [EdgeSegmentData] = []
        for polyline in payload.edgePolylines {
            let pts = polyline.points
            guard pts.count >= 2 else { continue }
            for i in 0..<(pts.count - 1) {
                edgeSegments.append(EdgeSegmentData(
                    start: pts[i],
                    end: pts[i + 1],
                    edgeId: UInt32(polyline.edgeId)
                ))
            }
        }
        let edgeSegmentCount = edgeSegments.count
        let edgeSegmentBuffer: MTLBuffer?
        if edgeSegmentCount > 0 {
            edgeSegmentBuffer = device.makeBuffer(bytes: edgeSegments, length: edgeSegments.count * MemoryLayout<EdgeSegmentData>.stride, options: .storageModeShared)
            edgeSegmentBuffer?.label = "\(solidId) EdgeSegments"
        } else {
            edgeSegmentBuffer = nil
        }

        // Build vertexBuffer
        var vertexDatas: [VertexData] = []
        for vp in payload.vertexPoints {
            vertexDatas.append(VertexData(
                position: vp.position,
                vertexId: UInt32(vp.vertexId)
            ))
        }
        let vertexCount = vertexDatas.count
        let vertexBuffer: MTLBuffer?
        if vertexCount > 0 {
            vertexBuffer = device.makeBuffer(bytes: vertexDatas, length: vertexDatas.count * MemoryLayout<VertexData>.stride, options: .storageModeShared)
            vertexBuffer?.label = "\(solidId) Vertices"
        } else {
            vertexBuffer = nil
        }

        return MetalMesh(
            positionBuffer: positions,
            normalBuffer: normals,
            indexBuffer: indices,
            indexCount: payload.indices.count,
            transform: transform,
            color: color,
            candidateMesh: CandidateMesh(id: solidId, payload: payload, transform: transform),
            faceRanges: payload.faceRanges,
            edgePolylines: payload.edgePolylines,
            vertexPoints: payload.vertexPoints,
            triangleFaceIdBuffer: faceIdBuffer,
            edgeSegmentBuffer: edgeSegmentBuffer,
            edgeSegmentCount: edgeSegmentCount,
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount
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

    /// Computes view and projection matrices for the given aspect ratio and camera,
    /// respecting the camera's projection mode (perspective vs orthographic).
    public func viewAndProjectionMatrices(
        aspect: Float,
        camera: Camera
    ) -> (view: simd_float4x4, projection: simd_float4x4) {
        let eye = camera.position
        let target = camera.target
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: Orientation.worldUp)
        let projMatrix: simd_float4x4
        if camera.projection == .orthographic {
            let baseDist = max(10.0, simd_length(eye - target))
            let dist = max(1.0, baseDist * camera.orthographicScale)
            let halfH = dist * 0.4
            let halfW = halfH * aspect
            projMatrix = Orientation.makeOrthographic(left: -halfW, right: halfW, bottom: -halfH, top: halfH, nearZ: 0.1, farZ: 1000.0)
        } else {
            projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
        }
        return (view: viewMatrix, projection: projMatrix)
    }

    /// Computes view and projection matrices for the given aspect ratio and optional camera override,
    /// respecting the current projection mode (perspective vs orthographic).
    public func viewAndProjectionMatrices(
        aspect: Float,
        cameraOverride: Camera? = nil
    ) -> (view: simd_float4x4, projection: simd_float4x4) {
        viewAndProjectionMatrices(aspect: aspect, camera: cameraOverride ?? camera)
    }

    // MARK: - Residency

    func updateResidency() {
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
            if let tf = mesh.triangleFaceIdBuffer { allocations.append(tf) }
            if let es = mesh.edgeSegmentBuffer { allocations.append(es) }
            if let vb = mesh.vertexBuffer { allocations.append(vb) }
        }
        for geom in gizmoGeometry.values {
            allocations += [geom.positionBuffer, geom.defaultColorBuffer, geom.activeColorBuffer]
        }
        residencySet.addAllocations(allocations)
        residencySet.commit()
    }

    // MARK: - Encoding

    struct EncodeContext {
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

    private func requiredArenaCapacity(meshCount: Int? = nil) -> Int {
        // One block per visible solid, plus edge passes, outline, grid, axes, labels, snap marker, gizmo, and sub-element highlights.
        let count = meshCount ?? meshes.count
        return UniformArena.capacity(forDraws: count * 2 + 16, blockSize: MemoryLayout<OutlineUniforms>.stride)
    }

    private func drawSubElementHighlight(
        _ ctx: EncodeContext,
        scene: SceneSnapshot,
        sub: SelectedSubElement,
        isPreselection: Bool,
        viewMatrix: simd_float4x4,
        projMatrix: simd_float4x4,
        viewportSize: CGSize,
        drawCalls: inout Int
    ) {
        guard let mesh = scene.meshes[sub.solidId], !scene.hiddenSolidIds.contains(sub.solidId) else { return }
        switch sub.elementType {
        case .face:
            let color: SIMD4<Float> = isPreselection ? SIMD4(0.0, 0.85, 1.0, 0.35) : SIMD4(1.0, 0.65, 0.0, 0.45)
            let faceRange = mesh.faceRanges.first(where: { $0.faceId == sub.elementId })
            guard let range = faceRange?.triangleRange, !range.isEmpty else { return }
            let triangleCount = range.upperBound - range.lowerBound
            let indexCount = triangleCount * 3
            let indexOffset = range.lowerBound * 3 * MemoryLayout<UInt32>.stride
            guard indexOffset + indexCount * MemoryLayout<UInt32>.stride <= mesh.indexBuffer.length else { return }

            let uniforms = RenderUniforms(
                modelMatrix: mesh.transform.matrix,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                normalMatrix: mesh.transform.normalMatrix,
                color: color
            )
            guard ctx.bindUniforms(uniforms, at: 2) else { return }
            ctx.encoder.setRenderPipelineState(overlayPipeline)
            ctx.encoder.setDepthStencilState(overlayDepthState)
            ctx.encoder.setCullMode(.back)
            ctx.bind(mesh.positionBuffer, at: 0)
            ctx.bind(mesh.normalBuffer, at: 1)
            ctx.encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: indexCount,
                indexType: .uint32,
                indexBuffer: mesh.indexBuffer.gpuAddress + UInt64(indexOffset),
                indexBufferLength: mesh.indexBuffer.length - indexOffset
            )
            drawCalls += 1

        case .edge:
            let color: SIMD4<Float> = isPreselection ? SIMD4(0.0, 0.85, 1.0, 1.0) : SIMD4(1.0, 0.65, 0.0, 1.0)
            guard mesh.edgeSegmentCount > 0, let segBuf = mesh.edgeSegmentBuffer else { return }
            let edgeUniforms = EdgeHighlightUniforms(
                modelMatrix: mesh.transform.matrix,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                color: color,
                viewportWidth: Float(max(viewportSize.width, 1.0)),
                viewportHeight: Float(max(viewportSize.height, 1.0)),
                lineWidth: 3.0,
                targetEdgeId: UInt32(sub.elementId),
                depthBias: 0.005
            )
            guard ctx.bindUniforms(edgeUniforms, at: 2) else { return }
            ctx.encoder.setRenderPipelineState(edgeHighlightPipeline)
            ctx.encoder.setDepthStencilState(edgeHighlightDepthState)
            ctx.encoder.setCullMode(.none)
            ctx.bind(segBuf, at: 3)
            ctx.encoder.drawPrimitives(
                primitiveType: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: mesh.edgeSegmentCount
            )
            drawCalls += 1

        case .vertex:
            let color: SIMD4<Float> = isPreselection ? SIMD4(0.0, 0.85, 1.0, 1.0) : SIMD4(1.0, 0.65, 0.0, 1.0)
            let vertexPoint = mesh.vertexPoints.first(where: { $0.vertexId == sub.elementId })
            guard let vp = vertexPoint,
                  let positions = snapPositionBuffer,
                  let normals = snapNormalBuffer,
                  let indices = snapIndexBuffer,
                  snapIndexCount > 0 else { return }
            let world4 = mesh.transform.matrix * SIMD4<Float>(vp.position, 1.0)
            let worldPos = SIMD3<Float>(world4.x, world4.y, world4.z)
            var modelMatrix = matrix_identity_float4x4
            modelMatrix.columns.3 = SIMD4<Float>(worldPos, 1.0)
            let uniforms = RenderUniforms(
                modelMatrix: modelMatrix,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                normalMatrix: matrix_identity_float3x3,
                color: color
            )
            guard ctx.bindUniforms(uniforms, at: 2) else { return }
            ctx.encoder.setRenderPipelineState(solidPipeline)
            ctx.encoder.setDepthStencilState(snapDepthState)
            ctx.encoder.setCullMode(.none)
            ctx.bind(positions, at: 0)
            ctx.bind(normals, at: 1)
            ctx.encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: snapIndexCount,
                indexType: .uint32,
                indexBuffer: indices.gpuAddress,
                indexBufferLength: indices.length
            )
            drawCalls += 1
        }
    }

    @discardableResult
    private func renderScene(
        _ ctx: EncodeContext,
        scene: SceneSnapshot,
        aspect: Float,
        cameraOverride: Camera? = nil,
        includeGizmo: Bool = true,
        viewportSize: CGSize = CGSize(width: 800, height: 600)
    ) -> Int {
        let encoder = ctx.encoder
        encoder.setArgumentTable(ctx.table, stages: [.vertex, .fragment])
        encoder.setRenderPipelineState(solidPipeline)
        encoder.setDepthStencilState(solidDepthState)
        // Euclid emits counter-clockwise triangles; Metal assumes clockwise unless told otherwise.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)

        let activeCamera = cameraOverride ?? scene.camera
        let matrices = viewAndProjectionMatrices(aspect: aspect, camera: activeCamera)
        let viewMatrix = matrices.view
        let projMatrix = matrices.projection

        var drawCalls = 0
        for (id, mesh) in scene.meshes where !scene.hiddenSolidIds.contains(id) {
            let uniforms = RenderUniforms(
                modelMatrix: mesh.transform.matrix,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                normalMatrix: mesh.transform.normalMatrix,
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

        // B-rep edge rendering pass (instanced screen-space quad ribbons with depth bias)
        if scene.showsEdges {
            encoder.setRenderPipelineState(cadEdgePipeline)
            encoder.setDepthStencilState(cadEdgeDepthState)
            encoder.setCullMode(.none)
            for (id, mesh) in scene.meshes where !scene.hiddenSolidIds.contains(id) && mesh.edgeSegmentCount > 0 {
                guard let segBuf = mesh.edgeSegmentBuffer else { continue }
                let edgeUniforms = CadEdgeUniforms(
                    modelMatrix: mesh.transform.matrix,
                    viewMatrix: viewMatrix,
                    projectionMatrix: projMatrix,
                    color: SIMD4<Float>(0.15, 0.15, 0.18, 1.0),
                    viewportWidth: Float(max(viewportSize.width, 1.0)),
                    viewportHeight: Float(max(viewportSize.height, 1.0)),
                    lineWidth: 1.2,
                    depthBias: 0.003
                )
                guard ctx.bindUniforms(edgeUniforms, at: 2) else { break }
                ctx.bind(segBuf, at: 3)
                encoder.drawPrimitives(
                    primitiveType: .triangle,
                    vertexStart: 0,
                    vertexCount: 6,
                    instanceCount: mesh.edgeSegmentCount
                )
                drawCalls += 1
            }
        }

        // Selection outline pass for the selected solid (cull .front, depth test .lessEqual, write: false)
        if let selectedId = scene.selectedId,
           let mesh = scene.meshes[selectedId],
           !scene.hiddenSolidIds.contains(selectedId) {
            let outlineUniforms = OutlineUniforms(
                modelMatrix: mesh.transform.matrix,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                normalMatrix: mesh.transform.normalMatrix,
                color: SIMD4<Float>(1.0, 0.65, 0.0, 1.0),
                outlineWidth: 0.008
            )
            if ctx.bindUniforms(outlineUniforms, at: 2) {
                encoder.setRenderPipelineState(outlinePipeline)
                encoder.setDepthStencilState(outlineDepthState)
                encoder.setCullMode(.front)
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
        }

        // Sub-element highlight passes: committed selection (amber) and hover preselection (cyan)
        if let selectedSub = scene.selectedSubElement {
            drawSubElementHighlight(
                ctx,
                scene: scene,
                sub: selectedSub,
                isPreselection: false,
                viewMatrix: viewMatrix,
                projMatrix: projMatrix,
                viewportSize: viewportSize,
                drawCalls: &drawCalls
            )
        }

        if let preselectedSub = scene.preselectedSubElement,
           preselectedSub != scene.selectedSubElement {
            drawSubElementHighlight(
                ctx,
                scene: scene,
                sub: preselectedSub,
                isPreselection: true,
                viewMatrix: viewMatrix,
                projMatrix: projMatrix,
                viewportSize: viewportSize,
                drawCalls: &drawCalls
            )
        }

        let lineUniforms = GridUniforms(viewProjectionMatrix: projMatrix * viewMatrix)

        // Ground grid on Z = 0
        if showsGrid, let positions = gridPositionBuffer, let colors = gridColorBuffer, gridVertexCount > 0,
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
        if showsAxes, let positions = axesPositionBuffer, let colors = axesColorBuffer, axesVertexCount > 0,
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
        if showsAxes, let centers = labelCenterBuffer, let offsets = labelOffsetBuffer, let uvs = labelTexCoordBuffer,
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
        if let snap = scene.activeSnap, let positions = snapPositionBuffer, let normals = snapNormalBuffer,
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

        // Gizmo rendering for selected solid
        if includeGizmo,
           let selectedId = scene.selectedId,
           let mesh = scene.meshes[selectedId],
           !scene.hiddenSolidIds.contains(selectedId) {
            drawGizmo(
                ctx,
                mesh: mesh,
                viewMatrix: viewMatrix,
                projMatrix: projMatrix,
                activeGizmoHandle: scene.activeGizmoHandle,
                drawCalls: &drawCalls
            )
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

        let scene = MainActor.assumeIsolated { snapshotSceneState() }
        let interval = Self.signposter.beginInterval("Frame")
        defer { Self.signposter.endInterval("Frame", interval) }

        frameNumber += 1
        let slot = Int(frameNumber % UInt64(Self.framesInFlight))
        if frameNumber > UInt64(Self.framesInFlight) {
            // Waits for the GPU to release this slot's allocator and arena.
            _ = frameEvent.wait(untilSignaledValue: frameNumber - UInt64(Self.framesInFlight), timeoutMS: 1000)
        }
        let required = requiredArenaCapacity(meshCount: scene.meshes.count)
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
        let drawCalls = renderScene(
            EncodeContext(encoder: encoder, table: frameTable, arena: arena),
            scene: scene,
            aspect: aspect,
            includeGizmo: showsGizmo,
            viewportSize: view.drawableSize
        )
        encoder.endEncoding()
        commandBuffer.endCommandBuffer()

        commandQueue.waitForDrawable(drawable)
        commandQueue.commit([commandBuffer], options: makeCommitOptions())
        commandQueue.signalDrawable(drawable)
        commandQueue.signalEvent(frameEvent, value: frameNumber)
        drawable.present()

        lastDrawCalls = drawCalls
        RenderInstrumentation.shared.recordRender(drawCalls: drawCalls)
        onFrameRendered?()
    }

    // MARK: - Snapshot

    public func captureSnapshotPngBase64() async -> String? {
        await captureSnapshotPngBase64(view: nil, includeGizmo: false)
    }

    public func captureSnapshotPngBase64(view: ViewportPerspective?) async -> String? {
        await captureSnapshotPngBase64(view: view, includeGizmo: false)
    }

    public func captureSnapshotPngBase64(scene: SceneSnapshot) async -> String? {
        await captureSnapshotPngBase64(view: nil, includeGizmo: false, scene: scene)
    }

    public func captureSnapshotPngBase64(view: ViewportPerspective?, includeGizmo: Bool) async -> String? {
        await captureSnapshotPngBase64(view: view, includeGizmo: includeGizmo, scene: nil)
    }

    public func captureSnapshotPngBase64(
        view: ViewportPerspective?,
        includeGizmo: Bool,
        scene sceneOverride: SceneSnapshot?
    ) async -> String? {
        let scene = if let sceneOverride {
            sceneOverride
        } else {
            await MainActor.run { [self] in
                self.snapshotSceneState()
            }
        }
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
              let arena = UniformArena(device: device, capacity: requiredArenaCapacity(meshCount: scene.meshes.count)),
              let snapshotResidency = try? device.makeResidencySet(descriptor: MTLResidencySetDescriptor()),
              let commandBuffer = device.makeCommandBuffer() else { return nil }

        snapshotResidency.addAllocations([colorTexture, depthTexture, arena.buffer])
        for mesh in scene.meshes.values {
            snapshotResidency.addAllocations([mesh.positionBuffer, mesh.normalBuffer, mesh.indexBuffer])
            if let tf = mesh.triangleFaceIdBuffer { snapshotResidency.addAllocations([tf]) }
            if let es = mesh.edgeSegmentBuffer { snapshotResidency.addAllocations([es]) }
            if let vb = mesh.vertexBuffer { snapshotResidency.addAllocations([vb]) }
        }
        if let billboardTexture { snapshotResidency.addAllocations([billboardTexture]) }
        let statics: [MTLBuffer?] = [
            gridPositionBuffer, gridColorBuffer, axesPositionBuffer, axesColorBuffer,
            labelCenterBuffer, labelOffsetBuffer, labelTexCoordBuffer, labelColorBuffer,
            snapPositionBuffer, snapNormalBuffer, snapIndexBuffer
        ]
        snapshotResidency.addAllocations(statics.compactMap { $0 })
        if includeGizmo {
            for geom in gizmoGeometry.values {
                snapshotResidency.addAllocations([geom.positionBuffer, geom.defaultColorBuffer, geom.activeColorBuffer])
            }
        }
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

        var drawCalls = 0
        let cameraOverride = view.map { Camera.preset($0) }
        let encoded: Bool = snapshotLock.withLock {
            snapshotAllocator.reset()
            commandBuffer.beginCommandBuffer(allocator: snapshotAllocator)
            commandBuffer.useResidencySet(snapshotResidency)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                commandBuffer.endCommandBuffer()
                return false
            }
            drawCalls = renderScene(
                EncodeContext(encoder: encoder, table: snapshotTable, arena: arena),
                scene: scene,
                aspect: Float(width) / Float(height),
                cameraOverride: cameraOverride,
                includeGizmo: includeGizmo,
                viewportSize: CGSize(width: width, height: height)
            )
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

        lastDrawCalls = drawCalls

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

    // MARK: - Sub-element Picking (BL-SEL-02)

    /// Offscreen GPU sub-element picking at the specified pointer coordinate.
    /// Encodes face, edge, and vertex passes into a 1x1 scissored .rgba32Uint render target,
    /// and reads back the resulting sub-element identity.
    public func pickSubElement(
        at pointer: SIMD2<Float>,
        viewportSize: CGSize,
        filter: SelectionFilter = .all
    ) -> SubElementPickResult? {
        guard filter.allowsSubElements else { return nil }
        let width = Int(viewportSize.width)
        let height = Int(viewportSize.height)
        guard width > 0, height > 0 else { return nil }

        let px = Int(pointer.x)
        let py = Int(pointer.y)
        guard px >= 0, px < width, py >= 0, py < height else { return nil }

        let aspect = Float(width) / Float(height)
        let matrices = viewAndProjectionMatrices(aspect: aspect)
        let viewMatrix = matrices.view
        let projMatrix = matrices.projection

        let visibleEntries = meshes.filter { !hiddenSolidIds.contains($0.key) }
        guard !visibleEntries.isEmpty else { return nil }

        var solidTable: [SolidId] = []
        for (id, _) in visibleEntries {
            solidTable.append(id)
        }

        let requiredCapacity = UniformArena.capacity(
            forDraws: solidTable.count * 3 + 4,
            blockSize: MemoryLayout<PickUniforms>.stride
        )

        let result: SubElementPickResult? = pickLock.withLock { () -> SubElementPickResult? in
            if pickColorTexture?.width != width || pickColorTexture?.height != height {
                let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba32Uint,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                colorDesc.usage = [.renderTarget]
                colorDesc.storageMode = .shared
                pickColorTexture = device.makeTexture(descriptor: colorDesc)

                let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: Self.depthFormat,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                depthDesc.usage = [.renderTarget]
                depthDesc.storageMode = .private
                pickDepthTexture = device.makeTexture(descriptor: depthDesc)
            }

            guard let colorTexture = pickColorTexture,
                  let depthTexture = pickDepthTexture,
                  let arena = UniformArena(device: device, capacity: requiredCapacity),
                  let pickResidency = try? device.makeResidencySet(descriptor: MTLResidencySetDescriptor()),
                  let commandBuffer = device.makeCommandBuffer() else {
                return MadeCore.pickSubElement(
                    ray: screenPointToRay(screenPoint: pointer, viewportSize: viewportSize, viewMatrix: viewMatrix, projectionMatrix: projMatrix) ?? Ray3D(origin: .zero, direction: SIMD3(0, 0, -1)),
                    candidateMeshes: candidateMeshes(),
                    viewportSize: viewportSize,
                    viewMatrix: viewMatrix,
                    projectionMatrix: projMatrix,
                    filter: filter
                )
            }

            pickResidency.addAllocations([colorTexture, depthTexture, arena.buffer])
            for id in solidTable {
                if let mesh = meshes[id] {
                    pickResidency.addAllocations([mesh.positionBuffer, mesh.indexBuffer])
                    if let tf = mesh.triangleFaceIdBuffer { pickResidency.addAllocations([tf]) }
                    if let es = mesh.edgeSegmentBuffer { pickResidency.addAllocations([es]) }
                    if let vb = mesh.vertexBuffer { pickResidency.addAllocations([vb]) }
                }
            }
            pickResidency.commit()

            let pass = MTL4RenderPassDescriptor()
            pass.colorAttachments[0].texture = colorTexture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            pass.depthAttachment.texture = depthTexture
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1.0
            pass.depthAttachment.storeAction = .dontCare

            pickAllocator.reset()
            commandBuffer.beginCommandBuffer(allocator: pickAllocator)
            commandBuffer.useResidencySet(pickResidency)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                commandBuffer.endCommandBuffer()
                return nil
            }

            encoder.setArgumentTable(pickTable, stages: [.vertex, .fragment])
            encoder.setScissorRect(MTLScissorRect(x: px, y: py, width: 1, height: 1))

            // PASS 1: Faces
            if filter.allowsFaces {
                encoder.setRenderPipelineState(pickFacePipeline)
                encoder.setDepthStencilState(pickFaceDepthState)
                encoder.setFrontFacing(.counterClockwise)
                encoder.setCullMode(.back)

                for (idx, solidId) in solidTable.enumerated() {
                    guard let mesh = meshes[solidId], mesh.indexCount > 0 else { continue }
                    let solidIndex = UInt32(idx + 1)
                    let uniforms = PickUniforms(
                        modelMatrix: mesh.transform.matrix,
                        viewMatrix: viewMatrix,
                        projectionMatrix: projMatrix,
                        solidIndex: solidIndex,
                        subelementType: 1,
                        elementId: 0,
                        viewportWidth: Float(width),
                        viewportHeight: Float(height),
                        tolerancePx: 8.0,
                        depthBias: 0.005
                    )
                    guard let uAddr = arena.push(uniforms) else { continue }
                    pickTable.setAddress(mesh.positionBuffer.gpuAddress, index: 0)
                    pickTable.setAddress(uAddr, index: 1)
                    if let tf = mesh.triangleFaceIdBuffer {
                        pickTable.setAddress(tf.gpuAddress, index: 2)
                    }
                    encoder.drawIndexedPrimitives(
                        primitiveType: .triangle,
                        indexCount: mesh.indexCount,
                        indexType: .uint32,
                        indexBuffer: mesh.indexBuffer.gpuAddress,
                        indexBufferLength: mesh.indexBuffer.length
                    )
                }
            }

            // PASS 2: Edges
            if filter.allowsEdges {
                encoder.setRenderPipelineState(pickEdgePipeline)
                encoder.setDepthStencilState(pickEdgeDepthState)
                encoder.setCullMode(.none)

                for (idx, solidId) in solidTable.enumerated() {
                    guard let mesh = meshes[solidId], mesh.edgeSegmentCount > 0, let eb = mesh.edgeSegmentBuffer else { continue }
                    let solidIndex = UInt32(idx + 1)
                    let uniforms = PickUniforms(
                        modelMatrix: mesh.transform.matrix,
                        viewMatrix: viewMatrix,
                        projectionMatrix: projMatrix,
                        solidIndex: solidIndex,
                        subelementType: 2,
                        elementId: 0,
                        viewportWidth: Float(width),
                        viewportHeight: Float(height),
                        tolerancePx: 8.0,
                        depthBias: 0.005
                    )
                    guard let uAddr = arena.push(uniforms) else { continue }
                    pickTable.setAddress(uAddr, index: 1)
                    pickTable.setAddress(eb.gpuAddress, index: 3)
                    encoder.drawPrimitives(
                        primitiveType: .triangle,
                        vertexStart: 0,
                        vertexCount: 6,
                        instanceCount: mesh.edgeSegmentCount
                    )
                }
            }

            // PASS 3: Vertices
            if filter.allowsVertices {
                encoder.setRenderPipelineState(pickVertexPipeline)
                encoder.setDepthStencilState(pickVertexDepthState)
                encoder.setCullMode(.none)

                for (idx, solidId) in solidTable.enumerated() {
                    guard let mesh = meshes[solidId], mesh.vertexCount > 0, let vb = mesh.vertexBuffer else { continue }
                    let solidIndex = UInt32(idx + 1)
                    let uniforms = PickUniforms(
                        modelMatrix: mesh.transform.matrix,
                        viewMatrix: viewMatrix,
                        projectionMatrix: projMatrix,
                        solidIndex: solidIndex,
                        subelementType: 3,
                        elementId: 0,
                        viewportWidth: Float(width),
                        viewportHeight: Float(height),
                        tolerancePx: 8.0,
                        depthBias: 0.005
                    )
                    guard let uAddr = arena.push(uniforms) else { continue }
                    pickTable.setAddress(uAddr, index: 1)
                    pickTable.setAddress(vb.gpuAddress, index: 4)
                    encoder.drawPrimitives(
                        primitiveType: .triangle,
                        vertexStart: 0,
                        vertexCount: 6,
                        instanceCount: mesh.vertexCount
                    )
                }
            }

            encoder.endEncoding()
            commandBuffer.endCommandBuffer()

            let semaphore = DispatchSemaphore(value: 0)
            commandQueue.commit([commandBuffer], options: makeCommitOptions { _ in
                semaphore.signal()
            })
            semaphore.wait()

            var pixel = SIMD4<UInt32>(0, 0, 0, 0)
            colorTexture.getBytes(
                &pixel,
                bytesPerRow: width * MemoryLayout<SIMD4<UInt32>>.stride,
                from: MTLRegionMake2D(px, py, 1, 1),
                mipmapLevel: 0
            )

            guard pixel.x > 0 else {
                return nil
            }

            let solidTableIndex = Int(pixel.x) - 1
            guard solidTableIndex >= 0 && solidTableIndex < solidTable.count else { return nil }
            let solidId = solidTable[solidTableIndex]
            guard let mesh = meshes[solidId] else { return nil }

            let elementType: SubelementType
            switch pixel.y {
            case 1: elementType = .face
            case 2: elementType = .edge
            case 3: elementType = .vertex
            default: elementType = .face
            }

            let elementId = Int(pixel.z)

            let deterministicId: UUID?
            switch elementType {
            case .face:
                deterministicId = mesh.faceRanges.first(where: { $0.faceId == elementId })?.deterministicId
            case .edge:
                deterministicId = mesh.edgePolylines.first(where: { $0.edgeId == elementId })?.deterministicId
            case .vertex:
                deterministicId = mesh.vertexPoints.first(where: { $0.vertexId == elementId })?.deterministicId
            }

            let ray = screenPointToRay(
                screenPoint: pointer,
                viewportSize: viewportSize,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix
            )

            let hitPoint: SIMD3<Float>
            let distance: Float
            if let ray {
                if elementType == .vertex, let vp = mesh.vertexPoints.first(where: { $0.vertexId == elementId }) {
                    let w4 = mesh.transform.matrix * SIMD4<Float>(vp.position, 1.0)
                    let p = SIMD3<Float>(w4.x, w4.y, w4.z)
                    hitPoint = p
                    distance = simd_dot(p - ray.origin, ray.direction)
                } else {
                    hitPoint = ray.origin + ray.direction * 10.0
                    distance = 10.0
                }
            } else {
                hitPoint = .zero
                distance = 0.0
            }

            return SubElementPickResult(
                solidId: solidId,
                elementType: elementType,
                elementId: elementId,
                deterministicId: deterministicId,
                distance: distance,
                hitPoint: hitPoint
            )
        }
        return result
    }
}
