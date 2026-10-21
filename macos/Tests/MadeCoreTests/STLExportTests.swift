import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct STLExportTests {
    @Test func test12TriangleBoxExportByteCount() throws {
        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Box",
            def: .box(BoxParams(width: 10, depth: 10, height: 10))
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-box-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let count = try STLExporter.export(objects: [box], tolerance: 0.1, unit: .millimeters, to: tempURL)
        #expect(count == 12)

        let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let fileSize = attributes[.size] as? Int
        #expect(fileSize == 684) // 84-byte header + 12 triangles * 50 bytes = 684

        let readCount = try STLExporter.readTriangleCount(from: tempURL)
        #expect(readCount == 12)
    }

    @Test func testBoundsReReadingMatchesBoxExtents() throws {
        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Box",
            def: .box(BoxParams(width: 10, depth: 10, height: 10))
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-bounds-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try STLExporter.export(objects: [box], tolerance: 0.1, unit: .millimeters, to: tempURL)
        let bounds = try STLExporter.readBounds(from: tempURL)

        #expect(abs(bounds.min.x - (-5.0)) < 1e-4)
        #expect(abs(bounds.min.y - (-5.0)) < 1e-4)
        #expect(abs(bounds.min.z - (-5.0)) < 1e-4)
        #expect(abs(bounds.max.x - 5.0) < 1e-4)
        #expect(abs(bounds.max.y - 5.0) < 1e-4)
        #expect(abs(bounds.max.z - 5.0) < 1e-4)
        #expect(abs(bounds.size.x - 10.0) < 1e-4)
        #expect(abs(bounds.size.y - 10.0) < 1e-4)
        #expect(abs(bounds.size.z - 10.0) < 1e-4)
    }

    @Test func testUnitConversion() throws {
        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Box",
            def: .box(BoxParams(width: 10, depth: 10, height: 10))
        )

        // Inches conversion: 10 mm / 25.4 = ~0.393700787 in
        let tempInches = FileManager.default.temporaryDirectory.appendingPathComponent("test-inches-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: tempInches) }
        try STLExporter.export(objects: [box], tolerance: 0.1, unit: .inches, to: tempInches)
        let boundsInches = try STLExporter.readBounds(from: tempInches)
        let expectedInches = 10.0 / 25.4
        #expect(abs(boundsInches.size.x - expectedInches) < 1e-4)
        #expect(abs(boundsInches.size.y - expectedInches) < 1e-4)
        #expect(abs(boundsInches.size.z - expectedInches) < 1e-4)

        // Meters conversion: 10 mm / 1000 = 0.01 m
        let tempMeters = FileManager.default.temporaryDirectory.appendingPathComponent("test-meters-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: tempMeters) }
        try STLExporter.export(objects: [box], tolerance: 0.1, unit: .meters, to: tempMeters)
        let boundsMeters = try STLExporter.readBounds(from: tempMeters)
        let expectedMeters = 10.0 / 1000.0
        #expect(abs(boundsMeters.size.x - expectedMeters) < 1e-5)
        #expect(abs(boundsMeters.size.y - expectedMeters) < 1e-5)
        #expect(abs(boundsMeters.size.z - expectedMeters) < 1e-5)

        // Centimeters conversion: 10 mm / 10 = 1.0 cm
        let tempCM = FileManager.default.temporaryDirectory.appendingPathComponent("test-cm-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: tempCM) }
        try STLExporter.export(objects: [box], tolerance: 0.1, unit: .centimeters, to: tempCM)
        let boundsCM = try STLExporter.readBounds(from: tempCM)
        let expectedCM = 10.0 / 10.0
        #expect(abs(boundsCM.size.x - expectedCM) < 1e-4)
        #expect(abs(boundsCM.size.y - expectedCM) < 1e-4)
        #expect(abs(boundsCM.size.z - expectedCM) < 1e-4)
    }

    @Test func testRejectionOfNonPositiveTolerance() throws {
        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Box",
            def: .box(BoxParams(width: 10, depth: 10, height: 10))
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-tol-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        #expect(!STLExporter.validateTolerance(0.0))
        #expect(!STLExporter.validateTolerance(-1.0))
        #expect(!STLExporter.validateTolerance(.nan))
        #expect(!STLExporter.validateTolerance(.infinity))
        #expect(STLExporter.validateTolerance(0.01))

        #expect(throws: STLExporter.STLExportError.invalidTolerance(0.0)) {
            try STLExporter.export(objects: [box], tolerance: 0.0, to: tempURL)
        }
        #expect(throws: STLExporter.STLExportError.invalidTolerance(-0.5)) {
            try STLExporter.export(objects: [box], tolerance: -0.5, to: tempURL)
        }
    }

    @Test func testExclusionOfHiddenBodies() throws {
        let box1 = SceneObject(
            id: ObjectId("box-1"),
            name: "Box 1",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            isVisible: true
        )
        let box2 = SceneObject(
            id: ObjectId("box-2"),
            name: "Box 2",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            isVisible: false
        )
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-hidden-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let count = try STLExporter.export(objects: [box1, box2], tolerance: 0.1, to: tempURL)
        #expect(count == 12)
        let readCount = try STLExporter.readTriangleCount(from: tempURL)
        #expect(readCount == 12)

        #expect(throws: STLExporter.STLExportError.noVisibleObjects) {
            try STLExporter.export(objects: [box2], tolerance: 0.1, to: tempURL)
        }
    }

    @Test func testEmptyCandidateObjectsRejection() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-empty-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        #expect(throws: STLExporter.STLExportError.noVisibleObjects) {
            try STLExporter.export(objects: [], tolerance: 0.1, to: tempURL)
        }
    }

    @Test func testMemoryStreamingSafetyOnLargeTriangleCounts() throws {
        let triCount = 50_000
        var positions = [Float](repeating: 0, count: triCount * 9)
        var normals = [Float](repeating: 0, count: triCount * 9)
        var indices = [UInt32](repeating: 0, count: triCount * 3)

        for i in 0..<triCount {
            let vBase = i * 9
            let iBase = i * 3

            positions[vBase + 0] = Float(i)
            positions[vBase + 1] = 0
            positions[vBase + 2] = 0
            positions[vBase + 3] = Float(i)
            positions[vBase + 4] = 1
            positions[vBase + 5] = 0
            positions[vBase + 6] = Float(i) + 1
            positions[vBase + 7] = 0
            positions[vBase + 8] = 0

            normals[vBase + 2] = 1.0
            normals[vBase + 5] = 1.0
            normals[vBase + 8] = 1.0

            indices[iBase + 0] = UInt32(iBase + 0)
            indices[iBase + 1] = UInt32(iBase + 1)
            indices[iBase + 2] = UInt32(iBase + 2)
        }

        let mesh = MeshPayload(positions: positions, normals: normals, indices: indices)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-large-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let written = try STLExporter.export(meshes: [(mesh: mesh, transform: .identity)], to: tempURL)
        #expect(written == triCount)

        let readCount = try STLExporter.readTriangleCount(from: tempURL)
        #expect(readCount == triCount)

        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let expectedSize = 84 + triCount * 50
        #expect((attrs[.size] as? Int) == expectedSize)
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
        let destinationURL = readOnlyDir.appendingPathComponent("UnwritableExport.stl")

        let box = SceneObject(
            id: ObjectId("box-1"),
            name: "Box",
            def: .box(BoxParams(width: 10, depth: 10, height: 10))
        )

        #expect(throws: STLExporter.STLExportError.self) {
            try STLExporter.export(objects: [box], tolerance: 0.1, to: destinationURL)
        }
        #expect(!FileManager.default.fileExists(atPath: destinationURL.path))
    }
}
