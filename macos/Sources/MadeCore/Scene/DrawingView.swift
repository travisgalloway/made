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
    case section
    case detail
    case auxiliary
    case broken

    public var displayName: String {
        switch self {
        case .base: return "Base"
        case .projected: return "Projected"
        case .section: return "Section"
        case .detail: return "Detail"
        case .auxiliary: return "Auxiliary"
        case .broken: return "Broken"
        }
    }
}

/// Cutting plane line definition for section views.
public struct SectionLineDefinition: Sendable, Codable, Equatable {
    public var label: String
    public var startPointMM: SIMD2<Double>
    public var endPointMM: SIMD2<Double>
    public var arrowDirection: SIMD2<Double>

    public init(
        label: String = "A",
        startPointMM: SIMD2<Double> = SIMD2(-20, 0),
        endPointMM: SIMD2<Double> = SIMD2(20, 0),
        arrowDirection: SIMD2<Double> = SIMD2(0, 1)
    ) {
        self.label = label
        if simd_distance(startPointMM, endPointMM) < 1e-6 {
            self.startPointMM = SIMD2(-20, 0)
            self.endPointMM = SIMD2(20, 0)
        } else {
            self.startPointMM = startPointMM
            self.endPointMM = endPointMM
        }
        let len = simd_length(arrowDirection)
        self.arrowDirection = len > 1e-6 ? arrowDirection / len : SIMD2(0, 1)
    }
}

/// Cross-hatching pattern styles for sectioned regions.
public enum HatchPatternStyle: String, Sendable, Codable, CaseIterable, Equatable {
    case ansi31
    case ansi32
    case crossHatch
    case solid

    public var displayName: String {
        switch self {
        case .ansi31: return "ANSI31 (Cast Iron)"
        case .ansi32: return "ANSI32 (Steel)"
        case .crossHatch: return "Cross Hatch"
        case .solid: return "Solid"
        }
    }
}

/// Hatch pattern configuration controlling angle, spacing, and stroke style.
public struct HatchPatternDefinition: Sendable, Codable, Equatable {
    public var style: HatchPatternStyle
    public var angleDegrees: Double
    public var spacingMM: Double

    public init(
        style: HatchPatternStyle = .ansi31,
        angleDegrees: Double = 45.0,
        spacingMM: Double = 3.0
    ) {
        self.style = style
        self.angleDegrees = angleDegrees
        self.spacingMM = max(0.5, spacingMM)
    }

    public static let standard = HatchPatternDefinition()
}

/// Circular callout boundary definition for detail views.
public struct DetailCircleDefinition: Sendable, Codable, Equatable {
    public var label: String
    public var centerMM: SIMD2<Double>
    public var radiusMM: Double

    public init(
        label: String = "B",
        centerMM: SIMD2<Double> = .zero,
        radiusMM: Double = 15.0
    ) {
        self.label = label
        self.centerMM = centerMM
        self.radiusMM = max(1.0, radiusMM)
    }
}

/// Custom projection angle and direction definition for auxiliary views.
public struct AuxiliaryViewDefinition: Sendable, Codable, Equatable {
    public var label: String
    public var angleDegrees: Double
    public var customDirection: SIMD3<Double>?

    public init(
        label: String = "C",
        angleDegrees: Double = 45.0,
        customDirection: SIMD3<Double>? = nil
    ) {
        self.label = label
        self.angleDegrees = angleDegrees
        self.customDirection = customDirection
    }
}

/// Break view orientation axis.
public enum BreakOrientation: String, Sendable, Codable, CaseIterable, Equatable {
    case horizontal
    case vertical

    public var displayName: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

/// Graphical style for break boundary lines.
public enum BreakLineStyle: String, Sendable, Codable, CaseIterable, Equatable {
    case straight
    case zigzag
    case wavy

    public var displayName: String {
        switch self {
        case .straight: return "Straight"
        case .zigzag: return "Zigzag"
        case .wavy: return "Wavy"
        }
    }
}

/// Configuration defining an interrupted view region.
public struct BreakViewDefinition: Sendable, Codable, Equatable {
    public var orientation: BreakOrientation
    public var startMM: Double
    public var endMM: Double
    public var gapMM: Double
    public var style: BreakLineStyle

    public init(
        orientation: BreakOrientation = .horizontal,
        startMM: Double = -10.0,
        endMM: Double = 10.0,
        gapMM: Double = 5.0,
        style: BreakLineStyle = .zigzag
    ) {
        self.orientation = orientation
        self.startMM = min(startMM, endMM)
        self.endMM = max(startMM, endMM)
        self.gapMM = max(1.0, gapMM)
        self.style = style
    }

