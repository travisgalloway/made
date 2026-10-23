import Foundation
import simd

/// Coordinate system used for mass properties evaluation and reporting.
public enum MassPropertiesCoordinateSystem: String, CaseIterable, Identifiable, Sendable, Codable, Equatable {
    case centroid = "centroid"
    case bodyLocal = "bodyLocal"
    case world = "world"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .centroid:
            return "Center of Mass"
        case .bodyLocal:
            return "Body Local"
        case .world:
            return "World Origin"
        }
    }
}

/// 3x3 symmetric inertia tensor storing moments and products of inertia.
/// Internal storage is in kilograms · square millimeters (kg · mm²).
public struct InertiaTensor: Sendable, Equatable, Codable {
    public var ixx: Double
    public var iyy: Double
    public var izz: Double
    public var ixy: Double
    public var ixz: Double
    public var iyz: Double

    public init(
        ixx: Double = 0,
        iyy: Double = 0,
        izz: Double = 0,
        ixy: Double = 0,
        ixz: Double = 0,
        iyz: Double = 0
    ) {
        self.ixx = ixx
        self.iyy = iyy
        self.izz = izz
        self.ixy = ixy
        self.ixz = ixz
        self.iyz = iyz
    }

    /// Moment of inertia Ixx in kg · m².
    public var ixxMetersSquared: Double { ixx * 1e-6 }

    /// Moment of inertia Iyy in kg · m².
    public var iyyMetersSquared: Double { iyy * 1e-6 }

    /// Moment of inertia Izz in kg · m².
    public var izzMetersSquared: Double { izz * 1e-6 }

    /// Product of inertia Ixy in kg · m².
    public var ixyMetersSquared: Double { ixy * 1e-6 }

    /// Product of inertia Ixz in kg · m².
    public var ixzMetersSquared: Double { ixz * 1e-6 }

    /// Product of inertia Iyz in kg · m².
    public var iyzMetersSquared: Double { iyz * 1e-6 }

    /// Translates the inertia tensor by an offset vector using the parallel axis theorem (Huygens-Steiner theorem).
    /// To shift from center of mass to an offset reference point, pass positive mass.
    /// To shift from an offset reference point to center of mass, pass negative mass.
    public func translated(by offset: SIMD3<Double>, mass: Double) -> InertiaTensor {
        let dx = offset.x
        let dy = offset.y
        let dz = offset.z
        return InertiaTensor(
            ixx: ixx + mass * (dy * dy + dz * dz),
            iyy: iyy + mass * (dx * dx + dz * dz),
            izz: izz + mass * (dx * dx + dy * dy),
            ixy: ixy + mass * (dx * dy),
            ixz: ixz + mass * (dx * dz),
            iyz: iyz + mass * (dy * dz)
        )
    }

    /// Returns a new inertia tensor scaled by a uniform scalar factor.
    public func scaled(by factor: Double) -> InertiaTensor {
        InertiaTensor(
            ixx: ixx * factor,
            iyy: iyy * factor,
            izz: izz * factor,
            ixy: ixy * factor,
            ixz: ixz * factor,
            iyz: iyz * factor
        )
    }

    /// Rotates the inertia tensor by an orthonormal 3x3 rotation matrix: I' = R * I * R^T.
    public func rotated(by matrix: simd_double3x3) -> InertiaTensor {
        let iPhys = self.matrix(physicsSignConvention: true)
        let rotatedPhys = matrix * iPhys * matrix.transpose
        return InertiaTensor(
            ixx: rotatedPhys.columns.0.x,
            iyy: rotatedPhys.columns.1.y,
            izz: rotatedPhys.columns.2.z,
            ixy: -rotatedPhys.columns.0.y,
            ixz: -rotatedPhys.columns.0.z,
            iyz: -rotatedPhys.columns.1.z
        )
    }

    /// Returns the 3x3 symmetric matrix representation.
    /// When `physicsSignConvention` is true (default), off-diagonal elements are -Ixy, -Ixz, -Iyz for eigensolver.
    public func matrix(physicsSignConvention: Bool = true) -> simd_double3x3 {
        let s: Double = physicsSignConvention ? -1.0 : 1.0
        return simd_double3x3(
            SIMD3<Double>(ixx, s * ixy, s * ixz),
            SIMD3<Double>(s * ixy, iyy, s * iyz),
            SIMD3<Double>(s * ixz, s * iyz, izz)
        )
    }
}

/// Principal moments of inertia and orthonormal right-handed principal axes.
public struct PrincipalMoments: Sendable, Equatable, Codable {
    public var i1: Double
    public var i2: Double
    public var i3: Double
    public var axis1: SIMD3<Double>
    public var axis2: SIMD3<Double>
    public var axis3: SIMD3<Double>

