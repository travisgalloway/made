import Foundation
import simd

/// Classification of drawing annotations supported on 2D drawing sheets and views (BL-DRW-05).
public enum DrawingAnnotationKind: String, Sendable, Codable, CaseIterable {
    case linear
    case angular
    case radial
    case ordinate
    case baseline
    case note
    case leader
    case centerMark
    case centerline
    case holeCallout
    case balloon

    public var displayName: String {
        switch self {
        case .linear:
            return "Linear Dimension"
        case .angular:
            return "Angular Dimension"
        case .radial:
            return "Radial Dimension"
        case .ordinate:
            return "Ordinate Dimension"
        case .baseline:
            return "Baseline Dimension"
        case .note:
            return "Note"
        case .leader:
            return "Leader"
        case .centerMark:
            return "Center Mark"
        case .centerline:
            return "Centerline"
        case .holeCallout:
            return "Hole Callout"
        case .balloon:
            return "Balloon"
        }
    }
}

/// Measurement orientation for linear dimensions.
public enum LinearDimensionOrientation: String, Sendable, Codable, CaseIterable {
    case aligned
    case horizontal
    case vertical

    public var displayName: String {
        switch self {
        case .aligned:
            return "Aligned"
        case .horizontal:
            return "Horizontal"
        case .vertical:
            return "Vertical"
        }
    }
}

/// Axis orientation for ordinate dimensions.
public enum OrdinateDimensionAxis: String, Sendable, Codable, CaseIterable {
    case x
    case y

    public var displayName: String {
        switch self {
        case .x:
            return "X Axis"
        case .y:
            return "Y Axis"
        }
    }
}

/// Payload data for linear dimensions.
public struct LinearDimensionData: Sendable, Codable, Equatable {
    public var startPointMM: SIMD2<Double>
    public var endPointMM: SIMD2<Double>
    public var offsetMM: Double
    public var orientation: LinearDimensionOrientation
    public var prefix: String
    public var suffix: String
    public var textOverride: String?
    public var precision: Int
    public var tolerance: DimensionTolerance?

    public init(
        startPointMM: SIMD2<Double>,
        endPointMM: SIMD2<Double>,
        offsetMM: Double = 10.0,
        orientation: LinearDimensionOrientation = .aligned,
        prefix: String = "",
        suffix: String = "",
        textOverride: String? = nil,
        precision: Int = 2,
        tolerance: DimensionTolerance? = nil
    ) {
        self.startPointMM = startPointMM
        self.endPointMM = endPointMM
        self.offsetMM = offsetMM
        self.orientation = orientation
        self.prefix = prefix
        self.suffix = suffix
        self.textOverride = textOverride
        self.precision = precision
        self.tolerance = tolerance
    }

    /// Measured distance in millimeters according to the dimension orientation.
    public var measuredValue: Double {
        switch orientation {
        case .aligned:
            return hypot(endPointMM.x - startPointMM.x, endPointMM.y - startPointMM.y)
        case .horizontal:
            return abs(endPointMM.x - startPointMM.x)
        case .vertical:
            return abs(endPointMM.y - startPointMM.y)
        }
    }

    /// Formatted dimension text string using sheet drafting standard settings when provided.
    public func formattedText(using settings: DraftingStandardSettings? = nil) -> String {
        if let textOverride = textOverride, !textOverride.isEmpty {
            return textOverride
        }
        if let settings = settings {
            return settings.formatDimension(
                nominal: measuredValue,
                tolerance: tolerance,
                precision: precision,
                prefix: prefix,
                suffix: suffix
            )
        }
        if let tolerance = tolerance, tolerance.type != .none {
            let defaults = DraftingStandardSettings.ansi
            return defaults.formatDimension(
                nominal: measuredValue,
                tolerance: tolerance,
                precision: precision,
                prefix: prefix,
                suffix: suffix
            )
        }
        let clampedPrecision = max(0, min(6, precision))
        let numStr = String(format: "%.\(clampedPrecision)f", measuredValue)
        return "\(prefix)\(numStr)\(suffix)"
    }

