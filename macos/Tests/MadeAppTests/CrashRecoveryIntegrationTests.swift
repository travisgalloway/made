import Testing
import Foundation
import SwiftUI
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct CrashRecoveryIntegrationTests {
    private func createTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func testUntitledDocumentAutosaveWritesRecoverySnapshot() async throws {
        let tempRecoveryDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRecoveryDir) }

        let workspace = WorkspaceModel(recoveryDirectoryURL: tempRecoveryDir)
        #expect(workspace.currentDocumentURL == nil)
        #expect(!workspace.isDocumentModified)

        // Set short debounce for test (50ms)
        workspace.autosaveDebounceNanoseconds = 50_000_000

        // Perform edit to untitled workspace
        workspace.addDefaultCylinder()
        #expect(workspace.isDocumentModified)

        // Wait for debounce interval + buffer
        try await Task.sleep(nanoseconds: 120_000_000)

        // Modified state remains true for untitled document
        #expect(workspace.isDocumentModified)

        // Recovery snapshot was written to disk
        let pending = workspace.recoveryStore.loadPendingRecovery()
        #expect(pending != nil)
        #expect(pending?.metadata.originalDocumentURL == nil)
        #expect(pending?.metadata.documentTitle.contains("Untitled Project") == true)

        let package = try MadePackage(directoryURL: pending!.packageURL)
        #expect(package.documentData.objects.contains(where: { $0.id.rawValue.starts(with: "cylinder-") }))
    }

    @Test func testTitledDocumentAutosaveWritesInPlaceAndClearsRecovery() async throws {
        let tempRecoveryDir = try createTempDirectory()
        let tempWorkDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempRecoveryDir)
            try? FileManager.default.removeItem(at: tempWorkDir)
        }

        let packageURL = tempWorkDir.appendingPathComponent("TitledDoc.made")
        let workspace = WorkspaceModel(recoveryDirectoryURL: tempRecoveryDir)
        workspace.saveDocument(to: packageURL)
        #expect(!workspace.isDocumentModified)
        #expect(workspace.currentDocumentURL == packageURL)

        // Seed a recovery snapshot into recovery dir
        workspace.saveRecoverySnapshot()
        #expect(workspace.recoveryStore.loadPendingRecovery() != nil)

        // Set short debounce
        workspace.autosaveDebounceNanoseconds = 50_000_000

        // Perform edit
        workspace.addDefaultCylinder()
        #expect(workspace.isDocumentModified)

        // Wait for debounce
        try await Task.sleep(nanoseconds: 120_000_000)

        // Titled document autosaves in-place and clears modified state and recovery snapshot
        #expect(!workspace.isDocumentModified)
        #expect(workspace.recoveryStore.loadPendingRecovery() == nil)

        let readPackage = try MadePackage(directoryURL: packageURL)
        #expect(readPackage.documentData.objects.contains(where: { $0.id.rawValue.starts(with: "cylinder-") }))
    }

    @Test func testStartupDetectionAndRecoveryRestoration() throws {
        let tempRecoveryDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRecoveryDir) }

        let customSolidId = ObjectId("custom-box-1")
        let customSettings = DocumentSettings(
            units: UnitSettings(lengthUnit: .inches, angleUnit: .radians, decimalPrecision: 4),
            tolerances: KernelTolerances(linearTolerance: 0.05, angularTolerance: 0.02, chordalTolerance: 0.03)
        )
        let manifest = MadeManifest(documentSettings: customSettings)
        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            objects: [
                SceneObject(
                    id: customSolidId,
                    def: .box(BoxParams(width: 80, depth: 60, height: 40))
                )
            ],
            selectedId: customSolidId,
            rollbackIndex: nil
        )
        let package = MadePackage(manifest: manifest, documentData: docData)

        let originalDocURL = URL(fileURLWithPath: "/tmp/original_model.made")
        let metadata = CrashRecoveryMetadata(
            version: 1,
            savedAt: Date(),
            originalDocumentURL: originalDocURL,
            documentTitle: "original_model"
        )
        let store = CrashRecoveryStore(recoveryDirectoryURL: tempRecoveryDir)
        try store.saveSnapshot(package: package, metadata: metadata)

        // Initialize fresh workspace with recovery directory
        let workspace = WorkspaceModel(recoveryDirectoryURL: tempRecoveryDir)
        workspace.setUp()

        #expect(workspace.pendingRecoveryRecord != nil)
        #expect(workspace.isShowingRecoveryAlert == true)
        #expect(workspace.pendingRecoveryRecord?.metadata.documentTitle == "original_model")
        #expect(workspace.pendingRecoveryRecord?.metadata.originalDocumentURL == originalDocURL)

        // Execute recovery
        workspace.recoverDocument()

        #expect(!workspace.isShowingRecoveryAlert)
        #expect(workspace.pendingRecoveryRecord == nil)
        #expect(workspace.currentDocumentURL == originalDocURL)
        #expect(workspace.isDocumentModified == true)
        #expect(workspace.document.objects.count == 1)
        #expect(workspace.document.objects.first?.id == customSolidId)
        #expect(workspace.document.settings.units.lengthUnit == .inches)
        #expect(workspace.document.settings.units.decimalPrecision == 4)

        // Recovery record cleaned from disk
        #expect(workspace.recoveryStore.loadPendingRecovery() == nil)
    }

    @Test func testStartupDetectionAndDiscard() throws {
        let tempRecoveryDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRecoveryDir) }

        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            objects: [
                SceneObject(id: ObjectId("discard-box"), def: .box(BoxParams(width: 10, depth: 10, height: 10)))
            ],
            selectedId: ObjectId("discard-box"),
            rollbackIndex: nil
        )
        let package = MadePackage(documentData: docData)
        let metadata = CrashRecoveryMetadata(documentTitle: "DiscardMe")
        let store = CrashRecoveryStore(recoveryDirectoryURL: tempRecoveryDir)
        try store.saveSnapshot(package: package, metadata: metadata)

        let workspace = WorkspaceModel(recoveryDirectoryURL: tempRecoveryDir)
        workspace.setUp()

        #expect(workspace.pendingRecoveryRecord != nil)
        #expect(workspace.isShowingRecoveryAlert == true)

        let initialObjectCount = workspace.document.objects.count

        // Discard recovery
        workspace.discardRecovery()

        #expect(!workspace.isShowingRecoveryAlert)
        #expect(workspace.pendingRecoveryRecord == nil)
        #expect(workspace.document.objects.count == initialObjectCount)
        #expect(workspace.recoveryStore.loadPendingRecovery() == nil)
    }

    @Test func testExplicitSaveClearsRecoverySnapshot() throws {
        let tempRecoveryDir = try createTempDirectory()
        let tempWorkDir = try createTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempRecoveryDir)
            try? FileManager.default.removeItem(at: tempWorkDir)
        }

        let workspace = WorkspaceModel(recoveryDirectoryURL: tempRecoveryDir)
        workspace.saveRecoverySnapshot()
        #expect(workspace.recoveryStore.loadPendingRecovery() != nil)

        let saveURL = tempWorkDir.appendingPathComponent("ExplicitSave.made")
        workspace.saveDocument(to: saveURL)

        #expect(workspace.recoveryStore.loadPendingRecovery() == nil)
        #expect(workspace.currentDocumentURL == saveURL)
        #expect(!workspace.isDocumentModified)
    }

    @Test func testNewDocumentClearsRecoverySnapshot() throws {
        let tempRecoveryDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRecoveryDir) }

        let workspace = WorkspaceModel(recoveryDirectoryURL: tempRecoveryDir)
        workspace.saveRecoverySnapshot()
        #expect(workspace.recoveryStore.loadPendingRecovery() != nil)

        workspace.newDocument()

        #expect(workspace.recoveryStore.loadPendingRecovery() == nil)
        #expect(workspace.pendingRecoveryRecord == nil)
        #expect(!workspace.isShowingRecoveryAlert)
    }

    @Test func testCorruptRecoverySnapshotOnLaunchLeavesWorkspaceFunctional() throws {
        let tempRecoveryDir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempRecoveryDir) }

        let store = CrashRecoveryStore(recoveryDirectoryURL: tempRecoveryDir)
        try FileManager.default.createDirectory(at: tempRecoveryDir, withIntermediateDirectories: true)

        // Write corrupt recovery files
        try "corrupted json content".write(to: store.metadataURL, atomically: true, encoding: .utf8)
        let dummyPackageDir = store.packageURL
        try FileManager.default.createDirectory(at: dummyPackageDir, withIntermediateDirectories: true)
        try "invalid document data".write(to: dummyPackageDir.appendingPathComponent("document.json"), atomically: true, encoding: .utf8)

        let workspace = WorkspaceModel(recoveryDirectoryURL: tempRecoveryDir)
        workspace.setUp()

        #expect(workspace.pendingRecoveryRecord == nil)
        #expect(!workspace.isShowingRecoveryAlert)
        #expect(workspace.document.objects.count == 2)
    }
}
