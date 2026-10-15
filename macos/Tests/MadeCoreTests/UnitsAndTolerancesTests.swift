import Testing
import Foundation
@testable import MadeCore

@Suite struct UnitsAndTolerancesTests {
    // MARK: - LengthUnit Tests

    @Test func testLengthUnitConversionAccuracy() {
        let mm = 254.0

        // Millimeters
        #expect(LengthUnit.millimeters.toMillimeters(mm) == mm)
        #expect(LengthUnit.millimeters.fromMillimeters(mm) == mm)

        // Centimeters
        #expect(LengthUnit.centimeters.toMillimeters(25.4) == mm)
        #expect(abs(LengthUnit.centimeters.fromMillimeters(mm) - 25.4) < 1e-9)

        // Meters
        #expect(LengthUnit.meters.toMillimeters(0.254) == mm)
        #expect(abs(LengthUnit.meters.fromMillimeters(mm) - 0.254) < 1e-9)

        // Inches (1 in = 25.4 mm)
        #expect(LengthUnit.inches.toMillimeters(10.0) == mm)
        #expect(abs(LengthUnit.inches.fromMillimeters(mm) - 10.0) < 1e-9)

        // Feet (1 ft = 304.8 mm)
        #expect(abs(LengthUnit.feet.toMillimeters(1.0) - 304.8) < 1e-9)
        #expect(abs(LengthUnit.feet.fromMillimeters(304.8) - 1.0) < 1e-9)
    }

    @Test func testLengthUnitPropertiesAndSymbols() {
        #expect(LengthUnit.millimeters.symbol == "mm")
        #expect(LengthUnit.centimeters.symbol == "cm")
        #expect(LengthUnit.meters.symbol == "m")
        #expect(LengthUnit.inches.symbol == "in")
        #expect(LengthUnit.feet.symbol == "ft")

        for unit in LengthUnit.allCases {
            #expect(!unit.displayName.isEmpty)
            #expect(unit.id == unit.rawValue)
        }
    }

    // MARK: - AngleUnit Tests

    @Test func testAngleUnitConversionAccuracy() {
        // 180 degrees = pi radians
        let deg = 180.0
        let rad = Double.pi

        #expect(AngleUnit.degrees.toDegrees(deg) == deg)
        #expect(AngleUnit.degrees.fromDegrees(deg) == deg)

        #expect(abs(AngleUnit.radians.toDegrees(rad) - deg) < 1e-9)
        #expect(abs(AngleUnit.radians.fromDegrees(deg) - rad) < 1e-9)

        // 90 degrees = pi / 2 radians
        #expect(abs(AngleUnit.radians.toDegrees(Double.pi / 2.0) - 90.0) < 1e-9)
        #expect(abs(AngleUnit.radians.fromDegrees(90.0) - (Double.pi / 2.0)) < 1e-9)
    }

    @Test func testAngleUnitPropertiesAndSymbols() {
        #expect(AngleUnit.degrees.symbol == "deg")
        #expect(AngleUnit.radians.symbol == "rad")

        for unit in AngleUnit.allCases {
            #expect(!unit.displayName.isEmpty)
            #expect(unit.id == unit.rawValue)
        }
    }

    // MARK: - UnitSettings and Precision Formatting

    @Test func testUnitSettingsPrecisionClamping() {
        #expect(UnitSettings.clampPrecision(-5) == UnitSettings.minDecimalPrecision)
        #expect(UnitSettings.clampPrecision(0) == 0)
        #expect(UnitSettings.clampPrecision(3) == 3)
        #expect(UnitSettings.clampPrecision(6) == 6)
        #expect(UnitSettings.clampPrecision(12) == UnitSettings.maxDecimalPrecision)
    }