    /// Default formatted dimension text string.
    public var formattedText: String {
        formattedText(using: nil)
    }
}

/// Payload data for angular dimensions measuring vertex angles.
public struct AngularDimensionData: Sendable, Codable, Equatable {
    public var vertexMM: SIMD2<Double>
    public var startPointMM: SIMD2<Double>
    public var endPointMM: SIMD2<Double>
    public var arcRadiusMM: Double
    public var prefix: String
    public var suffix: String
    public var textOverride: String?
    public var precision: Int
    public var tolerance: DimensionTolerance?

    public init(
        vertexMM: SIMD2<Double>,
        startPointMM: SIMD2<Double>,
        endPointMM: SIMD2<Double>,
        arcRadiusMM: Double = 15.0,
        prefix: String = "",
        suffix: String = "",
        textOverride: String? = nil,
        precision: Int = 1,
        tolerance: DimensionTolerance? = nil
    ) {
        self.vertexMM = vertexMM
        self.startPointMM = startPointMM
        self.endPointMM = endPointMM
        self.arcRadiusMM = arcRadiusMM
        self.prefix = prefix
        self.suffix = suffix
        self.textOverride = textOverride
        self.precision = precision
        self.tolerance = tolerance
    }

    /// Measured angle in degrees between start ray and end ray.
    public var measuredDegrees: Double {
        let v1 = startPointMM - vertexMM
        let v2 = endPointMM - vertexMM
        let len1 = hypot(v1.x, v1.y)
        let len2 = hypot(v2.x, v2.y)
        guard len1 > 1e-9, len2 > 1e-9 else { return 0.0 }
        let dot = (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)
        let clamped = max(-1.0, min(1.0, dot))
        let radians = acos(clamped)
        return radians * 180.0 / .pi
    }

    /// Formatted angular dimension text string using sheet drafting standard settings when provided.
    public func formattedText(using settings: DraftingStandardSettings? = nil) -> String {
        if let textOverride = textOverride, !textOverride.isEmpty {
            return textOverride
        }
        let degSuffix = "°\(suffix)"
        if let settings = settings {
            return settings.formatDimension(
                nominal: measuredDegrees,
                tolerance: tolerance,
                precision: precision,
                prefix: prefix,
                suffix: degSuffix
            )
        }
        if let tolerance = tolerance, tolerance.type != .none {
            let defaults = DraftingStandardSettings.ansi
            return defaults.formatDimension(
                nominal: measuredDegrees,
                tolerance: tolerance,
                precision: precision,
                prefix: prefix,
                suffix: degSuffix
            )
        }
        let clampedPrecision = max(0, min(6, precision))
        let numStr = String(format: "%.\(clampedPrecision)f", measuredDegrees)
        return "\(prefix)\(numStr)°\(suffix)"
    }

    /// Default formatted angular dimension text string.
    public var formattedText: String {
        formattedText(using: nil)
    }
}

/// Payload data for radial and diameter dimensions.
public struct RadialDimensionData: Sendable, Codable, Equatable {
    public var centerMM: SIMD2<Double>
    public var arcPointMM: SIMD2<Double>
    public var isDiameter: Bool
    public var leaderOffsetMM: Double
    public var prefix: String
    public var suffix: String
    public var textOverride: String?
    public var precision: Int
    public var tolerance: DimensionTolerance?

    public init(
        centerMM: SIMD2<Double>,
        arcPointMM: SIMD2<Double>,
        isDiameter: Bool = false,
        leaderOffsetMM: Double = 15.0,
        prefix: String = "",
        suffix: String = "",
        textOverride: String? = nil,
        precision: Int = 2,
        tolerance: DimensionTolerance? = nil
    ) {
        self.centerMM = centerMM
        self.arcPointMM = arcPointMM
        self.isDiameter = isDiameter
        self.leaderOffsetMM = leaderOffsetMM
        self.prefix = prefix
        self.suffix = suffix
        self.textOverride = textOverride
        self.precision = precision
        self.tolerance = tolerance
    }

