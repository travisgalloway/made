import Testing
import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
@testable import MadeCore

@Suite(.serialized) struct MetalRendererGeometryTests {
    private let width = 800
    private let height = 600

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testBoxRendersInsideItsProjectedBounds() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        // Only the solid draws, so every covered pixel must belong to the box.
        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 40, depth: 30, height: 20))
        let mesh = try #require(renderer.createMesh(from: payload, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[SolidId("box")] = mesh

        let snapshot = await renderer.captureSnapshotPngBase64()
        let base64 = try #require(snapshot)
        let pixels = try decodeRGBA(base64)

        let bounds = projectedBounds(of: payload, renderer: renderer)
        let background = mostCommonPixel(pixels)

        var outside = 0
        var inside = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let p = (pixels[i], pixels[i + 1], pixels[i + 2])
                let covered = abs(Int(p.0) - Int(background.0)) > 4
                    || abs(Int(p.1) - Int(background.1)) > 4
                    || abs(Int(p.2) - Int(background.2)) > 4
                guard covered else { continue }
                if bounds.insetBy(dx: -2, dy: -2).contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                    inside += 1
                } else {
                    outside += 1
                }
            }
        }

        #expect(outside == 0, "pixels drawn outside the box's projected bounds")
        #expect(Double(inside) > (0.5 * Double(bounds.width * bounds.height)), "box covers too little of its projected bounds")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testBoxShowsItsTopFaceToACameraAbove() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 40, depth: 30, height: 20))
        let mesh = try #require(renderer.createMesh(from: payload, color: SIMD4<Float>(0, 0, 1, 1)))
        renderer.meshes[SolidId("box")] = mesh

        let snapshot = await renderer.captureSnapshotPngBase64()
        let pixels = try decodeRGBA(try #require(snapshot))

        // The lit top face reads about 239 in blue; an inside-out box shows a dimmer back face here, about 179.
        let topCenter = project(SIMD3<Float>(0, 0, 10), renderer: renderer)
        let i = (Int(topCenter.y) * width + Int(topCenter.x)) * 4
        #expect(pixels[i + 2] > 210, "front faces are culled, so the box renders inside-out")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testSelectionOutlineIncrementsDrawCallsAndRendersFringe() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 40, depth: 30, height: 20))
        let boxId = SolidId("box")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.2, 0.4, 0.8, 1.0)))
        renderer.meshes[boxId] = mesh

        // When unselected: exactly 1 draw call (the solid itself)
        renderer.selectedId = nil
        let unselectedSnapshot = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1)
        let unselectedPixels = try decodeRGBA(unselectedSnapshot)

        // When selected: exactly 2 draw calls (solid + outline)
        renderer.selectedId = boxId
        let selectedSnapshot = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 2)
        let selectedPixels = try decodeRGBA(selectedSnapshot)

        let background = mostCommonPixel(unselectedPixels)

        // Find pixels in selected snapshot that are amber outline (high red, medium green, low blue)
        var amberOutlinePixelCount = 0
        var fringePixelCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = selectedPixels[i]
                let g = selectedPixels[i + 1]
                let b = selectedPixels[i + 2]

                let isAmber = r > 180 && g > 100 && b < 60
                if isAmber {
                    amberOutlinePixelCount += 1
                }

                // Check if this pixel was background in unselectedPixels but became amber in selectedPixels
                let unselectedP = (unselectedPixels[i], unselectedPixels[i + 1], unselectedPixels[i + 2])
                let wasBackground = abs(Int(unselectedP.0) - Int(background.0)) <= 4
                    && abs(Int(unselectedP.1) - Int(background.1)) <= 4
                    && abs(Int(unselectedP.2) - Int(background.2)) <= 4
                if wasBackground && isAmber {
                    fringePixelCount += 1
                }
            }
        }

        #expect(amberOutlinePixelCount > 50, "Selection outline should render amber pixels")
        #expect(fringePixelCount > 20, "Selection outline should render fringe pixels extending outside the solid")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testNoSelectionIssuesNoOutlineDrawCalls() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let boxPayload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 30, depth: 30, height: 20))
        let cylPayload = EuclidEngine.toMeshPayload(EuclidEngine.makeCylinder(radius: 10, height: 30))
        let boxMesh = try #require(renderer.createMesh(from: boxPayload, solidId: SolidId("box"), color: SIMD4<Float>(0.5, 0.5, 0.5, 1.0)))
        let cylMesh = try #require(renderer.createMesh(from: cylPayload, solidId: SolidId("cyl"), color: SIMD4<Float>(0.6, 0.6, 0.6, 1.0)))
        renderer.meshes[SolidId("box")] = boxMesh
        renderer.meshes[SolidId("cyl")] = cylMesh

        renderer.selectedId = nil
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 2, "No outline draw calls should be issued when selectedId is nil")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testRemovedOrHiddenSolidIssuesNoOutline() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let payload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 40, depth: 30, height: 20))
        let boxId = SolidId("box")
        let boxMesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[boxId] = boxMesh

        // Nonexistent solid ID
        renderer.selectedId = SolidId("uninstalled")
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 1, "Uninstalled solid selection should produce 0 outline draw calls")

        // Hidden solid
        renderer.selectedId = boxId
        renderer.hiddenSolidIds.insert(boxId)
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 0, "Hidden solid selection should produce 0 draw calls total")

        // Unhide and removeMesh
        renderer.hiddenSolidIds.remove(boxId)
        #expect(renderer.selectedId == boxId)
        let removed = await renderer.removeMesh(for: boxId)
        #expect(removed)
        #expect(renderer.selectedId == nil, "removeMesh should clear selectedId if matching")
        _ = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 0, "Empty scene should produce 0 draw calls")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testOccludedSolidOutlineOccludedByForegroundSolid() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        // Background box at origin (0, 0, 0)
        let bgId = SolidId("bgBox")
        let bgPayload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 40, depth: 40, height: 40))
        let bgMesh = try #require(renderer.createMesh(from: bgPayload, solidId: bgId, color: SIMD4<Float>(0.1, 0.1, 0.1, 1.0)))
        renderer.meshes[bgId] = bgMesh

        // Foreground solid closer to default camera (eye is at (150, -150, 90), target is (0, 0, 10))
        let fgId = SolidId("fgBox")
        let fgTransform = Transform(position: SIMD3<Float>(50, -50, 30))
        let fgMesh = try #require(renderer.createMesh(from: bgPayload, solidId: fgId, transform: fgTransform, color: SIMD4<Float>(0.0, 1.0, 0.0, 1.0)))
        renderer.meshes[fgId] = fgMesh

        // Select the background solid
        renderer.selectedId = bgId
        let snapshot = try #require(await renderer.captureSnapshotPngBase64())
        #expect(renderer.lastDrawCalls == 3, "2 solids + 1 outline = 3 draw calls")

        let pixels = try decodeRGBA(snapshot)
        // Foreground solid center should be green (R low, G high, B low) and NOT amber outline
        let fgCenter = project(fgTransform.position, renderer: renderer)
        let i = (Int(fgCenter.y) * width + Int(fgCenter.x)) * 4
        let g = pixels[i + 1]
        let r = pixels[i]
        #expect(g > 150 && r < 50, "Foreground solid face must occlude background solid outline")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testOrthographicProjectionPreservesApparentWidthAcrossDepths() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        renderer.camera = Camera(
            position: SIMD3<Float>(0, -200, 0),
            target: SIMD3<Float>(0, 0, 0)
        )
        let boxPayload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 30, depth: 20, height: 20))
        let nearTransform = Transform(position: SIMD3<Float>(0, -100, 0))
        let farTransform = Transform(position: SIMD3<Float>(0, 50, 0))

        // 1. Perspective mode: near solid appears wider than far solid
        renderer.projectionMode = .perspective
        let nearBoundsPerspective = projectedBounds(of: boxPayload, transform: nearTransform, renderer: renderer)
        let farBoundsPerspective = projectedBounds(of: boxPayload, transform: farTransform, renderer: renderer)
        let nearWidthPerspective = nearBoundsPerspective.width
        let farWidthPerspective = farBoundsPerspective.width
        #expect(nearWidthPerspective > farWidthPerspective)

        // 2. Orthographic mode: near and far solids have equal projected width
        renderer.projectionMode = .orthographic
        let nearBoundsOrtho = projectedBounds(of: boxPayload, transform: nearTransform, renderer: renderer)
        let farBoundsOrtho = projectedBounds(of: boxPayload, transform: farTransform, renderer: renderer)
        let nearWidthOrtho = nearBoundsOrtho.width
        let farWidthOrtho = farBoundsOrtho.width
        #expect(abs(nearWidthOrtho - farWidthOrtho) < 1e-4)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testOrthographicSnapshotMatchesProjection() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)
        renderer.projectionMode = .orthographic

        let payload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 40, depth: 30, height: 20))
        let mesh = try #require(renderer.createMesh(from: payload, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[SolidId("ortho-box")] = mesh

        let snapshot = await renderer.captureSnapshotPngBase64()
        let base64 = try #require(snapshot)
        let pixels = try decodeRGBA(base64)

        let bounds = projectedBounds(of: payload, renderer: renderer)
        let background = mostCommonPixel(pixels)

        var outside = 0
        var inside = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let p = (pixels[i], pixels[i + 1], pixels[i + 2])
                let covered = abs(Int(p.0) - Int(background.0)) > 4
                    || abs(Int(p.1) - Int(background.1)) > 4
                    || abs(Int(p.2) - Int(background.2)) > 4
                guard covered else { continue }
                if bounds.insetBy(dx: -2, dy: -2).contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                    inside += 1
                } else {
                    outside += 1
                }
            }
        }

        #expect(outside == 0, "pixels drawn outside the orthographic box's projected bounds")
        #expect(Double(inside) > (0.5 * Double(bounds.width * bounds.height)), "box covers too little of its orthographic projected bounds")
    }

    private func viewProjection(_ renderer: MetalRenderer) -> simd_float4x4 {
        let matrices = renderer.viewAndProjectionMatrices(aspect: Float(width) / Float(height))
        return matrices.projection * matrices.view
    }

    private func project(_ point: SIMD3<Float>, renderer: MetalRenderer) -> CGPoint {
        let clip = viewProjection(renderer) * SIMD4<Float>(point, 1)
        let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
        return CGPoint(x: Double((ndc.x + 1) / 2) * Double(width), y: Double((1 - ndc.y) / 2) * Double(height))
    }

    private func projectedBounds(of payload: MeshPayload, transform: Transform = .identity, renderer: MetalRenderer) -> CGRect {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for v in stride(from: 0, to: payload.positions.count, by: 3) {
            let localPoint = SIMD3<Float>(payload.positions[v], payload.positions[v + 1], payload.positions[v + 2])
            let worldPoint = transform.transformPoint(localPoint)
            let p = project(worldPoint, renderer: renderer)
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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

    private func mostCommonPixel(_ pixels: [UInt8]) -> (UInt8, UInt8, UInt8) {
        var counts: [UInt32: Int] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let key = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
            counts[key, default: 0] += 1
        }
        let key = counts.max { $0.value < $1.value }!.key
        return (UInt8(key >> 16 & 0xFF), UInt8(key >> 8 & 0xFF), UInt8(key & 0xFF))
    }
}