    public init(
        i1: Double,
        i2: Double,
        i3: Double,
        axis1: SIMD3<Double>,
        axis2: SIMD3<Double>,
        axis3: SIMD3<Double>
    ) {
        self.i1 = i1
        self.i2 = i2
        self.i3 = i3
        self.axis1 = axis1
        self.axis2 = axis2
        self.axis3 = axis3
    }

    public var i1MetersSquared: Double { i1 * 1e-6 }
    public var i2MetersSquared: Double { i2 * 1e-6 }
    public var i3MetersSquared: Double { i3 * 1e-6 }
}

/// Mass properties calculated for a solid body in a specified coordinate system.
public struct MassProperties: Sendable, Equatable, Codable {
    public var volume: Double
    public var surfaceArea: Double
    public var density: Double
    public var mass: Double
    public var centerOfMass: SIMD3<Double>
    public var inertiaTensor: InertiaTensor
    public var principalMoments: PrincipalMoments
    public var coordinateSystem: MassPropertiesCoordinateSystem
    public var isMassOverridden: Bool
    public var isCenterOfMassOverridden: Bool

    public init(
        volume: Double,
        surfaceArea: Double,
        density: Double,
        mass: Double,
        centerOfMass: SIMD3<Double>,
        inertiaTensor: InertiaTensor,
        principalMoments: PrincipalMoments,
        coordinateSystem: MassPropertiesCoordinateSystem,
        isMassOverridden: Bool = false,
        isCenterOfMassOverridden: Bool = false
    ) {
        self.volume = volume
        self.surfaceArea = surfaceArea
        self.density = density
        self.mass = mass
        self.centerOfMass = centerOfMass
        self.inertiaTensor = inertiaTensor
        self.principalMoments = principalMoments
        self.coordinateSystem = coordinateSystem
        self.isMassOverridden = isMassOverridden
        self.isCenterOfMassOverridden = isCenterOfMassOverridden
    }

    /// Produces a formatted text report suitable for clipboard copying.
    public func formattedReport(units: UnitSettings) -> String {
        var lines: [String] = []
        lines.append("Mass Properties Report")
        if isMassOverridden || isCenterOfMassOverridden {
            lines.append("Status: Overridden (Purchased Part)")
        }
        lines.append("Coordinate System: \(coordinateSystem.displayName)")
        lines.append("----------------------------------------")
        lines.append("Density: \(String(format: "%.2f", density)) kg/m³")
        let massTag = isMassOverridden ? " (Overridden)" : ""
        lines.append("Mass: \(units.formatMass(mass))\(massTag)")
        lines.append("Volume: \(units.formatVolume(volume))")
        lines.append("Surface Area: \(units.formatArea(surfaceArea))")
        lines.append("")
        let cmTag = isCenterOfMassOverridden ? " (Overridden)" : ""
        lines.append("Center of Mass:\(cmTag)")
        lines.append("  X: \(units.formatLength(centerOfMass.x))")
        lines.append("  Y: \(units.formatLength(centerOfMass.y))")
        lines.append("  Z: \(units.formatLength(centerOfMass.z))")
        lines.append("")
        lines.append("Moments of Inertia (kg·mm²):")
        lines.append("  Ixx: \(String(format: "%.6e", inertiaTensor.ixx))")
        lines.append("  Iyy: \(String(format: "%.6e", inertiaTensor.iyy))")
        lines.append("  Izz: \(String(format: "%.6e", inertiaTensor.izz))")
        lines.append("  Ixy: \(String(format: "%.6e", inertiaTensor.ixy))")
        lines.append("  Ixz: \(String(format: "%.6e", inertiaTensor.ixz))")
        lines.append("  Iyz: \(String(format: "%.6e", inertiaTensor.iyz))")
        lines.append("")
        lines.append("Moments of Inertia (kg·m²):")
        lines.append("  Ixx: \(String(format: "%.6e", inertiaTensor.ixxMetersSquared))")
        lines.append("  Iyy: \(String(format: "%.6e", inertiaTensor.iyyMetersSquared))")
        lines.append("  Izz: \(String(format: "%.6e", inertiaTensor.izzMetersSquared))")
        lines.append("  Ixy: \(String(format: "%.6e", inertiaTensor.ixyMetersSquared))")
        lines.append("  Ixz: \(String(format: "%.6e", inertiaTensor.ixzMetersSquared))")
        lines.append("  Iyz: \(String(format: "%.6e", inertiaTensor.iyzMetersSquared))")
        lines.append("")
        lines.append("Principal Moments of Inertia (kg·mm²):")
        lines.append("  I1: \(String(format: "%.6e", principalMoments.i1))")
        lines.append("  I2: \(String(format: "%.6e", principalMoments.i2))")
        lines.append("  I3: \(String(format: "%.6e", principalMoments.i3))")
        lines.append("Principal Axes:")
        lines.append("  v1: (\(String(format: "%.4f", principalMoments.axis1.x)), \(String(format: "%.4f", principalMoments.axis1.y)), \(String(format: "%.4f", principalMoments.axis1.z)))")
        lines.append("  v2: (\(String(format: "%.4f", principalMoments.axis2.x)), \(String(format: "%.4f", principalMoments.axis2.y)), \(String(format: "%.4f", principalMoments.axis2.z)))")
        lines.append("  v3: (\(String(format: "%.4f", principalMoments.axis3.x)), \(String(format: "%.4f", principalMoments.axis3.y)), \(String(format: "%.4f", principalMoments.axis3.z)))")
        return lines.joined(separator: "\n")
    }
}