    /// Measured radius or diameter in millimeters.
    public var measuredValue: Double {
        let radius = hypot(arcPointMM.x - centerMM.x, arcPointMM.y - centerMM.y)
        return isDiameter ? (radius * 2.0) : radius
    }

    /// Formatted radial or diameter dimension text using sheet drafting standard settings when provided.
    public func formattedText(using settings: DraftingStandardSettings? = nil) -> String {
        if let textOverride = textOverride, !textOverride.isEmpty {
            return textOverride
        }
        let defaultSymbol = isDiameter ? "Ø" : "R"
        let effectivePrefix = prefix.isEmpty ? defaultSymbol : prefix
        if let settings = settings {
            return settings.formatDimension(
                nominal: measuredValue,
                tolerance: tolerance,
                precision: precision,
                prefix: effectivePrefix,
                suffix: suffix
            )
        }
        if let tolerance = tolerance, tolerance.type != .none {
            let defaults = DraftingStandardSettings.ansi
            return defaults.formatDimension(
                nominal: measuredValue,
                tolerance: tolerance,
                precision: precision,
                prefix: effectivePrefix,
                suffix: suffix
            )
        }
        let clampedPrecision = max(0, min(6, precision))
        let numStr = String(format: "%.\(clampedPrecision)f", measuredValue)
        return "\(effectivePrefix)\(numStr)\(suffix)"
    }

    /// Default formatted radial or diameter dimension text.
    public var formattedText: String {
        formattedText(using: nil)
    }
}

/// Payload data for ordinate dimensions referencing a baseline datum.
public struct OrdinateDimensionData: Sendable, Codable, Equatable {
    public var datumOriginMM: SIMD2<Double>
    public var locationMM: SIMD2<Double>
    public var axis: OrdinateDimensionAxis
    public var jogOffsetMM: Double
    public var prefix: String
    public var suffix: String
    public var textOverride: String?
    public var precision: Int
    public var tolerance: DimensionTolerance?

    public init(
        datumOriginMM: SIMD2<Double>,
        locationMM: SIMD2<Double>,
        axis: OrdinateDimensionAxis = .x,
        jogOffsetMM: Double = 12.0,
        prefix: String = "",
        suffix: String = "",
        textOverride: String? = nil,
        precision: Int = 2,
        tolerance: DimensionTolerance? = nil
    ) {
        self.datumOriginMM = datumOriginMM
        self.locationMM = locationMM
        self.axis = axis
        self.jogOffsetMM = jogOffsetMM
        self.prefix = prefix
        self.suffix = suffix
        self.textOverride = textOverride
        self.precision = precision
        self.tolerance = tolerance
    }

    /// Offset distance from datum origin along the measurement axis.
    public var measuredValue: Double {
        switch axis {
        case .x:
            return abs(locationMM.x - datumOriginMM.x)
        case .y:
            return abs(locationMM.y - datumOriginMM.y)
        }
    }

    /// Whether this ordinate dimension represents the origin baseline datum.
    public var isDatum: Bool {
        measuredValue < 1e-6
    }

    /// Formatted ordinate dimension text using sheet drafting standard settings when provided.
    public func formattedText(using settings: DraftingStandardSettings? = nil) -> String {
        if let textOverride = textOverride, !textOverride.isEmpty {
            return textOverride
        }
        if isDatum {
            return "0"
        }
        if let settings = settings {
            return settings.formatDimension(
                nominal: measuredValue,
                tolerance: tolerance,
                precision: precision,
                prefix: prefix,
                suffix: suffix
            )
        }
        if let tolerance = tolerance, tolerance.type != .none {
            let defaults = DraftingStandardSettings.ansi
            return defaults.formatDimension(
                nominal: measuredValue,
                tolerance: tolerance,
                precision: precision,
                prefix: prefix,
                suffix: suffix
            )
        }
        let clampedPrecision = max(0, min(6, precision))
        let numStr = String(format: "%.\(clampedPrecision)f", measuredValue)
        return "\(prefix)\(numStr)\(suffix)"
    }

