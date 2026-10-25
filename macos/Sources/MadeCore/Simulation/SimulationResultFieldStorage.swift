import Foundation
import simd

/// Supported serialization formats for CAE finite element result fields (ADR-D5 §8, BL-RES-01, #192).
public enum ResultFieldFormat: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case vtu
    case compactBinary

    public var displayName: String {
        switch self {
        case .vtu:
            return "VTU"
        case .compactBinary:
            return "Binary"
        }
    }

    public var fileExtension: String {
        switch self {
        case .vtu:
            return "vtu"
        case .compactBinary:
            return "bin"
        }
    }
}

/// Categorization of numerical field results across nodes and elements (BL-RES-01, #192).
public enum ResultFieldKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case displacement
    case vonMisesStress
    case temperature
    case cauchyStress
    case elementVonMisesStress
    case elementHeatFlux
    case bucklingMode
    case modeShape

    public var displayName: String {
        switch self {
        case .displacement:
            return "Displacement"
        case .vonMisesStress:
            return "von Mises Stress"
        case .temperature:
            return "Temperature"
        case .cauchyStress:
            return "Cauchy Stress Tensor"
        case .elementVonMisesStress:
            return "Element von Mises Stress"
        case .elementHeatFlux:
            return "Element Heat Flux"
        case .bucklingMode:
            return "Buckling Mode"
        case .modeShape:
            return "Mode Shape"
        }
    }

    public var isNodal: Bool {
        switch self {
        case .displacement, .vonMisesStress, .temperature, .cauchyStress, .bucklingMode, .modeShape:
            return true
        case .elementVonMisesStress, .elementHeatFlux:
            return false
        }
    }

    public var defaultComponentCount: Int {
        switch self {
        case .displacement, .elementHeatFlux:
            return 3
        case .vonMisesStress, .temperature, .elementVonMisesStress, .bucklingMode, .modeShape:
            return 1
        case .cauchyStress:
            return 6
        }
    }
}

/// Metadata summary describing an individual result field stored on disk or resident in memory (BL-RES-01, #192).
public struct ResultFieldMetadata: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var kind: ResultFieldKind
    public var componentCount: Int
    public var entityCount: Int
    public var minMagnitude: Double
    public var maxMagnitude: Double
    public var unitSymbol: String

    public init(
        name: String,
        kind: ResultFieldKind,
        componentCount: Int,
        entityCount: Int,
        minMagnitude: Double = 0.0,
        maxMagnitude: Double = 0.0,
        unitSymbol: String = ""
    ) {
        self.name = name
        self.kind = kind
        self.componentCount = componentCount
        self.entityCount = entityCount
        self.minMagnitude = minMagnitude
        self.maxMagnitude = maxMagnitude
        self.unitSymbol = unitSymbol
    }
}

/// Storage reference and cache descriptor for offloaded finite element solver result fields (ADR-D7, BL-RES-01, #192).
public struct ResultFieldStorageDescriptor: Sendable, Codable, Equatable, Hashable {
    public var storagePath: String
    public var format: ResultFieldFormat
    public var availableFields: [ResultFieldMetadata]
    public var byteSize: Int64
    public var isResident: Bool

    public init(
        storagePath: String,
        format: ResultFieldFormat,
        availableFields: [ResultFieldMetadata] = [],
        byteSize: Int64 = 0,
        isResident: Bool = false
    ) {
        self.storagePath = storagePath
        self.format = format
        self.availableFields = availableFields
        self.byteSize = byteSize
        self.isResident = isResident
    }

    enum CodingKeys: String, CodingKey {
        case storagePath, format, availableFields, byteSize, isResident
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.storagePath = try container.decodeIfPresent(String.self, forKey: .storagePath) ?? ""
        self.format = try container.decodeIfPresent(ResultFieldFormat.self, forKey: .format) ?? .vtu
        self.availableFields = try container.decodeIfPresent([ResultFieldMetadata].self, forKey: .availableFields) ?? []
        self.byteSize = try container.decodeIfPresent(Int64.self, forKey: .byteSize) ?? 0
        self.isResident = try container.decodeIfPresent(Bool.self, forKey: .isResident) ?? false
    }
}

/// Complete in-memory payload of discrete finite element result fields (BL-RES-01, #192).
public struct SimulationResultFields: Sendable, Codable, Equatable {
    public var studyId: UUID
    public var nodalDisplacements: [Int: SIMD3<Double>]?
    public var nodalVonMisesStresses: [Int: Double]?
    public var nodalTemperatures: [Int: Double]?
    public var nodalCauchyTensors: [Int: CauchyStressTensor]?
    public var elementVonMisesStresses: [Int: Double]?
    public var elementHeatFluxes: [Int: SIMD3<Double>]?
    public var bucklingModes: [SimulationBucklingMode]?
    public var modeShapes: [SimulationModeShape]?
    public var loadSteps: [SimulationLoadStep]?

    public init(
        studyId: UUID,
        nodalDisplacements: [Int: SIMD3<Double>]? = nil,
        nodalVonMisesStresses: [Int: Double]? = nil,
        nodalTemperatures: [Int: Double]? = nil,
        nodalCauchyTensors: [Int: CauchyStressTensor]? = nil,
        elementVonMisesStresses: [Int: Double]? = nil,
        elementHeatFluxes: [Int: SIMD3<Double>]? = nil,
        bucklingModes: [SimulationBucklingMode]? = nil,
        modeShapes: [SimulationModeShape]? = nil,
        loadSteps: [SimulationLoadStep]? = nil
    ) {
        self.studyId = studyId
        self.nodalDisplacements = nodalDisplacements
        self.nodalVonMisesStresses = nodalVonMisesStresses
        self.nodalTemperatures = nodalTemperatures
        self.nodalCauchyTensors = nodalCauchyTensors
        self.elementVonMisesStresses = elementVonMisesStresses
        self.elementHeatFluxes = elementHeatFluxes
        self.bucklingModes = bucklingModes
        self.modeShapes = modeShapes
        self.loadSteps = loadSteps
    }

