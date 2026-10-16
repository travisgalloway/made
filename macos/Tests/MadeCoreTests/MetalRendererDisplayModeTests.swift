import Testing
import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
@testable import MadeCore

@Suite(.serialized) struct MetalRendererDisplayModeTests {
    private let width = 800
    private let height = 600

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testShadedWithEdgesDrawCallsAndPixels() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.showsEdges = true
        renderer.displayMode = .shadedWithEdges

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.5, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        // .shadedWithEdges: 1 solid pass + 1 edge pass = 2 draw calls
        let snapshotWithEdges = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 2, "Shaded with edges must issue exactly 2 draw calls (solid + edges)")

        // Compare against .shaded mode (1 draw call)
        renderer.displayMode = .shaded
        let snapshotShaded = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1, "Shaded mode must issue 1 draw call")

        let pixelsWithEdges = try decodeRGBA(snapshotWithEdges)
        let pixelsShaded = try decodeRGBA(snapshotShaded)

        var edgePixelCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let diffR = abs(Int(pixelsWithEdges[i]) - Int(pixelsShaded[i]))
                let diffG = abs(Int(pixelsWithEdges[i + 1]) - Int(pixelsShaded[i + 1]))
                let diffB = abs(Int(pixelsWithEdges[i + 2]) - Int(pixelsShaded[i + 2]))
                if diffR > 10 || diffG > 10 || diffB > 10 {
                    edgePixelCount += 1
                }
            }
        }
        #expect(edgePixelCount > 100, "Shaded with edges must render distinct boundary edge pixels compared to shaded mode")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testShadedModeSuppressesEdgePass() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.showsEdges = true
        renderer.displayMode = .shaded

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.5, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        // In shaded mode, edge pass is suppressed regardless of showsEdges = true
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1, "Shaded mode must issue exactly 1 draw call, suppressing the edge pass")

        renderer.showsEdges = false
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1, "Shaded mode with showsEdges=false remains exactly 1 draw call")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testWireframeModeSuppressesSolidPass() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.displayMode = .wireframe

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.5, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        // .wireframe: 0 solid pass + 1 edge pass = 1 draw call
        let snapshotWireframe = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1, "Wireframe mode must issue exactly 1 draw call for edges, with solid pass suppressed")

        let pixels = try decodeRGBA(snapshotWireframe)

        // Verify high-contrast light edge pixels rendered against dark clear color (0.12, 0.12, 0.14)
        var lightEdgePixels = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = pixels[i]
                let g = pixels[i + 1]
                let b = pixels[i + 2]
                if r > 180 && g > 180 && b > 180 {
                    lightEdgePixels += 1
                }
            }
        }
        #expect(lightEdgePixels > 100, "Wireframe must render light high-contrast boundary edge ribbons (found \(lightEdgePixels))")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testHiddenLineRemovedPassOccludesBackEdges() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.5, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        // HLR: 1 unshaded face pass (clear color + write depth) + 1 visible edge pass = 2 draw calls
        renderer.displayMode = .hiddenLineRemoved
        let snapshotHLR = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 2, "HLR mode must issue exactly 2 draw calls")

        // Wireframe: all edges visible (compare: wireframe draws back edges, HLR occludes them)
        renderer.displayMode = .wireframe
        let snapshotWireframe = try #require(await renderer.captureSnapshotPngBase64())

        let pixelsHLR = try decodeRGBA(snapshotHLR)
        let pixelsWireframe = try decodeRGBA(snapshotWireframe)

        var hlrEdgePixels = 0
        var wireframeEdgePixels = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if pixelsHLR[i] > 180 && pixelsHLR[i + 1] > 180 && pixelsHLR[i + 2] > 180 {
                    hlrEdgePixels += 1
                }
                if pixelsWireframe[i] > 180 && pixelsWireframe[i + 1] > 180 && pixelsWireframe[i + 2] > 180 {
                    wireframeEdgePixels += 1
                }
            }
        }

        #expect(hlrEdgePixels > 50, "HLR must render visible front edges")
        #expect(wireframeEdgePixels > hlrEdgePixels, "Wireframe must contain back edges occluded in HLR (wireframe: \(wireframeEdgePixels), HLR: \(hlrEdgePixels))")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testHiddenLinesVisibleRendersOccludedAndVisibleEdges() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.5, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        // HLV: 1 unshaded face pass + 1 occluded edge pass + 1 visible edge pass = 3 draw calls
        renderer.displayMode = .hiddenLinesVisible
        let snapshotHLV = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 3, "HLV mode must issue exactly 3 draw calls")

        renderer.displayMode = .hiddenLineRemoved
        let snapshotHLR = try #require(await renderer.captureSnapshotPngBase64())

        let pixelsHLV = try decodeRGBA(snapshotHLV)
        let pixelsHLR = try decodeRGBA(snapshotHLR)

        // HLV contains both visible edges and occluded edges (which differ from HLR's occluded background)
        var occludedEdgePixels = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let diffR = abs(Int(pixelsHLV[i]) - Int(pixelsHLR[i]))
                let diffG = abs(Int(pixelsHLV[i + 1]) - Int(pixelsHLR[i + 1]))
                let diffB = abs(Int(pixelsHLV[i + 2]) - Int(pixelsHLR[i + 2]))
                if diffR > 5 || diffG > 5 || diffB > 5 {
                    occludedEdgePixels += 1
                }
            }
        }
        #expect(occludedEdgePixels > 50, "HLV must render occluded edges that are hidden in HLR (found \(occludedEdgePixels))")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testDisplayModeSwitchDoesNotRetessellate() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.5, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        let initialPosAddress = mesh.positionBuffer.gpuAddress
        let initialNormAddress = mesh.normalBuffer.gpuAddress
        let initialIndexAddress = mesh.indexBuffer.gpuAddress
        let initialEdgeAddress = mesh.edgeSegmentBuffer?.gpuAddress
        let initialIndexCount = mesh.indexCount
        let initialEdgeCount = mesh.edgeSegmentCount

        for mode in DisplayMode.allCases {
            renderer.displayMode = mode
            _ = try #require(await renderer.captureSnapshotPngBase64())

            guard let currentMesh = renderer.meshes[boxId] else {
                Issue.record("Mesh missing after switching to \(mode)")
                continue
            }
            #expect(currentMesh.positionBuffer.gpuAddress == initialPosAddress, "Position buffer unchanged in \(mode)")
            #expect(currentMesh.normalBuffer.gpuAddress == initialNormAddress, "Normal buffer unchanged in \(mode)")
            #expect(currentMesh.indexBuffer.gpuAddress == initialIndexAddress, "Index buffer unchanged in \(mode)")
            #expect(currentMesh.edgeSegmentBuffer?.gpuAddress == initialEdgeAddress, "Edge segment buffer unchanged in \(mode)")
            #expect(currentMesh.indexCount == initialIndexCount, "Index count unchanged in \(mode)")
            #expect(currentMesh.edgeSegmentCount == initialEdgeCount, "Edge count unchanged in \(mode)")
        }
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testEmptySceneDisplayModeSwitch() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.meshes.removeAll()

        for mode in DisplayMode.allCases {
            renderer.displayMode = mode
            _ = try #require(await renderer.captureSnapshotPngBase64())
            #expect(renderer.lastDrawCalls == 0, "Empty scene in mode \(mode) must issue 0 draw calls")
        }
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testMeshWithZeroEdgesDisplayMode() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        // EuclidEngine mesh has 0 B-Rep edge segments
        let payload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 30, depth: 30, height: 30))
        let boxId = SolidId("box-no-edges")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.5, 0.5, 0.5, 1.0)))
        renderer.meshes[boxId] = mesh

        #expect(mesh.edgeSegmentCount == 0)

        renderer.displayMode = .wireframe
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 0, "Wireframe with 0 edges must issue 0 draw calls")

        renderer.displayMode = .hiddenLineRemoved
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1, "HLR with 0 edges must issue 1 draw call (face pass only)")

        renderer.displayMode = .hiddenLinesVisible
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1, "HLV with 0 edges must issue 1 draw call (face pass only)")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testHiddenSolidDisplayModeBehavior() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.5, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh
        renderer.hiddenSolidIds.insert(boxId)

        for mode in DisplayMode.allCases {
            renderer.displayMode = mode
            _ = try #require(await renderer.captureSnapshotPngBase64())
            #expect(renderer.lastDrawCalls == 0, "Hidden solid in mode \(mode) must issue 0 draw calls")
        }
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testOrthographicCameraProjectionInAllDisplayModes() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.projectionMode = .orthographic

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.5, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh

        let expectedDrawCalls: [DisplayMode: Int] = [
            .shadedWithEdges: 2,
            .shaded: 1,
            .wireframe: 1,
            .hiddenLineRemoved: 2,
            .hiddenLinesVisible: 3
        ]

        for (mode, expected) in expectedDrawCalls {
            renderer.displayMode = mode
            _ = try #require(await renderer.captureSnapshotPngBase64())
            #expect(renderer.lastDrawCalls == expected, "Orthographic projection in mode \(mode) must issue \(expected) draw calls")
        }
    }

    // MARK: - Helpers

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
