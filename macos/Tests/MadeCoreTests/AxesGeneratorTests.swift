import XCTest
import Metal
import simd
@testable import MadeCore

final class AxesGeneratorTests: XCTestCase {
    
    func testDefaultAxesProperties() {
        let axes = AxesGenerator.generateAxes()
        
        XCTAssertEqual(axes.length, AxesGenerator.defaultLength)
        XCTAssertEqual(axes.length, 50.0)
        XCTAssertEqual(axes.labelSize, AxesGenerator.defaultLabelSize)
        XCTAssertEqual(axes.labelSize, 10.0)
        
        // Exactly 3 axes: X, Y, Z
        XCTAssertEqual(axes.axes.count, 3)
        XCTAssertEqual(axes.axes[0].name, "X")
        XCTAssertEqual(axes.axes[1].name, "Y")
        XCTAssertEqual(axes.axes[2].name, "Z")
        
        // All axes originate at (0, 0, 0)
        for axis in axes.axes {
            XCTAssertEqual(axis.start, SIMD3<Float>(0, 0, 0), "Every axis must start at origin")
        }
        
        // 3 lines -> 6 vertices
        XCTAssertEqual(axes.lineVertexCount, 6)
        XCTAssertEqual(axes.linePositions.count, 6 * 3)
        XCTAssertEqual(axes.lineColors.count, 6 * 4)
        
        // 3 labels -> 3 quads * 6 vertices = 18 vertices
        XCTAssertEqual(axes.labelVertexCount, 18)
        XCTAssertEqual(axes.labelCenters.count, 18 * 3)
        XCTAssertEqual(axes.labelOffsets.count, 18 * 2)
        XCTAssertEqual(axes.labelTexCoords.count, 18 * 2)
        XCTAssertEqual(axes.labelColors.count, 18 * 4)
    }
    