    /// Default formatted ordinate dimension text.
    public var formattedText: String {
        formattedText(using: nil)
    }
}

/// Payload data for baseline dimensions sharing a common datum reference point.
public struct BaselineDimensionData: Sendable, Codable, Equatable {
    public var basePointMM: SIMD2<Double>
    public var targetPointsMM: [SIMD2<Double>]
    public var stackSpacingMM: Double
    public var initialOffsetMM: Double
    public var orientation: LinearDimensionOrientation
    public var prefix: String
    public var suffix: String
    public var precision: Int
    public var tolerance: DimensionTolerance?

    public init(
        basePointMM: SIMD2<Double>,
        targetPointsMM: [SIMD2<Double>],
        stackSpacingMM: Double = 8.0,
        initialOffsetMM: Double = 10.0,
        orientation: LinearDimensionOrientation = .horizontal,
        prefix: String = "",
        suffix: String = "",
        precision: Int = 2,
        tolerance: DimensionTolerance? = nil
    ) {
        self.basePointMM = basePointMM
        self.targetPointsMM = targetPointsMM
        self.stackSpacingMM = stackSpacingMM
        self.initialOffsetMM = initialOffsetMM
        self.orientation = orientation
        self.prefix = prefix
        self.suffix = suffix
        self.precision = precision
        self.tolerance = tolerance
    }

    /// Measured distance for a specific target point index.
    public func measuredValue(forTargetIndex index: Int) -> Double {
        guard index >= 0 && index < targetPointsMM.count else { return 0.0 }
        let target = targetPointsMM[index]
        switch orientation {
        case .aligned:
            return hypot(target.x - basePointMM.x, target.y - basePointMM.y)
        case .horizontal:
            return abs(target.x - basePointMM.x)
        case .vertical:
            return abs(target.y - basePointMM.y)
        }
    }

    /// Stack offset in millimeters from reference for a target index.
    public func stackOffsetMM(forTargetIndex index: Int) -> Double {
        initialOffsetMM + (Double(index) * stackSpacingMM)
    }

    /// Formatted text string for a specific target point index using sheet drafting standard settings when provided.
    public func formattedText(forTargetIndex index: Int, using settings: DraftingStandardSettings? = nil) -> String {
        let val = measuredValue(forTargetIndex: index)
        if let settings = settings {
            return settings.formatDimension(
                nominal: val,
                tolerance: tolerance,
                precision: precision,
                prefix: prefix,
                suffix: suffix
            )
        }
        if let tolerance = tolerance, tolerance.type != .none {
            let defaults = DraftingStandardSettings.ansi
            return defaults.formatDimension(
                nominal: val,
                tolerance: tolerance,
                precision: precision,
                prefix: prefix,
                suffix: suffix
            )
        }
        let clampedPrecision = max(0, min(6, precision))
        let numStr = String(format: "%.\(clampedPrecision)f", val)
        return "\(prefix)\(numStr)\(suffix)"
    }

    /// Default formatted text string for a specific target point index.
    public func formattedText(forTargetIndex index: Int) -> String {
        formattedText(forTargetIndex: index, using: nil)
    }
}

/// Payload data for multi-line notes placed on drawing sheets.
public struct NoteAnnotationData: Sendable, Codable, Equatable {
    public var positionMM: SIMD2<Double>
    public var text: String
    public var fontSizePt: Double
    public var isBold: Bool
    public var hasBorder: Bool

    public init(
        positionMM: SIMD2<Double>,
        text: String = "NOTE",
        fontSizePt: Double = 10.0,
        isBold: Bool = false,
        hasBorder: Bool = false
    ) {
        self.positionMM = positionMM
        self.text = text
        self.fontSizePt = fontSizePt
        self.isBold = isBold
        self.hasBorder = hasBorder
    }
}

