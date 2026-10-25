import Foundation
import simd

/// Evaluator partitioning finite element results across CAD solid bodies and geometric targets (ADR-D5, BL-RES-06, #326).
public enum SimulationSummaryEvaluator: Sendable {

    /// Evaluates per-body result extrema and summary metrics across study targets or volume mesh sets.
    public static func evaluateBodySummaries(
        study: SimulationStudy,
        mesh: VolumeMesh,
        nodalDisplacements: [Int: SIMD3<Double>]? = nil,
        nodalVonMisesStresses: [Int: Double]? = nil,
        elementVonMisesStresses: [Int: Double]? = nil,
        nodalTemperatures: [Int: Double]? = nil,
        factorOfSafety: FactorOfSafetyResult? = nil
    ) -> [SimulationBodySummary] {
        var partitions: [(id: UUID, name: String, nodeIds: [Int], elementIds: [Int])] = []

        // 1. Partition by study.targets if explicitly configured
        if !study.targets.isEmpty {
            for target in study.targets {
                let (targetNodeIds, targetElIds) = MeshGeometryAssociator.associate(reference: target, mesh: mesh)
                let name = target.targetName.isEmpty ? "Body" : target.targetName
                partitions.append((id: target.targetId, name: name, nodeIds: targetNodeIds, elementIds: targetElIds))
            }
        }

        // 2. Fall back to mesh physical/solid sets if study.targets was empty
        if partitions.isEmpty {
            let boundaryNames = Set(study.fixtures.map(\.name) + study.loads.map(\.name))
            let solidSets = mesh.sets.filter { s in
                s.subelementType == nil && !s.elementIds.isEmpty && !boundaryNames.contains(s.name)
            }
            for s in solidSets {
                partitions.append((id: s.id, name: s.name, nodeIds: s.nodeIds, elementIds: s.elementIds))
            }
        }

        // 3. Fall back to treating the full mesh as a single body
        if partitions.isEmpty {
            let allNodeIds = mesh.nodes.map { $0.id }.sorted()
            let allElIds = mesh.elements.map { $0.id }.sorted()
            partitions.append((id: study.id, name: "Full Model", nodeIds: allNodeIds, elementIds: allElIds))
        }

        var summaries: [SimulationBodySummary] = []
        summaries.reserveCapacity(partitions.count)

        for partition in partitions {
            var maxVm: Double? = nil
            var minVm: Double? = nil
            var maxDisp: Double? = nil
            var minDisp: Double? = nil
            var minFos: Double? = nil
            var maxFos: Double? = nil
            var maxTemp: Double? = nil
            var minTemp: Double? = nil

            let pNodeSet = Set(partition.nodeIds)

            // Evaluate von Mises stress extrema
            if let nvm = nodalVonMisesStresses, !nvm.isEmpty {
                for nId in partition.nodeIds {
                    guard let s = nvm[nId] else { continue }
                    maxVm = max(maxVm ?? s, s)
                    minVm = min(minVm ?? s, s)
                }
            } else if let evm = elementVonMisesStresses, !evm.isEmpty {
                for elId in partition.elementIds {
                    guard let s = evm[elId] else { continue }
                    maxVm = max(maxVm ?? s, s)
                    minVm = min(minVm ?? s, s)
                }
            }

            // Evaluate displacement magnitude extrema
            if let disp = nodalDisplacements, !disp.isEmpty {
                for nId in partition.nodeIds {
                    guard let d = disp[nId] else { continue }
                    let mag = simd_length(d)
                    maxDisp = max(maxDisp ?? mag, mag)
                    minDisp = min(minDisp ?? mag, mag)
                }
            }

            // Evaluate Factor of Safety extrema
            if let fos = factorOfSafety {
                if !fos.nodalFactorsOfSafety.isEmpty {
                    for nId in partition.nodeIds {
                        guard let f = fos.nodalFactorsOfSafety[nId], f > 0.0 else { continue }
                        minFos = min(minFos ?? f, f)
                        maxFos = max(maxFos ?? f, f)
                    }
                } else if !pNodeSet.isEmpty {
                    minFos = fos.minFactorOfSafety
                    maxFos = fos.maxFactorOfSafety
                }
            }

            // Evaluate temperature extrema
            if let temps = nodalTemperatures, !temps.isEmpty {
                for nId in partition.nodeIds {
                    guard let t = temps[nId] else { continue }
                    maxTemp = max(maxTemp ?? t, t)
                    minTemp = min(minTemp ?? t, t)
                }
            }

            // Populate field extrema descriptors
            var extrema: [SimulationFieldExtrema] = []
            if let maxD = maxDisp, let minD = minDisp {
                extrema.append(SimulationFieldExtrema(fieldName: "Displacement Magnitude", unitSymbol: "mm", minValue: minD, maxValue: maxD))
            }
            if let maxV = maxVm, let minV = minVm {
                extrema.append(SimulationFieldExtrema(fieldName: "von Mises Stress", unitSymbol: "MPa", minValue: minV, maxValue: maxV))
            }
            if let minF = minFos, let maxF = maxFos {
                extrema.append(SimulationFieldExtrema(fieldName: "Factor of Safety", unitSymbol: "", minValue: minF, maxValue: maxF))
            }
            if let maxT = maxTemp, let minT = minTemp {
                extrema.append(SimulationFieldExtrema(fieldName: "Temperature", unitSymbol: "°C", minValue: minT, maxValue: maxT))
            }

            summaries.append(
                SimulationBodySummary(
                    id: partition.id,
                    bodyName: partition.name,
                    nodeCount: partition.nodeIds.count,
                    elementCount: partition.elementIds.count,
                    maxVonMisesStress: maxVm,
                    maxDisplacement: maxDisp,
                    minFactorOfSafety: minFos,
                    maxTemperature: maxTemp,
                    extrema: extrema
                )
            )
        }

        return summaries
    }

    /// Evaluates per-body summaries from an existing `SimulationStudyResults` container.
    public static func evaluateBodySummaries(
        study: SimulationStudy,
        mesh: VolumeMesh,
        results: SimulationStudyResults
    ) -> [SimulationBodySummary] {
        evaluateBodySummaries(
            study: study,
            mesh: mesh,
            nodalDisplacements: results.nodalDisplacements,
            nodalVonMisesStresses: results.nodalVonMisesStresses,
            elementVonMisesStresses: results.elementVonMisesStresses,
            nodalTemperatures: results.nodalTemperatures,
            factorOfSafety: results.factorOfSafety
        )
    }
}