/// Jacobi eigenvalue and eigenvector algorithm for symmetric 3x3 matrices.
public enum JacobiEigensolver {
    /// Decomposes a symmetric 3x3 matrix into sorted ascending eigenvalues (I1 <= I2 <= I3)
    /// and right-handed orthonormal eigenvectors.
    public static func decompose(matrix: simd_double3x3) -> (eigenvalues: SIMD3<Double>, eigenvectors: [SIMD3<Double>]) {
        var a = [
            [matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x],
            [matrix.columns.0.y, matrix.columns.1.y, matrix.columns.2.y],
            [matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z]
        ]
        var v: [[Double]] = [
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0]
        ]

        let maxSweeps = 50
        let epsilon = 1e-12

        for _ in 0..<maxSweeps {
            var maxOffDiag = 0.0
            for i in 0..<3 {
                for j in (i + 1)..<3 {
                    maxOffDiag = Swift.max(maxOffDiag, abs(a[i][j]))
                }
            }
            if maxOffDiag < epsilon { break }

            for p in 0..<2 {
                for q in (p + 1)..<3 {
                    let apq = a[p][q]
                    if abs(apq) < epsilon { continue }

                    let app = a[p][p]
                    let aqq = a[q][q]
                    let diff = aqq - app

                    let t: Double
                    if abs(diff) > epsilon {
                        let tau = diff / (2.0 * apq)
                        if tau >= 0 {
                            t = 1.0 / (tau + sqrt(1.0 + tau * tau))
                        } else {
                            t = -1.0 / (-tau + sqrt(1.0 + tau * tau))
                        }
                    } else {
                        t = (apq > 0) ? 1.0 : -1.0
                    }

                    let c = 1.0 / sqrt(1.0 + t * t)
                    let s = t * c
                    let tauRot = s / (1.0 + c)

                    a[p][q] = 0.0
                    a[q][p] = 0.0
                    a[p][p] = app - t * apq
                    a[q][q] = aqq + t * apq

                    for r in 0..<3 {
                        if r != p && r != q {
                            let arp = a[r][p]
                            let arq = a[r][q]
                            a[r][p] = arp - s * (arq + tauRot * arp)
                            a[p][r] = a[r][p]
                            a[r][q] = arq + s * (arp - tauRot * arq)
                            a[q][r] = a[r][q]
                        }
                    }

                    for r in 0..<3 {
                        let vrp = v[r][p]
                        let vrq = v[r][q]
                        v[r][p] = vrp - s * (vrq + tauRot * vrp)
                        v[r][q] = vrq + s * (vrp - tauRot * vrq)
                    }
                }
            }
        }

        let eval0 = a[0][0]
        let eval1 = a[1][1]
        let eval2 = a[2][2]
        var v0 = SIMD3<Double>(v[0][0], v[1][0], v[2][0])
        var v1 = SIMD3<Double>(v[0][1], v[1][1], v[2][1])
        var v2 = SIMD3<Double>(v[0][2], v[1][2], v[2][2])

        let l0 = simd_length(v0)
        let l1 = simd_length(v1)
        let l2 = simd_length(v2)
        v0 = l0 > epsilon ? v0 / l0 : SIMD3<Double>(1, 0, 0)
        v1 = l1 > epsilon ? v1 / l1 : SIMD3<Double>(0, 1, 0)
        v2 = l2 > epsilon ? v2 / l2 : SIMD3<Double>(0, 0, 1)

        var pairs: [(val: Double, vec: SIMD3<Double>)] = [
            (eval0, v0),
            (eval1, v1),
            (eval2, v2)
        ]
        pairs.sort { $0.val < $1.val }

        let sortedEvals = SIMD3<Double>(pairs[0].val, pairs[1].val, pairs[2].val)
        let axis1 = pairs[0].vec
        let axis2 = pairs[1].vec
        var axis3 = pairs[2].vec

        let cross = simd_cross(axis1, axis2)
        let det = simd_dot(cross, axis3)
        if det < 0 {
            axis3 = -axis3
        }

