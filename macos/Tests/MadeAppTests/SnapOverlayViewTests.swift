import Testing
import SwiftUI
import AppKit
import simd
@testable import MadeApp
import MadeCore

@Suite struct SnapOverlayViewTests {

    @Test func testGlyphShapesPathGeneration() {
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)

        // 1. EndpointSquareShape
        let squarePath = EndpointSquareShape().path(in: rect)
        #expect(!squarePath.isEmpty)
        #expect(squarePath.boundingRect.width == 20)
        #expect(squarePath.boundingRect.height == 20)

        // 2. MidpointTriangleShape
        let triPath = MidpointTriangleShape().path(in: rect)
        #expect(!triPath.isEmpty)
        #expect(triPath.boundingRect.width == 20)
        #expect(triPath.boundingRect.height == 20)

        // 3. CenterCircleCrossShape
        let crossPath = CenterCircleCrossShape().path(in: rect)
        #expect(!crossPath.isEmpty)
        #expect(crossPath.boundingRect.width >= 20)

        // 4. IntersectionXShape
        let xPath = IntersectionXShape().path(in: rect)
        #expect(!xPath.isEmpty)
        #expect(xPath.boundingRect.width == 20)
        #expect(xPath.boundingRect.height == 20)

        // 5. QuadrantDiamondShape
        let diamondPath = QuadrantDiamondShape().path(in: rect)
        #expect(!diamondPath.isEmpty)
        #expect(diamondPath.boundingRect.width == 20)
        #expect(diamondPath.boundingRect.height == 20)

        // 6. GridPlusShape
        let plusPath = GridPlusShape().path(in: rect)
        #expect(!plusPath.isEmpty)
        #expect(plusPath.boundingRect.width == 20)
        #expect(plusPath.boundingRect.height == 20)

        // 7. EdgeBarsShape
        let barsPath = EdgeBarsShape().path(in: rect)
        #expect(!barsPath.isEmpty)
    }

    @Test func testColorMappingForAllSnapKinds() {
        let allKinds = SnapKind.allCases
        #expect(allKinds.count == 8)

        for kind in allKinds {
            let overlayColor = SnapOverlayView.color(for: kind)
            let statusColor = ViewportStatusBar.snapColor(for: kind)
            #expect(overlayColor == statusColor, "Overlay and status bar colors must match for \(kind)")
        }

        // Distinct semantic color checks
        #expect(SnapOverlayView.color(for: .endpoint) != SnapOverlayView.color(for: .vertex))
        #expect(SnapOverlayView.color(for: .center) != SnapOverlayView.color(for: .intersection))
        #expect(SnapOverlayView.color(for: .midpoint) != SnapOverlayView.color(for: .endpoint))
        #expect(SnapOverlayView.color(for: .quadrant) != SnapOverlayView.color(for: .center))
    }

    @Test func testBadgeTextFormatting() {
        #expect(SnapOverlayView.badgeText(for: .endpoint) == "Endpoint")
        #expect(SnapOverlayView.badgeText(for: .vertex) == "Vertex")
        #expect(SnapOverlayView.badgeText(for: .center) == "Center")
        #expect(SnapOverlayView.badgeText(for: .intersection) == "Intersection")
        #expect(SnapOverlayView.badgeText(for: .midpoint) == "Midpoint")
        #expect(SnapOverlayView.badgeText(for: .quadrant) == "Quadrant")
        #expect(SnapOverlayView.badgeText(for: .edge) == "Edge")
        #expect(SnapOverlayView.badgeText(for: .grid) == "Grid")
    }

    @Test func testCanvasPositionCoordinateConversion() {
        // AppKit screen coordinates (0, 0 at bottom-left) converted to SwiftUI canvas (0, 0 at top-left)
        let viewportHeight: CGFloat = 600.0
        let screenPoint = SIMD2<Float>(150.0, 200.0)

        let canvasPos = SnapOverlayView.canvasPosition(screenPoint: screenPoint, viewportHeight: viewportHeight)
        #expect(canvasPos.x == 150.0)
        #expect(canvasPos.y == 400.0) // 600 - 200 = 400

        // Corner tests
        let originScreen = SIMD2<Float>(0.0, 0.0)
        let originCanvas = SnapOverlayView.canvasPosition(screenPoint: originScreen, viewportHeight: viewportHeight)
        #expect(originCanvas.x == 0.0)
        #expect(originCanvas.y == 600.0)

        let topScreen = SIMD2<Float>(800.0, 600.0)
        let topCanvas = SnapOverlayView.canvasPosition(screenPoint: topScreen, viewportHeight: viewportHeight)
        #expect(topCanvas.x == 800.0)
        #expect(topCanvas.y == 0.0)
    }

    @Test @MainActor func testSnapOverlayViewInstantiationAndLayout() {
        let snapResult = SnapResult(
            kind: .endpoint,
            point: SIMD3<Float>(10, 20, 0),
            screenPoint: SIMD2<Float>(120, 180),
            planePoint: SIMD2<Double>(10, 20)
        )

        let view = SnapOverlayView(snap: snapResult)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.frame.width == 800)
        #expect(hostingView.frame.height == 600)
    }

    @Test @MainActor func testWorkspaceActiveSnapResultUpdatesStatusBarAndOverlayState() {
        let workspace = WorkspaceModel()
        #expect(workspace.activeSnapResult == nil)
        #expect(workspace.activeSnapKind == nil)

        let snap = SnapResult(
            kind: .intersection,
            point: SIMD3<Float>(5, 5, 0),
            screenPoint: SIMD2<Float>(100, 100),
            planePoint: SIMD2<Double>(5, 5)
        )

        workspace.handleSnapChanged(snap)
        #expect(workspace.activeSnapResult == snap)
        #expect(workspace.activeSnapKind == .intersection)

        workspace.handleSnapChanged(nil)
        #expect(workspace.activeSnapResult == nil)
        #expect(workspace.activeSnapKind == nil)
    }
}