    public var breakSpan: Double {
        max(0.0, endMM - startMM)
    }

    public var compressionOffset: Double {
        max(0.0, breakSpan - gapMM)
    }
}

/// Auxiliary viewing direction derivation helper.
public enum DrawingAuxiliaryDerivation {
    public static func deriveDirection(from baseDirection: SIMD3<Double>, angleDegrees: Double) -> SIMD3<Double> {
        guard simd_length(baseDirection) >= 1e-9 else {
            return SIMD3<Double>(0, 0, 1)
        }
        let dir = simd_normalize(baseDirection)
        let rad = angleDegrees * .pi / 180.0
        if abs(sin(rad)) < 1e-9 && cos(rad) > 0 {
            return dir
        }

        let tempUp = abs(dir.z) > 0.99 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(0, 0, 1)
        let right = simd_normalize(simd_cross(dir, tempUp))
        let up = simd_normalize(simd_cross(right, dir))

        let rotated = dir * cos(rad) - up * sin(rad)
        let len = simd_length(rotated)
        return len > 1e-9 ? rotated / len : dir
    }
}

/// Circular edge clipping processor for detail views.
public enum DrawingDetailProcessor {
    public static func clipEdgesToCircle(
        edges: [HLREdge],
        centerMM: SIMD2<Double>,
        radiusMM: Double
    ) -> [HLREdge] {
        let r = max(1.0, radiusMM)
        let rSq = r * r
        var clippedEdges: [HLREdge] = []

        for edge in edges {
            guard edge.points2D.count >= 2 else { continue }
            let shiftedPoints = edge.points2D.map { $0 - centerMM }

            for i in 0..<(shiftedPoints.count - 1) {
                let p1 = shiftedPoints[i]
                let p2 = shiftedPoints[i + 1]
                let d = p2 - p1
                let dLenSq = simd_length_squared(d)

                if dLenSq < 1e-12 {
                    if simd_length_squared(p1) <= rSq {
                        clippedEdges.append(HLREdge(category: edge.category, points2D: [p1, p1]))
                    }
                    continue
                }

                let a = dLenSq
                let b = 2.0 * simd_dot(p1, d)
                let c = simd_length_squared(p1) - rSq

                let disc = b * b - 4.0 * a * c
                if disc < 0 {
                    continue
                }

                let sqrtDisc = sqrt(disc)
                let t1 = (-b - sqrtDisc) / (2.0 * a)
                let t2 = (-b + sqrtDisc) / (2.0 * a)

                let tEnter = max(0.0, min(t1, t2))
                let tExit = min(1.0, max(t1, t2))

                if tEnter < tExit {
                    let ptStart = p1 + d * tEnter
                    let ptEnd = p1 + d * tExit
                    clippedEdges.append(HLREdge(category: edge.category, points2D: [ptStart, ptEnd]))
                }
            }
        }

        return clippedEdges
    }
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
    public var sectionDefinition: SectionLineDefinition?
    public var hatchPattern: HatchPatternDefinition?
    public var detailDefinition: DetailCircleDefinition?
    public var auxiliaryDefinition: AuxiliaryViewDefinition?
    public var breakDefinition: BreakViewDefinition?
    public var customViewDirection: SIMD3<Double>?

    public var effectiveViewDirection: SIMD3<Double> {
        if let custom = customViewDirection, simd_length(custom) > 1e-6 {
            return simd_normalize(custom)
        }
        return standardView.direction
    }

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
        customProperties: [String: String] = [:],
        sectionDefinition: SectionLineDefinition? = nil,
        hatchPattern: HatchPatternDefinition? = nil,
        detailDefinition: DetailCircleDefinition? = nil,
        auxiliaryDefinition: AuxiliaryViewDefinition? = nil,
        breakDefinition: BreakViewDefinition? = nil,
        customViewDirection: SIMD3<Double>? = nil
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
        self.sectionDefinition = sectionDefinition
        self.hatchPattern = hatchPattern
        self.detailDefinition = detailDefinition
        self.auxiliaryDefinition = auxiliaryDefinition
        self.breakDefinition = breakDefinition
        self.customViewDirection = customViewDirection
    }

    public static func clipEdgesToCircle(
        edges: [HLREdge],
        centerMM: SIMD2<Double>,
        radiusMM: Double
    ) -> [HLREdge] {
        DrawingDetailProcessor.clipEdgesToCircle(edges: edges, centerMM: centerMM, radiusMM: radiusMM)
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