        return (sortedEvals, [axis1, axis2, axis3])
    }
}

/// Helper to build `MassProperties` from intrinsic body-local properties and spatial transform.
public func buildMassProperties(
    volume: Double,
    surfaceArea: Double,
    density: Double,
    mass: Double,
    centerOfMassLocal: SIMD3<Double>,
    centroidInertia: InertiaTensor,
    transform: Transform,
    coordinateSystem: MassPropertiesCoordinateSystem,
    override: MassOverride? = nil
) -> MassProperties {
    let isMassOverridden = (override?.isPurchased == true && override?.overrideMass != nil)
    let isCmOverridden = (override?.isPurchased == true && override?.overrideCenterOfMass != nil)

    let effectiveMass = isMassOverridden ? (override?.overrideMass ?? mass) : mass
    let effectiveCmLocal = isCmOverridden ? (override?.overrideCenterOfMass ?? centerOfMassLocal) : centerOfMassLocal

    var effectiveCentroidInertia = centroidInertia
    if isMassOverridden && mass > 1e-12 {
        let factor = effectiveMass / mass
        effectiveCentroidInertia = centroidInertia.scaled(by: factor)
    }

    let rot = transform.rotation
    let qx = Double(rot.imag.x)
    let qy = Double(rot.imag.y)
    let qz = Double(rot.imag.z)
    let qw = Double(rot.real)
    let qlen = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    let nx = qlen > 1e-12 ? qx / qlen : 0.0
    let ny = qlen > 1e-12 ? qy / qlen : 0.0
    let nz = qlen > 1e-12 ? qz / qlen : 0.0
    let nw = qlen > 1e-12 ? qw / qlen : 1.0

    let r00 = 1.0 - 2.0 * (ny * ny + nz * nz)
    let r01 = 2.0 * (nx * ny - nz * nw)
    let r02 = 2.0 * (nx * nz + ny * nw)

    let r10 = 2.0 * (nx * ny + nz * nw)
    let r11 = 1.0 - 2.0 * (nx * nx + nz * nz)
    let r12 = 2.0 * (ny * nz - nx * nw)

    let r20 = 2.0 * (nx * nz - ny * nw)
    let r21 = 2.0 * (ny * nz + nx * nw)
    let r22 = 1.0 - 2.0 * (nx * nx + ny * ny)

    let rMatrix = simd_double3x3(
        SIMD3<Double>(r00, r10, r20),
        SIMD3<Double>(r01, r11, r21),
        SIMD3<Double>(r02, r12, r22)
    )

    let pos = SIMD3<Double>(Double(transform.position.x), Double(transform.position.y), Double(transform.position.z))

    let effectiveCm: SIMD3<Double>
    let effectiveInertia: InertiaTensor

    switch coordinateSystem {
    case .centroid:
        effectiveCm = SIMD3<Double>(0, 0, 0)
        effectiveInertia = effectiveCentroidInertia

    case .bodyLocal:
        effectiveCm = effectiveCmLocal
        effectiveInertia = effectiveCentroidInertia.translated(by: effectiveCmLocal, mass: effectiveMass)

    case .world:
        effectiveCm = rMatrix * effectiveCmLocal + pos
        let iCentroidWorld = effectiveCentroidInertia.rotated(by: rMatrix)
        effectiveInertia = iCentroidWorld.translated(by: effectiveCm, mass: effectiveMass)
    }

    let (evals, axes) = JacobiEigensolver.decompose(matrix: effectiveInertia.matrix(physicsSignConvention: true))
    let principalMoments = PrincipalMoments(
        i1: evals.x,
        i2: evals.y,
        i3: evals.z,
        axis1: axes[0],
        axis2: axes[1],
        axis3: axes[2]
    )

    return MassProperties(
        volume: volume,
        surfaceArea: surfaceArea,
        density: density,
        mass: effectiveMass,
        centerOfMass: effectiveCm,
        inertiaTensor: effectiveInertia,
        principalMoments: principalMoments,
        coordinateSystem: coordinateSystem,
        isMassOverridden: isMassOverridden,
        isCenterOfMassOverridden: isCmOverridden
    )
}

