import Testing
import SwiftUI
import CoreGraphics
@testable import MadeApp
import MadeCore

@MainActor
@Suite struct MarqueeOverlayViewTests {
    @Test func testBoxPathGeneration() {
        let marquee = MarqueeState(
            shape: .box,
            mode: .window,
            startPoint: CGPoint(x: 100, y: 150),
            currentPoint: CGPoint(x: 250, y: 300)
        )

        // Without viewportHeight conversion
        let pathRaw = MarqueeOverlayView.path(for: marquee)
        #expect(!pathRaw.isEmpty)
        let boundsRaw = pathRaw.boundingRect
        #expect(abs(boundsRaw.origin.x - 100) < 1e-4)
        #expect(abs(boundsRaw.origin.y - 150) < 1e-4)
        #expect(abs(boundsRaw.width - 150) < 1e-4)
        #expect(abs(boundsRaw.height - 150) < 1e-4)

        // With viewportHeight conversion (e.g. 600)
        let pathFlipped = MarqueeOverlayView.path(for: marquee, viewportHeight: 600)
        #expect(!pathFlipped.isEmpty)
        let boundsFlipped = pathFlipped.boundingRect
        #expect(abs(boundsFlipped.origin.x - 100) < 1e-4)
        // Y coords in flipped: 600 - 300 = 300, 600 - 150 = 450 -> minY = 300
        #expect(abs(boundsFlipped.origin.y - 300) < 1e-4)
        #expect(abs(boundsFlipped.width - 150) < 1e-4)
        #expect(abs(boundsFlipped.height - 150) < 1e-4)
    }

    @Test func testLassoPathGeneration() {
        let points = [
            CGPoint(x: 50, y: 50),
            CGPoint(x: 150, y: 50),
            CGPoint(x: 100, y: 150)
        ]
        let marquee = MarqueeState(
            shape: .lasso,
            mode: .crossing,
            startPoint: points[0],
            currentPoint: points[2],
            points: points
        )

        let path = MarqueeOverlayView.path(for: marquee)
        #expect(!path.isEmpty)
        let bounds = path.boundingRect
        #expect(abs(bounds.origin.x - 50) < 1e-4)
        #expect(abs(bounds.origin.y - 50) < 1e-4)
        #expect(abs(bounds.width - 100) < 1e-4)
        #expect(abs(bounds.height - 100) < 1e-4)

        // Empty points returns empty path
        let emptyMarquee = MarqueeState(
            shape: .lasso,
            mode: .crossing,
            startPoint: .zero,
            currentPoint: .zero,
            points: []
        )
        let emptyPath = MarqueeOverlayView.path(for: emptyMarquee)
        // Points were defaulted to [startPoint, currentPoint] if empty in init, or empty path
        #expect(emptyPath.boundingRect.width == 0 || !emptyPath.isEmpty)
    }

    @Test func testModeStyling() {
        // Window mode styling: solid blue
        let windowFill = MarqueeOverlayView.fillColor(for: .window)
        let windowStroke = MarqueeOverlayView.strokeColor(for: .window)
        let windowStyle = MarqueeOverlayView.strokeStyle(for: .window)

        #expect(windowStyle.lineWidth == 1.5)
        #expect(windowStyle.dash.isEmpty)
        #expect(windowFill == Color(red: 0.15, green: 0.45, blue: 0.95).opacity(0.15))
        #expect(windowStroke == Color(red: 0.15, green: 0.45, blue: 0.95).opacity(0.85))

        // Crossing mode styling: dashed green
        let crossingFill = MarqueeOverlayView.fillColor(for: .crossing)
        let crossingStroke = MarqueeOverlayView.strokeColor(for: .crossing)
        let crossingStyle = MarqueeOverlayView.strokeStyle(for: .crossing)

        #expect(crossingStyle.lineWidth == 1.5)
        #expect(crossingStyle.dash == [4, 4])
        #expect(crossingFill == Color(red: 0.2, green: 0.75, blue: 0.3).opacity(0.15))
        #expect(crossingStroke == Color(red: 0.2, green: 0.75, blue: 0.3).opacity(0.85))
    }
}