/// Payload data for leader annotations pointing from geometry to descriptive text.
public struct LeaderAnnotationData: Sendable, Codable, Equatable {
    public var arrowPointMM: SIMD2<Double>
    public var elbowPointMM: SIMD2<Double>
    public var text: String
    public var landingLengthMM: Double
    public var fontSizePt: Double

    public init(
        arrowPointMM: SIMD2<Double>,
        elbowPointMM: SIMD2<Double>,
        text: String = "NOTE",
        landingLengthMM: Double = 8.0,
        fontSizePt: Double = 10.0
    ) {
        self.arrowPointMM = arrowPointMM
        self.elbowPointMM = elbowPointMM
        self.text = text
        self.landingLengthMM = landingLengthMM
        self.fontSizePt = fontSizePt
    }
}

/// Payload data for center marks marking hole or arc centers.
public struct CenterMarkData: Sendable, Codable, Equatable {
    public var centerMM: SIMD2<Double>
    public var markSizeMM: Double
    public var extensionMM: Double
    public var rotationDegrees: Double

    public init(
        centerMM: SIMD2<Double>,
        markSizeMM: Double = 5.0,
        extensionMM: Double = 3.0,
        rotationDegrees: Double = 0.0
    ) {
        self.centerMM = centerMM
        self.markSizeMM = markSizeMM
        self.extensionMM = extensionMM
        self.rotationDegrees = rotationDegrees
    }
}

/// Payload data for centerline annotations indicating symmetry axes.
public struct CenterlineData: Sendable, Codable, Equatable {
    public var startPointMM: SIMD2<Double>
    public var endPointMM: SIMD2<Double>
    public var extensionMM: Double

    public init(
        startPointMM: SIMD2<Double>,
        endPointMM: SIMD2<Double>,
        extensionMM: Double = 3.0
    ) {
        self.startPointMM = startPointMM
        self.endPointMM = endPointMM
        self.extensionMM = extensionMM
    }
}

/// Payload data for hole callouts with engineering symbols and Hole Wizard parameters.
public struct HoleCalloutAnnotationData: Sendable, Codable, Equatable {
    public var anchorPointMM: SIMD2<Double>
    public var elbowPointMM: SIMD2<Double>
    public var holeType: HoleType
    public var standard: HoleStandard
    public var sizeDesignation: String?
    public var diameter: Double
    public var depth: Double
    public var isThrough: Bool
    public var counterboreDiameter: Double
    public var counterboreDepth: Double
    public var countersinkDiameter: Double
    public var countersinkAngle: Double
    public var threadDesignation: String?
    public var holeCount: Int
    public var textOverride: String?
    public var landingLengthMM: Double
    public var precision: Int

    public init(
        anchorPointMM: SIMD2<Double>,
        elbowPointMM: SIMD2<Double>,
        holeType: HoleType = .simple,
        standard: HoleStandard = .custom,
        sizeDesignation: String? = nil,
        diameter: Double = 5.0,
        depth: Double = 10.0,
        isThrough: Bool = true,
        counterboreDiameter: Double = 0.0,
        counterboreDepth: Double = 0.0,
        countersinkDiameter: Double = 0.0,
        countersinkAngle: Double = 90.0,
        threadDesignation: String? = nil,
        holeCount: Int = 1,
        textOverride: String? = nil,
        landingLengthMM: Double = 8.0,
        precision: Int = 2
    ) {
        self.anchorPointMM = anchorPointMM
        self.elbowPointMM = elbowPointMM
        self.holeType = holeType
        self.standard = standard
        self.sizeDesignation = sizeDesignation
        self.diameter = diameter
        self.depth = depth
        self.isThrough = isThrough
        self.counterboreDiameter = counterboreDiameter
        self.counterboreDepth = counterboreDepth
        self.countersinkDiameter = countersinkDiameter
        self.countersinkAngle = countersinkAngle
        self.threadDesignation = threadDesignation
        self.holeCount = max(1, holeCount)
        self.textOverride = textOverride
        self.landingLengthMM = landingLengthMM
        self.precision = precision
    }

