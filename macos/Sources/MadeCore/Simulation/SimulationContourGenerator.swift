import Foundation
import simd

/// Pure Swift geometry generator converting VolumeMesh and simulation scalar fields to GPU-ready MeshPayload with per-vertex colors (BL-RES-02, #193).
public enum SimulationContourGenerator: Sendable {

    private struct EdgeKey: Hashable {
        let a: Int
        let b: Int

        init(_ n1: Int, _ n2: Int) {
            if n1 < n2 {
                self.a = n1
                self.b = n2
            } else {
                self.a = n2
                self.b = n1
            }
        }
    }

    /// Generates a MeshPayload with per-vertex colormap colors and calculates spatial extrema.
    public static func generatePayload(
        mesh: VolumeMesh,
        study: SimulationStudy,
        results: SimulationStudyResults,
        fields: SimulationResultFields?,
        settings: SimulationContourSettings,
        displaySettings: SimulationMeshDisplaySettings,
        elementFilter: Set<Int>? = nil,
        deformationMultiplier: Double = 1.0,
        displacementsOverride: [Int: SIMD3<Double>]? = nil
    ) -> (payload: MeshPayload, extrema: SimulationContourExtrema) {
        let fieldName = settings.field.displayName
        let unitSymbol = settings.field.defaultUnitSymbol

        guard !mesh.nodes.isEmpty, !mesh.elements.isEmpty else {
            let emptyExtrema = SimulationContourExtrema(
                fieldName: fieldName,
                unitSymbol: unitSymbol,
                actualMin: 0.0,
                actualMax: 0.0,
                effectiveMin: 0.0,
                effectiveMax: 0.0
            )
            return (MeshPayload(positions: [], normals: [], indices: [], colors: []), emptyExtrema)
        }

        var nodeMap: [Int: SIMD3<Double>] = [:]
        nodeMap.reserveCapacity(mesh.nodes.count)

        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude

        for node in mesh.nodes {
            nodeMap[node.id] = node.position
            minX = min(minX, node.position.x)
            maxX = max(maxX, node.position.x)
            minY = min(minY, node.position.y)
            maxY = max(maxY, node.position.y)
            minZ = min(minZ, node.position.z)
            maxZ = max(maxZ, node.position.z)
        }

        let displacements = displacementsOverride ?? (fields?.nodalDisplacements ?? results.nodalDisplacements)
        let effectiveScale = max(0.0, settings.deformationScale)

        func nodeRenderPosition(_ id: Int) -> SIMD3<Double> {
            guard let pos = nodeMap[id] else { return .zero }
            if settings.isDeformed, let disp = displacements?[id] {
                if disp.x.isNaN || disp.y.isNaN || disp.z.isNaN { return pos }
                return pos + effectiveScale * deformationMultiplier * disp
            }
            return pos
        }

        // 1. Extract scalar field dictionary
        let (nodalScalars, elementScalars) = extractScalars(
            field: settings.field,
            study: study,
            results: results,
            fields: fields,
            displacementsOverride: displacementsOverride
        )

        // 2. Compute actual extrema and spatial anchors
        var actualMin = Double.greatestFiniteMagnitude
        var actualMax = -Double.greatestFiniteMagnitude
        var minId: Int? = nil
        var maxId: Int? = nil

        if settings.field.isNodal {
            for (id, val) in nodalScalars where !val.isNaN {
                if val < actualMin {
                    actualMin = val
                    minId = id
                }
                if val > actualMax {
                    actualMax = val
                    maxId = id
                }
            }
        } else {
            for (id, val) in elementScalars where !val.isNaN {
                if val < actualMin {
                    actualMin = val
                    minId = id
                }
                if val > actualMax {
                    actualMax = val
                    maxId = id
                }
            }
        }

        if actualMin > actualMax {
            actualMin = 0.0
            actualMax = 0.0
        }

        let (effectiveMin, effectiveMax) = settings.effectiveRange(for: actualMin, actualMax: actualMax)

        var minPosition: SIMD3<Double>? = nil
        var maxPosition: SIMD3<Double>? = nil

        if settings.field.isNodal {
            if let id = minId { minPosition = nodeRenderPosition(id) }
            if let id = maxId { maxPosition = nodeRenderPosition(id) }
        } else {
            if let id = minId, let elem = mesh.elements.first(where: { $0.id == id }) {
                let pts = elem.nodeIndices.prefix(4).map { nodeRenderPosition($0) }
                if !pts.isEmpty {
                    minPosition = pts.reduce(SIMD3<Double>.zero, +) / Double(pts.count)
                }
            }
            if let id = maxId, let elem = mesh.elements.first(where: { $0.id == id }) {
                let pts = elem.nodeIndices.prefix(4).map { nodeRenderPosition($0) }
                if !pts.isEmpty {
                    maxPosition = pts.reduce(SIMD3<Double>.zero, +) / Double(pts.count)
                }
            }
        }

        let extrema = SimulationContourExtrema(
            fieldName: fieldName,
            unitSymbol: unitSymbol,
            actualMin: actualMin,
            actualMax: actualMax,
            effectiveMin: effectiveMin,
            effectiveMax: effectiveMax,
            minNodeId: minId,
            maxNodeId: maxId,
            minPosition: minPosition,
            maxPosition: maxPosition
        )

        // 3. Slice thresholding
        let sliceAxisMin: Double
        let sliceAxisMax: Double
        switch displaySettings.sliceAxis {
        case .x: sliceAxisMin = minX; sliceAxisMax = maxX
        case .y: sliceAxisMin = minY; sliceAxisMax = maxY
        case .z: sliceAxisMin = minZ; sliceAxisMax = maxZ
        }
        let axisRange = max(0.0, sliceAxisMax - sliceAxisMin)
        let clampedSlicePos = max(0.0, min(1.0, displaySettings.slicePosition))
        let sliceThreshold = axisRange > 1e-9 ? sliceAxisMin + clampedSlicePos * axisRange : sliceAxisMin

        struct KeptContourElement {
            let id: Int
            let nodeIds: (Int, Int, Int, Int)
            let p0: SIMD3<Double>
            let p1: SIMD3<Double>
            let p2: SIMD3<Double>
            let p3: SIMD3<Double>
            let centroid: SIMD3<Double>
        }

        var keptElements: [KeptContourElement] = []
        keptElements.reserveCapacity(mesh.elements.count)

        for elem in mesh.elements where elem.nodeIndices.count >= 4 {
            if let filter = elementFilter, !filter.contains(elem.id) {
                continue
            }

            let n0 = elem.nodeIndices[0]
            let n1 = elem.nodeIndices[1]
            let n2 = elem.nodeIndices[2]
            let n3 = elem.nodeIndices[3]

            guard nodeMap[n0] != nil,
                  nodeMap[n1] != nil,
                  nodeMap[n2] != nil,
                  nodeMap[n3] != nil else {
                continue
            }

            let p0 = nodeRenderPosition(n0)
            let p1 = nodeRenderPosition(n1)
            let p2 = nodeRenderPosition(n2)
            let p3 = nodeRenderPosition(n3)

            let centroid = (p0 + p1 + p2 + p3) * 0.25

            if displaySettings.isSliceEnabled, axisRange > 1e-9 {
                let centroidComponent: Double
                switch displaySettings.sliceAxis {
                case .x: centroidComponent = centroid.x
                case .y: centroidComponent = centroid.y
                case .z: centroidComponent = centroid.z
                }
                if !displaySettings.isSliceInverted {
                    if centroidComponent > sliceThreshold + 1e-9 { continue }
                } else {
                    if centroidComponent < sliceThreshold - 1e-9 { continue }
                }
            }

            keptElements.append(KeptContourElement(
                id: elem.id,
                nodeIds: (n0, n1, n2, n3),
                p0: p0,
                p1: p1,
                p2: p2,
                p3: p3,
                centroid: centroid
            ))
        }

        guard !keptElements.isEmpty else {
            return (MeshPayload(positions: [], normals: [], indices: [], colors: []), extrema)
        }

        let shrink = max(0.0, min(0.9, displaySettings.elementShrink))
        let shrinkScale = 1.0 - shrink

        var positions: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []
        var colors: [Float] = []
        var edgePolylines: [EdgePolyline] = []

        positions.reserveCapacity(keptElements.count * 12 * 3)
        normals.reserveCapacity(keptElements.count * 12 * 3)
        indices.reserveCapacity(keptElements.count * 12)
        colors.reserveCapacity(keptElements.count * 12 * 4)

        let isZeroRange = abs(effectiveMax - effectiveMin) < 1e-12

        func normalizedT(_ val: Double) -> Double {
            if isZeroRange { return 0.5 }
            let t = (val - effectiveMin) / (effectiveMax - effectiveMin)
            return max(0.0, min(1.0, t.isNaN ? 0.5 : t))
        }

        var currentIndex: UInt32 = 0

        func addFace(
            v0: SIMD3<Double>,
            v1: SIMD3<Double>,
            v2: SIMD3<Double>,
            opposite: SIMD3<Double>,
            c0: SIMD4<Float>,
            c1: SIMD4<Float>,
            c2: SIMD4<Float>
        ) {
            let edgeA = v1 - v0
            let edgeB = v2 - v0
            var normal = simd_cross(edgeA, edgeB)
            let toOpposite = opposite - v0

            var finalV1 = v1
            var finalV2 = v2
            var finalC1 = c1
            var finalC2 = c2

            if simd_dot(toOpposite, normal) > 0 {
                normal = -normal
                finalV1 = v2
                finalV2 = v1
                finalC1 = c2
                finalC2 = c1
            }

            let normalLength = simd_length(normal)
            let unitNormal = normalLength > 1e-12 ? (normal / normalLength) : SIMD3<Double>(0, 0, 1)

            positions.append(Float(v0.x))
            positions.append(Float(v0.y))
            positions.append(Float(v0.z))
            normals.append(Float(unitNormal.x))
            normals.append(Float(unitNormal.y))
            normals.append(Float(unitNormal.z))
            colors.append(c0.x); colors.append(c0.y); colors.append(c0.z); colors.append(c0.w)

            positions.append(Float(finalV1.x))
            positions.append(Float(finalV1.y))
            positions.append(Float(finalV1.z))
            normals.append(Float(unitNormal.x))
            normals.append(Float(unitNormal.y))
            normals.append(Float(unitNormal.z))
            colors.append(finalC1.x); colors.append(finalC1.y); colors.append(finalC1.z); colors.append(finalC1.w)

            positions.append(Float(finalV2.x))
            positions.append(Float(finalV2.y))
            positions.append(Float(finalV2.z))
            normals.append(Float(unitNormal.x))
            normals.append(Float(unitNormal.y))
            normals.append(Float(unitNormal.z))
            colors.append(finalC2.x); colors.append(finalC2.y); colors.append(finalC2.z); colors.append(finalC2.w)

            indices.append(currentIndex)
            indices.append(currentIndex + 1)
            indices.append(currentIndex + 2)
            currentIndex += 3
        }

        for item in keptElements {
            let sp0: SIMD3<Double>
            let sp1: SIMD3<Double>
            let sp2: SIMD3<Double>
            let sp3: SIMD3<Double>

            if shrink > 0.0 {
                let c = item.centroid
                sp0 = c + (item.p0 - c) * shrinkScale
                sp1 = c + (item.p1 - c) * shrinkScale
                sp2 = c + (item.p2 - c) * shrinkScale
                sp3 = c + (item.p3 - c) * shrinkScale
            } else {
                sp0 = item.p0
                sp1 = item.p1
                sp2 = item.p2
                sp3 = item.p3
            }

            let color0: SIMD4<Float>
            let color1: SIMD4<Float>
            let color2: SIMD4<Float>
            let color3: SIMD4<Float>

            if settings.field.isNodal {
                let val0 = nodalScalars[item.nodeIds.0] ?? effectiveMin
                let val1 = nodalScalars[item.nodeIds.1] ?? effectiveMin
                let val2 = nodalScalars[item.nodeIds.2] ?? effectiveMin
                let val3 = nodalScalars[item.nodeIds.3] ?? effectiveMin

                color0 = SimulationColorMap.evaluate(t: normalizedT(val0), map: settings.colorMap)
                color1 = SimulationColorMap.evaluate(t: normalizedT(val1), map: settings.colorMap)
                color2 = SimulationColorMap.evaluate(t: normalizedT(val2), map: settings.colorMap)
                color3 = SimulationColorMap.evaluate(t: normalizedT(val3), map: settings.colorMap)
            } else {
                let elemVal = elementScalars[item.id] ?? effectiveMin
                let elemColor = SimulationColorMap.evaluate(t: normalizedT(elemVal), map: settings.colorMap)
                color0 = elemColor
                color1 = elemColor
                color2 = elemColor
                color3 = elemColor
            }

            addFace(v0: sp0, v1: sp1, v2: sp2, opposite: sp3, c0: color0, c1: color1, c2: color2)
            addFace(v0: sp0, v1: sp2, v2: sp3, opposite: sp1, c0: color0, c1: color2, c2: color3)
            addFace(v0: sp0, v1: sp3, v2: sp1, opposite: sp2, c0: color0, c1: color3, c2: color1)
            addFace(v0: sp1, v1: sp3, v2: sp2, opposite: sp0, c0: color1, c1: color3, c2: color2)
        }

        // 4. Mesh wireframe edges
        if settings.showMeshEdges {
            var seenEdges = Set<EdgeKey>()
            var edgeCounter = 0

            for item in keptElements {
                let sp0: SIMD3<Double>
                let sp1: SIMD3<Double>
                let sp2: SIMD3<Double>
                let sp3: SIMD3<Double>

                if shrink > 0.0 {
                    let c = item.centroid
                    sp0 = c + (item.p0 - c) * shrinkScale
                    sp1 = c + (item.p1 - c) * shrinkScale
                    sp2 = c + (item.p2 - c) * shrinkScale
                    sp3 = c + (item.p3 - c) * shrinkScale
                } else {
                    sp0 = item.p0
                    sp1 = item.p1
                    sp2 = item.p2
                    sp3 = item.p3
                }

                let edgeDefs: [(n1: Int, n2: Int, pA: SIMD3<Double>, pB: SIMD3<Double>)] = [
                    (item.nodeIds.0, item.nodeIds.1, sp0, sp1),
                    (item.nodeIds.1, item.nodeIds.2, sp1, sp2),
                    (item.nodeIds.2, item.nodeIds.0, sp2, sp0),
                    (item.nodeIds.0, item.nodeIds.3, sp0, sp3),
                    (item.nodeIds.1, item.nodeIds.3, sp1, sp3),
                    (item.nodeIds.2, item.nodeIds.3, sp2, sp3)
                ]

                for edge in edgeDefs {
                    if shrink == 0.0 {
                        let key = EdgeKey(edge.n1, edge.n2)
                        guard seenEdges.insert(key).inserted else { continue }
                    }

                    let ptA = SIMD3<Float>(Float(edge.pA.x), Float(edge.pA.y), Float(edge.pA.z))
                    let ptB = SIMD3<Float>(Float(edge.pB.x), Float(edge.pB.y), Float(edge.pB.z))
                    let polyline = EdgePolyline(
                        edgeId: edgeCounter,
                        points: [ptA, ptB],
                        segmentRange: edgeCounter..<(edgeCounter + 1)
                    )
                    edgePolylines.append(polyline)
                    edgeCounter += 1
                }
            }
        }

        let payload = MeshPayload(
            positions: positions,
            normals: normals,
            indices: indices,
            edgePolylines: edgePolylines,
            colors: colors
        )

        return (payload, extrema)
    }