/// Computes mass properties for a closed triangular polyhedral mesh using divergence theorem tetrahedral integration.
public func computeMeshMassProperties(
    positions: [SIMD3<Float>],
    indices: [UInt32],
    transform: Transform = .identity,
    density: Double = 1000.0,
    coordinateSystem: MassPropertiesCoordinateSystem = .centroid,
    override: MassOverride? = nil
) -> MassProperties? {
    guard !positions.isEmpty, indices.count >= 3 else { return nil }

    let scale = SIMD3<Double>(Double(transform.scale.x), Double(transform.scale.y), Double(transform.scale.z))
    let scaledPositions = positions.map { SIMD3<Double>(Double($0.x), Double($0.y), Double($0.z)) * scale }

    var totalVolume: Double = 0.0
    var totalArea: Double = 0.0
    var firstMoment = SIMD3<Double>(0, 0, 0)
    var intXX: Double = 0.0
    var intYY: Double = 0.0
    var intZZ: Double = 0.0
    var intXY: Double = 0.0
    var intXZ: Double = 0.0
    var intYZ: Double = 0.0

    let triCount = indices.count / 3
    for t in 0..<triCount {
        let i0 = Int(indices[t * 3])
        let i1 = Int(indices[t * 3 + 1])
        let i2 = Int(indices[t * 3 + 2])

        guard i0 < scaledPositions.count, i1 < scaledPositions.count, i2 < scaledPositions.count else { continue }
        let p0 = scaledPositions[i0]
        let p1 = scaledPositions[i1]
        let p2 = scaledPositions[i2]

        let edge1 = p1 - p0
        let edge2 = p2 - p0
        let cross = simd_cross(edge1, edge2)
        totalArea += 0.5 * simd_length(cross)

        let det = simd_dot(p0, simd_cross(p1, p2))
        let vTet = det / 6.0
        totalVolume += vTet

        let sumP = p0 + p1 + p2
        firstMoment += vTet * 0.25 * sumP

        let v20 = vTet / 20.0
        intXX += v20 * (p0.x * p0.x + p1.x * p1.x + p2.x * p2.x + sumP.x * sumP.x)
        intYY += v20 * (p0.y * p0.y + p1.y * p1.y + p2.y * p2.y + sumP.y * sumP.y)
        intZZ += v20 * (p0.z * p0.z + p1.z * p1.z + p2.z * p2.z + sumP.z * sumP.z)
        intXY += v20 * (p0.x * p0.y + p1.x * p1.y + p2.x * p2.y + sumP.x * sumP.y)
        intXZ += v20 * (p0.x * p0.z + p1.x * p1.z + p2.x * p2.z + sumP.x * sumP.z)
        intYZ += v20 * (p0.y * p0.z + p1.y * p1.z + p2.y * p2.z + sumP.y * sumP.z)
    }

    let cleanVolume = abs(totalVolume)
    guard cleanVolume > 1e-9 else { return nil }

    let sign: Double = totalVolume < 0 ? -1.0 : 1.0
    let normFirstMoment = firstMoment * sign
    let centerOfMassLocal = normFirstMoment / cleanVolume

    let normIntXX = intXX * sign
    let normIntYY = intYY * sign
    let normIntZZ = intZZ * sign
    let normIntXY = intXY * sign
    let normIntXZ = intXZ * sign
    let normIntYZ = intYZ * sign

    let rhoMM3 = density * 1e-9
    let mass = cleanVolume * rhoMM3

    let ixx0 = rhoMM3 * (normIntYY + normIntZZ)
    let iyy0 = rhoMM3 * (normIntXX + normIntZZ)
    let izz0 = rhoMM3 * (normIntXX + normIntYY)
    let ixy0 = rhoMM3 * normIntXY
    let ixz0 = rhoMM3 * normIntXZ
    let iyz0 = rhoMM3 * normIntYZ

    let cm = centerOfMassLocal
    let ixxCm = ixx0 - mass * (cm.y * cm.y + cm.z * cm.z)
    let iyyCm = iyy0 - mass * (cm.x * cm.x + cm.z * cm.z)
    let izzCm = izz0 - mass * (cm.x * cm.x + cm.y * cm.y)
    let ixyCm = ixy0 - mass * (cm.x * cm.y)
    let ixzCm = ixz0 - mass * (cm.x * cm.z)
    let iyzCm = iyz0 - mass * (cm.y * cm.z)

    let centroidInertia = InertiaTensor(
        ixx: max(0.0, ixxCm),
        iyy: max(0.0, iyyCm),
        izz: max(0.0, izzCm),
        ixy: ixyCm,
        ixz: ixzCm,
        iyz: iyzCm
    )

    return buildMassProperties(
        volume: cleanVolume,
        surfaceArea: totalArea,
        density: density,
        mass: mass,
        centerOfMassLocal: centerOfMassLocal,
        centroidInertia: centroidInertia,
        transform: transform,
        coordinateSystem: coordinateSystem,
        override: override
    )
}