    /// Convenience initializer populating hole callout parameters directly from a 3D Hole Wizard feature.
    public init(
        anchorPointMM: SIMD2<Double>,
        elbowPointMM: SIMD2<Double>,
        holeParams: HoleParams,
        holeCount: Int = 1,
        landingLengthMM: Double = 8.0,
        precision: Int = 2
    ) {
        let count = holeCount > 0 ? holeCount : max(1, holeParams.points.count)
        let resolvedThread = holeParams.threadMetadata?.designation ?? holeParams.sizeDesignation
        self.init(
            anchorPointMM: anchorPointMM,
            elbowPointMM: elbowPointMM,
            holeType: holeParams.holeType,
            standard: holeParams.standard,
            sizeDesignation: holeParams.sizeDesignation,
            diameter: holeParams.diameter,
            depth: holeParams.depth,
            isThrough: holeParams.isThrough,
            counterboreDiameter: holeParams.counterboreDiameter,
            counterboreDepth: holeParams.counterboreDepth,
            countersinkDiameter: holeParams.countersinkDiameter,
            countersinkAngle: holeParams.countersinkAngle,
            threadDesignation: resolvedThread,
            holeCount: count,
            landingLengthMM: landingLengthMM,
            precision: precision
        )
    }

    /// Formatted callout string lines.
    public var formattedCalloutLines: [String] {
        HoleCalloutFormatter.format(self)
    }

    /// Complete callout text string separated by newlines.
    public var formattedCalloutText: String {
        formattedCalloutLines.joined(separator: "\n")
    }
}

/// Generates standard multi-line engineering callout text using ISO/ASME symbols.
public enum HoleCalloutFormatter {
    private static func formatNumber(_ value: Double, precision: Int) -> String {
        let clampedPrecision = max(0, min(6, precision))
        // Format with precision, trimming trailing zeros after decimal point if whole number or cleaner
        let str = String(format: "%.\(clampedPrecision)f", value)
        if clampedPrecision > 0 && str.contains(".") {
            var trimmed = str
            while trimmed.hasSuffix("0") {
                trimmed.removeLast()
            }
            if trimmed.hasSuffix(".") {
                trimmed.removeLast()
            }
            return trimmed
        }
        return str
    }

    /// Produces formatted callout lines according to engineering drafting conventions.
    public static func format(_ data: HoleCalloutAnnotationData) -> [String] {
        if let override = data.textOverride, !override.isEmpty {
            return override.components(separatedBy: "\n")
        }

        let qtyPrefix = data.holeCount > 1 ? "\(data.holeCount)x " : ""
        let diaStr = formatNumber(data.diameter, precision: data.precision)
        let depthStr = formatNumber(data.depth, precision: data.precision)

        var lines: [String] = []

        switch data.holeType {
        case .simple:
            let depthNote = data.isThrough ? " THRU" : " ↧ \(depthStr)"
            lines.append("\(qtyPrefix)Ø\(diaStr)\(depthNote)")

        case .counterbore:
            let depthNote = data.isThrough ? " THRU" : " ↧ \(depthStr)"
            lines.append("\(qtyPrefix)Ø\(diaStr)\(depthNote)")

            let cbDiaStr = formatNumber(data.counterboreDiameter, precision: data.precision)
            let cbDepthStr = formatNumber(data.counterboreDepth, precision: data.precision)
            lines.append("⌴ Ø\(cbDiaStr) ↧ \(cbDepthStr)")

        case .countersink:
            let depthNote = data.isThrough ? " THRU" : " ↧ \(depthStr)"
            lines.append("\(qtyPrefix)Ø\(diaStr)\(depthNote)")

            let csDiaStr = formatNumber(data.countersinkDiameter, precision: data.precision)
            let csAngleStr = formatNumber(data.countersinkAngle, precision: 1)
            lines.append("⌵ Ø\(csDiaStr) x \(csAngleStr)°")

        case .tapped:
            let thread = data.threadDesignation ?? data.sizeDesignation ?? "M\(diaStr)"
            let depthNote = data.isThrough ? " THRU" : " ↧ \(depthStr)"
            lines.append("\(qtyPrefix)\(thread)\(depthNote)")
            if !data.isThrough {
                lines.append("TAP DRILL Ø\(diaStr)")
            }
        }

        return lines
    }
}