    @Test func testUnitSettingsFormatting() {
        let settings = UnitSettings(lengthUnit: .millimeters, angleUnit: .degrees, decimalPrecision: 2)
        #expect(settings.formatLength(12.3456) == "12.35 mm")
        #expect(settings.formatLength(12.3456, includeSymbol: false) == "12.35")
        #expect(settings.formatAngle(45.6789) == "45.68 deg")
        #expect(settings.formatAngle(45.6789, includeSymbol: false) == "45.68")

        let inchSettings = UnitSettings(lengthUnit: .inches, angleUnit: .radians, decimalPrecision: 3)
        // 25.4 mm = 1.0 inch
        #expect(inchSettings.formatLength(25.4) == "1.000 in")
        // 180 deg = pi rad ≈ 3.142 rad
        #expect(inchSettings.formatAngle(180.0) == "3.142 rad")
    }

    // MARK: - KernelTolerances Tests

    @Test func testKernelTolerancesDefaults() {
        let tol = KernelTolerances.default
        #expect(tol.linearTolerance == 0.001)
        #expect(tol.angularTolerance == 0.1)
        #expect(tol.chordalTolerance == 0.01)
        #expect(tol.isValid)
    }

    @Test func testKernelTolerancesBoundsClamping() {
        // Negative values clamp to minimum positive bounds
        let negativeTol = KernelTolerances(linearTolerance: -5.0, angularTolerance: -1.0, chordalTolerance: -0.5)
        let clampedNeg = negativeTol.clamped()
        #expect(clampedNeg.linearTolerance == KernelTolerances.minLinearTolerance)
        #expect(clampedNeg.angularTolerance == KernelTolerances.minAngularTolerance)
        #expect(clampedNeg.chordalTolerance == KernelTolerances.minChordalTolerance)
        #expect(clampedNeg.isValid)

        // Zero values clamp to minimum positive bounds
        let zeroTol = KernelTolerances(linearTolerance: 0.0, angularTolerance: 0.0, chordalTolerance: 0.0)
        let clampedZero = zeroTol.clamped()
        #expect(clampedZero.linearTolerance == KernelTolerances.minLinearTolerance)
        #expect(clampedZero.angularTolerance == KernelTolerances.minAngularTolerance)
        #expect(clampedZero.chordalTolerance == KernelTolerances.minChordalTolerance)
        #expect(clampedZero.isValid)

        // Excessive values clamp to maximum bounds
        let highTol = KernelTolerances(linearTolerance: 100.0, angularTolerance: 90.0, chordalTolerance: 20.0)
        let clampedHigh = highTol.clamped()
        #expect(clampedHigh.linearTolerance == KernelTolerances.maxLinearTolerance)
        #expect(clampedHigh.angularTolerance == KernelTolerances.maxAngularTolerance)
        #expect(clampedHigh.chordalTolerance == KernelTolerances.maxChordalTolerance)
        #expect(clampedHigh.isValid)

        // Non-finite values (NaN / infinity) clamp to defaults
        let nanTol = KernelTolerances(linearTolerance: Double.nan, angularTolerance: Double.infinity, chordalTolerance: -Double.infinity)
        let clampedNan = nanTol.clamped()
        #expect(clampedNan.linearTolerance == KernelTolerances.defaultLinearTolerance)
        #expect(clampedNan.angularTolerance == KernelTolerances.defaultAngularTolerance)
        #expect(clampedNan.chordalTolerance == KernelTolerances.defaultChordalTolerance)
        #expect(clampedNan.isValid)
    }

    @Test func testCodableRoundtrips() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let origTol = KernelTolerances(linearTolerance: 0.005, angularTolerance: 0.25, chordalTolerance: 0.02)
        let tolData = try encoder.encode(origTol)
        let decodedTol = try decoder.decode(KernelTolerances.self, from: tolData)
        #expect(origTol == decodedTol)

        let origUnit = UnitSettings(lengthUnit: .inches, angleUnit: .radians, decimalPrecision: 4)
        let unitData = try encoder.encode(origUnit)
        let decodedUnit = try decoder.decode(UnitSettings.self, from: unitData)
        #expect(origUnit == decodedUnit)
    }
}
