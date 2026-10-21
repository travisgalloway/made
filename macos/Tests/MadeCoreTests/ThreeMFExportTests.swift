import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct ThreeMFExportTests {
    @Test func testCRC32ChecksumStandardVector() {
        // Standard check vector for IEEE 802.3 CRC-32 on ASCII "123456789" is 0xCBF43926
        let asciiString = "123456789"
        let data = Data(asciiString.utf8)
        let checksum = CRC32.checksum(data)
        #expect(checksum == 0xCBF43926)

        // Empty data has CRC-32 of 0x00000000
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test func testZipArchiveRoundTrip() throws {
        let entry1 = ZipEntry(path: "hello.txt", data: Data("Hello, 3MF!".utf8))
        let entry2 = ZipEntry(path: "nested/folder/data.bin", data: Data([0xDE, 0xAD, 0xBE, 0xEF]))

        let archiveData = ZipArchive.create(entries: [entry1, entry2])
        let unpacked = try ZipArchive.read(from: archiveData)

        #expect(unpacked.count == 2)
        #expect(unpacked[0].path == "hello.txt")
        #expect(String(data: unpacked[0].data, encoding: .utf8) == "Hello, 3MF!")
        #expect(unpacked[1].path == "nested/folder/data.bin")
        #expect(unpacked[1].data == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test func testSingleBoxExportStructureAndXML() throws {
        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Test Cube",
            def: .box(BoxParams(width: 10, depth: 20, height: 30)),
            material: MaterialAttributes(color: SIMD4<Float>(1.0, 0.0, 0.5, 1.0))
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-cube-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try ThreeMFExporter.export(objects: [box], tolerance: 0.1, unit: .millimeters, to: tempURL)
        #expect(result.objectCount == 1)
        #expect(result.triangleCount == 12)
        #expect(result.openEdgeCount == 0)
        #expect(result.warnings.isEmpty)

        // Verify ZIP archive contents
        let entries = try ZipArchive.read(from: tempURL)
        let filePaths = Set(entries.map { $0.path })
        #expect(filePaths.contains("[Content_Types].xml"))
        #expect(filePaths.contains("_rels/.rels"))
        #expect(filePaths.contains("3D/3dmodel.model"))

        // Inspect 3D/3dmodel.model XML
        guard let modelXML = ZipArchive.string(named: "3D/3dmodel.model", in: entries) else {
            Issue.record("Missing 3D/3dmodel.model")
            return
        }

        #expect(modelXML.contains("<model unit=\"millimeter\""))
        #expect(modelXML.contains("<basematerials id=\"1\">"))
        #expect(modelXML.contains("displaycolor=\"#FF0080FF\""))
        #expect(modelXML.contains("<object id=\"2\" type=\"model\" name=\"Test Cube\" pid=\"1\" pindex=\"0\">"))
        #expect(modelXML.contains("<vertices>"))
        #expect(modelXML.contains("<triangles>"))
        #expect(modelXML.contains("<build>"))
        #expect(modelXML.contains("<item objectid=\"2\" />"))
    }

    @Test func testMultipleObjectsWithColorMappingAndBuildItems() throws {
        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Body A",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            material: MaterialAttributes(color: SIMD4<Float>(1.0, 0.0, 0.0, 1.0)) // Red
        )
        let cylinder = SceneObject(
            id: ObjectId("cyl-1"),
            name: "Body B",
            def: .cylinder(CylinderParams(radius: 5, height: 15)),
            material: MaterialAttributes(color: SIMD4<Float>(0.0, 0.0, 1.0, 1.0)) // Blue
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-multi-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try ThreeMFExporter.export(objects: [box, cylinder], tolerance: 0.1, unit: .millimeters, to: tempURL)
        #expect(result.objectCount == 2)
        #expect(result.openEdgeCount == 0)

        let entries = try ZipArchive.read(from: tempURL)
        guard let modelXML = ZipArchive.string(named: "3D/3dmodel.model", in: entries) else {
            Issue.record("Missing 3D/3dmodel.model")
            return
        }

        #expect(modelXML.contains("displaycolor=\"#FF0000FF\""))
        #expect(modelXML.contains("displaycolor=\"#0000FFFF\""))
        #expect(modelXML.contains("<object id=\"2\" type=\"model\" name=\"Body A\" pid=\"1\" pindex=\"0\">"))
        #expect(modelXML.contains("<object id=\"3\" type=\"model\" name=\"Body B\" pid=\"1\" pindex=\"1\">"))
        #expect(modelXML.contains("<item objectid=\"2\" />"))
        #expect(modelXML.contains("<item objectid=\"3\" />"))
    }

    @Test func testIdenticalBodyNamesReceiveUniqueIntegerObjectIds() throws {
        // Edge case 2: Two bodies with the exact same name must receive distinct integer IDs in <resources> and <build>
        let box1 = SceneObject(
            id: ObjectId("box-1"),
            name: "Duplicate Name",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            material: MaterialAttributes(color: SIMD4<Float>(1.0, 1.0, 0.0, 1.0))
        )
        let box2 = SceneObject(
            id: ObjectId("box-2"),
            name: "Duplicate Name",
            def: .box(BoxParams(width: 5, depth: 5, height: 5)),
            material: MaterialAttributes(color: SIMD4<Float>(0.0, 1.0, 1.0, 1.0))
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-dup-names-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try ThreeMFExporter.export(objects: [box1, box2], tolerance: 0.1, unit: .millimeters, to: tempURL)
        #expect(result.objectCount == 2)

        let entries = try ZipArchive.read(from: tempURL)
        guard let modelXML = ZipArchive.string(named: "3D/3dmodel.model", in: entries) else {
            Issue.record("Missing 3D/3dmodel.model")
            return
        }

        #expect(modelXML.contains("<object id=\"2\" type=\"model\" name=\"Duplicate Name\" pid=\"1\" pindex=\"0\">"))
        #expect(modelXML.contains("<object id=\"3\" type=\"model\" name=\"Duplicate Name\" pid=\"1\" pindex=\"1\">"))
        #expect(modelXML.contains("<item objectid=\"2\" />"))
        #expect(modelXML.contains("<item objectid=\"3\" />"))
    }

    @Test func testNonASCIIAndXMLReservedCharactersEscaped() throws {
        // Edge case 3: XML reserved characters and Unicode in body names
        let specialName = #"Special & <Body> "Quote" 'Apos' 日本語 🚀"#
        let box = SceneObject(
            id: ObjectId("box-special"),
            name: specialName,
            def: .box(BoxParams(width: 10, depth: 10, height: 10))
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-special-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try ThreeMFExporter.export(objects: [box], tolerance: 0.1, to: tempURL)

        let entries = try ZipArchive.read(from: tempURL)
        guard let modelXML = ZipArchive.string(named: "3D/3dmodel.model", in: entries) else {
            Issue.record("Missing 3D/3dmodel.model")
            return
        }

        let escapedExpected = #"Special &amp; &lt;Body&gt; &quot;Quote&quot; &apos;Apos&apos; 日本語 🚀"#
        #expect(modelXML.contains("name=\"\(escapedExpected)\""))
        #expect(!modelXML.contains("Special & <Body>"))
    }

    @Test func testUnitConversionAndCoordinateScaling() throws {
        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Box",
            def: .box(BoxParams(width: 10, depth: 10, height: 10))
        )

        // Centimeters: 10 mm = 1.0 cm
        let tempCM = FileManager.default.temporaryDirectory.appendingPathComponent("test-cm-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempCM) }
        try ThreeMFExporter.export(objects: [box], tolerance: 0.1, unit: .centimeters, to: tempCM)
        let entriesCM = try ZipArchive.read(from: tempCM)
        guard let xmlCM = ZipArchive.string(named: "3D/3dmodel.model", in: entriesCM) else {
            Issue.record("Missing model XML")
            return
        }
        #expect(xmlCM.contains("<model unit=\"centimeter\""))
        // Extents: min -0.5, max 0.5 in cm
        #expect(xmlCM.contains("x=\"0.5\"") || xmlCM.contains("x=\"-0.5\""))

        // Inches: 10 mm / 25.4 = ~0.3937 in
        let tempIN = FileManager.default.temporaryDirectory.appendingPathComponent("test-in-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempIN) }
        try ThreeMFExporter.export(objects: [box], tolerance: 0.1, unit: .inches, to: tempIN)
        let entriesIN = try ZipArchive.read(from: tempIN)
        guard let xmlIN = ZipArchive.string(named: "3D/3dmodel.model", in: entriesIN) else {
            Issue.record("Missing model XML")
            return
        }
        #expect(xmlIN.contains("<model unit=\"inch\""))

        // Meters: 10 mm / 1000 = 0.01 m
        let tempM = FileManager.default.temporaryDirectory.appendingPathComponent("test-m-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempM) }
        try ThreeMFExporter.export(objects: [box], tolerance: 0.1, unit: .meters, to: tempM)
        let entriesM = try ZipArchive.read(from: tempM)
        guard let xmlM = ZipArchive.string(named: "3D/3dmodel.model", in: entriesM) else {
            Issue.record("Missing model XML")
            return
        }
        #expect(xmlM.contains("<model unit=\"meter\""))
    }

    @Test func testExclusionOfHiddenBodies() throws {
        let visibleBox = SceneObject(
            id: ObjectId("box-vis"),
            name: "Visible Box",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            isVisible: true
        )
        let hiddenBox = SceneObject(
            id: ObjectId("box-hid"),
            name: "Hidden Box",
            def: .box(BoxParams(width: 20, depth: 20, height: 20)),
            isVisible: false
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-hidden-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try ThreeMFExporter.export(objects: [visibleBox, hiddenBox], tolerance: 0.1, to: tempURL)
        #expect(result.objectCount == 1)
        #expect(result.triangleCount == 12)

        let entries = try ZipArchive.read(from: tempURL)
        guard let modelXML = ZipArchive.string(named: "3D/3dmodel.model", in: entries) else {
            Issue.record("Missing model XML")
            return
        }
        #expect(modelXML.contains("name=\"Visible Box\""))
        #expect(!modelXML.contains("Hidden Box"))
        #expect(!modelXML.contains("<item objectid=\"3\" />"))
    }

    @Test func testEmptyCandidateObjectsRejection() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-empty-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        #expect(throws: ThreeMFExportError.noVisibleObjects) {
            try ThreeMFExporter.export(objects: [], tolerance: 0.1, to: tempURL)
        }

        let hiddenOnly = SceneObject(
            id: ObjectId("hid"),
            name: "Hidden",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            isVisible: false
        )
        #expect(throws: ThreeMFExportError.noVisibleObjects) {
            try ThreeMFExporter.export(objects: [hiddenOnly], tolerance: 0.1, to: tempURL)
        }
    }

    @Test func testRejectionOfNonPositiveTolerance() throws {
        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Box",
            def: .box(BoxParams(width: 10, depth: 10, height: 10))
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-tol-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        #expect(!ThreeMFExporter.validateTolerance(0.0))
        #expect(!ThreeMFExporter.validateTolerance(-1.0))
        #expect(!ThreeMFExporter.validateTolerance(.nan))
        #expect(!ThreeMFExporter.validateTolerance(.infinity))
        #expect(ThreeMFExporter.validateTolerance(0.01))

        #expect(throws: ThreeMFExportError.invalidTolerance(0.0)) {
            try ThreeMFExporter.export(objects: [box], tolerance: 0.0, to: tempURL)
        }
        #expect(throws: ThreeMFExportError.invalidTolerance(-0.5)) {
            try ThreeMFExporter.export(objects: [box], tolerance: -0.5, to: tempURL)
        }
    }

    @Test func testOpenEdgeMeshExportsWithWarnings() throws {
        // Edge case 4: Open boundary edge mesh (e.g. a flat square composed of 2 triangles sharing 1 edge -> 4 boundary open edges)
        let positions: [Float] = [
            0, 0, 0,  // 0
            10, 0, 0, // 1
            10, 10, 0,// 2
            0, 10, 0  // 3
        ]
        let normals: [Float] = [
            0, 0, 1,
            0, 0, 1,
            0, 0, 1,
            0, 0, 1
        ]
        let indices: [UInt32] = [
            0, 1, 2,
            0, 2, 3
        ]
        let openMesh = MeshPayload(positions: positions, normals: normals, indices: indices)

        let openBody = ThreeMFBody(name: "OpenSheet", mesh: openMesh)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-openedge-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try ThreeMFExporter.export(bodies: [openBody], unit: .millimeters, to: tempURL)
        #expect(result.objectCount == 1)
        #expect(result.triangleCount == 2)
        #expect(result.openEdgeCount > 0)
        #expect(!result.warnings.isEmpty)
        #expect(result.warnings.first?.contains("OpenSheet") == true)
        #expect(result.warnings.first?.contains("open boundary edges") == true)

        // Archive was still written successfully
        let entries = try ZipArchive.read(from: tempURL)
        #expect(entries.count == 3)
    }

    @Test func testUnwritableDestinationLeavesNoPartialFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let readOnlyDir = tempDir.appendingPathComponent("ReadOnlyDir")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)
        let destinationURL = readOnlyDir.appendingPathComponent("UnwritableExport.3mf")

        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Box",
            def: .box(BoxParams(width: 10, depth: 10, height: 10))
        )

        #expect(throws: ThreeMFExportError.self) {
            try ThreeMFExporter.export(objects: [box], tolerance: 0.1, to: destinationURL)
        }
        #expect(!FileManager.default.fileExists(atPath: destinationURL.path))
    }
}
