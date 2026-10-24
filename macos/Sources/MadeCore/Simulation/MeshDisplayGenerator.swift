import Foundation
import simd

/// Pure Swift geometry generator converting VolumeMesh to GPU-ready MeshPayload (BL-MSH-05, #278).
public enum MeshDisplayGenerator {

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

    /// Generates a MeshPayload with solid faces and wireframe edges from a volume mesh.
    public static func generatePayload(
        mesh: VolumeMesh,
        settings: SimulationMeshDisplaySettings,
        elementFilter: Set<Int>? = nil
    ) -> MeshPayload {
        guard !mesh.nodes.isEmpty, !mesh.elements.isEmpty else {
            return MeshPayload(positions: [], normals: [], indices: [])
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

        guard !nodeMap.isEmpty else {
            return MeshPayload(positions: [], normals: [], indices: [])
        }

        let sliceAxisMin: Double
        let sliceAxisMax: Double
        switch settings.sliceAxis {
        case .x:
            sliceAxisMin = minX
            sliceAxisMax = maxX
        case .y:
            sliceAxisMin = minY
            sliceAxisMax = maxY
        case .z:
            sliceAxisMin = minZ
            sliceAxisMax = maxZ
        }

        let axisRange = max(0.0, sliceAxisMax - sliceAxisMin)
        let clampedSlicePosition = max(0.0, min(1.0, settings.slicePosition))
        let sliceThreshold: Double
        if axisRange > 1e-9 {
            sliceThreshold = sliceAxisMin + clampedSlicePosition * axisRange
        } else {
            sliceThreshold = sliceAxisMin
        }

        struct KeptElement {
            let id: Int
            let nodeIds: (Int, Int, Int, Int)
            let p0: SIMD3<Double>
            let p1: SIMD3<Double>
            let p2: SIMD3<Double>
            let p3: SIMD3<Double>
            let centroid: SIMD3<Double>
        }

        var keptElements: [KeptElement] = []
        keptElements.reserveCapacity(mesh.elements.count)

        for elem in mesh.elements where elem.nodeIndices.count >= 4 {
            if let filter = elementFilter, !filter.contains(elem.id) {
                continue
            }

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

            let centroid = (p0 + p1 + p2 + p3) * 0.25

            if settings.isSliceEnabled, axisRange > 1e-9 {
                let centroidComponent: Double
                switch settings.sliceAxis {
                case .x: centroidComponent = centroid.x
                case .y: centroidComponent = centroid.y
                case .z: centroidComponent = centroid.z
                }

                if !settings.isSliceInverted {
                    if centroidComponent > sliceThreshold + 1e-9 {
                        continue
                    }
                } else {
                    if centroidComponent < sliceThreshold - 1e-9 {
                        continue
                    }
                }
            }

            keptElements.append(KeptElement(
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
            return MeshPayload(positions: [], normals: [], indices: [])
        }

        let shrink = max(0.0, min(0.9, settings.elementShrink))
        let shrinkScale = 1.0 - shrink

        var positions: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []
        var edgePolylines: [EdgePolyline] = []

        if settings.showFaces {
            positions.reserveCapacity(keptElements.count * 12 * 3)
            normals.reserveCapacity(keptElements.count * 12 * 3)
            indices.reserveCapacity(keptElements.count * 12)

            var currentIndex: UInt32 = 0

            func addTriangle(
                v0: SIMD3<Double>,
                v1: SIMD3<Double>,
                v2: SIMD3<Double>,
                opposite: SIMD3<Double>
            ) {
                let edgeA = v1 - v0
                let edgeB = v2 - v0
                var normal = simd_cross(edgeA, edgeB)
                let toOpposite = opposite - v0

                let finalV0 = v0
                var finalV1 = v1
                var finalV2 = v2

                if simd_dot(toOpposite, normal) > 0 {
                    normal = -normal
                    finalV1 = v2
                    finalV2 = v1
                }

                let normalLength = simd_length(normal)
                let unitNormal: SIMD3<Double>
                if normalLength > 1e-12 {
                    unitNormal = normal / normalLength
                } else {
                    unitNormal = SIMD3<Double>(0, 0, 1)
                }

                positions.append(Float(finalV0.x))
                positions.append(Float(finalV0.y))
                positions.append(Float(finalV0.z))
                normals.append(Float(unitNormal.x))
                normals.append(Float(unitNormal.y))
                normals.append(Float(unitNormal.z))

                positions.append(Float(finalV1.x))
                positions.append(Float(finalV1.y))
                positions.append(Float(finalV1.z))
                normals.append(Float(unitNormal.x))
                normals.append(Float(unitNormal.y))
                normals.append(Float(unitNormal.z))

                positions.append(Float(finalV2.x))
                positions.append(Float(finalV2.y))
                positions.append(Float(finalV2.z))
                normals.append(Float(unitNormal.x))
                normals.append(Float(unitNormal.y))
                normals.append(Float(unitNormal.z))

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

                addTriangle(v0: sp0, v1: sp1, v2: sp2, opposite: sp3)
                addTriangle(v0: sp0, v1: sp2, v2: sp3, opposite: sp1)
                addTriangle(v0: sp0, v1: sp3, v2: sp1, opposite: sp2)
                addTriangle(v0: sp1, v1: sp3, v2: sp2, opposite: sp0)
            }
        }

        if settings.showEdges {
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

        return MeshPayload(
            positions: positions,
            normals: normals,
            indices: indices,
            edgePolylines: edgePolylines
        )
    }
}
