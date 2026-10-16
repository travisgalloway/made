import Testing
import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
@testable import MadeCore

@Suite(.serialized) struct MetalRendererEdgeTests {
    private let width = 800
    private let height = 600

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testBoxRendersAntialiasedBRepEdges() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.showsEdges = true

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.5, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        // showsEdges = true with 1 solid with 12 edge segments must issue 2 draw calls (solid + edges)
        let snapshotWithEdges = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 2)

        let pixelsWithEdges = try decodeRGBA(snapshotWithEdges)

        // When showsEdges = false, exactly 1 draw call is issued
        renderer.showsEdges = false
        let snapshotWithoutEdges = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1)

        let pixelsWithoutEdges = try decodeRGBA(snapshotWithoutEdges)

        // Verify that B-rep edge rendering creates antialiased boundary edge pixels
        var edgePixelCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let diffR = abs(Int(pixelsWithEdges[i]) - Int(pixelsWithoutEdges[i]))
                let diffG = abs(Int(pixelsWithEdges[i + 1]) - Int(pixelsWithoutEdges[i + 1]))
                let diffB = abs(Int(pixelsWithEdges[i + 2]) - Int(pixelsWithoutEdges[i + 2]))
                if diffR > 10 || diffG > 10 || diffB > 10 {
                    edgePixelCount += 1
                }
            }
        }
        #expect(edgePixelCount > 100, "B-rep edge pass must render antialiased edge pixels along box boundaries (found \(edgePixelCount))")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testCylinderRendersCircularBRepEdgesAndSilhouettes() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.showsEdges = true

        let payload = NativeGeometryGenerator.generateCylinder(radius: 15, height: 30)
        let cylId = SolidId("cyl")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: cylId, color: SIMD4<Float>(0.3, 0.6, 0.9, 1.0)))
        renderer.meshes[cylId] = mesh

        let snapshotWithEdges = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 2, "Cylinder must issue 2 draw calls (solid + circular B-rep edges)")

        renderer.showsEdges = false
        let snapshotWithoutEdges = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1, "Cylinder without showsEdges issues 1 draw call")

        let pixelsWithEdges = try decodeRGBA(snapshotWithEdges)
        let pixelsWithoutEdges = try decodeRGBA(snapshotWithoutEdges)

        // 1. Verify B-rep circular edge pass rendered top/bottom rim edges
        var rimEdgePixelCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let diffR = abs(Int(pixelsWithEdges[i]) - Int(pixelsWithoutEdges[i]))
                let diffG = abs(Int(pixelsWithEdges[i + 1]) - Int(pixelsWithoutEdges[i + 1]))
                let diffB = abs(Int(pixelsWithEdges[i + 2]) - Int(pixelsWithoutEdges[i + 2]))
                if diffR > 10 || diffG > 10 || diffB > 10 {
                    rimEdgePixelCount += 1
                }
            }
        }
        #expect(rimEdgePixelCount > 50, "Cylinder circular B-rep edges must render pixels on top and bottom caps")

        // 2. Verify dynamic silhouette contour on curved surfaces (present in fragment shader)
        var darkContourPixels = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let g = pixelsWithEdges[i + 1]
                let b = pixelsWithEdges[i + 2]
                // Silhouette contour blends into edge color (~97, 97, 105 in sRGB)
                // Illuminated cylinder side has b > 160; silhouette contour reduces b < 140 while on solid
                if b > 90 && b < 140 && g < 130 {
                    darkContourPixels += 1
                }
            }
        }
        #expect(darkContourPixels > 50, "Dynamic silhouette contour on curved cylinder side must darken profile edges")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testCameraOrbitDoesNotTriggerRetessellation() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.showsEdges = true

        let payload = NativeGeometryGenerator.generateCylinder(radius: 15, height: 30)
        let cylId = SolidId("cyl")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: cylId, color: SIMD4<Float>(0.4, 0.7, 0.9, 1.0)))
        renderer.meshes[cylId] = mesh

        let originalBufferAddress = mesh.edgeSegmentBuffer?.gpuAddress
        #expect(originalBufferAddress != nil)

        // Orbit camera through multiple angles: silhouettes must update on GPU without CPU re-tessellation
        let step = Float.pi / 4.0
        for _ in 0..<8 {
            renderer.camera = Camera.orbit(camera: renderer.camera, deltaAzimuth: step, deltaElevation: 0)
            let snapshot = try #require(await renderer.captureSnapshotPngBase64())
            #expect(!snapshot.isEmpty)

            // Invariant 1: zero CPU or kernel re-tessellation during camera moves.
            // Edge segment buffer allocation address must remain strictly identical.
            #expect(renderer.meshes[cylId]?.edgeSegmentBuffer?.gpuAddress == originalBufferAddress)
        }
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testMeshWithZeroEdgesIssuesNoEdgeDrawCalls() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.showsEdges = true

        // Euclid payload has empty edgePolylines (edgeSegmentCount == 0)
        let payload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 30, depth: 30, height: 30))
        let mesh = try #require(renderer.createMesh(from: payload, solidId: SolidId("euclidBox"), color: SIMD4<Float>(0.5, 0.5, 0.5, 1.0)))
        renderer.meshes[SolidId("euclidBox")] = mesh

        #expect(mesh.edgeSegmentCount == 0)
        #expect(mesh.edgeSegmentBuffer == nil)

        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1, "Mesh with 0 edge segments must issue 0 edge draw calls (1 draw call for solid)")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testHiddenSolidIssuesNoEdgeDrawCalls() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.showsEdges = true

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        // Hide solid
        renderer.hiddenSolidIds.insert(boxId)

        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 0, "Hidden solid must issue 0 draw calls total (suppressing solid and edges)")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testShowsEdgesToggleSuppressesEdgeDrawCalls() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        // Default showsEdges = true -> 2 draw calls
        renderer.showsEdges = true
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 2)

        // Toggle showsEdges = false -> 1 draw call
        renderer.showsEdges = false
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1)

        // Toggle showsEdges = true -> 2 draw calls
        renderer.showsEdges = true
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 2)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testOrthographicProjectionEdgeRendering() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.showsEdges = true
        renderer.projectionMode = .orthographic

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.3, 0.7, 0.4, 1.0)))
        renderer.meshes[boxId] = mesh

        let snapshotWithEdges = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 2, "Orthographic mode must render 2 draw calls (solid + edges)")

        renderer.showsEdges = false
        let snapshotWithoutEdges = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1)

        let pixelsWithEdges = try decodeRGBA(snapshotWithEdges)
        let pixelsWithoutEdges = try decodeRGBA(snapshotWithoutEdges)

        var edgePixelCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let diffR = abs(Int(pixelsWithEdges[i]) - Int(pixelsWithoutEdges[i]))
                let diffG = abs(Int(pixelsWithEdges[i + 1]) - Int(pixelsWithoutEdges[i + 1]))
                let diffB = abs(Int(pixelsWithEdges[i + 2]) - Int(pixelsWithoutEdges[i + 2]))
                if diffR > 10 || diffG > 10 || diffB > 10 {
                    edgePixelCount += 1
                }
            }
        }
        #expect(edgePixelCount > 100, "Orthographic projection must render antialiased edge pixels")
    }

    // MARK: - Helpers

    private func viewProjection(_ renderer: MetalRenderer) -> simd_float4x4 {
        let matrices = renderer.viewAndProjectionMatrices(aspect: Float(width) / Float(height))
        return matrices.projection * matrices.view
    }

    private func project(_ point: SIMD3<Float>, renderer: MetalRenderer) -> CGPoint {
        let clip = viewProjection(renderer) * SIMD4<Float>(point, 1)
        let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
        return CGPoint(x: Double((ndc.x + 1) / 2) * Double(width), y: Double((1 - ndc.y) / 2) * Double(height))
    }

    private func decodeRGBA(_ base64: String) throws -> [UInt8] {
        let data = try #require(Data(base64Encoded: base64))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}
