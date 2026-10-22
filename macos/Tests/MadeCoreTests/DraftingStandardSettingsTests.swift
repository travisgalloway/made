import Testing
import Foundation
@testable import MadeCore

@Suite struct DraftingStandardSettingsTests {

    // MARK: - Presets and Defaults Tests

    @Test func testISOPresetDefaults() {
        let iso = DraftingStandardSettings.iso
        #expect(iso.standard == .iso)
        #expect(iso.arrows.style == .closedFilled)
        #expect(iso.arrows.lengthMM == 3.0)
        #expect(iso.arrows.widthMM == 1.0)
        #expect(abs(iso.arrows.lengthPoints - (3.0 * (72.0 / 25.4))) < 1e-6)
        #expect(abs(iso.arrows.widthPoints - (1.0 * (72.0 / 25.4))) < 1e-6)

        #expect(iso.text.placement == .aligned)
        #expect(iso.text.decimalSeparator == .comma)
        #expect(iso.text.trailingZeros == .suppress)
        #expect(iso.text.textHeightMM == 3.5)
        #expect(iso.text.textGapMM == 1.0)

        #expect(iso.tolerances.defaultType == .none)
        #expect(iso.tolerances.linearToleranceMM == 0.1)
        #expect(iso.tolerances.angularToleranceDeg == 0.5)
        #expect(iso.tolerances.upperDeviationMM == 0.1)
        #expect(iso.tolerances.lowerDeviationMM == -0.1)
        #expect(iso.tolerances.precision == 2)
        #expect(iso.tolerances.textScale == 0.75)
    }

    @Test func testANSIPresetDefaults() {
        let ansi = DraftingStandardSettings.ansi
        #expect(ansi.standard == .ansi)
        #expect(ansi.arrows.style == .closedFilled)
        #expect(ansi.arrows.lengthMM == 3.2)
        #expect(ansi.arrows.widthMM == 1.0)
        #expect(abs(ansi.arrows.lengthPoints - (3.2 * (72.0 / 25.4))) < 1e-6)

        #expect(ansi.text.placement == .unidirectional)
        #expect(ansi.text.decimalSeparator == .period)
        #expect(ansi.text.trailingZeros == .show)
        #expect(ansi.text.textHeightMM == 3.0)
        #expect(ansi.text.textGapMM == 1.0)

        #expect(ansi.tolerances.defaultType == .none)
        #expect(ansi.tolerances.linearToleranceMM == 0.13)
        #expect(ansi.tolerances.angularToleranceDeg == 0.5)
        #expect(ansi.tolerances.upperDeviationMM == 0.13)
        #expect(ansi.tolerances.lowerDeviationMM == -0.13)
        #expect(ansi.tolerances.precision == 2)
        #expect(ansi.tolerances.textScale == 0.80)
    }

    // MARK: - Numeric and Decimal Separator Formatting

    @Test func testDecimalSeparatorFormatting() {
        // Period separator (ANSI)
        let ansiFormatted = DraftingStandardSettings.formatNumber(12.345, precision: 2, separator: .period, trailingZeros: .show)
        #expect(ansiFormatted == "12.35")

        // Comma separator (ISO)
        let isoFormatted = DraftingStandardSettings.formatNumber(12.345, precision: 2, separator: .comma, trailingZeros: .show)
        #expect(isoFormatted == "12,35")
    }

    @Test func testTrailingZeroSuppression() {
        // ISO suppresses trailing zeros
        let isoSuppressed = DraftingStandardSettings.formatNumber(25.50, precision: 2, separator: .comma, trailingZeros: .suppress)
        #expect(isoSuppressed == "25,5")

        let isoWhole = DraftingStandardSettings.formatNumber(25.00, precision: 2, separator: .comma, trailingZeros: .suppress)
        #expect(isoWhole == "25")

        // ANSI retains trailing zeros
        let ansiRetained = DraftingStandardSettings.formatNumber(25.50, precision: 2, separator: .period, trailingZeros: .show)
        #expect(ansiRetained == "25.50")

        let ansiWhole = DraftingStandardSettings.formatNumber(25.00, precision: 2, separator: .period, trailingZeros: .show)
        #expect(ansiWhole == "25.00")
    }

    // MARK: - Tolerance Formatting

