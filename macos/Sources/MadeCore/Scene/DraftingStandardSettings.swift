import Foundation

/// Arrowhead rendering styles supported in engineering drawings (BL-DRW-10).
public enum ArrowheadStyle: String, Sendable, Codable, CaseIterable {
    case closedFilled
    case open
    case tick

    public var displayName: String {
        switch self {
        case .closedFilled:
            return "Closed Filled"
        case .open:
            return "Open"
        case .tick:
            return "Architectural Tick"
        }
    }
}

/// Dimension text alignment relative to the dimension line.
public enum DimensionTextPlacement: String, Sendable, Codable, CaseIterable {
    case aligned
    case unidirectional

    public var displayName: String {
        switch self {
        case .aligned:
            return "Aligned (ISO)"
        case .unidirectional:
            return "Unidirectional (ANSI)"
        }
    }
}

/// Decimal separator character used for dimension and tolerance text.
public enum DecimalSeparator: String, Sendable, Codable, CaseIterable {
    case comma
    case period

    public var displayName: String {
        switch self {
        case .comma:
            return "Comma (,)"
        case .period:
            return "Period (.)"
        }
    }

    public var character: Character {
        switch self {
        case .comma:
            return ","
        case .period:
            return "."
        }
    }

    public var string: String {
        String(character)
    }
}

/// Behavior for trailing decimal zeros in formatted dimension values.
public enum TrailingZeroDisplay: String, Sendable, Codable, CaseIterable {
    case suppress
    case show

    public var displayName: String {
        switch self {
        case .suppress:
            return "Suppress (ISO)"
        case .show:
            return "Show (ANSI)"
        }
    }
}

/// Tolerance specification methods for annotations and dimensions.
public enum DraftingToleranceType: String, Sendable, Codable, CaseIterable {
    case none
    case symmetrical
    case deviation
    case limits
    case basic

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .symmetrical:
            return "Symmetrical (±)"
        case .deviation:
            return "Deviation (+/-)"
        case .limits:
            return "Limits"
        case .basic:
            return "Basic"
        }
    }
}

/// Arrowhead sizing and geometry defaults for a drawing sheet.
public struct DraftingArrowDefaults: Sendable, Codable, Equatable {
    public var style: ArrowheadStyle
    public var lengthMM: Double {
        didSet { lengthMM = max(0.5, min(20.0, lengthMM)) }
    }
    public var widthMM: Double {
        didSet { widthMM = max(0.2, min(10.0, widthMM)) }
    }

    public init(
        style: ArrowheadStyle = .closedFilled,
        lengthMM: Double = 3.0,
        widthMM: Double = 1.0
    ) {
        self.style = style
        self.lengthMM = max(0.5, min(20.0, lengthMM))
        self.widthMM = max(0.2, min(10.0, widthMM))
    }

    public var lengthPoints: Double {
        lengthMM * DrawingSheet.pointsPerMillimeter
    }

    public var widthPoints: Double {
        widthMM * DrawingSheet.pointsPerMillimeter
    }

    public static let iso = DraftingArrowDefaults(
        style: .closedFilled,
        lengthMM: 3.0,
        widthMM: 1.0
    )

    public static let ansi = DraftingArrowDefaults(
        style: .closedFilled,
        lengthMM: 3.2,
        widthMM: 1.0
    )

    private enum CodingKeys: String, CodingKey {
        case style
        case lengthMM
        case widthMM
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let s = try container.decodeIfPresent(ArrowheadStyle.self, forKey: .style) ?? .closedFilled
        let l = try container.decodeIfPresent(Double.self, forKey: .lengthMM) ?? 3.0
        let w = try container.decodeIfPresent(Double.self, forKey: .widthMM) ?? 1.0
        self.style = s
        self.lengthMM = max(0.5, min(20.0, l))
        self.widthMM = max(0.2, min(10.0, w))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(lengthMM, forKey: .lengthMM)
        try container.encode(widthMM, forKey: .widthMM)
    }
}

/// Dimension text typography and placement defaults for a drawing sheet.
public struct DraftingTextDefaults: Sendable, Codable, Equatable {
    public var placement: DimensionTextPlacement
    public var decimalSeparator: DecimalSeparator
    public var trailingZeros: TrailingZeroDisplay
    public var textHeightMM: Double {
        didSet { textHeightMM = max(1.0, min(20.0, textHeightMM)) }
    }
    public var textGapMM: Double {
        didSet { textGapMM = max(0.2, min(10.0, textGapMM)) }
    }