    // MARK: - Scalar Extraction

    public static func extractScalars(
        field: SimulationResultFieldKind,
        study: SimulationStudy,
        results: SimulationStudyResults,
        fields: SimulationResultFields?,
        displacementsOverride: [Int: SIMD3<Double>]? = nil
    ) -> (nodal: [Int: Double], element: [Int: Double]) {
        let activeDisplacements = displacementsOverride ?? (fields?.nodalDisplacements ?? results.nodalDisplacements)

        switch field {
        case .vonMisesStress:
            if let vm = fields?.nodalVonMisesStresses ?? results.nodalVonMisesStresses, !vm.isEmpty {
                return (vm, [:])
            }
            if let tensors = fields?.nodalCauchyTensors ?? results.nodalCauchyTensors, !tensors.isEmpty {
                var map: [Int: Double] = [:]
                map.reserveCapacity(tensors.count)
                for (id, tensor) in tensors {
                    map[id] = tensor.vonMisesStress
                }
                return (map, [:])
            }
            return ([:], [:])

        case .displacementMagnitude:
            if let disp = activeDisplacements, !disp.isEmpty {
                var map: [Int: Double] = [:]
                map.reserveCapacity(disp.count)
                for (id, d) in disp {
                    map[id] = sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
                }
                return (map, [:])
            }
            return ([:], [:])

        case .displacementX:
            if let disp = activeDisplacements, !disp.isEmpty {
                var map: [Int: Double] = [:]
                map.reserveCapacity(disp.count)
                for (id, d) in disp { map[id] = d.x }
                return (map, [:])
            }
            return ([:], [:])

        case .displacementY:
            if let disp = activeDisplacements, !disp.isEmpty {
                var map: [Int: Double] = [:]
                map.reserveCapacity(disp.count)
                for (id, d) in disp { map[id] = d.y }
                return (map, [:])
            }
            return ([:], [:])

        case .displacementZ:
            if let disp = activeDisplacements, !disp.isEmpty {
                var map: [Int: Double] = [:]
                map.reserveCapacity(disp.count)
                for (id, d) in disp { map[id] = d.z }
                return (map, [:])
            }
            return ([:], [:])

        case .temperature:
            if let temps = fields?.nodalTemperatures ?? results.nodalTemperatures, !temps.isEmpty {
                return (temps, [:])
            }
            return ([:], [:])

        case .factorOfSafety:
            let mat = study.materials.first.flatMap { MaterialLibrary.standard.material(withId: $0.materialId) }
            if let tensors = fields?.nodalCauchyTensors ?? results.nodalCauchyTensors, !tensors.isEmpty {
                let fos = FactorOfSafetyCalculator.evaluate(nodalTensors: tensors, material: mat, settings: study.factorOfSafetySettings)
                return (fos.nodalFactorsOfSafety, [:])
            } else if let stresses = fields?.nodalVonMisesStresses ?? results.nodalVonMisesStresses, !stresses.isEmpty {
                let fos = FactorOfSafetyCalculator.evaluate(nodalVonMisesStresses: stresses, material: mat, settings: study.factorOfSafetySettings)
                return (fos.nodalFactorsOfSafety, [:])
            }
            return ([:], [:])

        case .majorPrincipalStress:
            if let tensors = fields?.nodalCauchyTensors ?? results.nodalCauchyTensors, !tensors.isEmpty {
                var map: [Int: Double] = [:]
                map.reserveCapacity(tensors.count)
                for (id, t) in tensors {
                    map[id] = t.principalStresses.sigma1
                }
                return (map, [:])
            }
            return ([:], [:])

        case .minorPrincipalStress:
            if let tensors = fields?.nodalCauchyTensors ?? results.nodalCauchyTensors, !tensors.isEmpty {
                var map: [Int: Double] = [:]
                map.reserveCapacity(tensors.count)
                for (id, t) in tensors {
                    map[id] = t.principalStresses.sigma3
                }
                return (map, [:])
            }
            return ([:], [:])

        case .maxShearStress:
            if let tensors = fields?.nodalCauchyTensors ?? results.nodalCauchyTensors, !tensors.isEmpty {
                var map: [Int: Double] = [:]
                map.reserveCapacity(tensors.count)
                for (id, t) in tensors {
                    let p = t.principalStresses
                    map[id] = max(0.0, (p.sigma1 - p.sigma3) * 0.5)
                }
                return (map, [:])
            }
            return ([:], [:])

        case .elementVonMisesStress:
            if let evm = fields?.elementVonMisesStresses ?? results.elementVonMisesStresses, !evm.isEmpty {
                return ([:], evm)
            }
            return ([:], [:])

        case .elementHeatFluxMagnitude:
            if let flux = fields?.elementHeatFluxes ?? results.elementHeatFluxes, !flux.isEmpty {
                var map: [Int: Double] = [:]
                map.reserveCapacity(flux.count)
                for (id, f) in flux {
                    map[id] = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
                }
                return ([:], map)
            }
            return ([:], [:])
        }
    }

