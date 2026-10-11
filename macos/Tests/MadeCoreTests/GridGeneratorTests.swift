import XCTest
import Metal
import simd
@testable import MadeCore

final class GridGeneratorTests: XCTestCase {
    
    func testDefaultGridProperties() {
        let grid = GridGenerator.generateGrid()
        
        // Spacing must match defaultGridSpacing (10.0 mm)
        XCTAssertEqual(grid.spacing, defaultGridSpacing)
        XCTAssertEqual(grid.spacing, 10.0)
        XCTAssertEqual(grid.size, 300.0)
        
        // For size 300 and spacing 10:
        // halfSize = 150, steps = 15
        // lines along Y = -15...15 (31 lines)
        // lines along X = -15...15 (31 lines)
        // total lines = 62, total vertices = 124, total positions = 372 floats
        XCTAssertEqual(grid.lineCount, 62)
        XCTAssertEqual(grid.vertexCount, 124)
        XCTAssertEqual(grid.positions.count, 124 * 3)
        XCTAssertEqual(grid.colors.count, 124 * 4)
    }
    
    func testAllVerticesLieOnGroundPlaneZZero() {
        let grid = GridGenerator.generateGrid()
        
        for line in grid.lines {
            XCTAssertEqual(line.start.z, 0.0, accuracy: 1e-6, "Line start Z must be strictly 0.0")
            XCTAssertEqual(line.end.z, 0.0, accuracy: 1e-6, "Line end Z must be strictly 0.0")
        }
        
        // Also verify the flat positions buffer
        for i in stride(from: 2, to: grid.positions.count, by: 3) {
            XCTAssertEqual(grid.positions[i], 0.0, accuracy: 1e-6, "Vertex Z must be strictly 0.0")
        }
    }
    
    func testGridLinesAreParallelToAxesAndStepBySpacing() {
        let grid = GridGenerator.generateGrid(size: 100.0, spacing: 10.0)
        // halfSize = 50, steps = 5 -> 11 lines along Y, 11 lines along X
        XCTAssertEqual(grid.lineCount, 22)
        
        let yParallelLines = grid.lines.filter { $0.start.x == $0.end.x }
        let xParallelLines = grid.lines.filter { $0.start.y == $0.end.y }
        
        XCTAssertEqual(yParallelLines.count, 11)
        XCTAssertEqual(xParallelLines.count, 11)
        
        // Check sorting and step along X
        let xCoords = yParallelLines.map { $0.start.x }.sorted()
        for i in 0..<(xCoords.count - 1) {
            XCTAssertEqual(xCoords[i + 1] - xCoords[i], 10.0, accuracy: 1e-5)
        }
        
        // Check extent
        XCTAssertEqual(xCoords.first!, -50.0, accuracy: 1e-5)
        XCTAssertEqual(xCoords.last!, 50.0, accuracy: 1e-5)
    }
    
    func testCenterAxesAreMajor() {
        let grid = GridGenerator.generateGrid(size: 60.0, spacing: 10.0)
        let majorLines = grid.lines.filter { $0.isMajor }
        
        // Exactly 2 major lines: X = 0 and Y = 0
        XCTAssertEqual(majorLines.count, 2)
        
        let centerLineY = majorLines.first { $0.start.x == 0.0 && $0.end.x == 0.0 }
        let centerLineX = majorLines.first { $0.start.y == 0.0 && $0.end.y == 0.0 }
        
        XCTAssertNotNil(centerLineY, "Must include X = 0 line")
        XCTAssertNotNil(centerLineX, "Must include Y = 0 line")
    }
    
    func testSnappedPointsLieOnGridLines() {
        let grid = GridGenerator.generateGrid(size: 300.0, spacing: 10.0)
        let samplePoints: [SIMD3<Float>] = [
            SIMD3<Float>(23.4, -48.1, 15.0),
            SIMD3<Float>(-102.7, 77.9, -5.0),
            SIMD3<Float>(0.0, 0.0, 0.0)
        ]
        
        let gridXValues = Set(grid.lines.filter { $0.start.x == $0.end.x }.map { Int($0.start.x.rounded()) })
        let gridYValues = Set(grid.lines.filter { $0.start.y == $0.end.y }.map { Int($0.start.y.rounded()) })
        
        for pt in samplePoints {
            let snapped = snapToGrid(pt, spacing: 10.0)
            XCTAssertTrue(gridXValues.contains(Int(snapped.x.rounded())), "Snapped X (\(snapped.x)) must align with a grid line")
            XCTAssertTrue(gridYValues.contains(Int(snapped.y.rounded())), "Snapped Y (\(snapped.y)) must align with a grid line")
        }
    }
    
    func testInvalidDimensionsReturnEmpty() {
        let empty1 = GridGenerator.generateGrid(size: -100, spacing: 10)
        XCTAssertEqual(empty1.lineCount, 0)
        
        let empty2 = GridGenerator.generateGrid(size: 100, spacing: 0)
        XCTAssertEqual(empty2.lineCount, 0)
    }
    