    public init(
        placement: DimensionTextPlacement = .aligned,
        decimalSeparator: DecimalSeparator = .comma,
        trailingZeros: TrailingZeroDisplay = .suppress,
        textHeightMM: Double = 3.5,
        textGapMM: Double = 1.0
    ) {
        self.placement = placement
        self.decimalSeparator = decimalSeparator
        self.trailingZeros = trailingZeros
        self.textHeightMM = max(1.0, min(20.0, textHeightMM))
        self.textGapMM = max(0.2, min(10.0, textGapMM))
    }

    public var textHeightPoints: Double {
        textHeightMM * DrawingSheet.pointsPerMillimeter
    }

    public var textGapPoints: Double {
        textGapMM * DrawingSheet.pointsPerMillimeter
    }

    public static let iso = DraftingTextDefaults(
        placement: .aligned,
        decimalSeparator: .comma,
        trailingZeros: .suppress,
        textHeightMM: 3.5,
        textGapMM: 1.0
    )

    public static let ansi = DraftingTextDefaults(
        placement: .unidirectional,
        decimalSeparator: .period,
        trailingZeros: .show,
        textHeightMM: 3.0,
        textGapMM: 1.0
    )

    private enum CodingKeys: String, CodingKey {
        case placement
        case decimalSeparator
        case trailingZeros
        case textHeightMM
        case textGapMM
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.placement = try container.decodeIfPresent(DimensionTextPlacement.self, forKey: .placement) ?? .aligned
        self.decimalSeparator = try container.decodeIfPresent(DecimalSeparator.self, forKey: .decimalSeparator) ?? .comma
        self.trailingZeros = try container.decodeIfPresent(TrailingZeroDisplay.self, forKey: .trailingZeros) ?? .suppress
        let h = try container.decodeIfPresent(Double.self, forKey: .textHeightMM) ?? 3.5
        let g = try container.decodeIfPresent(Double.self, forKey: .textGapMM) ?? 1.0
        self.textHeightMM = max(1.0, min(20.0, h))
        self.textGapMM = max(0.2, min(10.0, g))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(decimalSeparator, forKey: .decimalSeparator)
        try container.encode(trailingZeros, forKey: .trailingZeros)
        try container.encode(textHeightMM, forKey: .textHeightMM)
        try container.encode(textGapMM, forKey: .textGapMM)
    }
}

/// Tolerance parameters and formatting defaults for a drawing sheet.
public struct DraftingToleranceDefaults: Sendable, Codable, Equatable {
    public var defaultType: DraftingToleranceType
    public var linearToleranceMM: Double {
        didSet { linearToleranceMM = max(0.0, min(10.0, linearToleranceMM)) }
    }
    public var angularToleranceDeg: Double {
        didSet { angularToleranceDeg = max(0.0, min(45.0, angularToleranceDeg)) }
    }
    public var upperDeviationMM: Double
    public var lowerDeviationMM: Double
    public var precision: Int {
        didSet { precision = max(0, min(6, precision)) }
    }
    public var textScale: Double {
        didSet { textScale = max(0.1, min(2.0, textScale)) }
    }

    public init(
        defaultType: DraftingToleranceType = .none,
        linearToleranceMM: Double = 0.1,
        angularToleranceDeg: Double = 0.5,
        upperDeviationMM: Double = 0.1,
        lowerDeviationMM: Double = -0.1,
        precision: Int = 2,
        textScale: Double = 0.75
    ) {
        self.defaultType = defaultType
        self.linearToleranceMM = max(0.0, min(10.0, linearToleranceMM))
        self.angularToleranceDeg = max(0.0, min(45.0, angularToleranceDeg))
        self.upperDeviationMM = upperDeviationMM
        self.lowerDeviationMM = lowerDeviationMM
        self.precision = max(0, min(6, precision))
        self.textScale = max(0.1, min(2.0, textScale))
    }

    public static let iso = DraftingToleranceDefaults(
        defaultType: .none,
        linearToleranceMM: 0.1,
        angularToleranceDeg: 0.5,
        upperDeviationMM: 0.1,
        lowerDeviationMM: -0.1,
        precision: 2,
        textScale: 0.75
    )

