import Testing
import Foundation
import CoreGraphics
import ImageIO
import simd
@testable import MadeCore

@Suite struct SketchImageUnderlayTests {
    private static func makeTestImageData(width: Int = 120, height: Int = 80) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func testUnderlayInitializationAndDimensionReading() throws {
        let pngData = Self.makeTestImageData(width: 120, height: 80)
        let underlay = try SketchImageUnderlay(
            name: "Blueprint",
            imageData: pngData,
            origin: SIMD2<Double>(10, 20),
            opacity: 0.85
        )

        #expect(underlay.name == "Blueprint")
        #expect(underlay.pixelWidth == 120)
        #expect(underlay.pixelHeight == 80)
        #expect(underlay.width == 120.0)
        #expect(underlay.height == 80.0)
        #expect(underlay.origin.x == 10.0)
        #expect(underlay.origin.y == 20.0)
        #expect(underlay.opacity == 0.85)
        #expect(underlay.preserveAspectRatio == true)
        #expect(underlay.isVisible == true)
        #expect(underlay.isLocked == false)

        // Invalid image data throws error
        let corruptData = Data([0x00, 0x01, 0x02, 0x03])
        #expect(throws: SketchUnderlayError.invalidImageData) {
            _ = try SketchImageUnderlay(imageData: corruptData)
        }
    }

    @Test func testTwoPointCalibrationScalingAndOriginAnchor() throws {
        let pngData = Self.makeTestImageData(width: 200, height: 100)
        var underlay = try SketchImageUnderlay(
            name: "Ruler Reference",
            imageData: pngData,
            origin: SIMD2<Double>(0, 0)
        )

        // Point 1 on ruler at (10, 20), Point 2 at (10, 70).
        // Current Euclidean distance = 50. Target distance = 100.
        // Scale factor = 2.0.
        let p1 = SIMD2<Double>(10, 20)
        let p2 = SIMD2<Double>(10, 70)
        try underlay.calibrate(point1: p1, point2: p2, targetDistance: 100.0)

        // Width and height scaled by 2.0
        #expect(abs(underlay.width - 400.0) < 1e-6)
        #expect(abs(underlay.height - 200.0) < 1e-6)

        // Origin anchored: new origin = p1 + (old_origin - p1) * 2.0
        // (10, 20) + ((0, 0) - (10, 20)) * 2.0 = (10 - 20, 20 - 40) = (-10, -20)
        #expect(abs(underlay.origin.x - (-10.0)) < 1e-6)
        #expect(abs(underlay.origin.y - (-20.0)) < 1e-6)
    }

    @Test func testCalibrationDegenerateInputsThrow() throws {
        let pngData = Self.makeTestImageData(width: 100, height: 100)
        var underlay = try SketchImageUnderlay(imageData: pngData)

        let p1 = SIMD2<Double>(0, 0)
        let p2 = SIMD2<Double>(50, 0)

        // Non-positive or infinite target distance
        #expect(throws: SketchUnderlayError.degenerateDistance) {
            try underlay.calibrate(point1: p1, point2: p2, targetDistance: 0.0)
        }
        #expect(throws: SketchUnderlayError.degenerateDistance) {
            try underlay.calibrate(point1: p1, point2: p2, targetDistance: -10.0)
        }
        #expect(throws: SketchUnderlayError.degenerateDistance) {
            try underlay.calibrate(point1: p1, point2: p2, targetDistance: .nan)
        }
        #expect(throws: SketchUnderlayError.degenerateDistance) {
            try underlay.calibrate(point1: p1, point2: p2, targetDistance: .infinity)
        }

        // Coincident calibration points
        #expect(throws: SketchUnderlayError.coincidentPoints) {
            try underlay.calibrate(point1: p1, point2: p1, targetDistance: 50.0)
        }

        // Non-finite points
        #expect(throws: SketchUnderlayError.nonFiniteCoordinates) {
            try underlay.calibrate(point1: SIMD2<Double>(.nan, 0), point2: p2, targetDistance: 50.0)
        }
    }

    @Test func testAspectRatioLockDimensionUpdate() throws {
        let pngData = Self.makeTestImageData(width: 200, height: 100) // 2:1 aspect ratio
        var underlay = try SketchImageUnderlay(imageData: pngData)
        #expect(underlay.preserveAspectRatio == true)

        underlay.setWidth(400.0)
        #expect(abs(underlay.height - 200.0) < 1e-6)

        underlay.setHeight(50.0)
        #expect(abs(underlay.width - 100.0) < 1e-6)

        // With aspect ratio unlocked
        underlay.preserveAspectRatio = false
        underlay.setWidth(300.0)
        #expect(abs(underlay.height - 50.0) < 1e-6)
    }

    @Test func testUnderlayCodableRoundTrip() throws {
        let pngData = Self.makeTestImageData(width: 50, height: 50)
        let original = SketchImageUnderlay(
            name: "Floorplan",
            imageData: pngData,
            assetFilename: "floorplan.png",
            origin: SIMD2<Double>(5.5, -12.3),
            width: 250.0,
            height: 125.0,
            rotationAngle: 0.785398,
            opacity: 0.65,
            isLocked: true,
            isVisible: true,
            preserveAspectRatio: true
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SketchImageUnderlay.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.assetFilename == original.assetFilename)
        #expect(decoded.pixelWidth == original.pixelWidth)
        #expect(decoded.pixelHeight == original.pixelHeight)
        #expect(abs(decoded.origin.x - original.origin.x) < 1e-6)
        #expect(abs(decoded.origin.y - original.origin.y) < 1e-6)
        #expect(abs(decoded.width - original.width) < 1e-6)
        #expect(abs(decoded.height - original.height) < 1e-6)
        #expect(abs(decoded.rotationAngle - original.rotationAngle) < 1e-6)
        #expect(abs(decoded.opacity - original.opacity) < 1e-6)
        #expect(decoded.isLocked == original.isLocked)
        #expect(decoded.isVisible == original.isVisible)
        #expect(decoded.preserveAspectRatio == original.preserveAspectRatio)
    }

    @Test func testUnderlayQuadCornerGeneration() {
        let pngData = Self.makeTestImageData(width: 100, height: 50)
        let underlay = SketchImageUnderlay(
            imageData: pngData,
            pixelWidth: 100,
            pixelHeight: 50,
            origin: SIMD2<Double>(10, 20),
            width: 100.0,
            height: 50.0,
            rotationAngle: 0.0
        )

        let plane = SketchPlane.xy
        let corners = underlay.corners(on: plane)
        #expect(corners.count == 4)

        // c0: bottom-left (10, 20, 0)
        #expect(abs(corners[0].x - 10.0) < 1e-5)
        #expect(abs(corners[0].y - 20.0) < 1e-5)
        #expect(abs(corners[0].z - 0.0) < 1e-5)

        // c1: bottom-right (110, 20, 0)
        #expect(abs(corners[1].x - 110.0) < 1e-5)
        #expect(abs(corners[1].y - 20.0) < 1e-5)
        #expect(abs(corners[1].z - 0.0) < 1e-5)

        // c2: top-right (110, 70, 0)
        #expect(abs(corners[2].x - 110.0) < 1e-5)
        #expect(abs(corners[2].y - 70.0) < 1e-5)
        #expect(abs(corners[2].z - 0.0) < 1e-5)

        // c3: top-left (10, 70, 0)
        #expect(abs(corners[3].x - 10.0) < 1e-5)
        #expect(abs(corners[3].y - 70.0) < 1e-5)
        #expect(abs(corners[3].z - 0.0) < 1e-5)
    }
}
