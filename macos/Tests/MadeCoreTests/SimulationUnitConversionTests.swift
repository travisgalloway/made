import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SimulationUnitConversionTests {

    // MARK: - Force Conversions

    @Test func testForceConversions() {
        // Metric: 1000 N remains 1000 N
        #expect(abs(SimulationUnitConversion.displayForce(1000.0, unit: .millimeters) - 1000.0) < 1e-6)
        #expect(abs(SimulationUnitConversion.commitForce(1000.0, unit: .millimeters) - 1000.0) < 1e-6)
        #expect(SimulationUnitConversion.forceUnitSymbol(unit: .millimeters) == "N")
        #expect(SimulationUnitConversion.forceUnitSymbol(unit: .meters) == "N")

        // Imperial: 1 lbf = 4.4482216152605 N
        let canonicalN = 4.4482216152605
        let displayLbf = SimulationUnitConversion.displayForce(canonicalN, unit: .inches)
        #expect(abs(displayLbf - 1.0) < 1e-6)
        let committedN = SimulationUnitConversion.commitForce(displayLbf, unit: .inches)
        #expect(abs(committedN - canonicalN) < 1e-6)
        #expect(SimulationUnitConversion.forceUnitSymbol(unit: .inches) == "lbf")
        #expect(SimulationUnitConversion.forceUnitSymbol(unit: .feet) == "lbf")
    }

    // MARK: - Pressure & Stress Conversions

    @Test func testPressureAndStressConversions() {
        // Metric: 1 MPa remains 1 MPa
        #expect(abs(SimulationUnitConversion.displayPressure(1.0, unit: .millimeters) - 1.0) < 1e-6)
        #expect(abs(SimulationUnitConversion.commitPressure(1.0, unit: .millimeters) - 1.0) < 1e-6)
        #expect(SimulationUnitConversion.pressureUnitSymbol(unit: .millimeters) == "MPa")
        #expect(SimulationUnitConversion.stressUnitSymbol(unit: .millimeters) == "MPa")

        // Imperial: 1 MPa = 145.03773773 psi
        let canonicalMPa = 10.0
        let displayPsi = SimulationUnitConversion.displayPressure(canonicalMPa, unit: .inches)
        #expect(abs(displayPsi - 1450.3773773) < 1e-4)
        let committedMPa = SimulationUnitConversion.commitPressure(displayPsi, unit: .inches)
        #expect(abs(committedMPa - canonicalMPa) < 1e-6)
        #expect(SimulationUnitConversion.pressureUnitSymbol(unit: .inches) == "psi")
        #expect(SimulationUnitConversion.stressUnitSymbol(unit: .inches) == "psi")

        // Stress display and commit
        let dispStress = SimulationUnitConversion.displayStress(5.0, unit: .inches)
        #expect(abs(dispStress - 5.0 * 145.03773773) < 1e-4)
        let commStress = SimulationUnitConversion.commitStress(dispStress, unit: .inches)
        #expect(abs(commStress - 5.0) < 1e-6)
    }

    // MARK: - Gravity Conversions

    @Test func testGravityConversions() {
        // Metric: 9.80665 m/s² remains unchanged
        #expect(abs(SimulationUnitConversion.displayGravity(9.80665, unit: .meters) - 9.80665) < 1e-6)
        #expect(abs(SimulationUnitConversion.commitGravity(9.80665, unit: .meters) - 9.80665) < 1e-6)
        #expect(SimulationUnitConversion.gravityUnitSymbol(unit: .meters) == "m/s²")

        // Imperial: 1 m/s² = 3.280839895 ft/s²
        let canonicalG = 9.80665
        let displayG = SimulationUnitConversion.displayGravity(canonicalG, unit: .feet)
        #expect(abs(displayG - (9.80665 * 3.280839895)) < 1e-4)
        let committedG = SimulationUnitConversion.commitGravity(displayG, unit: .feet)
        #expect(abs(committedG - canonicalG) < 1e-6)
        #expect(SimulationUnitConversion.gravityUnitSymbol(unit: .feet) == "ft/s²")
        #expect(SimulationUnitConversion.gravityUnitSymbol(unit: .inches) == "ft/s²")
    }

    // MARK: - Temperature Conversions

    @Test func testTemperatureConversions() {
        // Metric: 100 °C remains 100 °C
        #expect(abs(SimulationUnitConversion.displayTemperature(100.0, unit: .millimeters) - 100.0) < 1e-6)
        #expect(abs(SimulationUnitConversion.commitTemperature(100.0, unit: .millimeters) - 100.0) < 1e-6)
        #expect(SimulationUnitConversion.temperatureUnitSymbol(unit: .millimeters) == "°C")

        // Imperial: T(°F) = T(°C) * 1.8 + 32
        // 0 °C -> 32 °F
        #expect(abs(SimulationUnitConversion.displayTemperature(0.0, unit: .inches) - 32.0) < 1e-6)
        #expect(abs(SimulationUnitConversion.commitTemperature(32.0, unit: .inches) - 0.0) < 1e-6)

        // 100 °C -> 212 °F
        #expect(abs(SimulationUnitConversion.displayTemperature(100.0, unit: .inches) - 212.0) < 1e-6)
        #expect(abs(SimulationUnitConversion.commitTemperature(212.0, unit: .inches) - 100.0) < 1e-6)

        // -40 °C -> -40 °F
        #expect(abs(SimulationUnitConversion.displayTemperature(-40.0, unit: .inches) - -40.0) < 1e-6)
        #expect(abs(SimulationUnitConversion.commitTemperature(-40.0, unit: .inches) - -40.0) < 1e-6)

        #expect(SimulationUnitConversion.temperatureUnitSymbol(unit: .inches) == "°F")
    }

    // MARK: - Heat Flux Conversions

    @Test func testHeatFluxConversions() {
        // Metric: 500 W/m²
        #expect(abs(SimulationUnitConversion.displayHeatFlux(500.0, unit: .millimeters) - 500.0) < 1e-6)
        #expect(abs(SimulationUnitConversion.commitHeatFlux(500.0, unit: .millimeters) - 500.0) < 1e-6)
        #expect(SimulationUnitConversion.heatFluxUnitSymbol(unit: .millimeters) == "W/m²")

        // Imperial: 1 W/m² = 0.316998396 BTU/(hr·ft²)
        let canonicalFlux = 1000.0
        let displayFlux = SimulationUnitConversion.displayHeatFlux(canonicalFlux, unit: .inches)
        #expect(abs(displayFlux - (1000.0 * 0.316998396)) < 1e-4)
        let committedFlux = SimulationUnitConversion.commitHeatFlux(displayFlux, unit: .inches)
        #expect(abs(committedFlux - canonicalFlux) < 1e-6)
        #expect(SimulationUnitConversion.heatFluxUnitSymbol(unit: .inches) == "BTU/(hr·ft²)")
    }

    // MARK: - Length & Displacement Conversions

    @Test func testLengthAndDisplacementConversions() {
        // 25.4 mm -> 1.0 inch
        let canonicalMm = 25.4
        let dispInches = SimulationUnitConversion.displayLength(canonicalMm, unit: .inches)
        #expect(abs(dispInches - 1.0) < 1e-6)
        let commMm = SimulationUnitConversion.commitLength(dispInches, unit: .inches)
        #expect(abs(commMm - canonicalMm) < 1e-6)
        #expect(SimulationUnitConversion.lengthUnitSymbol(unit: .inches) == "in")

        // 3D displacement vector
        let vecMm = SIMD3<Double>(25.4, 50.8, -12.7)
        let dispVec = SimulationUnitConversion.displayDisplacement(vecMm, unit: .inches)
        #expect(abs(dispVec.x - 1.0) < 1e-6)
        #expect(abs(dispVec.y - 2.0) < 1e-6)
        #expect(abs(dispVec.z - -0.5) < 1e-6)

        let commVec = SimulationUnitConversion.commitDisplacement(dispVec, unit: .inches)
        #expect(abs(commVec.x - vecMm.x) < 1e-6)
        #expect(abs(commVec.y - vecMm.y) < 1e-6)
        #expect(abs(commVec.z - vecMm.z) < 1e-6)
    }

    // MARK: - General Load Magnitude Conversions

    @Test func testLoadMagnitudeConversionsForAllKinds() {
        for kind in SimulationLoadKind.allCases {
            let metricSymbol = SimulationUnitConversion.loadUnitSymbol(kind: kind, unit: .millimeters)
            let imperialSymbol = SimulationUnitConversion.loadUnitSymbol(kind: kind, unit: .inches)

            #expect(!metricSymbol.isEmpty)
            #expect(!imperialSymbol.isEmpty)

            let testVal = 100.0
            let displayed = SimulationUnitConversion.displayLoadMagnitude(testVal, kind: kind, unit: .inches)
            let committed = SimulationUnitConversion.commitLoadMagnitude(displayed, kind: kind, unit: .inches)
            #expect(abs(committed - testVal) < 1e-5)
        }
    }

    // MARK: - Coordinate Resolution

    @Test func testEffectiveCoordinateSystemId() {
        let ucsStudy = UUID()
        let ucsChild = UUID()

        // 1. Child overrides study
        let studyWithUCS = SimulationStudy(coordinateSystemId: ucsStudy)
        let loadWithUCS = SimulationLoad(coordinateSystemId: ucsChild)
        let fixtureWithUCS = SimulationFixture(coordinateSystemId: ucsChild)

        #expect(SimulationUnitConversion.effectiveCoordinateSystemId(for: loadWithUCS, in: studyWithUCS) == ucsChild)
        #expect(SimulationUnitConversion.effectiveCoordinateSystemId(for: fixtureWithUCS, in: studyWithUCS) == ucsChild)

        // 2. Child inherits study UCS when child is nil
        let loadDefault = SimulationLoad(coordinateSystemId: nil)
        let fixtureDefault = SimulationFixture(coordinateSystemId: nil)

        #expect(SimulationUnitConversion.effectiveCoordinateSystemId(for: loadDefault, in: studyWithUCS) == ucsStudy)
        #expect(SimulationUnitConversion.effectiveCoordinateSystemId(for: fixtureDefault, in: studyWithUCS) == ucsStudy)

        // 3. Both nil -> returns nil (global)
        let studyGlobal = SimulationStudy(coordinateSystemId: nil)
        #expect(SimulationUnitConversion.effectiveCoordinateSystemId(for: loadDefault, in: studyGlobal) == nil)
        #expect(SimulationUnitConversion.effectiveCoordinateSystemId(for: fixtureDefault, in: studyGlobal) == nil)
    }

    // MARK: - Coordinate Transformations

    @Test func testVectorAndPointTransformations() {
        // Coordinate system rotated 90 degrees around Z axis:
        // Local X = World Y, Local Y = -World X, Local Z = World Z
        // Origin at (10, 20, 30)
        let ucs = DatumCoordinateSystemGeometry(
            origin: SIMD3<Float>(10, 20, 30),
            xAxis: SIMD3<Float>(0, 1, 0),
            yAxis: SIMD3<Float>(-1, 0, 0),
            zAxis: SIMD3<Float>(0, 0, 1)
        )

        // Vector transforms (ignore origin)
        let localVec = SIMD3<Double>(1, 0, 0)
        let worldVec = SimulationUnitConversion.transformLocalVectorToWorld(localVec, coordinateSystem: ucs)
        #expect(abs(worldVec.x - 0) < 1e-6)
        #expect(abs(worldVec.y - 1) < 1e-6)
        #expect(abs(worldVec.z - 0) < 1e-6)

        let backToLocal = SimulationUnitConversion.transformWorldVectorToLocal(worldVec, coordinateSystem: ucs)
        #expect(abs(backToLocal.x - localVec.x) < 1e-6)
        #expect(abs(backToLocal.y - localVec.y) < 1e-6)
        #expect(abs(backToLocal.z - localVec.z) < 1e-6)

        // Point transforms (include origin offset)
        let localPt = SIMD3<Double>(5, 0, 0)
        let worldPt = SimulationUnitConversion.transformLocalPointToWorld(localPt, coordinateSystem: ucs)
        #expect(abs(worldPt.x - 10) < 1e-6)
        #expect(abs(worldPt.y - 25) < 1e-6) // 20 + 5
        #expect(abs(worldPt.z - 30) < 1e-6)

        let backPt = SimulationUnitConversion.transformWorldPointToLocal(worldPt, coordinateSystem: ucs)
        #expect(abs(backPt.x - localPt.x) < 1e-6)
        #expect(abs(backPt.y - localPt.y) < 1e-6)
        #expect(abs(backPt.z - localPt.z) < 1e-6)

        // Nil coordinate system fallback: returns original vector and point unchanged
        let orig = SIMD3<Double>(12, 34, 56)
        #expect(SimulationUnitConversion.transformLocalVectorToWorld(orig, coordinateSystem: nil) == orig)
        #expect(SimulationUnitConversion.transformWorldVectorToLocal(orig, coordinateSystem: nil) == orig)
        #expect(SimulationUnitConversion.transformLocalPointToWorld(orig, coordinateSystem: nil) == orig)
        #expect(SimulationUnitConversion.transformWorldPointToLocal(orig, coordinateSystem: nil) == orig)
    }

    // MARK: - Extrema Display and Transformations

    @Test func testDisplayExtremaScalarFields() {
        let inputExtrema = [
            SimulationFieldExtrema(fieldName: "Total Displacement", unitSymbol: "mm", minValue: 0.0, maxValue: 25.4),
            SimulationFieldExtrema(fieldName: "Von Mises Stress", unitSymbol: "MPa", minValue: 10.0, maxValue: 100.0),
            SimulationFieldExtrema(fieldName: "Nodal Temperature", unitSymbol: "°C", minValue: 0.0, maxValue: 100.0),
            SimulationFieldExtrema(fieldName: "Surface Heat Flux", unitSymbol: "W/m²", minValue: 0.0, maxValue: 1000.0),
            SimulationFieldExtrema(fieldName: "Modal Frequency", unitSymbol: "Hz", minValue: 120.0, maxValue: 450.0)
        ]

        // Metric display
        let metricResults = SimulationUnitConversion.displayExtrema(inputExtrema, coordinateSystem: nil, lengthUnit: .millimeters)
        #expect(metricResults[0].unitSymbol == "mm")
        #expect(metricResults[0].maxValue == 25.4)
        #expect(metricResults[1].unitSymbol == "MPa")
        #expect(metricResults[1].maxValue == 100.0)
        #expect(metricResults[2].unitSymbol == "°C")
        #expect(metricResults[2].maxValue == 100.0)
        #expect(metricResults[3].unitSymbol == "W/m²")
        #expect(metricResults[3].maxValue == 1000.0)
        #expect(metricResults[4].unitSymbol == "Hz")
        #expect(metricResults[4].maxValue == 450.0)

        // Imperial display
        let imperialResults = SimulationUnitConversion.displayExtrema(inputExtrema, coordinateSystem: nil, lengthUnit: .inches)
        #expect(imperialResults[0].unitSymbol == "in")
        #expect(abs(imperialResults[0].maxValue - 1.0) < 1e-5) // 25.4 mm = 1.0 in
        #expect(imperialResults[1].unitSymbol == "psi")
        #expect(abs(imperialResults[1].maxValue - (100.0 * 145.03773773)) < 1e-4)
        #expect(imperialResults[2].unitSymbol == "°F")
        #expect(abs(imperialResults[2].minValue - 32.0) < 1e-5)
        #expect(abs(imperialResults[2].maxValue - 212.0) < 1e-5)
        #expect(imperialResults[3].unitSymbol == "BTU/(hr·ft²)")
        #expect(abs(imperialResults[3].maxValue - (1000.0 * 0.316998396)) < 1e-4)
        #expect(imperialResults[4].unitSymbol == "Hz") // Unrecognized passes through
        #expect(imperialResults[4].maxValue == 450.0)
    }

    @Test func testDisplayExtremaDirectionalDisplacementWithUCS() {
        let extrema = [
            SimulationFieldExtrema(fieldName: "Ux", unitSymbol: "mm", minValue: -25.4, maxValue: 50.8),
            SimulationFieldExtrema(fieldName: "Uy", unitSymbol: "mm", minValue: 0.0, maxValue: 25.4),
            SimulationFieldExtrema(fieldName: "Uz", unitSymbol: "mm", minValue: -10.0, maxValue: 10.0)
        ]

        // 1. Without UCS (Global): values converted to document unit, field names preserved
        let globalResults = SimulationUnitConversion.displayExtrema(extrema, coordinateSystem: nil, lengthUnit: .inches)
        #expect(globalResults[0].fieldName == "Ux")
        #expect(globalResults[0].unitSymbol == "in")
        #expect(abs(globalResults[0].minValue - -1.0) < 1e-5)
        #expect(abs(globalResults[0].maxValue - 2.0) < 1e-5)

        // 2. With UCS rotated: Local X = World Y, Local Y = -World X, Local Z = World Z
        let rotatedUCS = DatumCoordinateSystemGeometry(
            origin: .zero,
            xAxis: SIMD3<Float>(0, 1, 0),
            yAxis: SIMD3<Float>(-1, 0, 0),
            zAxis: SIMD3<Float>(0, 0, 1)
        )

        let localResults = SimulationUnitConversion.displayExtrema(extrema, coordinateSystem: rotatedUCS, lengthUnit: .inches)
        // Local X corresponds to World Y (0 ... 25.4 mm -> 0 ... 1 in)
        #expect(localResults[0].fieldName.contains("Local"))
        #expect(localResults[0].unitSymbol == "in")
        #expect(abs(localResults[0].minValue - 0.0) < 1e-5)
        #expect(abs(localResults[0].maxValue - 1.0) < 1e-5)

        // Local Y corresponds to -World X:
        // World X is -25.4 ... 50.8 mm -> -World X is -50.8 ... 25.4 mm -> -2 ... 1 in
        #expect(localResults[1].fieldName.contains("Local"))
        #expect(abs(localResults[1].minValue - -2.0) < 1e-5)
        #expect(abs(localResults[1].maxValue - 1.0) < 1e-5)

        // Local Z corresponds to World Z (-10 ... 10 mm)
        #expect(localResults[2].fieldName.contains("Local"))
        #expect(abs(localResults[2].minValue - (-10.0 / 25.4)) < 1e-5)
        #expect(abs(localResults[2].maxValue - (10.0 / 25.4)) < 1e-5)
    }

    @Test func testDisplayExtremaEmptyAndUnrecognized() {
        #expect(SimulationUnitConversion.displayExtrema([], coordinateSystem: nil, lengthUnit: .millimeters).isEmpty)

        let unknown = [SimulationFieldExtrema(fieldName: "Custom Field", unitSymbol: "units", minValue: 1.0, maxValue: 9.0)]
        let res = SimulationUnitConversion.displayExtrema(unknown, coordinateSystem: nil, lengthUnit: .inches)
        #expect(res.count == 1)
        #expect(res[0].fieldName == "Custom Field")
        #expect(res[0].unitSymbol == "units")
        #expect(res[0].minValue == 1.0)
        #expect(res[0].maxValue == 9.0)
    }
}
