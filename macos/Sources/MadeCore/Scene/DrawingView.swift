import Foundation
import simd

/// Standard orthographic projection conventions for engineering drawings.
public enum DrawingProjectionAngle: String, Sendable, Codable, CaseIterable, Equatable {
    case firstAngle
    case thirdAngle

    public var displayName: String {
        switch self {
        case .firstAngle:
            return "First Angle (ISO)"
        case .thirdAngle:
            return "Third Angle (ANSI)"
        }
    }

    /// Derives the projected standard viewing direction given a base view and projection direction.
    public func projectedView(from base: HLRStandardView, direction: ProjectionDirection) -> HLRStandardView {
        let thirdAngleView = Self.thirdAngleDerived(from: base, direction: direction)
        switch self {
        case .thirdAngle:
            return thirdAngleView
        case .firstAngle:
            return thirdAngleView.opposite
        }
    }

    private static func thirdAngleDerived(from base: HLRStandardView, direction: ProjectionDirection) -> HLRStandardView {
        switch base {
        case .front:
            switch direction {
            case .right: return .right
            case .left: return .left
            case .above: return .top
            case .below: return .bottom
            case .isometricTopRight: return .isometricNE
            case .isometricTopLeft: return .isometricNW
            case .isometricBottomRight: return .isometricSE
            case .isometricBottomLeft: return .isometricSW
            }
        case .top:
            switch direction {
            case .right: return .right
            case .left: return .left
            case .above: return .back
            case .below: return .front
            case .isometricTopRight: return .isometricNE
            case .isometricTopLeft: return .isometricNW
            case .isometricBottomRight: return .isometricSE
            case .isometricBottomLeft: return .isometricSW
            }
        case .bottom:
            switch direction {
            case .right: return .right
            case .left: return .left
            case .above: return .front
            case .below: return .back
            case .isometricTopRight: return .isometricNE
            case .isometricTopLeft: return .isometricNW
            case .isometricBottomRight: return .isometricSE
            case .isometricBottomLeft: return .isometricSW
            }
        case .back:
            switch direction {
            case .right: return .left
            case .left: return .right
            case .above: return .top
            case .below: return .bottom
            case .isometricTopRight: return .isometricNW
            case .isometricTopLeft: return .isometricNE
            case .isometricBottomRight: return .isometricSW
            case .isometricBottomLeft: return .isometricSE
            }
        case .right:
            switch direction {
            case .right: return .back
            case .left: return .front
            case .above: return .top
            case .below: return .bottom
            case .isometricTopRight: return .isometricNE
            case .isometricTopLeft: return .isometricNW
            case .isometricBottomRight: return .isometricSE
            case .isometricBottomLeft: return .isometricSW
            }
        case .left:
            switch direction {
            case .right: return .front
            case .left: return .back
            case .above: return .top
            case .below: return .bottom
            case .isometricTopRight: return .isometricNE
            case .isometricTopLeft: return .isometricNW
            case .isometricBottomRight: return .isometricSE
            case .isometricBottomLeft: return .isometricSW
            }
        case .isometric, .isometricNE, .isometricNW, .isometricSE, .isometricSW:
            switch direction {
            case .right: return .right
            case .left: return .left
            case .above: return .top
            case .below: return .bottom
            case .isometricTopRight: return .isometricNE
            case .isometricTopLeft: return .isometricNW
            case .isometricBottomRight: return .isometricSE
            case .isometricBottomLeft: return .isometricSW
            }
        }
    }
}

/// Relative projection placement direction on the 2D drawing sheet.
public enum ProjectionDirection: String, Sendable, Codable, CaseIterable, Equatable {
    case right
    case left
    case above
    case below
    case isometricTopRight
    case isometricTopLeft
    case isometricBottomRight
    case isometricBottomLeft

    public var displayName: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .above: return "Above"
        case .below: return "Below"
        case .isometricTopRight: return "Isometric Top-Right"
        case .isometricTopLeft: return "Isometric Top-Left"
        case .isometricBottomRight: return "Isometric Bottom-Right"
        case .isometricBottomLeft: return "Isometric Bottom-Left"
        }
    }

    /// Default coordinate offset in millimeters relative to parent view center.
    public func offset(distance: Double) -> SIMD2<Double> {
        switch self {
        case .right: return SIMD2<Double>(distance, 0)
        case .left: return SIMD2<Double>(-distance, 0)
        case .above: return SIMD2<Double>(0, -distance)
        case .below: return SIMD2<Double>(0, distance)
        case .isometricTopRight: return SIMD2<Double>(distance, -distance)
        case .isometricTopLeft: return SIMD2<Double>(-distance, -distance)
        case .isometricBottomRight: return SIMD2<Double>(distance, distance)
        case .isometricBottomLeft: return SIMD2<Double>(-distance, distance)
        }
    }
}