    public var isEmpty: Bool {
        nodalDisplacements == nil &&
        nodalVonMisesStresses == nil &&
        nodalTemperatures == nil &&
        nodalCauchyTensors == nil &&
        elementVonMisesStresses == nil &&
        elementHeatFluxes == nil &&
        bucklingModes == nil &&
        modeShapes == nil &&
        loadSteps == nil
    }

    public func metadataList() -> [ResultFieldMetadata] {
        var list: [ResultFieldMetadata] = []

        if let d = nodalDisplacements, !d.isEmpty {
            let magnitudes = d.values.map { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) }
            let minMag = magnitudes.min() ?? 0.0
            let maxMag = magnitudes.max() ?? 0.0
            list.append(ResultFieldMetadata(
                name: "Displacement Magnitude",
                kind: .displacement,
                componentCount: 3,
                entityCount: d.count,
                minMagnitude: minMag,
                maxMagnitude: maxMag,
                unitSymbol: "mm"
            ))
        }

        if let s = nodalVonMisesStresses, !s.isEmpty {
            let minS = s.values.min() ?? 0.0
            let maxS = s.values.max() ?? 0.0
            list.append(ResultFieldMetadata(
                name: "von Mises Stress",
                kind: .vonMisesStress,
                componentCount: 1,
                entityCount: s.count,
                minMagnitude: minS,
                maxMagnitude: maxS,
                unitSymbol: "MPa"
            ))
        }

        if let t = nodalTemperatures, !t.isEmpty {
            let minT = t.values.min() ?? 0.0
            let maxT = t.values.max() ?? 0.0
            list.append(ResultFieldMetadata(
                name: "Temperature",
                kind: .temperature,
                componentCount: 1,
                entityCount: t.count,
                minMagnitude: minT,
                maxMagnitude: maxT,
                unitSymbol: "°C"
            ))
        }

        if let c = nodalCauchyTensors, !c.isEmpty {
            let vmValues = c.values.map(\.vonMisesStress)
            let minC = vmValues.min() ?? 0.0
            let maxC = vmValues.max() ?? 0.0
            list.append(ResultFieldMetadata(
                name: "Cauchy Stress Tensor",
                kind: .cauchyStress,
                componentCount: 6,
                entityCount: c.count,
                minMagnitude: minC,
                maxMagnitude: maxC,
                unitSymbol: "MPa"
            ))
        }

        if let es = elementVonMisesStresses, !es.isEmpty {
            let minES = es.values.min() ?? 0.0
            let maxES = es.values.max() ?? 0.0
            list.append(ResultFieldMetadata(
                name: "Element von Mises Stress",
                kind: .elementVonMisesStress,
                componentCount: 1,
                entityCount: es.count,
                minMagnitude: minES,
                maxMagnitude: maxES,
                unitSymbol: "MPa"
            ))
        }

        if let hf = elementHeatFluxes, !hf.isEmpty {
            let magnitudes = hf.values.map { sqrt($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) }
            let minHF = magnitudes.min() ?? 0.0
            let maxHF = magnitudes.max() ?? 0.0
            list.append(ResultFieldMetadata(
                name: "Element Heat Flux",
                kind: .elementHeatFlux,
                componentCount: 3,
                entityCount: hf.count,
                minMagnitude: minHF,
                maxMagnitude: maxHF,
                unitSymbol: "W/m²"
            ))
        }

        if let bm = bucklingModes, !bm.isEmpty {
            let factors = bm.map(\.loadFactor)
            let minF = factors.min() ?? 0.0
            let maxF = factors.max() ?? 0.0
            list.append(ResultFieldMetadata(
                name: "Buckling Modes",
                kind: .bucklingMode,
                componentCount: 1,
                entityCount: bm.count,
                minMagnitude: minF,
                maxMagnitude: maxF,
                unitSymbol: ""
            ))
        }

        if let ms = modeShapes, !ms.isEmpty {
            let freqs = ms.map(\.frequencyHz)
            let minFreq = freqs.min() ?? 0.0
            let maxFreq = freqs.max() ?? 0.0
            list.append(ResultFieldMetadata(
                name: "Natural Frequencies",
                kind: .modeShape,
                componentCount: 1,
                entityCount: ms.count,
                minMagnitude: minFreq,
                maxMagnitude: maxFreq,
                unitSymbol: "Hz"
            ))
        }

        return list
    }
}

// MARK: - VTU XML Parser Delegate

