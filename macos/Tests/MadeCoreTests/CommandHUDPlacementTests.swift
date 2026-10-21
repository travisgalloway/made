import Testing
import CoreGraphics
import simd
import MadeCore

@Suite struct CommandHUDPlacementTests {
    @Test func testScreenBoundingBoxCalculationAndYFlipping() {
        let viewportSize = CGSize(width: 800, height: 600)
        let bounds = SceneBounds(
            min: SIMD3<Float>(-10, -10, -10),
            max: SIMD3<Float>(10, 10, 10)
        )
        let camera = Camera(
            position: SIMD3<Float>(0, -100, 0),
            target: SIMD3<Float>(0, 0, 0)
        )
        let aspect: Float = 800.0 / 600.0
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix

        let rect = ScreenBoundsCalculator.screenBoundingBox(
            for: bounds,
            viewProjectionMatrix: vp,
            viewportSize: viewportSize
        )

        #expect(rect != nil)
        if let rect {
            #expect(rect.width > 0)
            #expect(rect.height > 0)
            // Center should be approximately at viewport center (400, 300)
            #expect(abs(rect.midX - 400) < 10)
            #expect(abs(rect.midY - 300) < 10)
            // Verify rect is fully inside viewport
            #expect(rect.minX >= 0)
            #expect(rect.maxX <= 800)
            #expect(rect.minY >= 0)
            #expect(rect.maxY <= 600)
        }
    }

    @Test func testScreenBoundingBoxInvalidInputs() {
        let bounds = SceneBounds(min: SIMD3<Float>(-1, -1, -1), max: SIMD3<Float>(1, 1, 1))
        #expect(ScreenBoundsCalculator.screenBoundingBox(for: bounds, viewProjectionMatrix: matrix_identity_float4x4, viewportSize: .zero) == nil)
        #expect(ScreenBoundsCalculator.screenBoundingBox(for: bounds, viewProjectionMatrix: matrix_identity_float4x4, viewportSize: CGSize(width: -100, height: 100)) == nil)
    }

    @Test func testRightCandidatePlacement() {
        let viewportSize = CGSize(width: 800, height: 600)
        let hudSize = CGSize(width: 200, height: 150)
        // Geometry on the left
        let geom = CGRect(x: 50, y: 150, width: 100, height: 100)

        let pos = CommandHUDPlacement.computePosition(
            geometryScreenRect: geom,
            viewportSize: viewportSize,
            hudSize: hudSize,
            margin: 16,
            padding: 16
        )

        let hudRect = CGRect(origin: pos, size: hudSize)
        #expect(pos.x == geom.maxX + 16)
        #expect(!hudRect.intersects(geom))
        #expect(hudRect.maxX <= viewportSize.width - 16)
        #expect(hudRect.minX >= 16)
        #expect(hudRect.minY >= 16)
        #expect(hudRect.maxY <= viewportSize.height - 16)
    }

    @Test func testLeftCandidatePlacement() {
        let viewportSize = CGSize(width: 800, height: 600)
        let hudSize = CGSize(width: 200, height: 150)
        // Geometry on the right, right edge near boundary so Right placement overflows
        let geom = CGRect(x: 650, y: 150, width: 100, height: 100)

        let pos = CommandHUDPlacement.computePosition(
            geometryScreenRect: geom,
            viewportSize: viewportSize,
            hudSize: hudSize,
            margin: 16,
            padding: 16
        )

        let hudRect = CGRect(origin: pos, size: hudSize)
        #expect(pos.x == geom.minX - 16 - hudSize.width)
        #expect(!hudRect.intersects(geom))
        #expect(hudRect.minX >= 16)
        #expect(hudRect.maxX <= viewportSize.width - 16)
    }

    @Test func testBelowCandidatePlacement() {
        let viewportSize = CGSize(width: 800, height: 600)
        let hudSize = CGSize(width: 200, height: 150)
        // Geometry spans horizontal width near top, so Right and Left cannot fit
        let geom = CGRect(x: 30, y: 30, width: 740, height: 80)

        let pos = CommandHUDPlacement.computePosition(
            geometryScreenRect: geom,
            viewportSize: viewportSize,
            hudSize: hudSize,
            margin: 16,
            padding: 16
        )

        let hudRect = CGRect(origin: pos, size: hudSize)
        #expect(pos.y == geom.maxY + 16)
        #expect(!hudRect.intersects(geom))
        #expect(hudRect.maxY <= viewportSize.height - 16)
    }

    @Test func testAboveCandidatePlacement() {
        let viewportSize = CGSize(width: 800, height: 600)
        let hudSize = CGSize(width: 200, height: 150)
        // Geometry spans horizontal width near bottom, Below overflows
        let geom = CGRect(x: 30, y: 450, width: 740, height: 80)

        let pos = CommandHUDPlacement.computePosition(
            geometryScreenRect: geom,
            viewportSize: viewportSize,
            hudSize: hudSize,
            margin: 16,
            padding: 16
        )

        let hudRect = CGRect(origin: pos, size: hudSize)
        #expect(pos.y == geom.minY - 16 - hudSize.height)
        #expect(!hudRect.intersects(geom))
        #expect(hudRect.minY >= 16)
    }