/// Analytic mass properties evaluation for a rectangular cuboid (Box).
public func computeAnalyticBox(
    width: Float,
    depth: Float,
    height: Float,
    density: Double = 1000.0,
    transform: Transform = .identity,
    coordinateSystem: MassPropertiesCoordinateSystem = .centroid,
    override: MassOverride? = nil
) -> MassProperties {
    let w = Double(abs(width))
    let d = Double(abs(depth))
    let h = Double(abs(height))
    let volume = w * d * h
    let surfaceArea = 2.0 * (w * d + w * h + d * h)
    let mass = volume * (density * 1e-9)

    let ixx = (1.0 / 12.0) * mass * (d * d + h * h)
    let iyy = (1.0 / 12.0) * mass * (w * w + h * h)
    let izz = (1.0 / 12.0) * mass * (w * w + d * d)

    let centroidInertia = InertiaTensor(ixx: ixx, iyy: iyy, izz: izz)

    return buildMassProperties(
        volume: volume,
        surfaceArea: surfaceArea,
        density: density,
        mass: mass,
        centerOfMassLocal: SIMD3<Double>(0, 0, 0),
        centroidInertia: centroidInertia,
        transform: transform,
        coordinateSystem: coordinateSystem,
        override: override
    )
}

/// Analytic mass properties evaluation for a right circular cylinder aligned with Z axis.
public func computeAnalyticCylinder(
    radius: Float,
    height: Float,
    density: Double = 1000.0,
    transform: Transform = .identity,
    coordinateSystem: MassPropertiesCoordinateSystem = .centroid,
    override: MassOverride? = nil
) -> MassProperties {
    let r = Double(abs(radius))
    let h = Double(abs(height))
    let volume = Double.pi * r * r * h
    let surfaceArea = 2.0 * Double.pi * r * (h + r)
    let mass = volume * (density * 1e-9)

    let izz = 0.5 * mass * r * r
    let ixx = (1.0 / 12.0) * mass * (3.0 * r * r + h * h)
    let iyy = ixx

    let centroidInertia = InertiaTensor(ixx: ixx, iyy: iyy, izz: izz)

    return buildMassProperties(
        volume: volume,
        surfaceArea: surfaceArea,
        density: density,
        mass: mass,
        centerOfMassLocal: SIMD3<Double>(0, 0, 0),
        centroidInertia: centroidInertia,
        transform: transform,
        coordinateSystem: coordinateSystem,
        override: override
    )
}

/// Analytic mass properties evaluation for a solid sphere.
public func computeAnalyticSphere(
    radius: Float,
    density: Double = 1000.0,
    transform: Transform = .identity,
    coordinateSystem: MassPropertiesCoordinateSystem = .centroid,
    override: MassOverride? = nil
) -> MassProperties {
    let r = Double(abs(radius))
    let volume = (4.0 / 3.0) * Double.pi * r * r * r
    let surfaceArea = 4.0 * Double.pi * r * r
    let mass = volume * (density * 1e-9)

    let i = (2.0 / 5.0) * mass * r * r
    let centroidInertia = InertiaTensor(ixx: i, iyy: i, izz: i)

    return buildMassProperties(
        volume: volume,
        surfaceArea: surfaceArea,
        density: density,
        mass: mass,
        centerOfMassLocal: SIMD3<Double>(0, 0, 0),
        centroidInertia: centroidInertia,
        transform: transform,
        coordinateSystem: coordinateSystem,
        override: override
    )
}

/// Analytic mass properties evaluation for a cone or conical frustum aligned with Z axis.
public func computeAnalyticCone(
    bottomRadius: Float,
    topRadius: Float = 0,
    height: Float,
    density: Double = 1000.0,
    transform: Transform = .identity,
    coordinateSystem: MassPropertiesCoordinateSystem = .centroid,
    override: MassOverride? = nil
) -> MassProperties {
    let r1 = Double(abs(bottomRadius))
    let r2 = Double(abs(topRadius))
    let h = Double(abs(height))

    let volume = (Double.pi * h / 3.0) * (r1 * r1 + r1 * r2 + r2 * r2)
    let slantHeight = sqrt(h * h + (r1 - r2) * (r1 - r2))
    let surfaceArea = Double.pi * (r1 * r1 + r2 * r2 + (r1 + r2) * slantHeight)
    let mass = volume * (density * 1e-9)

    let denom = r1 * r1 + r1 * r2 + r2 * r2
    let zCm: Double
    let ixxCm: Double
    let izz: Double

    if denom > 1e-12 {
        let zFromBase = (h / 4.0) * (r1 * r1 + 2.0 * r1 * r2 + 3.0 * r2 * r2) / denom
        zCm = -h / 2.0 + zFromBase

        izz = (3.0 / 10.0) * mass * (pow(r1, 4) + pow(r1, 3) * r2 + pow(r1, 2) * pow(r2, 2) + r1 * pow(r2, 3) + pow(r2, 4)) / denom

        if r2 == 0 {
            ixxCm = (3.0 / 20.0) * mass * r1 * r1 + (3.0 / 80.0) * mass * h * h
        } else {
            // Numerical / analytical integration of thin disks for transverse moment
            let steps = 100
            let dz = h / Double(steps)
            var sumTransverse = 0.0
            for s in 0..<steps {
                let zVal = -h / 2.0 + (Double(s) + 0.5) * dz
                let u = (zVal + h / 2.0) / h
                let rLocal = r1 + (r2 - r1) * u
                let dMass = (Double.pi * rLocal * rLocal * dz) * (density * 1e-9)
                let dIxxOrigin = 0.25 * dMass * rLocal * rLocal + dMass * zVal * zVal
                sumTransverse += dIxxOrigin
            }
            ixxCm = max(0.0, sumTransverse - mass * zCm * zCm)
        }
    } else {
        zCm = 0
        ixxCm = 0
        izz = 0
    }

    let centroidInertia = InertiaTensor(ixx: ixxCm, iyy: ixxCm, izz: izz)

    return buildMassProperties(
        volume: volume,
        surfaceArea: surfaceArea,
        density: density,
        mass: mass,
        centerOfMassLocal: SIMD3<Double>(0, 0, zCm),
        centroidInertia: centroidInertia,
        transform: transform,
        coordinateSystem: coordinateSystem,
        override: override
    )
}