private final class VTUParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var hasUnstructuredGrid: Bool = false
    var hasPiece: Bool = false
    var numberOfPoints: Int = 0
    var numberOfCells: Int = 0
    var studyIdString: String? = nil

    var dataArrays: [String: (type: String, components: Int, text: String)] = [:]

    private var currentArrayName: String?
    private var currentArrayType: String = ""
    private var currentArrayComponents: Int = 1
    private var currentText: String = ""
    var parseError: Error?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "UnstructuredGrid" {
            hasUnstructuredGrid = true
            if let sid = attributeDict["studyId"] {
                studyIdString = sid
            }
        } else if elementName == "Piece" {
            hasPiece = true
            if let ptsStr = attributeDict["NumberOfPoints"], let pts = Int(ptsStr) {
                numberOfPoints = pts
            }
            if let cellsStr = attributeDict["NumberOfCells"], let cells = Int(cellsStr) {
                numberOfCells = cells
            }
            if let sid = attributeDict["studyId"] {
                studyIdString = sid
            }
        } else if elementName == "DataArray" {
            currentArrayName = attributeDict["Name"]
            currentArrayType = attributeDict["type"] ?? "Float64"
            currentArrayComponents = Int(attributeDict["NumberOfComponents"] ?? "1") ?? 1
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentArrayName != nil {
            currentText.append(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "DataArray", let name = currentArrayName {
            dataArrays[name] = (type: currentArrayType, components: currentArrayComponents, text: currentText)
            currentArrayName = nil
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

// MARK: - Simulation Export Errors

/// Errors produced during simulation VTU result export or ParaView launch (BL-RES-09, #329).
public enum SimulationExportError: Error, LocalizedError, Equatable, Sendable {
    case studyNotFound(UUID)
    case studyNotSolved(UUID)
    case meshNotFound(UUID)
    case fieldsNotFound(UUID)
    case writeFailed(String)
    case openFailed(String)

    public var errorDescription: String? {
        switch self {
        case .studyNotFound(let id):
            return "Simulation study with ID \(id) was not found."
        case .studyNotSolved(let id):
            return "Simulation study with ID \(id) has not completed solving."
        case .meshNotFound(let id):
            return "Volume mesh for simulation study with ID \(id) was not found."
        case .fieldsNotFound(let id):
            return "Result fields for simulation study with ID \(id) were not found."
        case .writeFailed(let reason):
            return "Failed to write VTU export file: \(reason)"
        case .openFailed(let reason):
            return "Failed to open results in ParaView: \(reason)"
        }
    }
}

// MARK: - VTU Result Format

/// Serializer and deserializer for VTK XML UnstructuredGrid format (BL-RES-01, #192).
public enum VTUResultFormat: Sendable {

    private static func parseDoubles(_ text: String) -> [Double] {
        let tokens = text.split { $0.isWhitespace || $0.isNewline }
        var numbers: [Double] = []
        numbers.reserveCapacity(tokens.count)
        for token in tokens {
            if let val = Double(token) {
                numbers.append(val)
            }
        }
        return numbers
    }

    private static func parseInts(_ text: String) -> [Int] {
        let tokens = text.split { $0.isWhitespace || $0.isNewline }
        var numbers: [Int] = []
        numbers.reserveCapacity(tokens.count)
        for token in tokens {
            if let val = Int(token) {
                numbers.append(val)
            }
        }
        return numbers
    }

    public static func exportVTU(mesh: VolumeMesh, fields: SimulationResultFields) throws -> String {
        let nodeCount = mesh.nodes.count
        let elementCount = mesh.elements.count

        var xml = "<?xml version=\"1.0\"?>\n"
        xml += "<VTKFile type=\"UnstructuredGrid\" version=\"1.0\" byte_order=\"LittleEndian\">\n"
        xml += "  <UnstructuredGrid studyId=\"\(fields.studyId.uuidString)\">\n"
        xml += "    <Piece NumberOfPoints=\"\(nodeCount)\" NumberOfCells=\"\(elementCount)\">\n"

        // Points
        xml += "      <Points>\n"
        xml += "        <DataArray type=\"Float64\" Name=\"Points\" NumberOfComponents=\"3\" format=\"ascii\">\n"
        if nodeCount > 0 {
            var pointsText = ""
            pointsText.reserveCapacity(nodeCount * 30)
            for node in mesh.nodes {
                pointsText += " \(node.position.x) \(node.position.y) \(node.position.z)"
            }
            xml += pointsText + "\n"
        }
        xml += "        </DataArray>\n"
        xml += "      </Points>\n"

        // Cells
        xml += "      <Cells>\n"
        var nodeIdToPointIndex: [Int: Int] = [:]
        nodeIdToPointIndex.reserveCapacity(nodeCount)
        for (idx, node) in mesh.nodes.enumerated() {
            nodeIdToPointIndex[node.id] = idx
        }

        xml += "        <DataArray type=\"Int64\" Name=\"connectivity\" format=\"ascii\">\n"
        if elementCount > 0 {
            var connText = ""
            connText.reserveCapacity(elementCount * 30)
            for elem in mesh.elements {
                for nId in elem.nodeIndices {
                    let ptIdx = nodeIdToPointIndex[nId] ?? nId
                    connText += " \(ptIdx)"
                }
            }
            xml += connText + "\n"
        }
        xml += "        </DataArray>\n"

        xml += "        <DataArray type=\"Int64\" Name=\"offsets\" format=\"ascii\">\n"
        if elementCount > 0 {
            var runningOffset = 0
            var offsetsText = ""
            offsetsText.reserveCapacity(elementCount * 10)
            for elem in mesh.elements {
                runningOffset += elem.nodeIndices.count
                offsetsText += " \(runningOffset)"
            }
            xml += offsetsText + "\n"
        }
        xml += "        </DataArray>\n"

        xml += "        <DataArray type=\"UInt8\" Name=\"types\" format=\"ascii\">\n"
        if elementCount > 0 {
            var typesText = ""
            typesText.reserveCapacity(elementCount * 4)
            for elem in mesh.elements {
                let vtkType = (elem.order == .quadratic || elem.nodeIndices.count == 10) ? 24 : 10
                typesText += " \(vtkType)"
            }
            xml += typesText + "\n"
        }
        xml += "        </DataArray>\n"
        xml += "      </Cells>\n"

        // PointData
        xml += "      <PointData>\n"
        if nodeCount > 0 {
            var nodeIdsText = ""
            for node in mesh.nodes {
                nodeIdsText += " \(node.id)"
            }
            xml += "        <DataArray type=\"Int64\" Name=\"GlobalNodeIDs\" NumberOfComponents=\"1\" format=\"ascii\">\n"
            xml += nodeIdsText + "\n"
            xml += "        </DataArray>\n"

            if let disp = fields.nodalDisplacements {
                var dispText = ""
                for node in mesh.nodes {
                    let d = disp[node.id] ?? .zero
                    dispText += " \(d.x) \(d.y) \(d.z)"
                }
                xml += "        <DataArray type=\"Float64\" Name=\"Displacement\" NumberOfComponents=\"3\" format=\"ascii\">\n"
                xml += dispText + "\n"
                xml += "        </DataArray>\n"
            }

            if let vm = fields.nodalVonMisesStresses {
                var vmText = ""
                for node in mesh.nodes {
                    let s = vm[node.id] ?? 0.0
                    vmText += " \(s)"
                }
                xml += "        <DataArray type=\"Float64\" Name=\"VonMisesStress\" NumberOfComponents=\"1\" format=\"ascii\">\n"
                xml += vmText + "\n"
                xml += "        </DataArray>\n"
            }

            if let temp = fields.nodalTemperatures {
                var tempText = ""
                for node in mesh.nodes {
                    let t = temp[node.id] ?? 0.0
                    tempText += " \(t)"
                }
                xml += "        <DataArray type=\"Float64\" Name=\"Temperature\" NumberOfComponents=\"1\" format=\"ascii\">\n"
                xml += tempText + "\n"
                xml += "        </DataArray>\n"
            }

            if let cauchy = fields.nodalCauchyTensors {
                var cauchyText = ""
                for node in mesh.nodes {
                    let c = cauchy[node.id] ?? CauchyStressTensor()
                    cauchyText += " \(c.sxx) \(c.syy) \(c.szz) \(c.sxy) \(c.syz) \(c.szx)"
                }
                xml += "        <DataArray type=\"Float64\" Name=\"CauchyStress\" NumberOfComponents=\"6\" format=\"ascii\">\n"
                xml += cauchyText + "\n"
                xml += "        </DataArray>\n"
            }

            if let modes = fields.modeShapes {
                for mode in modes {
                    var mDispText = ""
                    for node in mesh.nodes {
                        let d = mode.nodalDisplacements[node.id] ?? .zero
                        mDispText += " \(d.x) \(d.y) \(d.z)"
                    }
                    xml += "        <DataArray type=\"Float64\" Name=\"ModeShape_\(mode.modeNumber)_Displacement\" NumberOfComponents=\"3\" format=\"ascii\">\n"
                    xml += mDispText + "\n"
                    xml += "        </DataArray>\n"
                }
            }

            if let bModes = fields.bucklingModes {
                for mode in bModes {
                    var bDispText = ""
                    for node in mesh.nodes {
                        let d = mode.nodalDisplacements[node.id] ?? .zero
                        bDispText += " \(d.x) \(d.y) \(d.z)"
                    }
                    xml += "        <DataArray type=\"Float64\" Name=\"BucklingMode_\(mode.modeNumber)_Displacement\" NumberOfComponents=\"3\" format=\"ascii\">\n"
                    xml += bDispText + "\n"
                    xml += "        </DataArray>\n"
                }
            }
        }
        xml += "      </PointData>\n"

        // CellData
        xml += "      <CellData>\n"
        if elementCount > 0 {
            var elemIdsText = ""
            for elem in mesh.elements {
                elemIdsText += " \(elem.id)"
            }
            xml += "        <DataArray type=\"Int64\" Name=\"GlobalElementIDs\" NumberOfComponents=\"1\" format=\"ascii\">\n"
            xml += elemIdsText + "\n"
            xml += "        </DataArray>\n"

            if let evm = fields.elementVonMisesStresses {
                var evmText = ""
                for elem in mesh.elements {
                    let s = evm[elem.id] ?? 0.0
                    evmText += " \(s)"
                }
                xml += "        <DataArray type=\"Float64\" Name=\"ElementVonMisesStress\" NumberOfComponents=\"1\" format=\"ascii\">\n"
                xml += evmText + "\n"
                xml += "        </DataArray>\n"
            }

            if let flux = fields.elementHeatFluxes {
                var fluxText = ""
                for elem in mesh.elements {
                    let q = flux[elem.id] ?? .zero
                    fluxText += " \(q.x) \(q.y) \(q.z)"
                }
                xml += "        <DataArray type=\"Float64\" Name=\"HeatFlux\" NumberOfComponents=\"3\" format=\"ascii\">\n"
                xml += fluxText + "\n"
                xml += "        </DataArray>\n"
            }
        }
        xml += "      </CellData>\n"

        xml += "    </Piece>\n"
        xml += "  </UnstructuredGrid>\n"
        xml += "</VTKFile>\n"
        return xml
    }

    public static func importVTU(data: Data) throws(CAEErrorCode) -> (mesh: VolumeMesh?, fields: SimulationResultFields) {
        guard !data.isEmpty else {
            throw CAEErrorCode.resultParsingFailed(details: "VTU data is empty")
        }

        let parser = XMLParser(data: data)
        let delegate = VTUParserDelegate()
        parser.delegate = delegate

        guard parser.parse() else {
            let errDesc = delegate.parseError?.localizedDescription ?? "XML parse failure"
            throw CAEErrorCode.resultParsingFailed(details: "Failed to parse VTU XML: \(errDesc)")
        }

        guard delegate.hasUnstructuredGrid, delegate.hasPiece else {
            throw CAEErrorCode.resultParsingFailed(details: "Missing UnstructuredGrid or Piece element in VTU file")
        }

        let studyId = delegate.studyIdString.flatMap(UUID.init) ?? UUID()
        let nPoints = delegate.numberOfPoints
        let nCells = delegate.numberOfCells

        var nodes: [VolumeMeshNode] = []
        var nodeIds: [Int] = []
        if nPoints > 0 {
            guard let pointsEntry = delegate.dataArrays["Points"] else {
                throw CAEErrorCode.resultParsingFailed(details: "Missing Points DataArray in VTU")
            }
            let coords = parseDoubles(pointsEntry.text)
            guard coords.count == nPoints * 3 else {
                throw CAEErrorCode.resultParsingFailed(details: "Point coordinate count mismatch: expected \(nPoints * 3), got \(coords.count)")
            }

            if let gIdsEntry = delegate.dataArrays["GlobalNodeIDs"] {
                nodeIds = parseInts(gIdsEntry.text)
                guard nodeIds.count == nPoints else {
                    throw CAEErrorCode.resultParsingFailed(details: "GlobalNodeIDs count mismatch")
                }
            } else {
                nodeIds = Array(1...nPoints)
            }

            nodes.reserveCapacity(nPoints)
            for i in 0..<nPoints {
                let pos = SIMD3<Double>(coords[3 * i], coords[3 * i + 1], coords[3 * i + 2])
                nodes.append(VolumeMeshNode(id: nodeIds[i], position: pos))
            }
        }

        var elements: [VolumeMeshElement] = []
        if nCells > 0 {
            guard let connEntry = delegate.dataArrays["connectivity"],
                  let offsetsEntry = delegate.dataArrays["offsets"],
                  let typesEntry = delegate.dataArrays["types"] else {
                throw CAEErrorCode.resultParsingFailed(details: "Missing connectivity, offsets, or types in Cells")
            }
            let connectivity = parseInts(connEntry.text)
            let offsets = parseInts(offsetsEntry.text)
            let types = parseInts(typesEntry.text)
            guard offsets.count == nCells, types.count == nCells else {
                throw CAEErrorCode.resultParsingFailed(details: "Cell offsets or types count mismatch")
            }

            let elemIds: [Int]
            if let gElemEntry = delegate.dataArrays["GlobalElementIDs"] {
                elemIds = parseInts(gElemEntry.text)
                guard elemIds.count == nCells else {
                    throw CAEErrorCode.resultParsingFailed(details: "GlobalElementIDs count mismatch")
                }
            } else {
                elemIds = Array(1...nCells)
            }

            elements.reserveCapacity(nCells)
            for j in 0..<nCells {
                let startIdx = (j == 0) ? 0 : offsets[j - 1]
                let endIdx = offsets[j]
                guard startIdx <= endIdx, endIdx <= connectivity.count else {
                    throw CAEErrorCode.resultParsingFailed(details: "Invalid cell connectivity range")
                }
                let cellPointIndices = connectivity[startIdx..<endIdx]
                let cellNodeIndices = cellPointIndices.map { ptIdx in
                    (ptIdx >= 0 && ptIdx < nodeIds.count) ? nodeIds[ptIdx] : (ptIdx + 1)
                }
                let typeVal = types[j]
                let order: MeshElementOrder = (typeVal == 24 || cellNodeIndices.count == 10) ? .quadratic : .linear
                elements.append(VolumeMeshElement(id: elemIds[j], order: order, nodeIndices: cellNodeIndices, tag: 0))
            }
        }

        var nodalDisplacements: [Int: SIMD3<Double>]? = nil
        if let dispEntry = delegate.dataArrays["Displacement"], nPoints > 0 {
            let vals = parseDoubles(dispEntry.text)
            if vals.count == nPoints * 3 {
                var d: [Int: SIMD3<Double>] = [:]
                d.reserveCapacity(nPoints)
                for i in 0..<nPoints {
                    d[nodeIds[i]] = SIMD3<Double>(vals[3 * i], vals[3 * i + 1], vals[3 * i + 2])
                }
                nodalDisplacements = d
            }
        }

        var nodalVonMisesStresses: [Int: Double]? = nil
        if let vmEntry = delegate.dataArrays["VonMisesStress"], nPoints > 0 {
            let vals = parseDoubles(vmEntry.text)
            if vals.count == nPoints {
                var vm: [Int: Double] = [:]
                vm.reserveCapacity(nPoints)
                for i in 0..<nPoints {
                    vm[nodeIds[i]] = vals[i]
                }
                nodalVonMisesStresses = vm
            }
        }

        var nodalTemperatures: [Int: Double]? = nil
        if let tempEntry = delegate.dataArrays["Temperature"], nPoints > 0 {
            let vals = parseDoubles(tempEntry.text)
            if vals.count == nPoints {
                var t: [Int: Double] = [:]
                t.reserveCapacity(nPoints)
                for i in 0..<nPoints {
                    t[nodeIds[i]] = vals[i]
                }
                nodalTemperatures = t
            }
        }

        var nodalCauchyTensors: [Int: CauchyStressTensor]? = nil
        if let cauchyEntry = delegate.dataArrays["CauchyStress"], nPoints > 0 {
            let vals = parseDoubles(cauchyEntry.text)
            if vals.count == nPoints * 6 {
                var c: [Int: CauchyStressTensor] = [:]
                c.reserveCapacity(nPoints)
                for i in 0..<nPoints {
                    c[nodeIds[i]] = CauchyStressTensor(
                        sxx: vals[6 * i],
                        syy: vals[6 * i + 1],
                        szz: vals[6 * i + 2],
                        sxy: vals[6 * i + 3],
                        syz: vals[6 * i + 4],
                        szx: vals[6 * i + 5]
                    )
                }
                nodalCauchyTensors = c
            }
        }

        var elementVonMisesStresses: [Int: Double]? = nil
        if let evmEntry = delegate.dataArrays["ElementVonMisesStress"], nCells > 0 {
            let vals = parseDoubles(evmEntry.text)
            if vals.count == nCells {
                let elemIds = delegate.dataArrays["GlobalElementIDs"].map { parseInts($0.text) } ?? Array(1...nCells)
                var evm: [Int: Double] = [:]
                evm.reserveCapacity(nCells)
                for j in 0..<nCells {
                    evm[elemIds[j]] = vals[j]
                }
                elementVonMisesStresses = evm
            }
        }

        var elementHeatFluxes: [Int: SIMD3<Double>]? = nil
        if let hfEntry = delegate.dataArrays["HeatFlux"], nCells > 0 {
            let vals = parseDoubles(hfEntry.text)
            if vals.count == nCells * 3 {
                let elemIds = delegate.dataArrays["GlobalElementIDs"].map { parseInts($0.text) } ?? Array(1...nCells)
                var hf: [Int: SIMD3<Double>] = [:]
                hf.reserveCapacity(nCells)
                for j in 0..<nCells {
                    hf[elemIds[j]] = SIMD3<Double>(vals[3 * j], vals[3 * j + 1], vals[3 * j + 2])
                }
                elementHeatFluxes = hf
            }
        }

        var modeShapes: [SimulationModeShape] = []
        for (key, entry) in delegate.dataArrays where key.hasPrefix("ModeShape_") && key.hasSuffix("_Displacement") {
            let parts = key.components(separatedBy: "_")
            if parts.count == 3, let modeNum = Int(parts[1]) {
                let vals = parseDoubles(entry.text)
                if vals.count == nPoints * 3 {
                    var mDisp: [Int: SIMD3<Double>] = [:]
                    mDisp.reserveCapacity(nPoints)
                    for i in 0..<nPoints {
                        mDisp[nodeIds[i]] = SIMD3<Double>(vals[3 * i], vals[3 * i + 1], vals[3 * i + 2])
                    }
                    modeShapes.append(SimulationModeShape(modeNumber: modeNum, frequencyHz: 0.0, nodalDisplacements: mDisp))
                }
            }
        }
        modeShapes.sort { $0.modeNumber < $1.modeNumber }

        var bucklingModes: [SimulationBucklingMode] = []
        for (key, entry) in delegate.dataArrays where key.hasPrefix("BucklingMode_") && key.hasSuffix("_Displacement") {
            let parts = key.components(separatedBy: "_")
            if parts.count == 3, let modeNum = Int(parts[1]) {
                let vals = parseDoubles(entry.text)
                if vals.count == nPoints * 3 {
                    var bDisp: [Int: SIMD3<Double>] = [:]
                    bDisp.reserveCapacity(nPoints)
                    for i in 0..<nPoints {
                        bDisp[nodeIds[i]] = SIMD3<Double>(vals[3 * i], vals[3 * i + 1], vals[3 * i + 2])
                    }
                    bucklingModes.append(SimulationBucklingMode(modeNumber: modeNum, loadFactor: 0.0, nodalDisplacements: bDisp))
                }
            }
        }
        bucklingModes.sort { $0.modeNumber < $1.modeNumber }

        let mesh: VolumeMesh? = (nPoints > 0 || nCells > 0) ? VolumeMesh(nodes: nodes, elements: elements) : VolumeMesh()
        let fields = SimulationResultFields(
            studyId: studyId,
            nodalDisplacements: nodalDisplacements,
            nodalVonMisesStresses: nodalVonMisesStresses,
            nodalTemperatures: nodalTemperatures,
            nodalCauchyTensors: nodalCauchyTensors,
            elementVonMisesStresses: elementVonMisesStresses,
            elementHeatFluxes: elementHeatFluxes,
            bucklingModes: bucklingModes.isEmpty ? nil : bucklingModes,
            modeShapes: modeShapes.isEmpty ? nil : modeShapes
        )
        return (mesh: mesh, fields: fields)
    }

    public static func importVTU(xmlString: String) throws(CAEErrorCode) -> (mesh: VolumeMesh?, fields: SimulationResultFields) {
        guard let data = xmlString.data(using: .utf8) else {
            throw CAEErrorCode.resultParsingFailed(details: "Unable to encode string to UTF-8")
        }
        return try importVTU(data: data)
    }
}

// MARK: - Compact Binary Result Format

/// Serializer and deserializer for high-density binary simulation results (BL-RES-01, #192).
public enum CompactBinaryResultFormat: Sendable {
    private static let magicHeader: [UInt8] = [0x4D, 0x44, 0x52, 0x45, 0x53, 0x30, 0x31, 0x00] // "MDRES01\0"
    private static let currentVersion: UInt32 = 1

    private static let bitNodalDisplacements: UInt64 = 1 << 0
    private static let bitNodalVonMises: UInt64 = 1 << 1
    private static let bitNodalTemperatures: UInt64 = 1 << 2
    private static let bitNodalCauchy: UInt64 = 1 << 3
    private static let bitElementVonMises: UInt64 = 1 << 4
    private static let bitElementHeatFluxes: UInt64 = 1 << 5
    private static let bitBucklingModes: UInt64 = 1 << 6
    private static let bitModeShapes: UInt64 = 1 << 7

    public static func serialize(
        fields: SimulationResultFields,
        nodeIds: [Int]? = nil,
        elementIds: [Int]? = nil
    ) -> Data {
        var data = Data()

        // 1. Magic header
        data.append(contentsOf: magicHeader)

        // 2. Version
        var version = currentVersion.littleEndian
        withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }

        // 3. UUID
        var uuid = fields.studyId.uuid
        withUnsafeBytes(of: &uuid) { data.append(contentsOf: $0) }

        // Determine node IDs
        let finalNodeIds: [Int]
        if let nodeIds {
            finalNodeIds = nodeIds
        } else {
            var nSet = Set<Int>()
            if let d = fields.nodalDisplacements { nSet.formUnion(d.keys) }
            if let s = fields.nodalVonMisesStresses { nSet.formUnion(s.keys) }
            if let t = fields.nodalTemperatures { nSet.formUnion(t.keys) }
            if let c = fields.nodalCauchyTensors { nSet.formUnion(c.keys) }
            finalNodeIds = nSet.sorted()
        }

        // Determine element IDs
        let finalElementIds: [Int]
        if let elementIds {
            finalElementIds = elementIds
        } else {
            var eSet = Set<Int>()
            if let es = fields.elementVonMisesStresses { eSet.formUnion(es.keys) }
            if let hf = fields.elementHeatFluxes { eSet.formUnion(hf.keys) }
            finalElementIds = eSet.sorted()
        }

        // Bitmask
        var bitmask: UInt64 = 0
        if fields.nodalDisplacements != nil { bitmask |= bitNodalDisplacements }
        if fields.nodalVonMisesStresses != nil { bitmask |= bitNodalVonMises }
        if fields.nodalTemperatures != nil { bitmask |= bitNodalTemperatures }
        if fields.nodalCauchyTensors != nil { bitmask |= bitNodalCauchy }
        if fields.elementVonMisesStresses != nil { bitmask |= bitElementVonMises }
        if fields.elementHeatFluxes != nil { bitmask |= bitElementHeatFluxes }
        if fields.bucklingModes != nil { bitmask |= bitBucklingModes }
        if fields.modeShapes != nil { bitmask |= bitModeShapes }

        // Counts & bitmask
        var nCount = UInt64(finalNodeIds.count).littleEndian
        var eCount = UInt64(finalElementIds.count).littleEndian
        var mask = bitmask.littleEndian
        withUnsafeBytes(of: &nCount) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &eCount) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &mask) { data.append(contentsOf: $0) }

        // Node IDs
        for nId in finalNodeIds {
            var idVal = Int64(nId).littleEndian
            withUnsafeBytes(of: &idVal) { data.append(contentsOf: $0) }
        }

        // Element IDs
        for eId in finalElementIds {
            var idVal = Int64(eId).littleEndian
            withUnsafeBytes(of: &idVal) { data.append(contentsOf: $0) }
        }

        // Field payloads
        if bitmask & bitNodalDisplacements != 0 {
            for nId in finalNodeIds {
                let v = fields.nodalDisplacements?[nId] ?? .zero
                var x = v.x.bitPattern.littleEndian
                var y = v.y.bitPattern.littleEndian
                var z = v.z.bitPattern.littleEndian
                withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &z) { data.append(contentsOf: $0) }
            }
        }

        if bitmask & bitNodalVonMises != 0 {
            for nId in finalNodeIds {
                let s = fields.nodalVonMisesStresses?[nId] ?? 0.0
                var val = s.bitPattern.littleEndian
                withUnsafeBytes(of: &val) { data.append(contentsOf: $0) }
            }
        }

        if bitmask & bitNodalTemperatures != 0 {
            for nId in finalNodeIds {
                let t = fields.nodalTemperatures?[nId] ?? 0.0
                var val = t.bitPattern.littleEndian
                withUnsafeBytes(of: &val) { data.append(contentsOf: $0) }
            }
        }

        if bitmask & bitNodalCauchy != 0 {
            for nId in finalNodeIds {
                let c = fields.nodalCauchyTensors?[nId] ?? CauchyStressTensor()
                var sxx = c.sxx.bitPattern.littleEndian
                var syy = c.syy.bitPattern.littleEndian
                var szz = c.szz.bitPattern.littleEndian
                var sxy = c.sxy.bitPattern.littleEndian
                var syz = c.syz.bitPattern.littleEndian
                var szx = c.szx.bitPattern.littleEndian
                withUnsafeBytes(of: &sxx) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &syy) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &szz) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &sxy) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &syz) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &szx) { data.append(contentsOf: $0) }
            }
        }

        if bitmask & bitElementVonMises != 0 {
            for eId in finalElementIds {
                let s = fields.elementVonMisesStresses?[eId] ?? 0.0
                var val = s.bitPattern.littleEndian
                withUnsafeBytes(of: &val) { data.append(contentsOf: $0) }
            }
        }

        if bitmask & bitElementHeatFluxes != 0 {
            for eId in finalElementIds {
                let q = fields.elementHeatFluxes?[eId] ?? .zero
                var x = q.x.bitPattern.littleEndian
                var y = q.y.bitPattern.littleEndian
                var z = q.z.bitPattern.littleEndian
                withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &z) { data.append(contentsOf: $0) }
            }
        }

        if bitmask & bitBucklingModes != 0 {
            let modes = fields.bucklingModes ?? []
            var countVal = UInt32(modes.count).littleEndian
            withUnsafeBytes(of: &countVal) { data.append(contentsOf: $0) }
            for mode in modes {
                var mNum = Int32(mode.modeNumber).littleEndian
                var lf = mode.loadFactor.bitPattern.littleEndian
                withUnsafeBytes(of: &mNum) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &lf) { data.append(contentsOf: $0) }
                for nId in finalNodeIds {
                    let d = mode.nodalDisplacements[nId] ?? .zero
                    var x = d.x.bitPattern.littleEndian
                    var y = d.y.bitPattern.littleEndian
                    var z = d.z.bitPattern.littleEndian
                    withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
                    withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
                    withUnsafeBytes(of: &z) { data.append(contentsOf: $0) }
                }
            }
        }

        if bitmask & bitModeShapes != 0 {
            let shapes = fields.modeShapes ?? []
            var countVal = UInt32(shapes.count).littleEndian
            withUnsafeBytes(of: &countVal) { data.append(contentsOf: $0) }
            for shape in shapes {
                var mNum = Int32(shape.modeNumber).littleEndian
                var freq = shape.frequencyHz.bitPattern.littleEndian
                withUnsafeBytes(of: &mNum) { data.append(contentsOf: $0) }
                withUnsafeBytes(of: &freq) { data.append(contentsOf: $0) }
                for nId in finalNodeIds {
                    let d = shape.nodalDisplacements[nId] ?? .zero
                    var x = d.x.bitPattern.littleEndian
                    var y = d.y.bitPattern.littleEndian
                    var z = d.z.bitPattern.littleEndian
                    withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
                    withUnsafeBytes(of: &y) { data.append(contentsOf: $0) }
                    withUnsafeBytes(of: &z) { data.append(contentsOf: $0) }
                }
            }
        }

        return data
    }

    private struct Reader {
        let data: Data
        var offset: Int = 0

        mutating func read<T>(_: T.Type) throws(CAEErrorCode) -> T {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else {
                throw CAEErrorCode.resultParsingFailed(details: "Truncated binary result data at offset \(offset)")
            }
            let value = data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset, as: T.self)
            }
            offset += size
            return value
        }

        mutating func readBytes(count: Int) throws(CAEErrorCode) -> [UInt8] {
            guard offset + count <= data.count else {
                throw CAEErrorCode.resultParsingFailed(details: "Truncated binary result data reading \(count) bytes")
            }
            let slice = Array(data[offset..<(offset + count)])
            offset += count
            return slice
        }
    }

    public static func deserialize(data: Data) throws(CAEErrorCode) -> SimulationResultFields {
        guard data.count >= 52 else {
            throw CAEErrorCode.resultParsingFailed(details: "Binary data too short for header (got \(data.count) bytes, need at least 52)")
        }

        var reader = Reader(data: data)
        let magic = try reader.readBytes(count: 8)
        guard magic == magicHeader else {
            throw CAEErrorCode.resultParsingFailed(details: "Invalid compact binary header magic")
        }

        let version = UInt32(littleEndian: try reader.read(UInt32.self))
        guard version == currentVersion else {
            throw CAEErrorCode.resultParsingFailed(details: "Unsupported binary format version: \(version)")
        }

        let uuidBytes = try reader.readBytes(count: 16)
        let studyUUID = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))

        let nodeCount = Int(UInt64(littleEndian: try reader.read(UInt64.self)))
        let elementCount = Int(UInt64(littleEndian: try reader.read(UInt64.self)))
        let bitmask = UInt64(littleEndian: try reader.read(UInt64.self))

        var nodeIds: [Int] = []
        nodeIds.reserveCapacity(nodeCount)
        for _ in 0..<nodeCount {
            let idVal = Int64(littleEndian: try reader.read(Int64.self))
            nodeIds.append(Int(idVal))
        }

        var elementIds: [Int] = []
        elementIds.reserveCapacity(elementCount)
        for _ in 0..<elementCount {
            let idVal = Int64(littleEndian: try reader.read(Int64.self))
            elementIds.append(Int(idVal))
        }

        var nodalDisplacements: [Int: SIMD3<Double>]? = nil
        if bitmask & bitNodalDisplacements != 0 {
            var d: [Int: SIMD3<Double>] = [:]
            d.reserveCapacity(nodeCount)
            for nId in nodeIds {
                let x = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                let y = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                let z = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                d[nId] = SIMD3<Double>(x, y, z)
            }
            nodalDisplacements = d
        }

        var nodalVonMisesStresses: [Int: Double]? = nil
        if bitmask & bitNodalVonMises != 0 {
            var s: [Int: Double] = [:]
            s.reserveCapacity(nodeCount)
            for nId in nodeIds {
                let val = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                s[nId] = val
            }
            nodalVonMisesStresses = s
        }

        var nodalTemperatures: [Int: Double]? = nil
        if bitmask & bitNodalTemperatures != 0 {
            var t: [Int: Double] = [:]
            t.reserveCapacity(nodeCount)
            for nId in nodeIds {
                let val = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                t[nId] = val
            }
            nodalTemperatures = t
        }

        var nodalCauchyTensors: [Int: CauchyStressTensor]? = nil
        if bitmask & bitNodalCauchy != 0 {
            var c: [Int: CauchyStressTensor] = [:]
            c.reserveCapacity(nodeCount)
            for nId in nodeIds {
                let sxx = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                let syy = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                let szz = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                let sxy = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                let syz = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                let szx = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                c[nId] = CauchyStressTensor(sxx: sxx, syy: syy, szz: szz, sxy: sxy, syz: syz, szx: szx)
            }
            nodalCauchyTensors = c
        }

        var elementVonMisesStresses: [Int: Double]? = nil
        if bitmask & bitElementVonMises != 0 {
            var es: [Int: Double] = [:]
            es.reserveCapacity(elementCount)
            for eId in elementIds {
                let val = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                es[eId] = val
            }
            elementVonMisesStresses = es
        }

        var elementHeatFluxes: [Int: SIMD3<Double>]? = nil
        if bitmask & bitElementHeatFluxes != 0 {
            var hf: [Int: SIMD3<Double>] = [:]
            hf.reserveCapacity(elementCount)
            for eId in elementIds {
                let x = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                let y = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                let z = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                hf[eId] = SIMD3<Double>(x, y, z)
            }
            elementHeatFluxes = hf
        }

        var bucklingModes: [SimulationBucklingMode]? = nil
        if bitmask & bitBucklingModes != 0 {
            let mCount = Int(UInt32(littleEndian: try reader.read(UInt32.self)))
            var modes: [SimulationBucklingMode] = []
            modes.reserveCapacity(mCount)
            for _ in 0..<mCount {
                let mNum = Int(Int32(littleEndian: try reader.read(Int32.self)))
                let lf = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                var d: [Int: SIMD3<Double>] = [:]
                d.reserveCapacity(nodeCount)
                for nId in nodeIds {
                    let x = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                    let y = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                    let z = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                    d[nId] = SIMD3<Double>(x, y, z)
                }
                modes.append(SimulationBucklingMode(modeNumber: mNum, loadFactor: lf, nodalDisplacements: d))
            }
            bucklingModes = modes
        }

        var modeShapes: [SimulationModeShape]? = nil
        if bitmask & bitModeShapes != 0 {
            let sCount = Int(UInt32(littleEndian: try reader.read(UInt32.self)))
            var shapes: [SimulationModeShape] = []
            shapes.reserveCapacity(sCount)
            for _ in 0..<sCount {
                let mNum = Int(Int32(littleEndian: try reader.read(Int32.self)))
                let freq = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                var d: [Int: SIMD3<Double>] = [:]
                d.reserveCapacity(nodeCount)
                for nId in nodeIds {
                    let x = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                    let y = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                    let z = Double(bitPattern: UInt64(littleEndian: try reader.read(UInt64.self)))
                    d[nId] = SIMD3<Double>(x, y, z)
                }
                shapes.append(SimulationModeShape(modeNumber: mNum, frequencyHz: freq, nodalDisplacements: d))
            }
            modeShapes = shapes
        }

        return SimulationResultFields(
            studyId: studyUUID,
            nodalDisplacements: nodalDisplacements,
            nodalVonMisesStresses: nodalVonMisesStresses,
            nodalTemperatures: nodalTemperatures,
            nodalCauchyTensors: nodalCauchyTensors,
            elementVonMisesStresses: elementVonMisesStresses,
            elementHeatFluxes: elementHeatFluxes,
            bucklingModes: bucklingModes,
            modeShapes: modeShapes
        )
    }
}

