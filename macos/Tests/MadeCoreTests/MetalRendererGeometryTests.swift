import Testing
import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
@testable import MadeCore

@Suite struct MetalRendererGeometryTests {
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

    private func viewProjection(_ renderer: MetalRenderer) -> simd_float4x4 {
        let view = Orientation.makeLookAt(eye: renderer.cameraPosition, target: renderer.cameraTarget, up: Orientation.worldUp)
        let proj = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: Float(width) / Float(height), nearZ: 0.1, farZ: 1000.0)
        return proj * view
    }

    private func project(_ point: SIMD3<Float>, renderer: MetalRenderer) -> CGPoint {
        let clip = viewProjection(renderer) * SIMD4<Float>(point, 1)
        let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
        return CGPoint(x: Double((ndc.x + 1) / 2) * Double(width), y: Double((1 - ndc.y) / 2) * Double(height))
    }

    private func projectedBounds(of payload: MeshPayload, renderer: MetalRenderer) -> CGRect {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for v in stride(from: 0, to: payload.positions.count, by: 3) {
            let p = project(SIMD3<Float>(payload.positions[v], payload.positions[v + 1], payload.positions[v + 2]), renderer: renderer)
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
