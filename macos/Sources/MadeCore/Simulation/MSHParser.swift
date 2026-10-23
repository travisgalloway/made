import Foundation
import simd

/// Parser for Gmsh MSH 2.2 ASCII finite element mesh decks (ADR-D5 §4, #188).
public enum MSHParser {

    /// Parses an MSH 2.2 ASCII mesh from a disk file URL.
    public static func parse(fileURL: URL) throws(CAEErrorCode) -> VolumeMesh {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CAEErrorCode.resultParsingFailed(details: "Unable to read MSH file at \(fileURL.path): \(error.localizedDescription)")
        }
        return try parse(data: data)
    }

    /// Parses an MSH 2.2 ASCII mesh from raw UTF-8 data.
    public static func parse(data: Data) throws(CAEErrorCode) -> VolumeMesh {
        guard let content = String(data: data, encoding: .utf8) else {
            throw CAEErrorCode.resultParsingFailed(details: "MSH data is not valid UTF-8 text")
        }
        return try parse(content: content)
    }

    /// Parses an MSH 2.2 ASCII mesh from string content.
    public static func parse(content: String) throws(CAEErrorCode) -> VolumeMesh {
        let rawLines = content.components(separatedBy: .newlines)
        var lineIndex = 0

        func nextLine() -> String? {
            while lineIndex < rawLines.count {
                let trimmed = rawLines[lineIndex].trimmingCharacters(in: .whitespaces)
                lineIndex += 1
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            return nil
        }

        var hasValidMeshFormat = false
        var nodes: [VolumeMeshNode] = []
        var nodeMap: [Int: SIMD3<Double>] = [:]
        var elements: [VolumeMeshElement] = []
        var surfaceTriangles: [VolumeMeshElement] = []

        var physicalNames: [Int: (dim: Int, name: String)] = [:]
        var physicalNameOrder: [Int] = []
        var physicalGroupElementIds: [Int: [Int]] = [:]
        var physicalGroupNodeIds: [Int: Set<Int>] = [:]

        var seenNodesSection = false
        var seenElementsSection = false

        while let line = nextLine() {
            if line == "$MeshFormat" {
                guard let formatLine = nextLine() else {
                    throw CAEErrorCode.resultParsingFailed(details: "Unexpected end of file in $MeshFormat section")
                }
                let tokens = formatLine.split(whereSeparator: \.isWhitespace).map(String.init)
                guard !tokens.isEmpty, tokens[0].hasPrefix("2.") else {
                    throw CAEErrorCode.resultParsingFailed(details: "Unsupported MSH version: '\(formatLine)'. Expected MSH 2.x.")
                }
                guard let endFormat = nextLine(), endFormat == "$EndMeshFormat" else {
                    throw CAEErrorCode.resultParsingFailed(details: "Missing $EndMeshFormat terminator")
                }
                hasValidMeshFormat = true
            } else if line == "$PhysicalNames" {
                guard let countLine = nextLine(), let totalNames = Int(countLine), totalNames >= 0 else {
                    throw CAEErrorCode.resultParsingFailed(details: "Invalid or missing physical names count in $PhysicalNames section")
                }

                for _ in 0..<totalNames {
                    guard let pLine = nextLine() else {
                        throw CAEErrorCode.resultParsingFailed(details: "Truncated $PhysicalNames section, expected \(totalNames) physical names")
                    }
                    let parts = pLine.split(whereSeparator: \.isWhitespace).map(String.init)
                    guard parts.count >= 3,
                          let dim = Int(parts[0]),
                          let tag = Int(parts[1]) else {
                        throw CAEErrorCode.resultParsingFailed(details: "Malformed physical name entry: '\(pLine)'")
                    }
                    let rawName: String
                    if let firstQuote = pLine.firstIndex(of: "\""),
                       let lastQuote = pLine.lastIndex(of: "\""),
                       firstQuote != lastQuote {
                        rawName = String(pLine[pLine.index(after: firstQuote)..<lastQuote])
                    } else {
                        rawName = parts[2...].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    }
                    if physicalNames[tag] == nil {
                        physicalNameOrder.append(tag)
                    }
                    physicalNames[tag] = (dim: dim, name: rawName)
                }

                guard let endPhysicalNames = nextLine(), endPhysicalNames == "$EndPhysicalNames" else {
                    throw CAEErrorCode.resultParsingFailed(details: "Missing $EndPhysicalNames terminator")
                }
            } else if line == "$Nodes" {
                seenNodesSection = true
                guard let countLine = nextLine(), let totalNodes = Int(countLine), totalNodes >= 0 else {
                    throw CAEErrorCode.resultParsingFailed(details: "Invalid or missing node count in $Nodes section")
                }

                nodes.reserveCapacity(totalNodes)
                nodeMap.reserveCapacity(totalNodes)

                for _ in 0..<totalNodes {
                    guard let nodeLine = nextLine() else {
                        throw CAEErrorCode.resultParsingFailed(details: "Truncated $Nodes section, expected \(totalNodes) nodes")
                    }
                    let parts = nodeLine.split(whereSeparator: \.isWhitespace).map(String.init)
                    guard parts.count >= 4,
                          let id = Int(parts[0]),
                          let x = Double(parts[1]),
                          let y = Double(parts[2]),
                          let z = Double(parts[3]) else {
                        throw CAEErrorCode.resultParsingFailed(details: "Malformed node entry: '\(nodeLine)'")
                    }
                    let position = SIMD3<Double>(x, y, z)
                    nodes.append(VolumeMeshNode(id: id, position: position))
                    nodeMap[id] = position
                }

                guard let endNodes = nextLine(), endNodes == "$EndNodes" else {
                    throw CAEErrorCode.resultParsingFailed(details: "Missing $EndNodes terminator")
                }
            } else if line == "$Elements" {
                seenElementsSection = true
                guard let countLine = nextLine(), let totalElements = Int(countLine), totalElements >= 0 else {
                    throw CAEErrorCode.resultParsingFailed(details: "Invalid or missing element count in $Elements section")
                }

                elements.reserveCapacity(totalElements)

                for _ in 0..<totalElements {
                    guard let elmLine = nextLine() else {
                        throw CAEErrorCode.resultParsingFailed(details: "Truncated $Elements section, expected \(totalElements) elements")
                    }
                    let parts = elmLine.split(whereSeparator: \.isWhitespace).map(String.init)
                    guard parts.count >= 3,
                          let elmId = Int(parts[0]),
                          let elmType = Int(parts[1]),
                          let numTags = Int(parts[2]),
                          numTags >= 0,
                          parts.count >= 3 + numTags else {
                        throw CAEErrorCode.resultParsingFailed(details: "Malformed element header: '\(elmLine)'")
                    }

                    let tagIndex = 3
                    let tagValue = (numTags > 0 && tagIndex < parts.count) ? (Int(parts[tagIndex]) ?? 0) : 0
                    let nodeStartIndex = 3 + numTags
                    let nodeIndices = parts[nodeStartIndex...].compactMap { Int($0) }

                    if tagValue != 0 {
                        physicalGroupElementIds[tagValue, default: []].append(elmId)
                        physicalGroupNodeIds[tagValue, default: Set<Int>()].formUnion(nodeIndices)
                    }

                    switch elmType {
                    case 4: // 4-node linear tetrahedron (C3D4)
                        guard nodeIndices.count == 4 else {
                            throw CAEErrorCode.resultParsingFailed(details: "C3D4 tetrahedron \(elmId) must have exactly 4 nodes, got \(nodeIndices.count)")
                        }
                        elements.append(VolumeMeshElement(id: elmId, order: .linear, nodeIndices: nodeIndices, tag: tagValue))

                    case 11: // 10-node quadratic tetrahedron (C3D10)
                        guard nodeIndices.count == 10 else {
                            throw CAEErrorCode.resultParsingFailed(details: "C3D10 tetrahedron \(elmId) must have exactly 10 nodes, got \(nodeIndices.count)")
                        }
                        elements.append(VolumeMeshElement(id: elmId, order: .quadratic, nodeIndices: nodeIndices, tag: tagValue))

                    case 2: // 3-node linear boundary surface triangle
                        guard nodeIndices.count == 3 else {
                            throw CAEErrorCode.resultParsingFailed(details: "Linear triangle \(elmId) must have exactly 3 nodes, got \(nodeIndices.count)")
                        }
                        surfaceTriangles.append(VolumeMeshElement(id: elmId, order: .linear, nodeIndices: nodeIndices, tag: tagValue))

                    case 9: // 6-node quadratic boundary surface triangle
                        guard nodeIndices.count == 6 else {
                            throw CAEErrorCode.resultParsingFailed(details: "Quadratic triangle \(elmId) must have exactly 6 nodes, got \(nodeIndices.count)")
                        }
                        surfaceTriangles.append(VolumeMeshElement(id: elmId, order: .quadratic, nodeIndices: nodeIndices, tag: tagValue))

                    default:
                        // Other element types (lines, points, prisms, pyramids) are skipped
                        break
                    }
                }

                guard let endElements = nextLine(), endElements == "$EndElements" else {
                    throw CAEErrorCode.resultParsingFailed(details: "Missing $EndElements terminator")
                }
            } else if line.hasPrefix("$") && !line.hasPrefix("$End") {
                // Skip unhandled section until matching $End<Section>
                let sectionName = String(line.dropFirst())
                let endMarker = "$End\(sectionName)"
                while let inner = nextLine() {
                    if inner == endMarker {
                        break
                    }
                }
            }
        }

        guard hasValidMeshFormat else {
            throw CAEErrorCode.resultParsingFailed(details: "Missing or invalid $MeshFormat header in MSH file")
        }
        guard seenNodesSection else {
            throw CAEErrorCode.resultParsingFailed(details: "Missing $Nodes section in MSH file")
        }
        guard seenElementsSection else {
            throw CAEErrorCode.resultParsingFailed(details: "Missing $Elements section in MSH file")
        }

        // Calculate mesh statistics
        let statistics: SimulationMeshStatistics
        if elements.isEmpty {
            statistics = SimulationMeshStatistics(
                nodeCount: nodes.count,
                elementCount: 0,
                minElementQuality: 1.0,
                avgElementQuality: 1.0
            )
        } else {
            var minQuality = 1.0
            var sumQuality = 0.0

            for tet in elements {
                let quality = calculateTetrahedronQuality(tet: tet, nodeMap: nodeMap)
                minQuality = min(minQuality, quality)
                sumQuality += quality
            }

            let avgQuality = sumQuality / Double(elements.count)
            statistics = SimulationMeshStatistics(
                nodeCount: nodes.count,
                elementCount: elements.count,
                minElementQuality: minQuality,
                avgElementQuality: avgQuality
            )
        }

        var sets: [VolumeMeshSet] = []
        for tag in physicalNameOrder {
            guard let info = physicalNames[tag] else { continue }
            let subType: SubelementType?
            switch info.dim {
            case 1:
                subType = .edge
            case 2:
                subType = .face
            default:
                subType = nil
            }
            let elIds = physicalGroupElementIds[tag] ?? []
            let nIds = (physicalGroupNodeIds[tag] ?? []).sorted()
            sets.append(VolumeMeshSet(
                name: info.name,
                nodeIds: nIds,
                elementIds: elIds,
                subelementType: subType,
                tag: tag
            ))
        }

        return VolumeMesh(
            nodes: nodes,
            elements: elements,
            surfaceTriangles: surfaceTriangles,
            statistics: statistics,
            sets: sets
        )
    }

    /// Evaluates aspect ratio and volume-to-edge quality metric normalized to [0, 1].
    /// Ideal equilateral tetrahedron returns 1.0; coplanar/degenerate elements return 0.0.
    private static func calculateTetrahedronQuality(
        tet: VolumeMeshElement,
        nodeMap: [Int: SIMD3<Double>]
    ) -> Double {
        guard tet.nodeIndices.count >= 4,
              let p0 = nodeMap[tet.nodeIndices[0]],
              let p1 = nodeMap[tet.nodeIndices[1]],
              let p2 = nodeMap[tet.nodeIndices[2]],
              let p3 = nodeMap[tet.nodeIndices[3]] else {
            return 0.0
        }

        let v01 = p1 - p0
        let v02 = p2 - p0
        let v03 = p3 - p0

        let cross = simd_cross(v02, v03)
        let det = simd_dot(v01, cross)
        let volume = abs(det) / 6.0

        let l01_sq = simd_length_squared(p1 - p0)
        let l02_sq = simd_length_squared(p2 - p0)
        let l03_sq = simd_length_squared(p3 - p0)
        let l12_sq = simd_length_squared(p2 - p1)
        let l13_sq = simd_length_squared(p3 - p1)
        let l23_sq = simd_length_squared(p3 - p2)

        let sumEdgeSq = l01_sq + l02_sq + l03_sq + l12_sq + l13_sq + l23_sq
        let l_rms = sqrt(sumEdgeSq / 6.0)

        guard l_rms > 1e-12, volume > 1e-18 else {
            return 0.0
        }

        // Q = (6 * sqrt(2) * V) / (L_rms^3)
        let rawQuality = (6.0 * sqrt(2.0) * volume) / (l_rms * l_rms * l_rms)
        return min(1.0, max(0.0, rawQuality))
    }
}
