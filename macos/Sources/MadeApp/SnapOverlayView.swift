import SwiftUI
import MadeCore

// MARK: - CAD Snap Glyph Vector Shapes

public struct EndpointSquareShape: Shape, Sendable {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        Path(rect)
    }
}

public struct MidpointTriangleShape: Shape, Sendable {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

public struct CenterCircleCrossShape: Shape, Sendable {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: rect)
        p.move(to: CGPoint(x: rect.midX, y: rect.minY - 2))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + 2))
        p.move(to: CGPoint(x: rect.minX - 2, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX + 2, y: rect.midY))
        return p
    }
}

public struct IntersectionXShape: Shape, Sendable {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

public struct QuadrantDiamondShape: Shape, Sendable {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

public struct GridPlusShape: Shape, Sendable {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

public struct EdgeBarsShape: Shape, Sendable {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX - 2, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY))
        return p
    }
}

// MARK: - SnapOverlayView

/// Renders CAD visual glyphs and high-contrast text badges at screen coordinates for active snapping feedback.
public struct SnapOverlayView: View {
    public let snap: SnapResult

    public init(snap: SnapResult) {
        self.snap = snap
    }

    nonisolated public static func color(for kind: SnapKind) -> Color {
        switch kind {
        case .endpoint:
            return Color(red: 0.0, green: 0.8, blue: 0.4) // Emerald
        case .vertex:
            return Color.orange // Amber
        case .center:
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        case .intersection:
            return Color(red: 0.95, green: 0.2, blue: 0.2) // Red
        case .midpoint:
            return Color.cyan
        case .quadrant:
            return Color(red: 0.7, green: 0.3, blue: 0.9) // Purple
        case .edge:
            return Color.cyan
        case .grid:
            return Color(red: 0.2, green: 0.9, blue: 0.2) // Green
        }
    }

    nonisolated public static func badgeText(for kind: SnapKind) -> String {
        kind.rawValue.capitalized
    }

    /// Converts Metal/AppKit bottom-left screen coordinates to SwiftUI top-left canvas coordinates.
    nonisolated public static func canvasPosition(screenPoint: SIMD2<Float>, viewportHeight: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(screenPoint.x), y: viewportHeight - CGFloat(screenPoint.y))
    }

    @ViewBuilder
    public static func glyphView(for kind: SnapKind, color: Color) -> some View {
        Group {
            switch kind {
            case .endpoint, .vertex:
                EndpointSquareShape()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            case .midpoint:
                MidpointTriangleShape()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 12, height: 10)
            case .center:
                CenterCircleCrossShape()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            case .intersection:
                IntersectionXShape()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            case .quadrant:
                QuadrantDiamondShape()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            case .edge:
                EdgeBarsShape()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            case .grid:
                GridPlusShape()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
            }
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            if let screenPoint = snap.screenPoint {
                let pos = Self.canvasPosition(screenPoint: screenPoint, viewportHeight: geometry.size.height)
                let snapColor = Self.color(for: snap.kind)
                let text = Self.badgeText(for: snap.kind)

                ZStack {
                    Self.glyphView(for: snap.kind, color: snapColor)
                        .position(x: pos.x, y: pos.y)

                    HStack(spacing: 3) {
                        Circle()
                            .fill(snapColor)
                            .frame(width: 4, height: 4)
                        Text(text)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                            .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                    )
                    .position(x: pos.x + 36, y: max(16, pos.y - 14))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("snap-overlay-view")
    }
}