    public static let ansi = DraftingToleranceDefaults(
        defaultType: .none,
        linearToleranceMM: 0.13,
        angularToleranceDeg: 0.5,
        upperDeviationMM: 0.13,
        lowerDeviationMM: -0.13,
        precision: 2,
        textScale: 0.80
    )

    private enum CodingKeys: String, CodingKey {
        case defaultType
        case linearToleranceMM
        case angularToleranceDeg
        case upperDeviationMM
        case lowerDeviationMM
        case precision
        case textScale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultType = try container.decodeIfPresent(DraftingToleranceType.self, forKey: .defaultType) ?? .none
        let lin = try container.decodeIfPresent(Double.self, forKey: .linearToleranceMM) ?? 0.1
        let ang = try container.decodeIfPresent(Double.self, forKey: .angularToleranceDeg) ?? 0.5
        self.upperDeviationMM = try container.decodeIfPresent(Double.self, forKey: .upperDeviationMM) ?? 0.1
        self.lowerDeviationMM = try container.decodeIfPresent(Double.self, forKey: .lowerDeviationMM) ?? -0.1
        let prec = try container.decodeIfPresent(Int.self, forKey: .precision) ?? 2
        let scale = try container.decodeIfPresent(Double.self, forKey: .textScale) ?? 0.75
        self.linearToleranceMM = max(0.0, min(10.0, lin))
        self.angularToleranceDeg = max(0.0, min(45.0, ang))
        self.precision = max(0, min(6, prec))
        self.textScale = max(0.1, min(2.0, scale))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultType, forKey: .defaultType)
        try container.encode(linearToleranceMM, forKey: .linearToleranceMM)
        try container.encode(angularToleranceDeg, forKey: .angularToleranceDeg)
        try container.encode(upperDeviationMM, forKey: .upperDeviationMM)
        try container.encode(lowerDeviationMM, forKey: .lowerDeviationMM)
        try container.encode(precision, forKey: .precision)
        try container.encode(textScale, forKey: .textScale)
    }
}

/// Tolerance specification attached to an individual dimension annotation.
public struct DimensionTolerance: Sendable, Codable, Equatable {
    public var type: DraftingToleranceType
    public var upperValue: Double
    public var lowerValue: Double
    public var precision: Int?

    public init(
        type: DraftingToleranceType = .none,
        upperValue: Double = 0.0,
        lowerValue: Double = 0.0,
        precision: Int? = nil
    ) {
        self.type = type
        self.upperValue = upperValue
        self.lowerValue = lowerValue
        self.precision = precision.map { max(0, min(6, $0)) }
    }

    public init(symmetrical value: Double, precision: Int? = nil) {
        self.type = .symmetrical
        self.upperValue = abs(value)
        self.lowerValue = -abs(value)
        self.precision = precision.map { max(0, min(6, $0)) }
    }
}

/// Complete drafting standard configuration for an engineering drawing sheet.
public struct DraftingStandardSettings: Sendable, Codable, Equatable {
    public var standard: DrawingStandard
    public var arrows: DraftingArrowDefaults
    public var text: DraftingTextDefaults
    public var tolerances: DraftingToleranceDefaults

    public init(
        standard: DrawingStandard = .iso,
        arrows: DraftingArrowDefaults = .iso,
        text: DraftingTextDefaults = .iso,
        tolerances: DraftingToleranceDefaults = .iso
    ) {
        self.standard = standard
        self.arrows = arrows
        self.text = text
        self.tolerances = tolerances
    }

    public static let iso = DraftingStandardSettings(
        standard: .iso,
        arrows: .iso,
        text: .iso,
        tolerances: .iso
    )

    public static let ansi = DraftingStandardSettings(
        standard: .ansi,
        arrows: .ansi,
        text: .ansi,
        tolerances: .ansi
    )

    // MARK: - Normalization Helpers