    /// Generates boundary wireframe polylines on undeformed mesh geometry (BL-RES-03, #324).
    public static func generateUndeformedWireframePayload(
        mesh: VolumeMesh,
        displaySettings: SimulationMeshDisplaySettings
    ) -> MeshPayload {
        guard !mesh.nodes.isEmpty, !mesh.elements.isEmpty else {
            return MeshPayload(positions: [], normals: [], indices: [], edgePolylines: [], colors: [])
        }

        var nodeMap: [Int: SIMD3<Double>] = [:]
        nodeMap.reserveCapacity(mesh.nodes.count)

        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude

        for node in mesh.nodes {
            nodeMap[node.id] = node.position
            minX = min(minX, node.position.x)
            maxX = max(maxX, node.position.x)
            minY = min(minY, node.position.y)
            maxY = max(maxY, node.position.y)
            minZ = min(minZ, node.position.z)
            maxZ = max(maxZ, node.position.z)
        }

        let sliceAxisMin: Double
        let sliceAxisMax: Double
        switch displaySettings.sliceAxis {
        case .x: sliceAxisMin = minX; sliceAxisMax = maxX
        case .y: sliceAxisMin = minY; sliceAxisMax = maxY
        case .z: sliceAxisMin = minZ; sliceAxisMax = maxZ
        }
        let axisRange = max(0.0, sliceAxisMax - sliceAxisMin)
        let clampedSlicePos = max(0.0, min(1.0, displaySettings.slicePosition))
        let sliceThreshold = axisRange > 1e-9 ? sliceAxisMin + clampedSlicePos * axisRange : sliceAxisMin

        var seenEdges = Set<EdgeKey>()
        var edgePolylines: [EdgePolyline] = []
        var edgeCounter = 0

        for elem in mesh.elements where elem.nodeIndices.count >= 4 {
            let n0 = elem.nodeIndices[0]
            let n1 = elem.nodeIndices[1]
            let n2 = elem.nodeIndices[2]
            let n3 = elem.nodeIndices[3]

            guard let p0 = nodeMap[n0],
                  let p1 = nodeMap[n1],
                  let p2 = nodeMap[n2],
                  let p3 = nodeMap[n3] else {
                continue
            }

            if displaySettings.isSliceEnabled, axisRange > 1e-9 {
                let centroid = (p0 + p1 + p2 + p3) * 0.25
                let centroidComponent: Double
                switch displaySettings.sliceAxis {
                case .x: centroidComponent = centroid.x
                case .y: centroidComponent = centroid.y
                case .z: centroidComponent = centroid.z
                }
                if !displaySettings.isSliceInverted {
                    if centroidComponent > sliceThreshold + 1e-9 { continue }
                } else {
                    if centroidComponent < sliceThreshold - 1e-9 { continue }
                }
            }

            let edgeDefs: [(n1: Int, n2: Int, pA: SIMD3<Double>, pB: SIMD3<Double>)] = [
                (n0, n1, p0, p1),
                (n1, n2, p1, p2),
                (n2, n0, p2, p0),
                (n0, n3, p0, p3),
                (n1, n3, p1, p3),
                (n2, n3, p2, p3)
            ]

            for edge in edgeDefs {
                let key = EdgeKey(edge.n1, edge.n2)
                guard seenEdges.insert(key).inserted else { continue }

                let ptA = SIMD3<Float>(Float(edge.pA.x), Float(edge.pA.y), Float(edge.pA.z))
                let ptB = SIMD3<Float>(Float(edge.pB.x), Float(edge.pB.y), Float(edge.pB.z))
                let polyline = EdgePolyline(
                    edgeId: edgeCounter,
                    points: [ptA, ptB],
                    segmentRange: edgeCounter..<(edgeCounter + 1)
                )
                edgePolylines.append(polyline)
                edgeCounter += 1
            }
        }

        return MeshPayload(
            positions: [],
            normals: [],
            indices: [],
            edgePolylines: edgePolylines,
            colors: []
        )
    }
}