    @Test func testEdgePaddingClamping() {
        let viewportSize = CGSize(width: 800, height: 600)
        let hudSize = CGSize(width: 200, height: 150)
        // Geometry placed near top edge
        let geom = CGRect(x: 50, y: 10, width: 80, height: 40)

        let pos = CommandHUDPlacement.computePosition(
            geometryScreenRect: geom,
            viewportSize: viewportSize,
            hudSize: hudSize,
            margin: 16,
            padding: 20
        )

        let hudRect = CGRect(origin: pos, size: hudSize)
        #expect(hudRect.minY >= 20)
        #expect(hudRect.minX >= 20)
        #expect(hudRect.maxX <= viewportSize.width - 20)
        #expect(hudRect.maxY <= viewportSize.height - 20)
        #expect(!hudRect.intersects(geom))
    }

    @Test func testFallbackCornersForViewportSpanningGeometry() {
        let viewportSize = CGSize(width: 800, height: 600)
        let hudSize = CGSize(width: 200, height: 150)
        // Cross geometry spanning center: Right, Left, Below, Above all collide
        let geom = CGRect(x: 50, y: 50, width: 700, height: 500)

        let pos = CommandHUDPlacement.computePosition(
            geometryScreenRect: geom,
            viewportSize: viewportSize,
            hudSize: hudSize,
            margin: 16,
            padding: 16
        )

        // Fallback should pick a valid corner inside viewport without crashing
        let hudRect = CGRect(origin: pos, size: hudSize)
        #expect(hudRect.minX >= 16)
        #expect(hudRect.minY >= 16)
        #expect(hudRect.maxX <= viewportSize.width - 16)
        #expect(hudRect.maxY <= viewportSize.height - 16)
    }

    @Test func testNilOrOffscreenGeometryDefaultsToTopRight() {
        let viewportSize = CGSize(width: 800, height: 600)
        let hudSize = CGSize(width: 200, height: 150)
        let padding: CGFloat = 16

        let posNil = CommandHUDPlacement.computePosition(
            geometryScreenRect: nil,
            viewportSize: viewportSize,
            hudSize: hudSize,
            padding: padding
        )
        #expect(posNil.x == viewportSize.width - hudSize.width - padding)
        #expect(posNil.y == padding)

        let offscreenGeom = CGRect(x: 1000, y: 1000, width: 50, height: 50)
        let posOff = CommandHUDPlacement.computePosition(
            geometryScreenRect: offscreenGeom,
            viewportSize: viewportSize,
            hudSize: hudSize,
            padding: padding
        )
        #expect(posOff.x == viewportSize.width - hudSize.width - padding)
        #expect(posOff.y == padding)
    }

    @Test func testNonCoveringInvariantOnVariousPlacements() {
        let viewportSize = CGSize(width: 1000, height: 800)
        let hudSize = CGSize(width: 220, height: 180)

        let testGeometries: [CGRect] = [
            CGRect(x: 100, y: 100, width: 120, height: 120),
            CGRect(x: 400, y: 300, width: 150, height: 150),
            CGRect(x: 750, y: 200, width: 100, height: 100),
            CGRect(x: 200, y: 600, width: 140, height: 100),
            CGRect(x: 700, y: 650, width: 100, height: 80)
        ]

        for geom in testGeometries {
            let pos = CommandHUDPlacement.computePosition(
                geometryScreenRect: geom,
                viewportSize: viewportSize,
                hudSize: hudSize
            )
            let hudRect = CGRect(origin: pos, size: hudSize)
            #expect(!hudRect.intersects(geom))
        }
    }

    @Test func testDimensionLabelPerspectiveProjection() {
        let viewportSize = CGSize(width: 800, height: 600)
        let camera = Camera(
            position: SIMD3<Float>(0, -100, 0),
            target: SIMD3<Float>(0, 0, 0)
        )
        let aspect: Float = 800.0 / 600.0
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix

        let candidate = DimensionLabelCandidate(
            id: "width",
            label: "Width",
            value: 30.0,
            worldAnchor: SIMD3<Float>(0, 0, 0),
            size: CGSize(width: 80, height: 28)
        )

        let placements = DimensionLabelPlacement.computePlacements(
            candidates: [candidate],
            viewProjectionMatrix: vp,
            viewportSize: viewportSize
        )

        #expect(placements.count == 1)
        let result = placements[0]
        #expect(result.isVisible)
        #expect(result.id == "width")
        #expect(abs(result.center.x - 400) < 5)
        #expect(abs(result.center.y - 300) < 5)
        #expect(result.frame.width == 80)
        #expect(result.frame.height == 28)
    }

