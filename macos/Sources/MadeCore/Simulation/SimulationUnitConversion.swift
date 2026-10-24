import Foundation
import simd

/// Unit conversions, coordinate frame resolutions, and result transformations for simulation studies (BL-SIM-03, #350).
public enum SimulationUnitConversion: Sendable {

    // MARK: - Unit Conversion Constants

    /// Force conversion factor: 1 lbf = 4.4482216152605 N.
    public static let forceFactor: Double = 4.4482216152605

    /// Pressure and stress conversion factor: 1 MPa = 145.03773773 psi.
    public static let pressureFactor: Double = 145.03773773

    /// Gravitational acceleration conversion factor: 1 m/s² = 3.280839895 ft/s².
    public static let gravityFactor: Double = 3.280839895

    /// Thermal heat flux conversion factor: 1 W/m² = 0.316998396 BTU/(hr·ft²).
    public static let heatFluxFactor: Double = 0.316998396

    /// Convection heat transfer coefficient conversion factor: 1 W/(m²·K) = 0.17611018368 BTU/(hr·ft²·°F).
    public static let convectionFactor: Double = 0.17611018368

    /// Heat power conversion factor: 1 W = 3.412141633 BTU/hr.
    public static let heatPowerFactor: Double = 3.412141633

    /// Stress conversion factor to ksi: 1 MPa = 0.14503773773 ksi.
    public static let stressKsiFactor: Double = 0.14503773773

    /// Spring stiffness conversion factor: 1 lbf/in = 4.4482216152605 / 0.0254 N/m (~175.126835246 N/m).
    public static let springStiffnessFactor: Double = 4.4482216152605 / 0.0254

    /// Moment conversion factor: 1 N·m = 1 / (4.4482216152605 * 0.0254) lbf·in (~8.85074579 lbf·in).
    public static let momentFactor: Double = 1.0 / (4.4482216152605 * 0.0254)

    /// Rotational speed conversion factor: 1 rad/s = 60.0 / (2.0 * Double.pi) RPM (~9.5492965855 RPM).
    public static let rotationalSpeedFactor: Double = 60.0 / (2.0 * Double.pi)

    // MARK: - Force Conversions

    /// Converts canonical force (Newtons) to the display value for the given document length unit.
    public static func displayForce(_ canonicalN: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonicalN / forceFactor : canonicalN
    }

    /// Converts display force value back to canonical Newtons.
    public static func commitForce(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal * forceFactor : displayVal
    }