/// Analytic mass properties evaluation for a circular torus centered in the XY plane.
public func computeAnalyticTorus(
    majorRadius: Float,
    minorRadius: Float,
    density: Double = 1000.0,
    transform: Transform = .identity,
    coordinateSystem: MassPropertiesCoordinateSystem = .centroid,
    override: MassOverride? = nil
) -> MassProperties {
    let bigR = Double(abs(majorRadius))
    let smallR = Double(abs(minorRadius))

    let volume = 2.0 * Double.pi * Double.pi * bigR * smallR * smallR
    let surfaceArea = 4.0 * Double.pi * Double.pi * bigR * smallR
    let mass = volume * (density * 1e-9)

    let izz = mass * (bigR * bigR + 0.75 * smallR * smallR)
    let ixx = mass * (0.5 * bigR * bigR + 0.625 * smallR * smallR)
    let iyy = ixx

    let centroidInertia = InertiaTensor(ixx: ixx, iyy: iyy, izz: izz)

    return buildMassProperties(
        volume: volume,
        surfaceArea: surfaceArea,
        density: density,
        mass: mass,
        centerOfMassLocal: SIMD3<Double>(0, 0, 0),
        centroidInertia: centroidInertia,
        transform: transform,
        coordinateSystem: coordinateSystem,
        override: override
    )
}

/// Mass properties calculator resolving materials and evaluating body properties.
public enum MassPropertiesCalculator {
    /// Resolves metadata dictionary for a given solid ID.
    @MainActor
    public static func resolveMetadata(for solidId: SolidId, in document: DocumentModel) -> [String: String] {
        if let comp = document.findComponentInstance(solidId: solidId) {
            return comp.metadata
        }
        if let uuid = UUID(uuidString: solidId.rawValue), let comp = document.findComponentInstance(id: uuid) {
            return comp.metadata
        }
        if let feat = document.features.last(where: { $0.outputSolidId == solidId }) ?? document.feature(for: solidId) {
            return feat.metadata
        }
        if let obj = document.objects.first(where: { $0.id == solidId }) {
            return obj.metadata
        }
        return [:]
    }

    /// Resolves mass override settings for a given solid ID.
    @MainActor
    public static func resolveMassOverride(for solidId: SolidId, in document: DocumentModel) -> MassOverride {
        MassOverride(metadata: resolveMetadata(for: solidId, in: document))
    }