/// Bubble geometry shapes supported for drawing balloon annotations (BL-DRW-08, #215).
public enum BalloonShape: String, Sendable, Codable, CaseIterable {
    case circular
    case splitCircular
    case box
    case hexagon
    case none

    public var displayName: String {
        switch self {
        case .circular: return "Circular"
        case .splitCircular: return "Split Circular"
        case .box: return "Box"
        case .hexagon: return "Hexagon"
        case .none: return "None (Text Only)"
        }
    }
}

/// Payload data for balloon callouts linked to assembly components or parts (BL-DRW-08, #215).
public struct BalloonAnnotationData: Sendable, Codable, Equatable {
    /// Attachment point pointing to the component geometry (view coordinates or sheet mm).
    public var anchorPointMM: SIMD2<Double>
    /// Center of the balloon callout bubble (view coordinates or sheet mm).
    public var balloonCenterMM: SIMD2<Double>
    /// Diameter or bounding size of the balloon callout in millimeters.
    public var sizeMM: Double
    /// Shape style of the balloon callout bubble.
    public var shape: BalloonShape
    /// Item number resolved from BOM or assigned sequentially.
    public var itemNumber: String
    /// Quantity count (e.g. 1 or count from BOM).
    public var quantity: Int
    /// Whether to display quantity in split bubble or suffix.
    public var showQuantity: Bool
    /// Optional manual text override taking precedence over itemNumber.
    public var textOverride: String?
    /// UUID of the linked component instance in the assembly document model.
    public var componentInstanceId: UUID?
    /// Cached component name for display or fallback reference.
    public var componentName: String?

    public init(
        anchorPointMM: SIMD2<Double>,
        balloonCenterMM: SIMD2<Double>,
        sizeMM: Double = 10.0,
        shape: BalloonShape = .circular,
        itemNumber: String = "1",
        quantity: Int = 1,
        showQuantity: Bool = false,
        textOverride: String? = nil,
        componentInstanceId: UUID? = nil,
        componentName: String? = nil
    ) {
        self.anchorPointMM = anchorPointMM
        self.balloonCenterMM = balloonCenterMM
        self.sizeMM = max(5.0, sizeMM)
        self.shape = shape
        self.itemNumber = itemNumber
        self.quantity = max(1, quantity)
        self.showQuantity = showQuantity
        self.textOverride = textOverride
        self.componentInstanceId = componentInstanceId
        self.componentName = componentName
    }

    /// Formatted primary text string (override or itemNumber).
    public var formattedText: String {
        if let textOverride, !textOverride.isEmpty {
            return textOverride
        }
        return itemNumber
    }

    /// Formatted secondary quantity text.
    public var formattedQuantityText: String {
        "\(quantity)"
    }

    /// Computes the intersection point on the outer boundary of the balloon shape where the leader line terminates.
    /// Handles degenerate coincident points safely by applying a minimum offset.
    public func boundaryContactPointMM() -> SIMD2<Double> {
        Self.boundaryContactPointMM(centerMM: balloonCenterMM, anchorMM: anchorPointMM, sizeMM: sizeMM)
    }

    public static func boundaryContactPointMM(
        centerMM: SIMD2<Double>,
        anchorMM: SIMD2<Double>,
        sizeMM: Double
    ) -> SIMD2<Double> {
        let radius = max(2.5, sizeMM * 0.5)
        let delta = anchorMM - centerMM
        let dist = hypot(delta.x, delta.y)
        if dist < 1e-6 {
            // Degenerate case: anchor and center coincide; return point offset along default axis to prevent NaN
            return SIMD2<Double>(centerMM.x - radius, centerMM.y)
        }
        let dir = delta / dist
        return centerMM + (dir * radius)
    }
}

