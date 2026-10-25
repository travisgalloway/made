import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SimulationResultFieldStorageTests {

    @Test func testVTUExportAndImportRoundTripLinearMesh() throws {
        let studyId = UUID()
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0.0, 0.0, 0.0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(10.0, 0.0, 0.0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0.0, 10.0, 0.0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0.0, 0.0, 10.0))
        ]
        let elements = [
            VolumeMeshElement(id: 101, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 0)
        ]
        let mesh = VolumeMesh(nodes: nodes, elements: elements)

        let fields = SimulationResultFields(
            studyId: studyId,
            nodalDisplacements: [
                1: SIMD3<Double>(0.0, 0.0, 0.0),
                2: SIMD3<Double>(0.05, 0.01, -0.02),
                3: SIMD3<Double>(0.02, 0.04, 0.0),
                4: SIMD3<Double>(-0.01, 0.03, 0.08)
            ],
            nodalVonMisesStresses: [
                1: 15.2,
                2: 24.5,
                3: 18.0,
                4: 31.8
            ],
            nodalTemperatures: [
                1: 20.0,
                2: 85.0,
                3: 45.0,
                4: 100.0
            ],
            nodalCauchyTensors: [
                1: CauchyStressTensor(sxx: 10.0, syy: 5.0, szz: 2.0, sxy: 1.0, syz: 0.5, szx: 0.2),
                2: CauchyStressTensor(sxx: 20.0, syy: 8.0, szz: -3.0, sxy: 2.5, syz: 1.0, szx: -0.5),
                3: CauchyStressTensor(sxx: 12.0, syy: 14.0, szz: 1.0, sxy: 0.0, syz: 0.2, szx: 0.4),
                4: CauchyStressTensor(sxx: 25.0, syy: -2.0, szz: 6.0, sxy: 3.0, syz: -1.0, szx: 2.0)
            ],
            elementVonMisesStresses: [
                101: 22.4
            ],
            elementHeatFluxes: [
                101: SIMD3<Double>(120.0, -45.0, 10.0)
            ]
        )

        let vtuString = try VTUResultFormat.exportVTU(mesh: mesh, fields: fields)
        #expect(vtuString.contains("VTKFile"))
        #expect(vtuString.contains("NumberOfPoints=\"4\""))
        #expect(vtuString.contains("NumberOfCells=\"1\""))
        #expect(vtuString.contains("Displacement"))
        #expect(vtuString.contains("VonMisesStress"))
        #expect(vtuString.contains("ElementHeatFlux") || vtuString.contains("HeatFlux"))

        let (importedMeshOpt, importedFields) = try VTUResultFormat.importVTU(xmlString: vtuString)
        let importedMesh = try #require(importedMeshOpt)

        #expect(importedMesh.nodes.count == 4)
        #expect(importedMesh.elements.count == 1)
        #expect(importedMesh.elements[0].order == .linear)
        #expect(importedMesh.elements[0].nodeIndices == [1, 2, 3, 4])

        #expect(importedFields.studyId == studyId)
        let d2 = try #require(importedFields.nodalDisplacements?[2])
        #expect(abs(d2.x - 0.05) < 1e-4)
        #expect(abs(d2.y - 0.01) < 1e-4)
        #expect(abs(d2.z - -0.02) < 1e-4)

        let s4 = try #require(importedFields.nodalVonMisesStresses?[4])
        #expect(abs(s4 - 31.8) < 1e-4)

        let t3 = try #require(importedFields.nodalTemperatures?[3])
        #expect(abs(t3 - 45.0) < 1e-4)

        let c1 = try #require(importedFields.nodalCauchyTensors?[1])
        #expect(abs(c1.sxx - 10.0) < 1e-4)
        #expect(abs(c1.sxy - 1.0) < 1e-4)

        let es101 = try #require(importedFields.elementVonMisesStresses?[101])
        #expect(abs(es101 - 22.4) < 1e-4)

        let q101 = try #require(importedFields.elementHeatFluxes?[101])
        #expect(abs(q101.x - 120.0) < 1e-4)
    }

    @Test func testVTUExportAndImportRoundTripQuadraticMesh() throws {
        let nodes = (1...10).map { VolumeMeshNode(id: $0, position: SIMD3<Double>(Double($0), 0.0, 0.0)) }
        let element = VolumeMeshElement(
            id: 501,
            order: .quadratic,
            nodeIndices: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
            tag: 0
        )
        let mesh = VolumeMesh(nodes: nodes, elements: [element])

        let fields = SimulationResultFields(
            studyId: UUID(),
            nodalVonMisesStresses: [1: 100.0, 10: 250.0]
        )

        let vtuString = try VTUResultFormat.exportVTU(mesh: mesh, fields: fields)
        #expect(vtuString.contains("types"))
        // Quadratic tetrahedron VTK type 24
        #expect(vtuString.contains("24"))

        let (importedMeshOpt, importedFields) = try VTUResultFormat.importVTU(xmlString: vtuString)
        let importedMesh = try #require(importedMeshOpt)

        #expect(importedMesh.elements.count == 1)
        #expect(importedMesh.elements[0].order == .quadratic)
        #expect(importedMesh.elements[0].nodeIndices == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        #expect(importedFields.nodalVonMisesStresses?[10] == 250.0)
    }

    @Test func testVTUEmptyMeshEdgeCase() throws {
        let emptyMesh = VolumeMesh()
        let fields = SimulationResultFields(studyId: UUID())

        let vtuString = try VTUResultFormat.exportVTU(mesh: emptyMesh, fields: fields)
        #expect(vtuString.contains("NumberOfPoints=\"0\""))
        #expect(vtuString.contains("NumberOfCells=\"0\""))

        let (importedMesh, importedFields) = try VTUResultFormat.importVTU(xmlString: vtuString)
        #expect(importedMesh?.nodes.isEmpty ?? true)
        #expect(importedMesh?.elements.isEmpty ?? true)
        #expect(importedFields.isEmpty)
    }

    @Test func testVTUCorruptedXMLThrowsError() {
        #expect(throws: CAEErrorCode.self) {
            _ = try VTUResultFormat.importVTU(data: Data())
        }

        #expect(throws: CAEErrorCode.self) {
            _ = try VTUResultFormat.importVTU(xmlString: "<NotVTU><Piece/></NotVTU>")
        }

        #expect(throws: CAEErrorCode.self) {
            _ = try VTUResultFormat.importVTU(xmlString: "This is completely random text, not XML.")
        }
    }

    @Test func testCompactBinaryRoundTrip() throws {
        let studyId = UUID()
        let fields = SimulationResultFields(
            studyId: studyId,
            nodalDisplacements: [
                1: SIMD3<Double>(1.0, 2.0, 3.0),
                2: SIMD3<Double>(4.0, 5.0, 6.0)
            ],
            nodalVonMisesStresses: [
                1: 150.0,
                2: 300.0
            ],
            nodalTemperatures: [
                1: 25.5,
                2: 70.2
            ],
            nodalCauchyTensors: [
                1: CauchyStressTensor(sxx: 1, syy: 2, szz: 3, sxy: 4, syz: 5, szx: 6),
                2: CauchyStressTensor(sxx: 7, syy: 8, szz: 9, sxy: 10, syz: 11, szx: 12)
            ],
            elementVonMisesStresses: [
                100: 220.0
            ],
            elementHeatFluxes: [
                100: SIMD3<Double>(10.0, 20.0, 30.0)
            ],
            bucklingModes: [
                SimulationBucklingMode(modeNumber: 1, loadFactor: 3.45, nodalDisplacements: [
                    1: SIMD3<Double>(0.1, 0.2, 0.3),
                    2: SIMD3<Double>(0.4, 0.5, 0.6)
                ])
            ],
            modeShapes: [
                SimulationModeShape(modeNumber: 1, frequencyHz: 440.0, nodalDisplacements: [
                    1: SIMD3<Double>(0.01, 0.02, 0.03),
                    2: SIMD3<Double>(0.04, 0.05, 0.06)
                ])
            ]
        )

        let binaryData = CompactBinaryResultFormat.serialize(fields: fields, nodeIds: [1, 2], elementIds: [100])
        #expect(binaryData.count >= 52)

        let restored = try CompactBinaryResultFormat.deserialize(data: binaryData)
        #expect(restored.studyId == studyId)
        #expect(restored.nodalDisplacements?[1] == SIMD3<Double>(1.0, 2.0, 3.0))
        #expect(restored.nodalVonMisesStresses?[2] == 300.0)
        #expect(restored.nodalTemperatures?[1] == 25.5)
        #expect(restored.nodalCauchyTensors?[1]?.sxy == 4.0)
        #expect(restored.elementVonMisesStresses?[100] == 220.0)
        #expect(restored.elementHeatFluxes?[100] == SIMD3<Double>(10.0, 20.0, 30.0))
        #expect(restored.bucklingModes?.count == 1)
        #expect(restored.bucklingModes?[0].loadFactor == 3.45)
        #expect(restored.modeShapes?.count == 1)
        #expect(restored.modeShapes?[0].frequencyHz == 440.0)
    }

    @Test func testCompactBinaryHeaderValidationAndCorruption() throws {
        // 1. Truncated data (< 52 bytes)
        let shortData = Data([0x4D, 0x44, 0x45, 0x53])
        #expect(throws: CAEErrorCode.self) {
            _ = try CompactBinaryResultFormat.deserialize(data: shortData)
        }

        // 2. Invalid magic header
        let badMagic = Data(repeating: 0, count: 64)
        #expect(throws: CAEErrorCode.self) {
            _ = try CompactBinaryResultFormat.deserialize(data: badMagic)
        }

        // 3. Truncated payload
        let validFields = SimulationResultFields(
            studyId: UUID(),
            nodalDisplacements: [1: SIMD3<Double>(1, 2, 3)]
        )
        let fullData = CompactBinaryResultFormat.serialize(fields: validFields, nodeIds: [1], elementIds: [])
        let truncatedData = fullData.prefix(fullData.count - 10)
        #expect(throws: CAEErrorCode.self) {
            _ = try CompactBinaryResultFormat.deserialize(data: Data(truncatedData))
        }
    }

    @Test func testPackageStorageSaveAndLoadFields() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestPackageStorage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let studyId = UUID()
        let nodes = [
            VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0)),
            VolumeMeshNode(id: 2, position: SIMD3<Double>(1, 0, 0)),
            VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 1, 0)),
            VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 1))
        ]
        let elements = [
            VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 0)
        ]
        let mesh = VolumeMesh(nodes: nodes, elements: elements)

        let fields = SimulationResultFields(
            studyId: studyId,
            nodalDisplacements: [1: .zero, 2: SIMD3<Double>(0.1, 0, 0)],
            nodalVonMisesStresses: [1: 50.0, 2: 75.0],
            elementVonMisesStresses: [1: 60.0]
        )

        let descriptor = try SimulationResultFieldStorage.saveResultFields(fields: fields, mesh: mesh, toPackageURL: tempDir)
        #expect(descriptor.storagePath == "cache/results/\(studyId.uuidString)/results.vtu")
        #expect(descriptor.format == .vtu)
        #expect(descriptor.byteSize > 0)
        #expect(descriptor.isResident == true)

        let vtuFile = tempDir.appendingPathComponent(descriptor.storagePath)
        let binFile = tempDir.appendingPathComponent("cache/results/\(studyId.uuidString)/fields.bin")
        #expect(FileManager.default.fileExists(atPath: vtuFile.path))
        #expect(FileManager.default.fileExists(atPath: binFile.path))

        var results = SimulationStudyResults(
            status: .completed,
            fieldStorage: descriptor
        )
        #expect(!results.isFieldsLoaded)

        // Load fields from disk
        try results.loadFields(from: tempDir)
        #expect(results.isFieldsLoaded)
        #expect(results.nodalDisplacements?[2] == SIMD3<Double>(0.1, 0, 0))
        #expect(results.nodalVonMisesStresses?[2] == 75.0)
        #expect(results.elementVonMisesStresses?[1] == 60.0)

        // Unload fields
        results.unloadFields()
        #expect(!results.isFieldsLoaded)
        #expect(results.nodalDisplacements == nil)
        #expect(results.nodalVonMisesStresses == nil)
        #expect(results.elementVonMisesStresses == nil)
        #expect(results.fieldStorage?.isResident == false)

        // Idempotent unload
        results.unloadFields()
        #expect(!results.isFieldsLoaded)
    }

    @Test func testLoadFieldsMissingFileThrowsCleanError() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestMissingPackage-\(UUID().uuidString)")
        var results = SimulationStudyResults(
            status: .completed,
            fieldStorage: ResultFieldStorageDescriptor(
                storagePath: "cache/results/nonexistent/results.vtu",
                format: .vtu
            )
        )

        #expect(throws: CAEErrorCode.self) {
            try results.loadFields(from: tempDir)
        }
    }

    @Test func testResultFieldMetadataGeneration() throws {
        let fields = SimulationResultFields(
            studyId: UUID(),
            nodalDisplacements: [1: SIMD3<Double>(3.0, 4.0, 0.0)], // magnitude = 5.0
            nodalVonMisesStresses: [1: 100.0, 2: 250.0],
            nodalTemperatures: [1: 20.0, 2: 80.0],
            nodalCauchyTensors: [1: CauchyStressTensor(sxx: 100.0)],
            elementVonMisesStresses: [10: 150.0],
            elementHeatFluxes: [10: SIMD3<Double>(0.0, 30.0, 40.0)], // magnitude = 50.0
            bucklingModes: [SimulationBucklingMode(modeNumber: 1, loadFactor: 2.5, nodalDisplacements: [:])],
            modeShapes: [SimulationModeShape(modeNumber: 1, frequencyHz: 120.0, nodalDisplacements: [:])]
        )

        let metadata = fields.metadataList()
        #expect(metadata.count == 8)

        let dispMeta = try #require(metadata.first { $0.kind == ResultFieldKind.displacement })
        #expect(dispMeta.componentCount == 3)
        #expect(dispMeta.maxMagnitude == 5.0)
        #expect(dispMeta.unitSymbol == "mm")

        let stressMeta = try #require(metadata.first { $0.kind == ResultFieldKind.vonMisesStress })
        #expect(stressMeta.maxMagnitude == 250.0)
        #expect(stressMeta.minMagnitude == 100.0)
        #expect(stressMeta.unitSymbol == "MPa")

        let fluxMeta = try #require(metadata.first { $0.kind == ResultFieldKind.elementHeatFlux })
        #expect(fluxMeta.maxMagnitude == 50.0)
        #expect(fluxMeta.unitSymbol == "W/m²")
    }
}
