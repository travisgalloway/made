import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct MassPropertiesTests {

    // MARK: - 1. Analytic Box Tests

    @Test func testAnalyticBox10x20x30() {
        let props = computeAnalyticBox(
            width: 10,
            depth: 20,
            height: 30,
            density: 1000.0,
            coordinateSystem: .centroid
        )

        // Volume: 10 * 20 * 30 = 6000 mm³
        #expect(abs(props.volume - 6000.0) < 1e-6)

        // Surface Area: 2 * (10*20 + 10*30 + 20*30) = 2 * (200 + 300 + 600) = 2200 mm²
        #expect(abs(props.surfaceArea - 2200.0) < 1e-6)

        // Mass: 6000 mm³ * 1000 kg/m³ * 1e-9 = 0.006 kg = 6.0 g
        #expect(abs(props.mass - 0.006) < 1e-9)

        // Centroid at origin in .centroid frame
        #expect(abs(props.centerOfMass.x) < 1e-9)
        #expect(abs(props.centerOfMass.y) < 1e-9)
        #expect(abs(props.centerOfMass.z) < 1e-9)

        // Moments of Inertia at centroid:
        // Ixx = 1/12 * M * (d² + h²) = 0.006 / 12 * (400 + 900) = 0.0005 * 1300 = 0.65 kg·mm²
        // Iyy = 1/12 * M * (w² + h²) = 0.006 / 12 * (100 + 900) = 0.0005 * 1000 = 0.50 kg·mm²
        // Izz = 1/12 * M * (w² + d²) = 0.006 / 12 * (100 + 400) = 0.0005 * 500 = 0.25 kg·mm²
        #expect(abs(props.inertiaTensor.ixx - 0.65) < 1e-6)
        #expect(abs(props.inertiaTensor.iyy - 0.50) < 1e-6)
        #expect(abs(props.inertiaTensor.izz - 0.25) < 1e-6)
        #expect(abs(props.inertiaTensor.ixy) < 1e-9)
        #expect(abs(props.inertiaTensor.ixz) < 1e-9)
        #expect(abs(props.inertiaTensor.iyz) < 1e-9)

        // Principal moments sorted: I1 <= I2 <= I3 -> 0.25, 0.50, 0.65
        #expect(abs(props.principalMoments.i1 - 0.25) < 1e-6)
        #expect(abs(props.principalMoments.i2 - 0.50) < 1e-6)
        #expect(abs(props.principalMoments.i3 - 0.65) < 1e-6)
    }

    // MARK: - 2. Polyhedral Mesh Integrator vs Analytic Box

    @Test func testMeshPolyhedralIntegratorMatchesBox() {
        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 20, height: 30)
        let mesh = CandidateMesh(id: SolidId("box-test"), payload: payload, transform: .identity)

        let meshProps = computeMeshMassProperties(
            positions: mesh.positions,
            indices: mesh.indices,
            transform: .identity,
            density: 1000.0,
            coordinateSystem: .centroid
        )

        #expect(meshProps != nil)
        guard let meshProps else { return }

        // Volume and Area
        #expect(abs(meshProps.volume - 6000.0) < 1e-4)
        #expect(abs(meshProps.surfaceArea - 2200.0) < 1e-4)
        #expect(abs(meshProps.mass - 0.006) < 1e-7)

        // Centroid
        #expect(abs(meshProps.centerOfMass.x) < 1e-4)
        #expect(abs(meshProps.centerOfMass.y) < 1e-4)
        #expect(abs(meshProps.centerOfMass.z) < 1e-4)

        // Moments of Inertia
        #expect(abs(meshProps.inertiaTensor.ixx - 0.65) < 1e-4)
        #expect(abs(meshProps.inertiaTensor.iyy - 0.50) < 1e-4)
        #expect(abs(meshProps.inertiaTensor.izz - 0.25) < 1e-4)
        #expect(abs(meshProps.inertiaTensor.ixy) < 1e-4)
        #expect(abs(meshProps.inertiaTensor.ixz) < 1e-4)
        #expect(abs(meshProps.inertiaTensor.iyz) < 1e-4)

        // Principal moments
        #expect(abs(meshProps.principalMoments.i1 - 0.25) < 1e-4)
        #expect(abs(meshProps.principalMoments.i2 - 0.50) < 1e-4)
        #expect(abs(meshProps.principalMoments.i3 - 0.65) < 1e-4)
    }

    // MARK: - 3. Analytic Cylinder Tests

    @Test func testAnalyticCylinder() {
        let r: Float = 10.0
        let h: Float = 50.0
        let density: Double = 1000.0

        let props = computeAnalyticCylinder(
            radius: r,
            height: h,
            density: density,
            coordinateSystem: .centroid
        )

        let expectedVolume = Double.pi * 100.0 * 50.0 // 5000 * pi ~= 15707.963268
        let expectedArea = 2.0 * Double.pi * 10.0 * 50.0 + 2.0 * Double.pi * 100.0 // 1200 * pi ~= 3769.911184
        let expectedMass = expectedVolume * (density * 1e-9) // ~= 0.015707963 kg

        #expect(abs(props.volume - expectedVolume) < 1e-5)
        #expect(abs(props.surfaceArea - expectedArea) < 1e-5)
        #expect(abs(props.mass - expectedMass) < 1e-8)

        // Along symmetry axis Z: Izz = 0.5 * M * r²
        let expectedIzz = 0.5 * expectedMass * 100.0
        // Perpendicular: Ixx = Iyy = 1/12 * M * (3*r² + h²)
        let expectedIxx = (1.0 / 12.0) * expectedMass * (300.0 + 2500.0)

        #expect(abs(props.inertiaTensor.izz - expectedIzz) < 1e-6)
        #expect(abs(props.inertiaTensor.ixx - expectedIxx) < 1e-6)
        #expect(abs(props.inertiaTensor.iyy - expectedIxx) < 1e-6)

        // Principal moments sorted
        let minMom = min(expectedIzz, expectedIxx)
        let maxMom = max(expectedIzz, expectedIxx)
        #expect(abs(props.principalMoments.i1 - minMom) < 1e-6)
        #expect(abs(props.principalMoments.i3 - maxMom) < 1e-6)
    }

    // MARK: - 4. Analytic Sphere Tests

    @Test func testAnalyticSphere() {
        let r: Float = 15.0
        let density: Double = 1000.0

        let props = computeAnalyticSphere(
            radius: r,
            density: density,
            coordinateSystem: .centroid
        )

        let expectedVolume = (4.0 / 3.0) * Double.pi * 15.0 * 15.0 * 15.0 // 4500 * pi ~= 14137.16694
        let expectedArea = 4.0 * Double.pi * 15.0 * 15.0 // 900 * pi ~= 2827.433388
        let expectedMass = expectedVolume * (density * 1e-9)

        #expect(abs(props.volume - expectedVolume) < 1e-5)
        #expect(abs(props.surfaceArea - expectedArea) < 1e-5)
        #expect(abs(props.mass - expectedMass) < 1e-8)

        // Isotropic scalar inertia: 2/5 * M * r²
        let expectedI = (2.0 / 5.0) * expectedMass * 225.0
        #expect(abs(props.inertiaTensor.ixx - expectedI) < 1e-6)
        #expect(abs(props.inertiaTensor.iyy - expectedI) < 1e-6)
        #expect(abs(props.inertiaTensor.izz - expectedI) < 1e-6)

        // All principal moments must be equal to expectedI
        #expect(abs(props.principalMoments.i1 - expectedI) < 1e-6)
        #expect(abs(props.principalMoments.i2 - expectedI) < 1e-6)
        #expect(abs(props.principalMoments.i3 - expectedI) < 1e-6)
    }

    // MARK: - 5. Rotated and Translated Box (Parallel Axis & Rotations)

    @Test func testRotatedAndTranslatedBox() {
        // Box 10 x 20 x 30
        // Translate to (10, 20, 30)
        // Rotate 90 degrees around Z axis: X -> Y, Y -> -X
        let rot = simd_quatf(angle: .pi / 2.0, axis: SIMD3<Float>(0, 0, 1))
        let transform = Transform(
            position: SIMD3<Float>(10, 20, 30),
            rotation: rot,
            scale: SIMD3<Float>(1, 1, 1)
        )

        let worldProps = computeAnalyticBox(
            width: 10,
            depth: 20,
            height: 30,
            density: 1000.0,
            transform: transform,
            coordinateSystem: .world
        )

        // In world frame:
        // Center of mass is at (10, 20, 30)
        #expect(abs(worldProps.centerOfMass.x - 10.0) < 1e-5)
        #expect(abs(worldProps.centerOfMass.y - 20.0) < 1e-5)
        #expect(abs(worldProps.centerOfMass.z - 30.0) < 1e-5)

        // Local centroid inertia: Ixx=0.65, Iyy=0.50, Izz=0.25
        // Rotated by 90 deg around Z:
        // Ixx_rot = 0.50, Iyy_rot = 0.65, Izz_rot = 0.25
        // Parallel axis shift to (10, 20, 30):
        // Ixx_world = 0.50 + M * (20² + 30²) = 0.50 + 0.006 * 1300 = 8.30
        // Iyy_world = 0.65 + M * (10² + 30²) = 0.65 + 0.006 * 1000 = 6.65
        // Izz_world = 0.25 + M * (10² + 20²) = 0.25 + 0.006 * 500  = 3.25
        // Ixy_world = 0 + M * (10 * 20) = 0.006 * 200 = 1.20
        // Ixz_world = 0 + M * (10 * 30) = 0.006 * 300 = 1.80
        // Iyz_world = 0 + M * (20 * 30) = 0.006 * 600 = 3.60
        #expect(abs(worldProps.inertiaTensor.ixx - 8.30) < 1e-4)
        #expect(abs(worldProps.inertiaTensor.iyy - 6.65) < 1e-4)
        #expect(abs(worldProps.inertiaTensor.izz - 3.25) < 1e-4)
        #expect(abs(worldProps.inertiaTensor.ixy - 1.20) < 1e-4)
        #expect(abs(worldProps.inertiaTensor.ixz - 1.80) < 1e-4)
        #expect(abs(worldProps.inertiaTensor.iyz - 3.60) < 1e-4)
    }

    // MARK: - 6. Coordinate System Modes

    @Test func testCoordinateSystemModes() {
        let transform = Transform(
            position: SIMD3<Float>(5, 15, 25),
            rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            scale: SIMD3<Float>(1, 1, 1)
        )

        let centroidProps = computeAnalyticBox(width: 10, depth: 20, height: 30, density: 1000.0, transform: transform, coordinateSystem: .centroid)
        let bodyProps = computeAnalyticBox(width: 10, depth: 20, height: 30, density: 1000.0, transform: transform, coordinateSystem: .bodyLocal)
        let worldProps = computeAnalyticBox(width: 10, depth: 20, height: 30, density: 1000.0, transform: transform, coordinateSystem: .world)

        // Centroid frame
        #expect(centroidProps.coordinateSystem == .centroid)
        #expect(abs(centroidProps.centerOfMass.x) < 1e-9)
        #expect(abs(centroidProps.centerOfMass.y) < 1e-9)
        #expect(abs(centroidProps.centerOfMass.z) < 1e-9)
        #expect(abs(centroidProps.inertiaTensor.ixx - 0.65) < 1e-6)

        // Body local frame
        #expect(bodyProps.coordinateSystem == .bodyLocal)
        #expect(abs(bodyProps.centerOfMass.x) < 1e-9)
        #expect(abs(bodyProps.centerOfMass.y) < 1e-9)
        #expect(abs(bodyProps.centerOfMass.z) < 1e-9)
        #expect(abs(bodyProps.inertiaTensor.ixx - 0.65) < 1e-6)

        // World frame
        #expect(worldProps.coordinateSystem == .world)
        #expect(abs(worldProps.centerOfMass.x - 5.0) < 1e-5)
        #expect(abs(worldProps.centerOfMass.y - 15.0) < 1e-5)
        #expect(abs(worldProps.centerOfMass.z - 25.0) < 1e-5)
        // Ixx_world = 0.65 + 0.006 * (15² + 25²) = 0.65 + 0.006 * (225 + 625) = 0.65 + 5.10 = 5.75
        #expect(abs(worldProps.inertiaTensor.ixx - 5.75) < 1e-4)
    }

    // MARK: - 7. Jacobi 3x3 Eigensolver Tests

    @Test func testJacobiEigensolver() {
        // 1. Identity Matrix
        let identity = simd_double3x3(1.0)
        let (evalsI, axesI) = JacobiEigensolver.decompose(matrix: identity)
        #expect(abs(evalsI.x - 1.0) < 1e-9)
        #expect(abs(evalsI.y - 1.0) < 1e-9)
        #expect(abs(evalsI.z - 1.0) < 1e-9)
        // Orthonormal right-handed
        let detI = simd_dot(simd_cross(axesI[0], axesI[1]), axesI[2])
        #expect(abs(detI - 1.0) < 1e-6)

        // 2. Diagonal Matrix with distinct values: diag(50, 10, 30)
        let diag = simd_double3x3(
            SIMD3<Double>(50, 0, 0),
            SIMD3<Double>(0, 10, 0),
            SIMD3<Double>(0, 0, 30)
        )
        let (evalsDiag, axesDiag) = JacobiEigensolver.decompose(matrix: diag)
        // Ascending sorted: 10, 30, 50
        #expect(abs(evalsDiag.x - 10.0) < 1e-9)
        #expect(abs(evalsDiag.y - 30.0) < 1e-9)
        #expect(abs(evalsDiag.z - 50.0) < 1e-9)
        let detDiag = simd_dot(simd_cross(axesDiag[0], axesDiag[1]), axesDiag[2])
        #expect(abs(detDiag - 1.0) < 1e-6)

        // 3. Symmetric non-diagonal matrix:
        // [ 2, 1, 0 ]
        // [ 1, 2, 0 ]
        // [ 0, 0, 5 ]
        // Eigenvalues: 1, 3, 5
        let sym = simd_double3x3(
            SIMD3<Double>(2, 1, 0),
            SIMD3<Double>(1, 2, 0),
            SIMD3<Double>(0, 0, 5)
        )
        let (evalsSym, axesSym) = JacobiEigensolver.decompose(matrix: sym)
        #expect(abs(evalsSym.x - 1.0) < 1e-6)
        #expect(abs(evalsSym.y - 3.0) < 1e-6)
        #expect(abs(evalsSym.z - 5.0) < 1e-6)
        let detSym = simd_dot(simd_cross(axesSym[0], axesSym[1]), axesSym[2])
        #expect(abs(detSym - 1.0) < 1e-6)
    }

    // MARK: - 8. Material Density Resolution

    @Test @MainActor func testMaterialDensityResolution() {
        let doc = DocumentModel()

        // 1. Unassigned material -> 1000.0 kg/m³
        let boxSolidId = doc.addObject(def: .box(BoxParams(width: 10, depth: 10, height: 10)))
        let (_, defaultDensity) = MassPropertiesCalculator.resolveMaterialDensity(for: boxSolidId, in: doc)
        #expect(defaultDensity == 1000.0)

        // 2. Standard Material: Structural Steel (7850 kg/m³)
        let steelSolidId = doc.addObject(
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            material: MaterialAttributes(materialDefinitionId: StandardMaterials.structuralSteel.id)
        )
        let (steelName, steelDensity) = MassPropertiesCalculator.resolveMaterialDensity(for: steelSolidId, in: doc)
        #expect(steelName == StandardMaterials.structuralSteel.name)
        #expect(steelDensity == 7850.0)

        // 3. Standard Material: Aluminum 6061-T6 (2700 kg/m³)
        let alSolidId = doc.addObject(
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            material: MaterialAttributes(materialDefinitionId: StandardMaterials.aluminum6061T6.id)
        )
        let (alName, alDensity) = MassPropertiesCalculator.resolveMaterialDensity(for: alSolidId, in: doc)
        #expect(alName == StandardMaterials.aluminum6061T6.name)
        #expect(alDensity == 2700.0)

        // 4. Custom Document Material
        let customMat = MaterialDefinition(
            id: "custom-titanium-alloy",
            name: "Custom Titanium Alloy",
            category: .metal,
            description: "Custom density titanium",
            color: SIMD4<Float>(0.6, 0.6, 0.6, 1.0),
            citations: [],
            density: DensityQuantity(value: 4500.0, unit: .kgPerCubicMeter),
            youngsModulus: StressQuantity(value: 110, unit: .gigapascals),
            poissonsRatio: DimensionlessQuantity(value: 0.33, unit: .ratio),
            yieldStrength: StressQuantity(value: 800, unit: .megapascals),
            ultimateStrength: StressQuantity(value: 900, unit: .megapascals),
            thermalConductivity: ThermalConductivityQuantity(value: 7.0, unit: .wattsPerMeterKelvin),
            thermalExpansion: ThermalExpansionQuantity(value: 8.6, unit: .microstrainPerKelvin),
            specificHeat: SpecificHeatQuantity(value: 520, unit: .joulesPerKilogramKelvin)
        )
        doc.addCustomMaterial(customMat)

        let customSolidId = doc.addObject(
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            material: MaterialAttributes(materialDefinitionId: customMat.id)
        )
        let (customName, customResolvedDensity) = MassPropertiesCalculator.resolveMaterialDensity(for: customSolidId, in: doc)
        #expect(customName == "Custom Titanium Alloy")
        #expect(customResolvedDensity == 4500.0)
    }

    // MARK: - 9. Edge Cases (Degenerate, Empty, and Reversed Winding)

    @Test func testEmptyAndDegenerateMeshes() {
        // Empty positions
        let emptyProps = computeMeshMassProperties(positions: [], indices: [])
        #expect(emptyProps == nil)

        // Single degenerate triangle (0 volume)
        let singleTriPositions = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(10, 0, 0),
            SIMD3<Float>(0, 10, 0)
        ]
        let singleTriProps = computeMeshMassProperties(positions: singleTriPositions, indices: [0, 1, 2])
        #expect(singleTriProps == nil)
    }

    @Test func testReversedWindingHandledCleanly() {
        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 20, height: 30)

        var positions: [SIMD3<Float>] = []
        for i in stride(from: 0, to: payload.positions.count, by: 3) {
            positions.append(SIMD3<Float>(payload.positions[i], payload.positions[i + 1], payload.positions[i + 2]))
        }

        // Reverse triangle winding by swapping indices (i1 and i2)
        var reversedIndices: [UInt32] = []
        for t in stride(from: 0, to: payload.indices.count, by: 3) {
            reversedIndices.append(payload.indices[t])
            reversedIndices.append(payload.indices[t + 2])
            reversedIndices.append(payload.indices[t + 1])
        }

        let props = computeMeshMassProperties(
            positions: positions,
            indices: reversedIndices,
            transform: .identity,
            density: 1000.0,
            coordinateSystem: .centroid
        )

        #expect(props != nil)
        guard let props else { return }

        // Must still produce positive volume and correct positive mass & inertia
        #expect(abs(props.volume - 6000.0) < 1e-4)
        #expect(props.volume > 0)
        #expect(abs(props.mass - 0.006) < 1e-7)
        #expect(props.inertiaTensor.ixx > 0)
        #expect(props.inertiaTensor.iyy > 0)
        #expect(props.inertiaTensor.izz > 0)
    }

    // MARK: - 10. Formatted Report Export

    @Test func testFormattedReport() {
        let props = computeAnalyticBox(width: 10, depth: 20, height: 30, density: 1000.0, coordinateSystem: .centroid)
        let units = UnitSettings(lengthUnit: .millimeters, decimalPrecision: 2)
        let report = props.formattedReport(units: units)

        #expect(report.contains("Mass Properties Report"))
        #expect(report.contains("Coordinate System: Center of Mass"))
        #expect(report.contains("Mass: 6.00 g"))
        #expect(report.contains("Volume: 6000.00 mm³"))
        #expect(report.contains("Surface Area: 2200.00 mm²"))
        #expect(report.contains("Moments of Inertia (kg·mm²):"))
        #expect(report.contains("Principal Moments of Inertia (kg·mm²):"))
    }
}