/// Display styles controlling hidden line removal filtering for 2D drawing views.
public enum DrawingDisplayStyle: String, Sendable, Codable, CaseIterable, Equatable {
    case visibleLinesOnly
    case hiddenLinesVisible
    case shaded

    public var displayName: String {
        switch self {
        case .visibleLinesOnly: return "Visible Lines Only"
        case .hiddenLinesVisible: return "Hidden Lines Visible"
        case .shaded: return "Shaded"
        }
    }

    public var hlrOptions: HLROptions {
        switch self {
        case .visibleLinesOnly:
            return HLROptions(includeHidden: false, includeTangent: true, includeSilhouette: true)
        case .hiddenLinesVisible:
            return HLROptions(includeHidden: true, includeTangent: true, includeSilhouette: true)
        case .shaded:
            return HLROptions(includeHidden: false, includeTangent: true, includeSilhouette: true)
        }
    }
}

/// Ratio-based scale configuration for drawing views and sheets.
public struct DrawingViewScale: Sendable, Codable, Equatable, Hashable {
    public var numerator: Double
    public var denominator: Double

    public init(numerator: Double, denominator: Double) {
        self.numerator = max(1e-4, numerator)
        self.denominator = max(1e-4, denominator)
    }

    public init(_ numerator: Double, _ denominator: Double) {
        self.init(numerator: numerator, denominator: denominator)
    }

    public static let tenth = DrawingViewScale(1, 10)
    public static let fifth = DrawingViewScale(1, 5)
    public static let half = DrawingViewScale(1, 2)
    public static let full = DrawingViewScale(1, 1)
    public static let double = DrawingViewScale(2, 1)
    public static let quintuple = DrawingViewScale(5, 1)

    public static let standardScales: [DrawingViewScale] = [
        .tenth, .fifth, .half, .full, .double, .quintuple
    ]

    public var scaleFactor: Double {
        numerator / denominator
    }

    public var displayString: String {
        let isNumInteger = abs(numerator.rounded() - numerator) < 1e-6
        let isDenInteger = abs(denominator.rounded() - denominator) < 1e-6
        if isNumInteger && isDenInteger {
            return "\(Int(round(numerator))):\(Int(round(denominator)))"
        } else {
            let numStr = String(format: "%g", numerator)
            let denStr = String(format: "%g", denominator)
            return "\(numStr):\(denStr)"
        }
    }

    public static func parse(_ string: String) -> DrawingViewScale? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let separators: [Character] = [":", "/"]
        for sep in separators {
            if trimmed.contains(sep) {
                let parts = trimmed.split(separator: sep, maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count == 2,
                      let num = Double(parts[0]),
                      let den = Double(parts[1]),
                      num > 0, den > 0 else {
                    return nil
                }
                return DrawingViewScale(numerator: num, denominator: den)
            }
        }

        if let singleVal = Double(trimmed), singleVal > 0 {
            return DrawingViewScale(numerator: singleVal, denominator: 1.0)
        }

        return nil
    }
}

/// Category classification of a drawing view.
public enum DrawingViewKind: String, Sendable, Codable, CaseIterable, Equatable {
    case base
    case projected
}

/// Represents an individual 2D drawing view placed on a drawing sheet.
public struct DrawingView: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var kind: DrawingViewKind
    public var standardView: HLRStandardView
    public var parentViewId: UUID?
    public var projectionDirection: ProjectionDirection?
    public var positionMM: SIMD2<Double>
    public var scale: DrawingViewScale
    public var displayStyle: DrawingDisplayStyle
    public var projectionAngle: DrawingProjectionAngle?
    public var cachedHLR: HLRResult?
    public var customProperties: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        kind: DrawingViewKind = .base,
        standardView: HLRStandardView = .front,
        parentViewId: UUID? = nil,
        projectionDirection: ProjectionDirection? = nil,
        positionMM: SIMD2<Double> = SIMD2<Double>(100, 100),
        scale: DrawingViewScale = .full,
        displayStyle: DrawingDisplayStyle = .visibleLinesOnly,
        projectionAngle: DrawingProjectionAngle? = nil,
        cachedHLR: HLRResult? = nil,
        customProperties: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.standardView = standardView
        self.parentViewId = parentViewId
        self.projectionDirection = projectionDirection
        self.positionMM = positionMM
        self.scale = scale
        self.displayStyle = displayStyle
        self.projectionAngle = projectionAngle
        self.cachedHLR = cachedHLR
        self.customProperties = customProperties
    }
}

public extension HLRStandardView {
    /// Opposite viewing direction for first-angle derivation and camera transformations.
    var opposite: HLRStandardView {
        switch self {
        case .top: return .bottom
        case .bottom: return .top
        case .front: return .back
        case .back: return .front
        case .right: return .left
        case .left: return .right
        case .isometric, .isometricNE: return .isometricSW
        case .isometricNW: return .isometricSE
        case .isometricSE: return .isometricNW
        case .isometricSW: return .isometricNE
        }
    }
}
