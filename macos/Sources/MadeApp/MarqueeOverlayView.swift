import SwiftUI
import MadeCore

/// Non-interactive viewport overlay rendering the active box or lasso selection marquee.
public struct MarqueeOverlayView: View {
    public let marquee: MarqueeState

    public init(marquee: MarqueeState) {
        self.marquee = marquee
    }

    public var body: some View {
        GeometryReader { geometry in
            let path = Self.path(for: marquee, viewportHeight: geometry.size.height)
            ZStack {
                path
                    .fill(Self.fillColor(for: marquee.mode))
                path
                    .stroke(
                        Self.strokeColor(for: marquee.mode),
                        style: Self.strokeStyle(for: marquee.mode)
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("marquee-overlay")
    }

    /// Generates the 2D SwiftUI Path for the marquee, converting Metal viewport coordinates to SwiftUI canvas coordinates.
    nonisolated public static func path(for marquee: MarqueeState, viewportHeight: CGFloat? = nil) -> Path {
        func convert(_ pt: CGPoint) -> CGPoint {
            if let vh = viewportHeight, vh > 0 {
                return CGPoint(x: pt.x, y: vh - pt.y)
            }
            return pt
        }

        switch marquee.shape {
        case .box:
            let start = convert(marquee.startPoint)
            let current = convert(marquee.currentPoint)
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            return Path(rect)

        case .lasso:
            var path = Path()
            guard !marquee.points.isEmpty else { return path }
            let converted = marquee.points.map(convert)
            path.addLines(converted)
            path.closeSubpath()
            return path
        }
    }

    /// Background translucent fill color based on marquee mode.
    nonisolated public static func fillColor(for mode: MarqueeMode) -> Color {
        switch mode {
        case .window:
            return Color(red: 0.15, green: 0.45, blue: 0.95).opacity(0.15)
        case .crossing:
            return Color(red: 0.2, green: 0.75, blue: 0.3).opacity(0.15)
        }
    }

    /// Foreground border stroke color based on marquee mode.
    nonisolated public static func strokeColor(for mode: MarqueeMode) -> Color {
        switch mode {
        case .window:
            return Color(red: 0.15, green: 0.45, blue: 0.95).opacity(0.85)
        case .crossing:
            return Color(red: 0.2, green: 0.75, blue: 0.3).opacity(0.85)
        }
    }

    /// Border stroke style (solid for window, dashed for crossing).
    nonisolated public static func strokeStyle(for mode: MarqueeMode) -> StrokeStyle {
        switch mode {
        case .window:
            return StrokeStyle(lineWidth: 1.5)
        case .crossing:
            return StrokeStyle(lineWidth: 1.5, dash: [4, 4])
        }
    }
}