/// Codable payload container for drawing annotations.
public enum DrawingAnnotationData: Sendable, Codable, Equatable {
    case linear(LinearDimensionData)
    case angular(AngularDimensionData)
    case radial(RadialDimensionData)
    case ordinate(OrdinateDimensionData)
    case baseline(BaselineDimensionData)
    case note(NoteAnnotationData)
    case leader(LeaderAnnotationData)
    case centerMark(CenterMarkData)
    case centerline(CenterlineData)
    case holeCallout(HoleCalloutAnnotationData)
    case balloon(BalloonAnnotationData)

    public var kind: DrawingAnnotationKind {
        switch self {
        case .linear:
            return .linear
        case .angular:
            return .angular
        case .radial:
            return .radial
        case .ordinate:
            return .ordinate
        case .baseline:
            return .baseline
        case .note:
            return .note
        case .leader:
            return .leader
        case .centerMark:
            return .centerMark
        case .centerline:
            return .centerline
        case .holeCallout:
            return .holeCallout
        case .balloon:
            return .balloon
        }
    }
}

/// Parametric attachment metadata associating a drawing annotation with 3D model geometry or features (BL-DRW-07).
public struct DrawingAnnotationAttachment: Sendable, Codable, Equatable {
    public var modelPoints: [SIMD3<Double>]
    public var featureId: UUID?
    public var topologicalReference: TopologicalReference?

    public init(
        modelPoints: [SIMD3<Double>] = [],
        featureId: UUID? = nil,
        topologicalReference: TopologicalReference? = nil
    ) {
        self.modelPoints = modelPoints
        self.featureId = featureId
        self.topologicalReference = topologicalReference
    }
}

/// An annotation or dimension placed on a drawing sheet or attached to a drawing view.
public struct DrawingAnnotation: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var name: String
    /// View ID if attached to a specific drawing view, or nil if positioned in sheet space.
    public var viewId: UUID?
    public var data: DrawingAnnotationData
    public var isVisible: Bool
    public var customProperties: [String: String]
    public var isDangling: Bool
    public var sourceFeatureId: UUID?
    public var attachment: DrawingAnnotationAttachment?

    public init(
        id: UUID = UUID(),
        name: String,
        viewId: UUID? = nil,
        data: DrawingAnnotationData,
        isVisible: Bool = true,
        customProperties: [String: String] = [:],
        isDangling: Bool = false,
        sourceFeatureId: UUID? = nil,
        attachment: DrawingAnnotationAttachment? = nil
    ) {
        self.id = id
        self.name = name
        self.viewId = viewId
        self.data = data
        self.isVisible = isVisible
        self.customProperties = customProperties
        self.isDangling = isDangling
        self.sourceFeatureId = sourceFeatureId
        self.attachment = attachment
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case viewId
        case data
        case isVisible
        case customProperties
        case isDangling
        case sourceFeatureId
        case attachment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.viewId = try container.decodeIfPresent(UUID.self, forKey: .viewId)
        self.data = try container.decode(DrawingAnnotationData.self, forKey: .data)
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        self.customProperties = try container.decodeIfPresent([String: String].self, forKey: .customProperties) ?? [:]
        self.isDangling = try container.decodeIfPresent(Bool.self, forKey: .isDangling) ?? false
        self.sourceFeatureId = try container.decodeIfPresent(UUID.self, forKey: .sourceFeatureId)
        self.attachment = try container.decodeIfPresent(DrawingAnnotationAttachment.self, forKey: .attachment)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(viewId, forKey: .viewId)
        try container.encode(data, forKey: .data)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(customProperties, forKey: .customProperties)
        try container.encode(isDangling, forKey: .isDangling)
        try container.encodeIfPresent(sourceFeatureId, forKey: .sourceFeatureId)
        try container.encodeIfPresent(attachment, forKey: .attachment)
    }

    public var kind: DrawingAnnotationKind {
        data.kind
    }
}
