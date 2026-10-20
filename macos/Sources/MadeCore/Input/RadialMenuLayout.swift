import Foundation
import CoreGraphics

public enum RadialCommandKind: String, Sendable, CaseIterable, Equatable {
    case delete
    case hide
    case lock
    case duplicate
    case addBox
    case addCylinder
}

public struct RadialMenuItem: Sendable, Equatable, Identifiable {
    public let id: RadialCommandKind
    public let title: String
    public let iconName: String
    public let isDestructive: Bool

    public init(
        id: RadialCommandKind,
        title: String,
        iconName: String,
        isDestructive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.isDestructive = isDestructive
    }
}

public struct RadialMenuLayout: Sendable, Equatable {
    public let menuRadius: CGFloat
    public let itemRadius: CGFloat
    public let margin: CGFloat

    public var effectiveRadius: CGFloat {
        menuRadius + itemRadius + margin
    }

    public init(
        menuRadius: CGFloat = 54.0,
        itemRadius: CGFloat = 22.0,
        margin: CGFloat = 8.0
    ) {
        self.menuRadius = menuRadius
        self.itemRadius = itemRadius
        self.margin = margin
    }

    public func clampedCenter(pointer: CGPoint, viewportSize: CGSize) -> CGPoint {
        let eff = effectiveRadius
        let x: CGFloat
        if viewportSize.width < 2 * eff {
            x = viewportSize.width / 2.0
        } else {
            x = min(max(pointer.x, eff), viewportSize.width - eff)
        }

        let y: CGFloat
        if viewportSize.height < 2 * eff {
            y = viewportSize.height / 2.0
        } else {
            y = min(max(pointer.y, eff), viewportSize.height - eff)
        }

        return CGPoint(x: x, y: y)
    }

    public func itemAngle(index: Int, count: Int, startAngle: CGFloat = -.pi / 2) -> CGFloat {
        guard count > 0 else { return startAngle }
        let step = (2.0 * CGFloat.pi) / CGFloat(count)
        return startAngle + CGFloat(index) * step
    }

    public func itemPosition(center: CGPoint, index: Int, count: Int, startAngle: CGFloat = -.pi / 2) -> CGPoint {
        let angle = itemAngle(index: index, count: count, startAngle: startAngle)
        return CGPoint(
            x: center.x + menuRadius * cos(angle),
            y: center.y + menuRadius * sin(angle)
        )
    }
}
