import Testing
import Foundation
@testable import MadeCore

@Suite struct CrashRecoveryTests {
    private func createTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func testMetadataCodableRoundtrip() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        let originalURL = URL(fileURLWithPath: "/Users/test/Documents/model.made")

        let metadataWithURL = CrashRecoveryMetadata(
            version: 1,
            savedAt: date,
            originalDocumentURL: originalURL,
            documentTitle: "My Model"
        )

        let encoder = DocumentModelCoder.makeJSONEncoder()
        let encodedData = try encoder.encode(metadataWithURL)
        let decoder = DocumentModelCoder.makeJSONDecoder()
        let decodedWithURL = try decoder.decode(CrashRecoveryMetadata.self, from: encodedData)

        #expect(decodedWithURL == metadataWithURL)
        #expect(decodedWithURL.originalDocumentURL == originalURL)
        #expect(decodedWithURL.documentTitle == "My Model")
        #expect(decodedWithURL.version == 1)

        let metadataUntitled = CrashRecoveryMetadata(
            version: 1,
            savedAt: date,
            originalDocumentURL: nil,
            documentTitle: "Untitled Project"
        )
        let encodedUntitled = try encoder.encode(metadataUntitled)
        let decodedUntitled = try decoder.decode(CrashRecoveryMetadata.self, from: encodedUntitled)

        #expect(decodedUntitled == metadataUntitled)
        #expect(decodedUntitled.originalDocumentURL == nil)
        #expect(decodedUntitled.documentTitle == "Untitled Project")
    }

    @Test func testStoreSaveSnapshotAndLoadPendingRecovery() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = CrashRecoveryStore(recoveryDirectoryURL: tempDir)
        #expect(store.loadPendingRecovery() == nil)

        let docData = DocumentData(
            schemaVersion: 1,
            objects: [
                SceneObject(
                    id: boxSolidId,
                    def: .box(BoxParams(width: 50, depth: 40, height: 30))
                )
            ],
            selectedId: boxSolidId,
            rollbackIndex: nil
        )
        let package = MadePackage(documentData: docData)
        let metadata = CrashRecoveryMetadata(
            version: 1,
            savedAt: Date(),
            originalDocumentURL: nil,
            documentTitle: "Untitled Project"
        )

        try store.saveSnapshot(package: package, metadata: metadata)

        #expect(FileManager.default.fileExists(atPath: store.packageURL.path))
        #expect(FileManager.default.fileExists(atPath: store.metadataURL.path))

        let pending = store.loadPendingRecovery()
        #expect(pending != nil)
        #expect(pending?.metadata.documentTitle == "Untitled Project")
        #expect(pending?.metadata.originalDocumentURL == nil)
        #expect(pending?.packageURL == store.packageURL)
        #expect(pending?.metadataURL == store.metadataURL)

        // Read package to verify payload
        let loadedPackage = try MadePackage(directoryURL: pending!.packageURL)
        #expect(loadedPackage.documentData.objects.count == 1)
        #expect(loadedPackage.documentData.objects.first?.id == boxSolidId)
    }

    @Test func testClearRecoveryDeletesArtifacts() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = CrashRecoveryStore(recoveryDirectoryURL: tempDir)
        let docData = DocumentData(schemaVersion: 1, objects: [], selectedId: nil, rollbackIndex: nil)
        let package = MadePackage(documentData: docData)
        let metadata = CrashRecoveryMetadata(documentTitle: "Test")

        try store.saveSnapshot(package: package, metadata: metadata)
        #expect(store.loadPendingRecovery() != nil)

        try store.clearRecovery()
        #expect(!FileManager.default.fileExists(atPath: store.packageURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.metadataURL.path))
        #expect(store.loadPendingRecovery() == nil)
    }

    @Test func testDiscardRecordDeletesArtifacts() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = CrashRecoveryStore(recoveryDirectoryURL: tempDir)
        let docData = DocumentData(schemaVersion: 1, objects: [], selectedId: nil, rollbackIndex: nil)
        let package = MadePackage(documentData: docData)
        let metadata = CrashRecoveryMetadata(documentTitle: "Test")

        try store.saveSnapshot(package: package, metadata: metadata)
        guard let record = store.loadPendingRecovery() else {
            Issue.record("Expected pending recovery record")
            return
        }

        try store.discardRecord(record)
        #expect(!FileManager.default.fileExists(atPath: record.packageURL.path))
        #expect(!FileManager.default.fileExists(atPath: record.metadataURL.path))
        #expect(store.loadPendingRecovery() == nil)
    }

    @Test func testCorruptRecoveryHandling() throws {
        let tempDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = CrashRecoveryStore(recoveryDirectoryURL: tempDir)

        // 1. Missing package but metadata present
        try "{}".write(to: store.metadataURL, atomically: true, encoding: .utf8)
        #expect(store.loadPendingRecovery() == nil)

        // 2. Corrupt metadata JSON
        try FileManager.default.createDirectory(at: store.packageURL, withIntermediateDirectories: true)
        try "not valid json".write(to: store.metadataURL, atomically: true, encoding: .utf8)
        #expect(store.loadPendingRecovery() == nil)

        // 3. Valid metadata but corrupt package directory (empty directory missing manifest.json/document.json)
        let validMetadata = CrashRecoveryMetadata(documentTitle: "Corrupt Test")
        let metaBytes = try DocumentModelCoder.makeJSONEncoder().encode(validMetadata)
        try metaBytes.write(to: store.metadataURL)
        #expect(store.loadPendingRecovery() == nil)

        // 4. Unsupported future metadata version
        let futureMetadata = """
        {
          "version": 999,
          "savedAt": 1000.0,
          "documentTitle": "Future Model"
        }
        """.data(using: .utf8)!
        try futureMetadata.write(to: store.metadataURL)
        #expect(store.loadPendingRecovery() == nil)
    }
}