    @Test func testToleranceFormattingTypes() {
        let ansi = DraftingStandardSettings.ansi
        let iso = DraftingStandardSettings.iso

        // 1. None
        let noneDim = ansi.formatDimension(nominal: 50.0, tolerance: DimensionTolerance(type: .none), precision: 2)
        #expect(noneDim == "50.00")

        // 2. Symmetrical (±)
        let symTol = DimensionTolerance(symmetrical: 0.15, precision: 2)
        let symDimANSI = ansi.formatDimension(nominal: 50.0, tolerance: symTol, precision: 2)
        #expect(symDimANSI == "50.00 ±0.15")

        let symDimISO = iso.formatDimension(nominal: 50.0, tolerance: symTol, precision: 2)
        #expect(symDimISO == "50 ±0,15")

        // 3. Deviation (+/-)
        let devTol = DimensionTolerance(type: .deviation, upperValue: 0.1, lowerValue: -0.2, precision: 2)
        let devDimANSI = ansi.formatDimension(nominal: 50.0, tolerance: devTol, precision: 2)
        #expect(devDimANSI == "50.00 +0.10/-0.20")

        let devDimISO = iso.formatDimension(nominal: 50.0, tolerance: devTol, precision: 2)
        #expect(devDimISO == "50 +0,1/-0,2")

        // 4. Limits
        let limitsTol = DimensionTolerance(type: .limits, upperValue: 0.2, lowerValue: -0.1, precision: 2)
        let limitsDimANSI = ansi.formatDimension(nominal: 50.0, tolerance: limitsTol, precision: 2)
        #expect(limitsDimANSI == "50.20 - 49.90")

        let limitsDimISO = iso.formatDimension(nominal: 50.0, tolerance: limitsTol, precision: 2)
        #expect(limitsDimISO == "50,2 - 49,9")

        // 5. Basic
        let basicTol = DimensionTolerance(type: .basic)
        let basicDimANSI = ansi.formatDimension(nominal: 50.0, tolerance: basicTol, precision: 2, prefix: "REF ", suffix: " mm")
        #expect(basicDimANSI == "REF [50.00] mm")

        let basicDimISO = iso.formatDimension(nominal: 50.0, tolerance: basicTol, precision: 2)
        #expect(basicDimISO == "[50]")
    }

    // MARK: - Bounds Clamping Tests

    @Test func testNumericalBoundsClamping() {
        // Arrow defaults clamping
        let arrowsClampedLow = DraftingArrowDefaults(lengthMM: 0.1, widthMM: 0.05)
        #expect(arrowsClampedLow.lengthMM == 0.5)
        #expect(arrowsClampedLow.widthMM == 0.2)

        let arrowsClampedHigh = DraftingArrowDefaults(lengthMM: 50.0, widthMM: 25.0)
        #expect(arrowsClampedHigh.lengthMM == 20.0)
        #expect(arrowsClampedHigh.widthMM == 10.0)

        // Text defaults clamping
        let textClampedLow = DraftingTextDefaults(textHeightMM: 0.2, textGapMM: 0.05)
        #expect(textClampedLow.textHeightMM == 1.0)
        #expect(textClampedLow.textGapMM == 0.2)

        let textClampedHigh = DraftingTextDefaults(textHeightMM: 50.0, textGapMM: 30.0)
        #expect(textClampedHigh.textHeightMM == 20.0)
        #expect(textClampedHigh.textGapMM == 10.0)

        // Tolerance defaults clamping
        let tolClamped = DraftingToleranceDefaults(
            linearToleranceMM: -5.0,
            angularToleranceDeg: 90.0,
            precision: 10,
            textScale: 5.0
        )
        #expect(tolClamped.linearToleranceMM == 0.0)
        #expect(tolClamped.angularToleranceDeg == 45.0)
        #expect(tolClamped.precision == 6)
        #expect(tolClamped.textScale == 2.0)
    }

    // MARK: - Text Angle Normalization

    @Test func testTextAngleNormalization() {
        // Zero
        #expect(abs(DraftingStandardSettings.normalizeTextAngle(0.0)) < 1e-6)

        // First quadrant (pi/4)
        #expect(abs(DraftingStandardSettings.normalizeTextAngle(.pi / 4.0) - (.pi / 4.0)) < 1e-6)

        // Second quadrant (3*pi/4) should normalize to -pi/4
        #expect(abs(DraftingStandardSettings.normalizeTextAngle(3.0 * .pi / 4.0) - (-.pi / 4.0)) < 1e-6)

        // Pi should normalize to 0
        #expect(abs(DraftingStandardSettings.normalizeTextAngle(.pi)) < 1e-6)

        // Third quadrant (-3*pi/4) should normalize to pi/4
        #expect(abs(DraftingStandardSettings.normalizeTextAngle(-3.0 * .pi / 4.0) - (.pi / 4.0)) < 1e-6)

        // Upright bounds [-pi/2, pi/2]
        #expect(abs(DraftingStandardSettings.normalizeTextAngle(.pi / 2.0) - (.pi / 2.0)) < 1e-6)
        #expect(abs(DraftingStandardSettings.normalizeTextAngle(-.pi / 2.0) - (-.pi / 2.0)) < 1e-6)
    }

    // MARK: - JSON Round-Trip Serialization

    @Test func testJSONSerializationRoundTrip() throws {
        let original = DraftingStandardSettings(
            standard: .custom,
            arrows: DraftingArrowDefaults(style: .tick, lengthMM: 4.5, widthMM: 1.5),
            text: DraftingTextDefaults(placement: .unidirectional, decimalSeparator: .period, trailingZeros: .suppress, textHeightMM: 4.0, textGapMM: 1.2),
            tolerances: DraftingToleranceDefaults(defaultType: .symmetrical, linearToleranceMM: 0.2, precision: 3, textScale: 0.85)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DraftingStandardSettings.self, from: data)

        #expect(decoded == original)
    }
}