    @Test func testDimensionLabelOrthographicProjection() {
        let viewportSize = CGSize(width: 800, height: 600)
        let camera = Camera(
            position: SIMD3<Float>(0, -100, 0),
            target: SIMD3<Float>(0, 0, 0)
        )
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        let projMatrix = Orientation.makeOrthographic(left: -40, right: 40, bottom: -30, top: 30, nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix

        let candidate = DimensionLabelCandidate(
            id: "width",
            label: "Width",
            value: 20.0,
            worldAnchor: SIMD3<Float>(0, 0, 0),
            size: CGSize(width: 80, height: 28)
        )

        let placements = DimensionLabelPlacement.computePlacements(
            candidates: [candidate],
            viewProjectionMatrix: vp,
            viewportSize: viewportSize
        )

        #expect(placements.count == 1)
        let result = placements[0]
        #expect(result.isVisible)
        #expect(abs(result.center.x - 400) < 5)
        #expect(abs(result.center.y - 300) < 5)
    }

    @Test func testDimensionLabelBehindCameraCulling() {
        let viewportSize = CGSize(width: 800, height: 600)
        let camera = Camera(
            position: SIMD3<Float>(0, -100, 0),
            target: SIMD3<Float>(0, 0, 0)
        )
        let aspect: Float = 800.0 / 600.0
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix

        let candidate = DimensionLabelCandidate(
            id: "depth",
            label: "Depth",
            value: 50.0,
            worldAnchor: SIMD3<Float>(0, -200, 0),
            size: CGSize(width: 80, height: 28)
        )

        let placements = DimensionLabelPlacement.computePlacements(
            candidates: [candidate],
            viewProjectionMatrix: vp,
            viewportSize: viewportSize
        )

        #expect(placements.count == 1)
        #expect(!placements[0].isVisible)
    }

    @Test func testDimensionLabelOverlapOffsetting() {
        let viewportSize = CGSize(width: 800, height: 600)
        let camera = Camera(
            position: SIMD3<Float>(0, -100, 0),
            target: SIMD3<Float>(0, 0, 0)
        )
        let aspect: Float = 800.0 / 600.0
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix

        let c1 = DimensionLabelCandidate(id: "width", label: "Width", value: 30, worldAnchor: SIMD3<Float>(0, 0, 0), size: CGSize(width: 80, height: 28))
        let c2 = DimensionLabelCandidate(id: "depth", label: "Depth", value: 30, worldAnchor: SIMD3<Float>(0, 0, 0), size: CGSize(width: 80, height: 28))
        let c3 = DimensionLabelCandidate(id: "height", label: "Height", value: 30, worldAnchor: SIMD3<Float>(0, 0, 0), size: CGSize(width: 80, height: 28))

        let placements = DimensionLabelPlacement.computePlacements(
            candidates: [c1, c2, c3],
            viewProjectionMatrix: vp,
            viewportSize: viewportSize
        )

        #expect(placements.count == 3)
        for p in placements {
            #expect(p.isVisible)
        }

        #expect(!placements[0].frame.intersects(placements[1].frame))
        #expect(!placements[0].frame.intersects(placements[2].frame))
        #expect(!placements[1].frame.intersects(placements[2].frame))

        for p in placements {
            #expect(p.frame.minX >= 16)
            #expect(p.frame.maxX <= viewportSize.width - 16)
            #expect(p.frame.minY >= 16)
            #expect(p.frame.maxY <= viewportSize.height - 16)
        }
    }

    @Test func testDimensionLabel1mmFeatureBoundaryClamping() {
        let viewportSize = CGSize(width: 800, height: 600)
        let camera = Camera(
            position: SIMD3<Float>(0, -100, 0),
            target: SIMD3<Float>(0, 0, 0)
        )
        let aspect: Float = 800.0 / 600.0
        let viewMatrix = Orientation.makeLookAt(eye: camera.position, target: camera.target, up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: Float.pi / 4.0, aspect: aspect, nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix

        let candidate = DimensionLabelCandidate(
            id: "tinyFeature",
            label: "Edge",
            value: 1.0,
            worldAnchor: SIMD3<Float>(40, 0, 30),
            size: CGSize(width: 80, height: 28)
        )

        let padding: CGFloat = 20
        let placements = DimensionLabelPlacement.computePlacements(
            candidates: [candidate],
            viewProjectionMatrix: vp,
            viewportSize: viewportSize,
            padding: padding
        )

        #expect(placements.count == 1)
        let p = placements[0]
        #expect(p.isVisible)
        #expect(p.frame.minX >= padding)
        #expect(p.frame.maxX <= viewportSize.width - padding)
        #expect(p.frame.minY >= padding)
        #expect(p.frame.maxY <= viewportSize.height - padding)
    }

    @Test func testDimensionLabelInvalidViewportSize() {
        let candidate = DimensionLabelCandidate(
            id: "width",
            label: "Width",
            value: 10.0,
            worldAnchor: SIMD3<Float>(0, 0, 0)
        )

        let placementsZero = DimensionLabelPlacement.computePlacements(
            candidates: [candidate],
            viewProjectionMatrix: matrix_identity_float4x4,
            viewportSize: .zero
        )
        #expect(placementsZero.count == 1)
        #expect(!placementsZero[0].isVisible)

        let placementsNegative = DimensionLabelPlacement.computePlacements(
            candidates: [candidate],
            viewProjectionMatrix: matrix_identity_float4x4,
            viewportSize: CGSize(width: -100, height: -100)
        )
        #expect(placementsNegative.count == 1)
        #expect(!placementsNegative[0].isVisible)
    }
}

