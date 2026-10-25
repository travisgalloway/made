import Foundation
import simd

/// The origin or classification of a CAE numerical simulation probe (BL-RES-04, #325).
public enum SimulationProbeKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case point = "point"
    case pathSample = "pathSample"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .point:
            return "Point"
        case .pathSample:
            return "Path Sample"
        }
    }
}

/// A probed numerical simulation result sample at a spatial coordinate (BL-RES-04, #325).
public struct SimulationProbePoint: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: SimulationProbeKind
    public var position: SIMD3<Double>
    public var distanceAlongPath: Double?
    public var nodeId: Int?
    public var elementId: Int?
    public var fieldValues: [SimulationResultFieldKind: Double]
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: SimulationProbeKind = .point,
        position: SIMD3<Double>,
        distanceAlongPath: Double? = nil,
        nodeId: Int? = nil,
        elementId: Int? = nil,
        fieldValues: [SimulationResultFieldKind: Double] = [:],
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.position = position
        self.distanceAlongPath = distanceAlongPath
        self.nodeId = nodeId
        self.elementId = elementId
        self.fieldValues = fieldValues
        self.isSelected = isSelected
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, position, distanceAlongPath, nodeId, elementId, fieldValues, isSelected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Probe"
        self.kind = try container.decodeIfPresent(SimulationProbeKind.self, forKey: .kind) ?? .point
        self.position = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .position) ?? .zero
        self.distanceAlongPath = try container.decodeIfPresent(Double.self, forKey: .distanceAlongPath)
        self.nodeId = try container.decodeIfPresent(Int.self, forKey: .nodeId)
        self.elementId = try container.decodeIfPresent(Int.self, forKey: .elementId)
        self.fieldValues = try container.decodeIfPresent([SimulationResultFieldKind: Double].self, forKey: .fieldValues) ?? [:]
        self.isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
    }
}

/// Definition for a linear inspection path sampled at equidistant intervals (BL-RES-04, #325).
public struct SimulationPathProbeDefinition: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var startPoint: SIMD3<Double>
    public var endPoint: SIMD3<Double>
    public var sampleCount: Int
    public var isVisible: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Path Probe",
        startPoint: SIMD3<Double>,
        endPoint: SIMD3<Double>,
        sampleCount: Int = 10,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.sampleCount = max(2, sampleCount)
        self.isVisible = isVisible
    }

    enum CodingKeys: String, CodingKey {
        case id, name, startPoint, endPoint, sampleCount, isVisible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Path Probe"
        self.startPoint = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .startPoint) ?? .zero
        self.endPoint = try container.decodeIfPresent(SIMD3<Double>.self, forKey: .endPoint) ?? .zero
        let rawCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 10
        self.sampleCount = max(2, rawCount)
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
    }
}

/// Container table holding point probes and linear path probes for a simulation study (BL-RES-04, #325).
public struct SimulationProbeTable: Sendable, Codable, Equatable, Hashable {
    public var probes: [SimulationProbePoint]
    public var paths: [SimulationPathProbeDefinition]
    public var showProbeBadges: Bool
    public var isProbingActive: Bool

    public init(
        probes: [SimulationProbePoint] = [],
        paths: [SimulationPathProbeDefinition] = [],
        showProbeBadges: Bool = true,
        isProbingActive: Bool = false
    ) {
        self.probes = probes
        self.paths = paths
        self.showProbeBadges = showProbeBadges
        self.isProbingActive = isProbingActive
    }

    enum CodingKeys: String, CodingKey {
        case probes, paths, showProbeBadges, isProbingActive
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.probes = try container.decodeIfPresent([SimulationProbePoint].self, forKey: .probes) ?? []
        self.paths = try container.decodeIfPresent([SimulationPathProbeDefinition].self, forKey: .paths) ?? []
        self.showProbeBadges = try container.decodeIfPresent(Bool.self, forKey: .showProbeBadges) ?? true
        self.isProbingActive = try container.decodeIfPresent(Bool.self, forKey: .isProbingActive) ?? false
    }

    /// Serializes the probe table to an RFC 4180 compliant CSV string.
    ///
    /// - Parameter field: When specified, produces a table containing only the selected result field column.
    ///   When `nil`, produces a complete table containing columns for all `SimulationResultFieldKind` cases.
    public func toCSV(field: SimulationResultFieldKind? = nil) -> String {
        var lines: [String] = []

        if let field {
            let unitStr = field.defaultUnitSymbol.isEmpty ? "" : " [\(field.defaultUnitSymbol)]"
            let valueHeader = "Value\(unitStr)"
            let headers = [
                "Index", "Name", "Kind", "X [mm]", "Y [mm]", "Z [mm]",
                "Distance [mm]", "Node ID", "Element ID", valueHeader
            ]
            lines.append(headers.map { BillOfMaterials.escapeCSVField($0) }.joined(separator: ","))

            for (index, probe) in probes.enumerated() {
                let valStr: String
                if let v = probe.fieldValues[field] {
                    valStr = formatScalar(v)
                } else {
                    valStr = ""
                }

                let row: [String] = [
                    String(index + 1),
                    BillOfMaterials.escapeCSVField(probe.name),
                    BillOfMaterials.escapeCSVField(probe.kind.displayName),
                    formatScalar(probe.position.x),
                    formatScalar(probe.position.y),
                    formatScalar(probe.position.z),
                    probe.distanceAlongPath.map { formatScalar($0) } ?? "",
                    probe.nodeId.map { String($0) } ?? "",
                    probe.elementId.map { String($0) } ?? "",
                    valStr
                ]
                lines.append(row.joined(separator: ","))
            }
        } else {
            var headers = [
                "Index", "Name", "Kind", "X [mm]", "Y [mm]", "Z [mm]",
                "Distance [mm]", "Node ID", "Element ID"
            ]
            let allFields = SimulationResultFieldKind.allCases
            for f in allFields {
                let unitStr = f.defaultUnitSymbol.isEmpty ? "" : " [\(f.defaultUnitSymbol)]"
                headers.append("\(f.displayName)\(unitStr)")
            }
            lines.append(headers.map { BillOfMaterials.escapeCSVField($0) }.joined(separator: ","))

            for (index, probe) in probes.enumerated() {
                var row: [String] = [
                    String(index + 1),
                    BillOfMaterials.escapeCSVField(probe.name),
                    BillOfMaterials.escapeCSVField(probe.kind.displayName),
                    formatScalar(probe.position.x),
                    formatScalar(probe.position.y),
                    formatScalar(probe.position.z),
                    probe.distanceAlongPath.map { formatScalar($0) } ?? "",
                    probe.nodeId.map { String($0) } ?? "",
                    probe.elementId.map { String($0) } ?? ""
                ]
                for f in allFields {
                    if let v = probe.fieldValues[f] {
                        row.append(formatScalar(v))
                    } else {
                        row.append("")
                    }
                }
                lines.append(row.joined(separator: ","))
            }
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func formatScalar(_ val: Double) -> String {
        if val.isNaN { return "NaN" }
        if val.isInfinite { return val > 0 ? "Infinity" : "-Infinity" }
        let absVal = abs(val)
        if absVal >= 1e6 || (absVal < 1e-4 && absVal > 0) {
            return String(format: "%.4e", val)
        } else {
            return String(format: "%.4f", val)
        }
    }
}