    /// Resolves material name and mass density in kg/m³ for a given solid ID.
    @MainActor
    public static func resolveMaterialDensity(
        for solidId: SolidId,
        in document: DocumentModel,
        userMaterials: [MaterialDefinition] = []
    ) -> (materialName: String?, density: Double) {
        var materialDefId: String? = nil
        var directName: String? = nil

        if let comp = document.findComponentInstance(solidId: solidId) {
            materialDefId = comp.material.materialDefinitionId
            directName = comp.material.materialName
        } else if let feat = document.features.last(where: { $0.outputSolidId == solidId }) ?? document.feature(for: solidId) {
            materialDefId = feat.material.materialDefinitionId
            directName = feat.material.materialName
        } else if let obj = document.objects.first(where: { $0.id == solidId }) {
            materialDefId = obj.material.materialDefinitionId
            directName = obj.material.materialName
        }

        func findMaterial(id: String) -> MaterialDefinition? {
            if let custom = document.customMaterials.first(where: { $0.id == id }) {
                return custom
            }
            if let user = userMaterials.first(where: { $0.id == id }) {
                return user
            }
            if let std = StandardMaterials.all.first(where: { $0.id == id }) {
                return std
            }
            return nil
        }

        func findMaterialByName(_ name: String) -> MaterialDefinition? {
            if let custom = document.customMaterials.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return custom
            }
            if let user = userMaterials.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return user
            }
            if let std = StandardMaterials.all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.id.caseInsensitiveCompare(name) == .orderedSame }) {
                return std
            }
            return nil
        }

        if let id = materialDefId, let found = findMaterial(id: id) {
            return (found.name, found.density.baseSIValue)
        }

        if let name = directName, !name.isEmpty, let found = findMaterialByName(name) {
            return (found.name, found.density.baseSIValue)
        }

        let defaultAttr = document.settings.defaultMaterial
        if let defId = defaultAttr.materialDefinitionId, let found = findMaterial(id: defId) {
            return (found.name, found.density.baseSIValue)
        }
        if let defName = defaultAttr.materialName, !defName.isEmpty, let found = findMaterialByName(defName) {
            return (found.name, found.density.baseSIValue)
        }

        return (directName ?? defaultAttr.materialName, 1000.0)
    }

    /// Evaluates mass properties for a given solid ID.
    @MainActor
    public static func calculate(
        for solidId: SolidId,
        in document: DocumentModel,
        candidateMeshes: [CandidateMesh] = [],
        userMaterials: [MaterialDefinition] = [],
        coordinateSystem: MassPropertiesCoordinateSystem = .centroid
    ) -> MassProperties? {
        let (matName, density) = resolveMaterialDensity(for: solidId, in: document, userMaterials: userMaterials)
        _ = matName
        let massOverride = resolveMassOverride(for: solidId, in: document)

        // Check if primitive feature
        if let feat = document.features.last(where: { $0.outputSolidId == solidId }) ?? document.feature(for: solidId) {
            switch feat.operation {
            case .primitive(.box(let p)):
                return computeAnalyticBox(width: p.width, depth: p.depth, height: p.height, density: density, transform: feat.transform, coordinateSystem: coordinateSystem, override: massOverride)
            case .primitive(.cylinder(let p)):
                return computeAnalyticCylinder(radius: p.radius, height: p.height, density: density, transform: feat.transform, coordinateSystem: coordinateSystem, override: massOverride)
            case .primitive(.sphere(let p)):
                return computeAnalyticSphere(radius: p.radius, density: density, transform: feat.transform, coordinateSystem: coordinateSystem, override: massOverride)
            case .primitive(.cone(let p)):
                return computeAnalyticCone(bottomRadius: p.bottomRadius, topRadius: p.topRadius, height: p.height, density: density, transform: feat.transform, coordinateSystem: coordinateSystem, override: massOverride)
            case .primitive(.torus(let p)):
                return computeAnalyticTorus(majorRadius: p.majorRadius, minorRadius: p.minorRadius, density: density, transform: feat.transform, coordinateSystem: coordinateSystem, override: massOverride)
            default:
                break
            }
        }

        // Check if primitive scene object
        if let obj = document.objects.first(where: { $0.id == solidId }) {
            switch obj.def {
            case .box(let p):
                return computeAnalyticBox(width: p.width, depth: p.depth, height: p.height, density: density, transform: obj.transform, coordinateSystem: coordinateSystem, override: massOverride)
            case .cylinder(let p):
                return computeAnalyticCylinder(radius: p.radius, height: p.height, density: density, transform: obj.transform, coordinateSystem: coordinateSystem, override: massOverride)
            case .sphere(let p):
                return computeAnalyticSphere(radius: p.radius, density: density, transform: obj.transform, coordinateSystem: coordinateSystem, override: massOverride)
            case .cone(let p):
                return computeAnalyticCone(bottomRadius: p.bottomRadius, topRadius: p.topRadius, height: p.height, density: density, transform: obj.transform, coordinateSystem: coordinateSystem, override: massOverride)
            case .torus(let p):
                return computeAnalyticTorus(majorRadius: p.majorRadius, minorRadius: p.minorRadius, density: density, transform: obj.transform, coordinateSystem: coordinateSystem, override: massOverride)
            default:
                break
            }
        }

        // Evaluate from candidate mesh or resolved mesh
        if let mesh = candidateMeshes.first(where: { $0.id == solidId }) {
            return computeMeshMassProperties(positions: mesh.positions, indices: mesh.indices, transform: mesh.transform, density: density, coordinateSystem: coordinateSystem, override: massOverride)
        }

        if let resolved = MeasureTool.resolveMesh(for: solidId, in: document, candidateMeshes: candidateMeshes) {
            return computeMeshMassProperties(positions: resolved.positions, indices: resolved.indices, transform: resolved.transform, density: density, coordinateSystem: coordinateSystem, override: massOverride)
        }

        return nil
    }
}