    /// Display unit symbol for force under the given document length unit.
    public static func forceUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "lbf" : "N"
    }

    // MARK: - Pressure Conversions

    /// Converts canonical pressure (MPa) to the display value for the given document length unit.
    public static func displayPressure(_ canonicalMPa: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonicalMPa * pressureFactor : canonicalMPa
    }

    /// Converts display pressure value back to canonical MPa.
    public static func commitPressure(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal / pressureFactor : displayVal
    }

    /// Display unit symbol for pressure under the given document length unit.
    public static func pressureUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "psi" : "MPa"
    }

    // MARK: - Gravity Conversions

    /// Converts canonical acceleration (m/s²) to the display value for the given document length unit.
    public static func displayGravity(_ canonical: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonical * gravityFactor : canonical
    }

    /// Converts display acceleration value back to canonical m/s².
    public static func commitGravity(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal / gravityFactor : displayVal
    }

    /// Display unit symbol for acceleration under the given document length unit.
    public static func gravityUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "ft/s²" : "m/s²"
    }

    // MARK: - Temperature Conversions

    /// Converts canonical temperature (°C) to the display value for the given document length unit.
    public static func displayTemperature(_ canonicalC: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonicalC * 1.8 + 32.0 : canonicalC
    }

    /// Converts display temperature value back to canonical °C.
    public static func commitTemperature(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? (displayVal - 32.0) / 1.8 : displayVal
    }

    /// Display unit symbol for temperature under the given document length unit.
    public static func temperatureUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "°F" : "°C"
    }

    // MARK: - Heat Flux Conversions

    /// Converts canonical heat flux (W/m²) to the display value for the given document length unit.
    public static func displayHeatFlux(_ canonical: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonical * heatFluxFactor : canonical
    }

    /// Converts display heat flux value back to canonical W/m².
    public static func commitHeatFlux(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal / heatFluxFactor : displayVal
    }

    /// Display unit symbol for heat flux under the given document length unit.
    public static func heatFluxUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "BTU/(hr·ft²)" : "W/m²"
    }

    // MARK: - Convection Conversions

    /// Converts canonical convection coefficient (W/(m²·K)) to display value for the given document length unit.
    public static func displayConvection(_ canonical: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonical * convectionFactor : canonical
    }

    /// Converts display convection coefficient back to canonical W/(m²·K).
    public static func commitConvection(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal / convectionFactor : displayVal
    }

    /// Display unit symbol for convection coefficient under the given document length unit.
    public static func convectionUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "BTU/(hr·ft²·°F)" : "W/(m²·K)"
    }

    // MARK: - Heat Power Conversions

    /// Converts canonical heat power (W) to display value for the given document length unit.
    public static func displayHeatPower(_ canonical: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonical * heatPowerFactor : canonical
    }

    /// Converts display heat power back to canonical Watts.
    public static func commitHeatPower(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal / heatPowerFactor : displayVal
    }

    /// Display unit symbol for heat power under the given document length unit.
    public static func heatPowerUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "BTU/hr" : "W"
    }

    // MARK: - Length and Displacement Conversions

    /// Converts canonical length (mm) to the display value for the given document length unit.
    public static func displayLength(_ canonicalMm: Double, unit: LengthUnit) -> Double {
        unit.fromMillimeters(canonicalMm)
    }

    /// Converts display length value back to canonical millimeters.
    public static func commitLength(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.toMillimeters(displayVal)
    }

    /// Display unit symbol for length under the given document length unit.
    public static func lengthUnitSymbol(unit: LengthUnit) -> String {
        unit.symbol
    }

    /// Converts a canonical 3D displacement vector (mm) to display units.
    public static func displayDisplacement(_ canonicalMm: SIMD3<Double>, unit: LengthUnit) -> SIMD3<Double> {
        SIMD3<Double>(
            unit.fromMillimeters(canonicalMm.x),
            unit.fromMillimeters(canonicalMm.y),
            unit.fromMillimeters(canonicalMm.z)
        )
    }

    /// Converts a display 3D displacement vector to canonical millimeters.
    public static func commitDisplacement(_ displayVal: SIMD3<Double>, unit: LengthUnit) -> SIMD3<Double> {
        SIMD3<Double>(
            unit.toMillimeters(displayVal.x),
            unit.toMillimeters(displayVal.y),
            unit.toMillimeters(displayVal.z)
        )
    }

    // MARK: - Stress Conversions

    /// Converts canonical stress (MPa) to display value for the given document length unit.
    public static func displayStress(_ canonicalMPa: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonicalMPa * pressureFactor : canonicalMPa
    }

    /// Converts display stress value back to canonical MPa.
    public static func commitStress(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal / pressureFactor : displayVal
    }

    /// Display unit symbol for stress under the given document length unit.
    public static func stressUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "psi" : "MPa"
    }

    // MARK: - Spring Stiffness Conversions

    /// Converts canonical spring stiffness (N/m) to display value for the given document length unit.
    public static func displayStiffness(_ canonicalNm: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonicalNm / springStiffnessFactor : canonicalNm
    }

    /// Converts display spring stiffness value back to canonical N/m.
    public static func commitStiffness(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal * springStiffnessFactor : displayVal
    }

    /// Display unit symbol for spring stiffness under the given document length unit.
    public static func stiffnessUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "lbf/in" : "N/m"
    }

    // MARK: - Moment Conversions

    /// Converts canonical moment (N·m) to the display value for the given document length unit.
    public static func displayMoment(_ canonicalNm: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonicalNm * momentFactor : canonicalNm
    }

    /// Converts display moment value back to canonical N·m.
    public static func commitMoment(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal / momentFactor : displayVal
    }

    /// Display unit symbol for moment under the given document length unit.
    public static func momentUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "lbf·in" : "N·m"
    }

    // MARK: - Rotational Speed Conversions

    /// Converts canonical rotational speed (rad/s) to display value (RPM if imperial, rad/s if metric).
    public static func displayRotationalSpeed(_ canonicalRadS: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? canonicalRadS * rotationalSpeedFactor : canonicalRadS
    }

    /// Converts display rotational speed back to canonical rad/s.
    public static func commitRotationalSpeed(_ displayVal: Double, unit: LengthUnit) -> Double {
        unit.isImperial ? displayVal / rotationalSpeedFactor : displayVal
    }

    /// Display unit symbol for rotational speed under the given document length unit.
    public static func rotationalSpeedUnitSymbol(unit: LengthUnit) -> String {
        unit.isImperial ? "RPM" : "rad/s"
    }

    // MARK: - General Load Magnitude Conversions

    /// Converts canonical load magnitude according to load kind and document length unit.
    public static func displayLoadMagnitude(_ magnitude: Double, kind: SimulationLoadKind, unit: LengthUnit) -> Double {
        switch kind {
        case .force, .remoteLoad, .bearing:
            return displayForce(magnitude, unit: unit)
        case .pressure:
            return displayPressure(magnitude, unit: unit)
        case .gravity:
            return displayGravity(magnitude, unit: unit)
        case .moment:
            return displayMoment(magnitude, unit: unit)
        case .centrifugal:
            return displayRotationalSpeed(magnitude, unit: unit)
        case .thermalLoad, .temperature:
            return displayTemperature(magnitude, unit: unit)
        case .thermalFlux:
            return displayHeatFlux(magnitude, unit: unit)
        case .convection:
            return displayConvection(magnitude, unit: unit)
        case .heatPower:
            return displayHeatPower(magnitude, unit: unit)
        }
    }

    /// Converts display load magnitude back to canonical units according to load kind and document length unit.
    public static func commitLoadMagnitude(_ displayVal: Double, kind: SimulationLoadKind, unit: LengthUnit) -> Double {
        switch kind {
        case .force, .remoteLoad, .bearing:
            return commitForce(displayVal, unit: unit)
        case .pressure:
            return commitPressure(displayVal, unit: unit)
        case .gravity:
            return commitGravity(displayVal, unit: unit)
        case .moment:
            return commitMoment(displayVal, unit: unit)
        case .centrifugal:
            return commitRotationalSpeed(displayVal, unit: unit)
        case .thermalLoad, .temperature:
            return commitTemperature(displayVal, unit: unit)
        case .thermalFlux:
            return commitHeatFlux(displayVal, unit: unit)
        case .convection:
            return commitConvection(displayVal, unit: unit)
        case .heatPower:
            return commitHeatPower(displayVal, unit: unit)
        }
    }

    /// Appropriate unit symbol for the specified load kind and document length unit.
    public static func loadUnitSymbol(kind: SimulationLoadKind, unit: LengthUnit) -> String {
        switch kind {
        case .force, .remoteLoad, .bearing:
            return forceUnitSymbol(unit: unit)
        case .pressure:
            return pressureUnitSymbol(unit: unit)
        case .gravity:
            return gravityUnitSymbol(unit: unit)
        case .moment:
            return momentUnitSymbol(unit: unit)
        case .centrifugal:
            return rotationalSpeedUnitSymbol(unit: unit)
        case .thermalLoad, .temperature:
            return temperatureUnitSymbol(unit: unit)
        case .thermalFlux:
            return heatFluxUnitSymbol(unit: unit)
        case .convection:
            return convectionUnitSymbol(unit: unit)
        case .heatPower:
            return heatPowerUnitSymbol(unit: unit)
        }
    }

    // MARK: - Coordinate Resolution

    /// Resolves the effective coordinate system ID for a load within a study.
    public static func effectiveCoordinateSystemId(for load: SimulationLoad, in study: SimulationStudy) -> UUID? {
        load.coordinateSystemId ?? study.coordinateSystemId
    }

    /// Resolves the effective coordinate system ID for a fixture within a study.
    public static func effectiveCoordinateSystemId(for fixture: SimulationFixture, in study: SimulationStudy) -> UUID? {
        fixture.coordinateSystemId ?? study.coordinateSystemId
    }

    // MARK: - Coordinate Transformations

    /// Transforms a direction vector from local coordinate system space to world space.
    public static func transformLocalVectorToWorld(
        _ vector: SIMD3<Double>,
        coordinateSystem: DatumCoordinateSystemGeometry?
    ) -> SIMD3<Double> {
        guard let cs = coordinateSystem else { return vector }
        let x = SIMD3<Double>(Double(cs.xAxis.x), Double(cs.xAxis.y), Double(cs.xAxis.z))
        let y = SIMD3<Double>(Double(cs.yAxis.x), Double(cs.yAxis.y), Double(cs.yAxis.z))
        let z = SIMD3<Double>(Double(cs.zAxis.x), Double(cs.zAxis.y), Double(cs.zAxis.z))
        return x * vector.x + y * vector.y + z * vector.z
    }

    /// Transforms a direction vector from world space to local coordinate system space.
    public static func transformWorldVectorToLocal(
        _ vector: SIMD3<Double>,
        coordinateSystem: DatumCoordinateSystemGeometry?
    ) -> SIMD3<Double> {
        guard let cs = coordinateSystem else { return vector }
        let x = SIMD3<Double>(Double(cs.xAxis.x), Double(cs.xAxis.y), Double(cs.xAxis.z))
        let y = SIMD3<Double>(Double(cs.yAxis.x), Double(cs.yAxis.y), Double(cs.yAxis.z))
        let z = SIMD3<Double>(Double(cs.zAxis.x), Double(cs.zAxis.y), Double(cs.zAxis.z))
        return SIMD3<Double>(
            simd_dot(vector, x),
            simd_dot(vector, y),
            simd_dot(vector, z)
        )
    }

    /// Transforms a 3D point from local coordinate system space into world space.
    public static func transformLocalPointToWorld(
        _ point: SIMD3<Double>,
        coordinateSystem: DatumCoordinateSystemGeometry?
    ) -> SIMD3<Double> {
        guard let cs = coordinateSystem else { return point }
        let origin = SIMD3<Double>(Double(cs.origin.x), Double(cs.origin.y), Double(cs.origin.z))
        return origin + transformLocalVectorToWorld(point, coordinateSystem: cs)
    }

    /// Transforms a 3D point from world space into local coordinate system space.
    public static func transformWorldPointToLocal(
        _ point: SIMD3<Double>,
        coordinateSystem: DatumCoordinateSystemGeometry?
    ) -> SIMD3<Double> {
        guard let cs = coordinateSystem else { return point }
        let origin = SIMD3<Double>(Double(cs.origin.x), Double(cs.origin.y), Double(cs.origin.z))
        return transformWorldVectorToLocal(point - origin, coordinateSystem: cs)
    }

    // MARK: - Extrema Transformation

    /// Formats and transforms field extrema according to active document units and optional coordinate system.
    public static func displayExtrema(
        _ extrema: [SimulationFieldExtrema],
        coordinateSystem: DatumCoordinateSystemGeometry?,
        lengthUnit: LengthUnit
    ) -> [SimulationFieldExtrema] {
        guard !extrema.isEmpty else { return [] }

        // Identify directional displacement components (Ux, Uy, Uz)
        func isXDisplacement(_ name: String) -> Bool {
            let lower = name.lowercased()
            return lower == "ux" || lower == "displacement x" || lower == "u_x" || lower == "u1"
        }
        func isYDisplacement(_ name: String) -> Bool {
            let lower = name.lowercased()
            return lower == "uy" || lower == "displacement y" || lower == "u_y" || lower == "u2"
        }
        func isZDisplacement(_ name: String) -> Bool {
            let lower = name.lowercased()
            return lower == "uz" || lower == "displacement z" || lower == "u_z" || lower == "u3"
        }

        let xIndices = extrema.indices.filter { isXDisplacement(extrema[$0].fieldName) }
        let yIndices = extrema.indices.filter { isYDisplacement(extrema[$0].fieldName) }
        let zIndices = extrema.indices.filter { isZDisplacement(extrema[$0].fieldName) }

        let hasDirectionalDisplacement = (xIndices.count == 1 && yIndices.count == 1 && zIndices.count == 1)

        var rotatedRanges: [Int: (min: Double, max: Double)] = [:]
        if hasDirectionalDisplacement, let cs = coordinateSystem {
            let extX = extrema[xIndices[0]]
            let extY = extrema[yIndices[0]]
            let extZ = extrema[zIndices[0]]

            let ax = SIMD3<Double>(Double(cs.xAxis.x), Double(cs.xAxis.y), Double(cs.xAxis.z))
            let ay = SIMD3<Double>(Double(cs.yAxis.x), Double(cs.yAxis.y), Double(cs.yAxis.z))
            let az = SIMD3<Double>(Double(cs.zAxis.x), Double(cs.zAxis.y), Double(cs.zAxis.z))

            func projectRange(axis: SIMD3<Double>) -> (min: Double, max: Double) {
                let minVal = (axis.x >= 0 ? axis.x * extX.minValue : axis.x * extX.maxValue)
                           + (axis.y >= 0 ? axis.y * extY.minValue : axis.y * extY.maxValue)
                           + (axis.z >= 0 ? axis.z * extZ.minValue : axis.z * extZ.maxValue)
                let maxVal = (axis.x >= 0 ? axis.x * extX.maxValue : axis.x * extX.minValue)
                           + (axis.y >= 0 ? axis.y * extY.maxValue : axis.y * extY.minValue)
                           + (axis.z >= 0 ? axis.z * extZ.maxValue : axis.z * extZ.minValue)
                return (min: min(minVal, maxVal), max: max(minVal, maxVal))
            }

            rotatedRanges[xIndices[0]] = projectRange(axis: ax)
            rotatedRanges[yIndices[0]] = projectRange(axis: ay)
            rotatedRanges[zIndices[0]] = projectRange(axis: az)
        }

        func localLabel(_ name: String) -> String {
            if name.contains("Local") || name.contains("UCS") { return name }
            return "\(name) (Local)"
        }

        return extrema.enumerated().map { idx, ext in
            if let rotated = rotatedRanges[idx] {
                return SimulationFieldExtrema(
                    fieldName: localLabel(ext.fieldName),
                    unitSymbol: lengthUnit.symbol,
                    minValue: lengthUnit.fromMillimeters(rotated.min),
                    maxValue: lengthUnit.fromMillimeters(rotated.max)
                )
            }

            let lowerName = ext.fieldName.lowercased()
            let sym = ext.unitSymbol.trimmingCharacters(in: .whitespaces)

            // Displacement fields (mm)
            if sym == "mm" || sym == "in" || sym == "ft" || sym == "m" || sym == "cm" || lowerName.contains("displacement") || isXDisplacement(ext.fieldName) || isYDisplacement(ext.fieldName) || isZDisplacement(ext.fieldName) {
                return SimulationFieldExtrema(
                    fieldName: ext.fieldName,
                    unitSymbol: lengthUnit.symbol,
                    minValue: lengthUnit.fromMillimeters(ext.minValue),
                    maxValue: lengthUnit.fromMillimeters(ext.maxValue)
                )
            }

            // Stress fields (MPa)
            if sym == "MPa" || sym == "psi" || sym == "ksi" || lowerName.contains("stress") {
                return SimulationFieldExtrema(
                    fieldName: ext.fieldName,
                    unitSymbol: stressUnitSymbol(unit: lengthUnit),
                    minValue: displayStress(ext.minValue, unit: lengthUnit),
                    maxValue: displayStress(ext.maxValue, unit: lengthUnit)
                )
            }

            // Temperature fields (°C)
            if sym == "°C" || sym == "C" || sym == "°F" || sym == "F" || lowerName.contains("temperature") {
                return SimulationFieldExtrema(
                    fieldName: ext.fieldName,
                    unitSymbol: temperatureUnitSymbol(unit: lengthUnit),
                    minValue: displayTemperature(ext.minValue, unit: lengthUnit),
                    maxValue: displayTemperature(ext.maxValue, unit: lengthUnit)
                )
            }

            // Heat flux fields (W/m²)
            if sym == "W/m²" || sym == "W/m^2" || sym.contains("BTU") || lowerName.contains("flux") {
                return SimulationFieldExtrema(
                    fieldName: ext.fieldName,
                    unitSymbol: heatFluxUnitSymbol(unit: lengthUnit),
                    minValue: displayHeatFlux(ext.minValue, unit: lengthUnit),
                    maxValue: displayHeatFlux(ext.maxValue, unit: lengthUnit)
                )
            }

            // Unrecognized/custom fields pass through untouched
            return ext
        }
    }
}