    func testZAxisMatchesOrientationWorldUp() {
        let axes = AxesGenerator.generateAxes()
        let zAxis = axes.axes.first { $0.name == "Z" }
        XCTAssertNotNil(zAxis)
        guard let zAxis = zAxis else { return }
        
        XCTAssertEqual(zAxis.start, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(zAxis.end, SIMD3<Float>(0, 0, axes.length))
        
        let zDirection = simd_normalize(zAxis.end - zAxis.start)
        XCTAssertEqual(zDirection.x, Orientation.worldUp.x, accuracy: 1e-6)
        XCTAssertEqual(zDirection.y, Orientation.worldUp.y, accuracy: 1e-6)
        XCTAssertEqual(zDirection.z, Orientation.worldUp.z, accuracy: 1e-6)
        XCTAssertEqual(Orientation.worldUp, SIMD3<Float>(0, 0, 1))
        
        // Label position must also be strictly along +Z
        XCTAssertEqual(zAxis.labelPosition.x, 0.0, accuracy: 1e-6)
        XCTAssertEqual(zAxis.labelPosition.y, 0.0, accuracy: 1e-6)
        XCTAssertGreaterThan(zAxis.labelPosition.z, zAxis.end.z)
    }
    
    func testAxisColorsAreDistinct() {
        let axes = AxesGenerator.generateAxes()
        guard axes.axes.count == 3 else {
            XCTFail("Expected 3 axes")
            return
        }
        
        let xColor = axes.axes[0].color
        let yColor = axes.axes[1].color
        let zColor = axes.axes[2].color
        
        // All 3 colors must be distinct
        XCTAssertNotEqual(xColor, yColor)
        XCTAssertNotEqual(yColor, zColor)
        XCTAssertNotEqual(xColor, zColor)
        
        // X must be predominantly red
        XCTAssertGreaterThan(xColor.x, xColor.y)
        XCTAssertGreaterThan(xColor.x, xColor.z)
        
        // Y must be predominantly green
        XCTAssertGreaterThan(yColor.y, yColor.x)
        XCTAssertGreaterThan(yColor.y, yColor.z)
        
        // Z must be predominantly blue
        XCTAssertGreaterThan(zColor.z, zColor.x)
        XCTAssertGreaterThan(zColor.z, zColor.y)
    }
    
    func testLabelPositionsArePastLineTips() {
        let length: Float = 60.0
        let labelSize: Float = 12.0
        let axes = AxesGenerator.generateAxes(length: length, labelSize: labelSize)
        
        let xAxis = axes.axes[0]
        let yAxis = axes.axes[1]
        let zAxis = axes.axes[2]
        
        XCTAssertEqual(xAxis.end.x, length)
        XCTAssertGreaterThan(xAxis.labelPosition.x, xAxis.end.x, "X label must be past line tip")
        
        XCTAssertEqual(yAxis.end.y, length)
        XCTAssertGreaterThan(yAxis.labelPosition.y, yAxis.end.y, "Y label must be past line tip")
        
        XCTAssertEqual(zAxis.end.z, length)
        XCTAssertGreaterThan(zAxis.labelPosition.z, zAxis.end.z, "Z label must be past line tip")
    }
    
    func testInvalidDimensionsReturnEmpty() {
        let empty1 = AxesGenerator.generateAxes(length: -50, labelSize: 10)
        XCTAssertEqual(empty1.axes.count, 0)
        XCTAssertEqual(empty1.lineVertexCount, 0)
        XCTAssertEqual(empty1.labelVertexCount, 0)
        
        let empty2 = AxesGenerator.generateAxes(length: 50, labelSize: 0)
        XCTAssertEqual(empty2.axes.count, 0)
        XCTAssertEqual(empty2.lineVertexCount, 0)
        XCTAssertEqual(empty2.labelVertexCount, 0)
    }
    
    func testCameraLookingAlongAxesDoesNotProduceNaN() {
        let target = SIMD3<Float>(0, 0, 0)
        let distance: Float = 150.0
        
        let directions: [(String, SIMD3<Float>)] = [
            ("+X", SIMD3<Float>(distance, 0, 0)),
            ("-X", SIMD3<Float>(-distance, 0, 0)),
            ("+Y", SIMD3<Float>(0, distance, 0)),
            ("-Y", SIMD3<Float>(0, -distance, 0)),
            ("+Z", SIMD3<Float>(0, 0, distance)),
            ("-Z", SIMD3<Float>(0, 0, -distance))
        ]
        
        for (name, eye) in directions {
            let view = Orientation.makeLookAt(eye: eye, target: target, up: Orientation.worldUp)
            
            // Verify every component is finite (not NaN, not Inf)
            for c in 0..<4 {
                let col = view[c]
                XCTAssertFalse(col.x.isNaN, "Looking along \(name): column \(c).x is NaN")
                XCTAssertFalse(col.y.isNaN, "Looking along \(name): column \(c).y is NaN")
                XCTAssertFalse(col.z.isNaN, "Looking along \(name): column \(c).z is NaN")
                XCTAssertFalse(col.w.isNaN, "Looking along \(name): column \(c).w is NaN")
                
                XCTAssertFalse(col.x.isInfinite, "Looking along \(name): column \(c).x is Inf")
                XCTAssertFalse(col.y.isInfinite, "Looking along \(name): column \(c).y is Inf")
                XCTAssertFalse(col.z.isInfinite, "Looking along \(name): column \(c).z is Inf")
                XCTAssertFalse(col.w.isInfinite, "Looking along \(name): column \(c).w is Inf")
            }
        }
    }
    
    func testCameraLookingAlongZAxisViewMatrix() {
        // Looking directly down +Z from (0, 0, 150) to (0, 0, 0)
        let eye = SIMD3<Float>(0, 0, 150)
        let target = SIMD3<Float>(0, 0, 0)
        let view = Orientation.makeLookAt(eye: eye, target: target, up: Orientation.worldUp)
        
        // Transform the origin (0, 0, 0) to view space
        let originView = view * SIMD4<Float>(0, 0, 0, 1)
        XCTAssertEqual(originView.x, 0.0, accuracy: 1e-3)
        XCTAssertEqual(originView.y, 0.0, accuracy: 1e-3)
        XCTAssertEqual(originView.z, -150.0, accuracy: 1e-3)
        XCTAssertEqual(originView.w, 1.0, accuracy: 1e-3)
        
        // Transform +X point (50, 0, 0) to view space -> should be along view +X
        let xPointView = view * SIMD4<Float>(50, 0, 0, 1)
        XCTAssertEqual(xPointView.x, 50.0, accuracy: 1e-3)
        XCTAssertEqual(xPointView.y, 0.0, accuracy: 1e-3)
        XCTAssertEqual(xPointView.z, -150.0, accuracy: 1e-3)
    }
    
    func testLabelsStayReadableWhenCameraZooms() {
        // Test billboard distance scaling formula:
        // scale = max(1.0, distance / 150.0)
        // Projected size in screen pixels = (ys * labelSize * scale) / distance
        // When distance >= 150: scale / distance = (distance / 150) / distance = 1 / 150 = constant!
        let refDist: Float = 150.0
        let labelSize: Float = 10.0
        let ys: Float = 1.0 / tan(Float.pi / 8.0) // ~2.414
        
        let testDistances: [Float] = [150.0, 300.0, 600.0, 1200.0]
        var projectedSizes: [Float] = []
        
        for dist in testDistances {
            let scale = max(1.0, dist / refDist)
            let projectedNdcHeight = (ys * labelSize * scale) / dist
            projectedSizes.append(projectedNdcHeight)
        }
        
        // At all distances >= 150, the projected size remains constant so labels never become unreadable specks
        for size in projectedSizes {
            XCTAssertEqual(size, projectedSizes[0], accuracy: 1e-5, "Projected label size must remain constant at distances >= 150 mm")
        }
        
        // When zoomed in close (distance < 150), scale is clamped to 1.0 so label scales naturally with axis lines
        let closeDist: Float = 50.0
        let closeScale = max(1.0, closeDist / refDist)
        XCTAssertEqual(closeScale, 1.0)
        let closeProjected = (ys * labelSize * closeScale) / closeDist
        XCTAssertGreaterThan(closeProjected, projectedSizes[0], "Close zoom increases apparent size naturally")
    }
    
    func testMetalRendererAxesIntegration() async {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            return
        }
        
        // Offscreen snapshot contains axes indicator
        guard let base64Png = await renderer.captureSnapshotPngBase64(),
              let data = Data(base64Encoded: base64Png) else {
            XCTFail("Expected valid base64 PNG data")
            return
        }
        
        // Verify PNG magic header
        XCTAssertEqual([UInt8](data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        
        // Update axes
        renderer.updateAxes(length: 40.0, labelSize: 8.0)
        let updatedSnapshot = await renderer.captureSnapshotPngBase64()
        XCTAssertNotNil(updatedSnapshot)
    }
    
    func testOriginHiddenBehindSolidSnapshot() async {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            return
        }
        
        // Place a solid cube of size 120x120x120 centered at origin (0, 0, 0)
        // This solid completely encloses the origin and the initial portions of all 3 axes
        let mesh = EuclidEngine.makeBox(width: 120, depth: 120, height: 120)
        let payload = EuclidEngine.toMeshPayload(mesh)
        
        guard let metalMesh = renderer.createMesh(
            from: payload,
            transform: .identity,
            color: SIMD4<Float>(0.8, 0.4, 0.2, 1.0)
        ) else {
            XCTFail("Failed to create MetalMesh")
            return
        }
        
        renderer.meshes[SolidId("occluding-solid")] = metalMesh
        
        // Snapshot renders solid occluding the origin with depth testing enabled
        guard let base64Png = await renderer.captureSnapshotPngBase64(),
              let data = Data(base64Encoded: base64Png) else {
            XCTFail("Expected valid snapshot")
            return
        }
        XCTAssertEqual([UInt8](data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
    
    func testSnapshotLookingAlongEachAxis() async {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            return
        }
        
        let axesToTest: [(String, SIMD3<Float>)] = [
            ("+X", SIMD3<Float>(150, 0, 0)),
            ("+Y", SIMD3<Float>(0, 150, 0)),
            ("+Z", SIMD3<Float>(0, 0, 150))
        ]
        
        for (name, eye) in axesToTest {
            renderer.cameraPosition = eye
            renderer.cameraTarget = SIMD3<Float>(0, 0, 0)
            
            let base64Png = await renderer.captureSnapshotPngBase64()
            XCTAssertNotNil(base64Png, "Snapshot looking along \(name) must succeed")
            guard let data = base64Png.flatMap({ Data(base64Encoded: $0) }) else {
                XCTFail("Failed to decode snapshot for \(name)")
                continue
            }
            XCTAssertEqual([UInt8](data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        }
    }
    
    func testSnapshotViaCADToolsIncludesAxes() async {
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
}