    /// Normalizes an angle in radians so text always reads upright,
    /// within [-pi/2, pi/2].
    public static func normalizeTextAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2.0 * .pi)
        if a > .pi {
            a -= 2.0 * .pi
        } else if a <= -.pi {
            a += 2.0 * .pi
        }
        if a > (.pi / 2.0) {
            a -= .pi
        } else if a < -(.pi / 2.0) {
            a += .pi
        }
        return a
    }

    // MARK: - Formatting Helpers

    /// Formats a numeric value with specified decimal separator and trailing zero rules.
    public static func formatNumber(
        _ value: Double,
        precision: Int,
        separator: DecimalSeparator = .period,
        trailingZeros: TrailingZeroDisplay = .show
    ) -> String {
        let clampedPrecision = max(0, min(6, precision))
        let safeValue = abs(value) < 1e-12 ? 0.0 : value
        var str = String(format: "%.\(clampedPrecision)f", safeValue)
        if separator == .comma {
            str = str.replacingOccurrences(of: ".", with: ",")
        }
        if trailingZeros == .suppress && clampedPrecision > 0 {
            let sepChar = separator == .comma ? "," : "."
            if str.contains(sepChar) {
                while str.hasSuffix("0") {
                    str.removeLast()
                }
                if str.hasSuffix(sepChar) {
                    str.removeLast()
                }
            }
        }
        if str == "-0" || str == "-0,0" || str == "-0.0" {
            str = "0"
        }
        return str
    }

    /// Formats a numeric value using the standard text defaults.
    public func formatNumber(_ value: Double, precision: Int) -> String {
        Self.formatNumber(
            value,
            precision: precision,
            separator: text.decimalSeparator,
            trailingZeros: text.trailingZeros
        )
    }

    /// Formats a complete dimension string including prefix, nominal value, tolerance, and suffix.
    public func formatDimension(
        nominal: Double,
        tolerance: DimensionTolerance?,
        precision: Int,
        prefix: String = "",
        suffix: String = ""
    ) -> String {
        let effectiveTolerance = tolerance ?? DimensionTolerance(type: tolerances.defaultType)
        let tolPrecision = effectiveTolerance.precision ?? tolerances.precision

        switch effectiveTolerance.type {
        case .none:
            let numStr = formatNumber(nominal, precision: precision)
            return "\(prefix)\(numStr)\(suffix)"

        case .symmetrical:
            let numStr = formatNumber(nominal, precision: precision)
            let rawTol = effectiveTolerance.upperValue != 0 ? effectiveTolerance.upperValue : (effectiveTolerance.lowerValue != 0 ? effectiveTolerance.lowerValue : tolerances.linearToleranceMM)
            let tolVal = abs(rawTol)
            let tolStr = formatNumber(tolVal, precision: tolPrecision)
            return "\(prefix)\(numStr) ±\(tolStr)\(suffix)"

        case .deviation:
            let numStr = formatNumber(nominal, precision: precision)
            let isDefaultDev = (effectiveTolerance.upperValue == 0 && effectiveTolerance.lowerValue == 0)
            let upper = isDefaultDev ? tolerances.upperDeviationMM : effectiveTolerance.upperValue
            let lower = isDefaultDev ? tolerances.lowerDeviationMM : effectiveTolerance.lowerValue
            let upperStr = (upper >= 0 ? "+" : "") + formatNumber(upper, precision: tolPrecision)
            let lowerStr = (lower >= 0 ? "+" : "") + formatNumber(lower, precision: tolPrecision)
            return "\(prefix)\(numStr) \(upperStr)/\(lowerStr)\(suffix)"

        case .limits:
            let isDefaultDev = (effectiveTolerance.upperValue == 0 && effectiveTolerance.lowerValue == 0)
            let upper = isDefaultDev ? tolerances.upperDeviationMM : effectiveTolerance.upperValue
            let lower = isDefaultDev ? tolerances.lowerDeviationMM : effectiveTolerance.lowerValue
            let upperLimit = nominal + upper
            let lowerLimit: Double
            if lower <= 0 {
                lowerLimit = nominal + lower
            } else if nominal + lower > upperLimit {
                lowerLimit = nominal - lower
            } else {
                lowerLimit = nominal + lower
            }
            let upperStr = formatNumber(upperLimit, precision: tolPrecision)
            let lowerStr = formatNumber(lowerLimit, precision: tolPrecision)
            return "\(prefix)\(upperStr) - \(lowerStr)\(suffix)"

        case .basic:
            let numStr = formatNumber(nominal, precision: precision)
            return "\(prefix)[\(numStr)]\(suffix)"
        }
    }
}