    func testMetalRendererGridIntegration() async {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            return
        }
        
        // Snapshot with empty scene renders the ground grid on dark background
        guard let base64Png = await renderer.captureSnapshotPngBase64(),
              let data = Data(base64Encoded: base64Png) else {
            XCTFail("Expected valid base64 PNG data from captureSnapshotPngBase64")
            return
        }
        
        // Verify PNG magic header: 89 50 4E 47 0D 0A 1A 0A
        let pngHeader = [UInt8](data.prefix(8))
        XCTAssertEqual(pngHeader, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        
        // Update grid spacing
        renderer.updateGrid(size: 200, spacing: 20)
        let updatedSnapshot = await renderer.captureSnapshotPngBase64()
        XCTAssertNotNil(updatedSnapshot)
    }
    
    func testCameraBelowPlaneSnapshot() async {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            return
        }
        
        // Place camera beneath the ground plane looking up at the origin
        renderer.cameraPosition = SIMD3<Float>(100, -100, -150)
        renderer.cameraTarget = SIMD3<Float>(0, 0, 0)
        
        let base64Png = await renderer.captureSnapshotPngBase64()
        XCTAssertNotNil(base64Png)
        guard let data = Data(base64Encoded: base64Png!) else {
            XCTFail("Expected valid base64 data")
            return
        }
        XCTAssertEqual([UInt8](data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
    
    func testSolidsRestingOnGroundPlaneSnapshot() async {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            return
        }
        
        // Generate a box of width 40, depth 40, height 20
        // EuclidEngine generates a box centered at (0, 0, 0) with Z from -10 to +10.
        // Translating by +10 in Z puts the bottom face exactly on Z = 0.
        let mesh = EuclidEngine.makeBox(width: 40, depth: 40, height: 20)
        let payload = EuclidEngine.toMeshPayload(mesh)
        
        var restingTransform = Transform.identity
        restingTransform.position = SIMD3<Float>(0, 0, 10)
        
        guard let metalMesh = renderer.createMesh(
            from: payload,
            transform: restingTransform,
            color: SIMD4<Float>(0.35, 0.65, 0.95, 1.0)
        ) else {
            XCTFail("Failed to create MetalMesh")
            return
        }
        
        renderer.meshes[SolidId("box-resting")] = metalMesh
        
        let base64Png = await renderer.captureSnapshotPngBase64()
        XCTAssertNotNil(base64Png)
        guard let data = Data(base64Encoded: base64Png!) else {
            XCTFail("Expected valid base64 data")
            return
        }
        XCTAssertEqual([UInt8](data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
    
    func testSnapshotViaCADTools() async {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            return
        }
        
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: renderer)
        
        let result = await registry.callTool(name: "cad_capture_snapshot", arguments: [:])
        XCTAssertEqual(result.isError, false)
        
        guard let content = result.content.first,
              content.type == "image",
              let base64 = content.data else {
            XCTFail("Expected image content")
            return
        }
        XCTAssertEqual(content.mimeType, "image/png")
        guard let data = Data(base64Encoded: base64) else {
            XCTFail("Expected valid base64 PNG")
            return
        }
        XCTAssertEqual([UInt8](data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
    
    func testDefaultSceneWithSolidsAndGridSnapshot() async {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            return
        }
        
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let boxRes = await kernel.request(.makeBox(jobId: JobId("box-job"), solidId: boxSolidId, params: BoxParams(width: 40, depth: 30, height: 20)))
        guard case .success(_, let boxPayload) = boxRes else {
            XCTFail("Failed to generate box payload")
            return
        }
        
        let cylRes = await kernel.request(.makeCylinder(jobId: JobId("cyl-job"), solidId: cylinderSolidId, params: CylinderParams(radius: 15, height: 40)))
        guard case .success(_, let cylPayload) = cylRes else {
            XCTFail("Failed to generate cylinder payload")
            return
        }
        
        var boxTransform = Transform.identity
        boxTransform.position = SIMD3<Float>(-25, 0, 0)
        guard let boxMesh = renderer.createMesh(from: boxPayload, transform: boxTransform, color: SIMD4<Float>(0.35, 0.65, 0.95, 1.0)) else {
            XCTFail("Failed to create box mesh")
            return
        }
        
        var cylTransform = Transform.identity
        cylTransform.position = SIMD3<Float>(25, 0, 0)
        guard let cylMesh = renderer.createMesh(from: cylPayload, transform: cylTransform, color: SIMD4<Float>(0.95, 0.55, 0.35, 1.0)) else {
            XCTFail("Failed to create cylinder mesh")
            return
        }
        
        renderer.meshes[boxSolidId] = boxMesh
        renderer.meshes[cylinderSolidId] = cylMesh
        XCTAssertEqual(renderer.meshes.count, 2)
        
        let base64Png = await renderer.captureSnapshotPngBase64()
        XCTAssertNotNil(base64Png)
        guard let data = Data(base64Encoded: base64Png!) else {
            XCTFail("Expected valid base64 data")
            return
        }
        XCTAssertEqual([UInt8](data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