// MARK: - Result Field Package Storage

/// Package cache I/O utilities for saving and loading discrete CAE result fields (ADR-D7, BL-RES-01, #192).
public enum SimulationResultFieldStorage: Sendable {

    @discardableResult
    public static func saveResultFields(
        fields: SimulationResultFields,
        mesh: VolumeMesh = VolumeMesh(),
        toPackageURL packageURL: URL
    ) throws -> ResultFieldStorageDescriptor {
        let studyDir = packageURL.appendingPathComponent("cache/results/\(fields.studyId.uuidString)")
        try FileManager.default.createDirectory(at: studyDir, withIntermediateDirectories: true)

        let vtuURL = studyDir.appendingPathComponent("results.vtu")
        let vtuString = try VTUResultFormat.exportVTU(mesh: mesh, fields: fields)
        let vtuData = Data(vtuString.utf8)
        try vtuData.write(to: vtuURL, options: .atomic)

        let binURL = studyDir.appendingPathComponent("fields.bin")
        let binData = CompactBinaryResultFormat.serialize(
            fields: fields,
            nodeIds: mesh.nodes.isEmpty ? nil : mesh.nodes.map(\.id),
            elementIds: mesh.elements.isEmpty ? nil : mesh.elements.map(\.id)
        )
        try binData.write(to: binURL, options: .atomic)

        let relativePath = "cache/results/\(fields.studyId.uuidString)/results.vtu"
        let metadataList = fields.metadataList()
        let byteSize = Int64(vtuData.count + binData.count)

        return ResultFieldStorageDescriptor(
            storagePath: relativePath,
            format: .vtu,
            availableFields: metadataList,
            byteSize: byteSize,
            isResident: true
        )
    }
}
