import Foundation
import Testing
@testable import MadeCore

@Suite struct ExternalReferenceTests {

    @Test func testDescriptorInitialStatusUpToDate() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.step")
        try "ISO-10303-21;".write(to: fileURL, atomically: true, encoding: .utf8)

        let modDate = ExternalReferenceDescriptor.modificationDate(of: fileURL)
        #expect(modDate != nil)

        let desc = ExternalReferenceDescriptor(
            sourceURL: fileURL,
            isLinked: true,
            lastModifiedDate: modDate
        )

        #expect(desc.checkStatus() == .upToDate)
    }

    @Test func testDescriptorOutOfDateWhenFileModified() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.step")
        try "ISO-10303-21; initial".write(to: fileURL, atomically: true, encoding: .utf8)

        guard let initialDate = ExternalReferenceDescriptor.modificationDate(of: fileURL) else {
            Issue.record("Failed to read initial modification date")
            return
        }

        let desc = ExternalReferenceDescriptor(
            sourceURL: fileURL,
            isLinked: true,
            lastModifiedDate: initialDate
        )
        #expect(desc.checkStatus() == .upToDate)

        // Advance modification date on disk
        let futureDate = initialDate.addingTimeInterval(5.0)
        try FileManager.default.setAttributes([.modificationDate: futureDate], ofItemAtPath: fileURL.path)

        #expect(desc.checkStatus() == .outOfDate)
    }

    @Test func testDescriptorMissingFileWhenDeleted() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("temporary.step")
        try "STEP data".write(to: fileURL, atomically: true, encoding: .utf8)

        let desc = ExternalReferenceDescriptor(
            sourceURL: fileURL,
            isLinked: true,
            lastModifiedDate: Date()
        )
        #expect(desc.checkStatus() == .upToDate || desc.checkStatus() == .outOfDate)

        try FileManager.default.removeItem(at: fileURL)
        #expect(desc.checkStatus() == .missingFile)
    }

    @Test func testDescriptorWithoutRecordedDateIsUpToDateIfFileExists() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("part.step")
        try "STEP data".write(to: fileURL, atomically: true, encoding: .utf8)

        let desc = ExternalReferenceDescriptor(
            sourceURL: fileURL,
            isLinked: true,
            lastModifiedDate: nil
        )
        #expect(desc.checkStatus() == .upToDate)
    }

    @Test func testComputeChecksumForFileAndDirectoryPackage() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("sample.step")
        try "DATA 1".write(to: fileURL, atomically: true, encoding: .utf8)

        let hash1 = ExternalReferenceDescriptor.computeChecksum(of: fileURL)
        #expect(hash1 != nil)
        #expect(hash1?.count == 64)

        try "DATA 2".write(to: fileURL, atomically: true, encoding: .utf8)
        let hash2 = ExternalReferenceDescriptor.computeChecksum(of: fileURL)
        #expect(hash2 != hash1)

        // Test package directory containing document.json
        let pkgDir = tempDir.appendingPathComponent("Child.made")
        try FileManager.default.createDirectory(at: pkgDir, withIntermediateDirectories: true)
        let docJSON = pkgDir.appendingPathComponent("document.json")
        try "{\"version\":1}".write(to: docJSON, atomically: true, encoding: .utf8)

        let pkgHash = ExternalReferenceDescriptor.computeChecksum(of: pkgDir)
        #expect(pkgHash != nil)
        #expect(pkgHash?.count == 64)
    }

    @Test func testSupportedFormats() {
        #expect(ExternalReferenceDescriptor.isSupportedExternalReference(url: URL(fileURLWithPath: "/path/to/part.step")))
        #expect(ExternalReferenceDescriptor.isSupportedExternalReference(url: URL(fileURLWithPath: "/path/to/part.stp")))
        #expect(ExternalReferenceDescriptor.isSupportedExternalReference(url: URL(fileURLWithPath: "/path/to/part.STEP")))
        #expect(ExternalReferenceDescriptor.isSupportedExternalReference(url: URL(fileURLWithPath: "/path/to/Assembly.made")))
        #expect(!ExternalReferenceDescriptor.isSupportedExternalReference(url: URL(fileURLWithPath: "/path/to/part.txt")))
        #expect(!ExternalReferenceDescriptor.isSupportedExternalReference(url: URL(fileURLWithPath: "/path/to/part.obj")))
    }

    @Test func testImportedFeatureDataLinkedSerializationRoundtrip() throws {
        let externalPath = "/Users/engineer/CAD/bracket.step"
        let externalURL = URL(fileURLWithPath: externalPath)
        let now = Date(timeIntervalSince1970: 1700000000)

        let featureData = ImportedFeatureData(
            name: "bracket.step",
            sourceURL: externalURL,
            data: nil,
            isLinked: true,
            lastModifiedDate: now,
            fileChecksum: "deadbeef"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(featureData)

        let jsonString = String(data: data, encoding: .utf8)!
        let normalizedJSON = jsonString.replacingOccurrences(of: "\\/", with: "/")
        #expect(normalizedJSON.contains("\"isLinked\":true"))
        #expect(normalizedJSON.contains(externalPath))
        #expect(!normalizedJSON.contains("assets/"))

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ImportedFeatureData.self, from: data)

        #expect(decoded.name == "bracket.step")
        #expect(decoded.isLinked == true)
        #expect(decoded.sourceURL?.path == externalPath)
        #expect(decoded.fileChecksum == "deadbeef")
        #expect(decoded.lastModifiedDate != nil)
    }

    @Test func testImportedFeatureDataEmbeddedSerializationEncodesAssetsPath() throws {
        let externalURL = URL(fileURLWithPath: "/Users/engineer/CAD/bracket.step")
        let featureData = ImportedFeatureData(
            name: "bracket.step",
            sourceURL: externalURL,
            data: Data([1, 2, 3]),
            isLinked: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(featureData)
        let jsonString = String(data: data, encoding: .utf8)!
        let normalizedJSON = jsonString.replacingOccurrences(of: "\\/", with: "/")

        #expect(normalizedJSON.contains("assets/bracket.step"))
        #expect(!normalizedJSON.contains("\"isLinked\":true"))
    }

    @Test @MainActor func testDocumentModelRebasePathsExemptsLinkedReferences() {
        let doc = DocumentModel()
        let linkedURL = URL(fileURLWithPath: "/External/Libraries/motor.step")
        let embeddedURL = URL(fileURLWithPath: "assets/bracket.step")

        let linkedId = doc.addObject(def: .imported(
            name: "motor.step",
            sourceURL: linkedURL,
            data: nil,
            isLinked: true,
            lastModifiedDate: Date(),
            fileChecksum: "1234"
        ))

        let embeddedId = doc.addObject(def: .imported(
            name: "bracket.step",
            sourceURL: embeddedURL,
            data: Data([1, 2]),
            isLinked: false
        ))

        let packageURL = URL(fileURLWithPath: "/Projects/MyCar.made")
        doc.rebasePaths(to: packageURL)

        guard let linkedObj = doc.objects.first(where: { $0.id == linkedId }),
              let embeddedObj = doc.objects.first(where: { $0.id == embeddedId }) else {
            Issue.record("Missing objects")
            return
        }

        #expect(linkedObj.def.linkedSourceURL == linkedURL)
        #expect(linkedObj.def.isLinked == true)

        if case .imported(_, let embURL, _, let embLinked, _, _) = embeddedObj.def {
            #expect(embLinked == false)
            #expect(embURL == packageURL.appendingPathComponent("assets/bracket.step"))
        } else {
            Issue.record("Expected embedded object def")
        }
    }
}
