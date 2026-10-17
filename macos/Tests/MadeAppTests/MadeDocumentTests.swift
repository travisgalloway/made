import Testing
import Foundation
import SwiftUI
import UniformTypeIdentifiers
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct MadeDocumentTests {
    @Test func testFileDocumentContentTypes() {
        #expect(MadeDocument.readableContentTypes == [.madeDocument])
        #expect(MadeDocument.writableContentTypes == [.madeDocument])
    }

    @Test func testMadePackageGenerationAndFileWrapper() throws {
        let manifest = MadeManifest(schemaVersion: MadeManifest.currentSchemaVersion, appVersion: "0.1")
        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            objects: [
                SceneObject(id: ObjectId("box-1"), def: .box(BoxParams(width: 30, depth: 30, height: 30)))
            ],
            selectedId: ObjectId("box-1")
        )
        let package = MadePackage(
            manifest: manifest,
            documentData: docData,
            assets: ["test.step": "STEP_DATA".data(using: .utf8)!],
            parts: ["test.part.ts": "export default {}".data(using: .utf8)!]
        )

        let wrapper = try package.makeFileWrapper()
        #expect(wrapper.isDirectory)
        guard let children = wrapper.fileWrappers else {
            Issue.record("Missing file wrappers in directory wrapper")
            return
        }

        #expect(children["manifest.json"] != nil)
        #expect(children["document.json"] != nil)
        #expect(children["assets"] != nil)
        #expect(children["parts"] != nil)
        #expect(children["cache"] != nil)

        // Verify cache contains .gitignore
        let cacheWrapper = children["cache"]
        #expect(cacheWrapper?.isDirectory == true)
        let gitignore = cacheWrapper?.fileWrappers?[".gitignore"]
        #expect(gitignore != nil)
        let gitignoreText = String(data: gitignore?.regularFileContents ?? Data(), encoding: .utf8)
        #expect(gitignoreText?.contains("*") == true)

        // Verify round-trip through FileWrapper
        let readPackage = try MadePackage(fileWrapper: wrapper)
        #expect(readPackage.manifest.schemaVersion == MadeManifest.currentSchemaVersion)
        #expect(readPackage.documentData.objects.count == 1)
        #expect(readPackage.documentData.objects.first?.id == ObjectId("box-1"))
        #expect(readPackage.assets["test.step"] == "STEP_DATA".data(using: .utf8)!)
        #expect(readPackage.parts["test.part.ts"] == "export default {}".data(using: .utf8)!)
    }

    @Test func testWorkspaceModelNewSaveAndOpenRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("TestProject.made")

        let workspace = WorkspaceModel()
        workspace.newDocument()
        #expect(workspace.currentDocumentURL == nil)
        #expect(!workspace.isDocumentModified)

        // Modify document
        workspace.addDefaultBox()
        #expect(workspace.isDocumentModified)
        #expect(workspace.documentTitle == "Untitled Project — Edited")

        let boxId = workspace.selectedId!
        workspace.setParam(boxId, "width", 50.0)

        // Save document
        let saveResult = workspace.saveDocument(to: packageURL)
        #expect(saveResult)
        #expect(workspace.currentDocumentURL == packageURL)
        #expect(!workspace.isDocumentModified)
        #expect(workspace.documentTitle == "TestProject")
        #expect(FileManager.default.fileExists(atPath: packageURL.path))

        // Create fresh workspace and open document
        let workspace2 = WorkspaceModel()
        let openResult = workspace2.openDocument(at: packageURL)
        #expect(openResult)
        #expect(workspace2.currentDocumentURL == packageURL)
        #expect(!workspace2.isDocumentModified)
        #expect(workspace2.documentTitle == "TestProject")

        let restoredBox = workspace2.document.objects.first(where: { $0.id == boxId })
        #expect(restoredBox != nil)
        if case .box(let p) = restoredBox?.def {
            #expect(p.width == 50.0)
        } else {
            Issue.record("Expected box def")
        }
    }

    @Test func testCorruptFilePreservesActiveDocument() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create corrupt package with invalid JSON in document.json
        let corruptPackageURL = tempDir.appendingPathComponent("Corrupt.made")
        try FileManager.default.createDirectory(at: corruptPackageURL, withIntermediateDirectories: true)
        let manifestData = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        try manifestData.write(to: corruptPackageURL.appendingPathComponent("manifest.json"))
        let corruptDocData = "NOT_VALID_JSON".data(using: .utf8)!
        try corruptDocData.write(to: corruptPackageURL.appendingPathComponent("document.json"))

        let workspace = WorkspaceModel()
        let initialObjects = workspace.document.objects
        let initialSelected = workspace.selectedId
        let initialURL = workspace.currentDocumentURL

        let openResult = workspace.openDocument(at: corruptPackageURL)
        #expect(!openResult)

        // Workspace scene must remain completely unchanged (Invariant 3)
        #expect(workspace.document.objects == initialObjects)
        #expect(workspace.selectedId == initialSelected)
        #expect(workspace.currentDocumentURL == initialURL)

        // Error must be logged to console drawer
        #expect(workspace.logs.contains(where: { $0.subsystem == "Document" && $0.level == .error }))
    }

    @Test func testFutureSchemaVersionThrowsAndPreservesScene() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let futurePackageURL = tempDir.appendingPathComponent("FutureVersion.made")
        try FileManager.default.createDirectory(at: futurePackageURL, withIntermediateDirectories: true)
        let manifestData = "{\"schemaVersion\": 99, \"appVersion\": \"99.0\"}\n".data(using: .utf8)!
        try manifestData.write(to: futurePackageURL.appendingPathComponent("manifest.json"))
        let docData = "{\"schemaVersion\": 99, \"objects\": []}\n".data(using: .utf8)!
        try docData.write(to: futurePackageURL.appendingPathComponent("document.json"))

        // MadePackage direct load throws typed error
        #expect(throws: MadeDocumentError.unsupportedSchemaVersion(99)) {
            _ = try MadePackage(directoryURL: futurePackageURL)
        }

        let workspace = WorkspaceModel()
        let initialObjects = workspace.document.objects
        let initialSelected = workspace.selectedId
        let initialURL = workspace.currentDocumentURL

        let openResult = workspace.openDocument(at: futurePackageURL)
        #expect(!openResult)
        #expect(workspace.document.objects == initialObjects)
        #expect(workspace.selectedId == initialSelected)
        #expect(workspace.currentDocumentURL == initialURL)
        #expect(workspace.logs.contains(where: {
            $0.subsystem == "Document" &&
            $0.level == .error &&
            $0.message.contains("This document was created by a newer version of Made (schema version 99)")
        }))
    }

    @Test func testOpenV1PackageMigratesToV2InMemory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("V1Package.made")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let manifestData = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))
        let docData = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "def": {
                "kind": "box",
                "params": {
                  "width": 30.0,
                  "depth": 20.0,
                  "height": 10.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        try docData.write(to: packageURL.appendingPathComponent("document.json"))

        let package = try MadePackage(directoryURL: packageURL)
        #expect(package.manifest.schemaVersion == MadeManifest.currentSchemaVersion)
        #expect(package.documentData.schemaVersion == DocumentData.currentSchemaVersion)
        #expect(package.documentData.objects.count == 1)
        #expect(package.documentData.features?.count == 1)
        #expect(package.documentData.objects.first?.id == ObjectId("box-1"))
    }

    @Test func testOpenV1PackageLeavesDiskUnmodified() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("DiskUnmodified.made")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let manifestPath = packageURL.appendingPathComponent("manifest.json")
        let docPath = packageURL.appendingPathComponent("document.json")
        let originalManifest = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        let originalDoc = "{\"schemaVersion\": 1, \"objects\": []}\n".data(using: .utf8)!
        try originalManifest.write(to: manifestPath)
        try originalDoc.write(to: docPath)

        let workspace = WorkspaceModel()
        let openResult = workspace.openDocument(at: packageURL)
        #expect(openResult)

        // Read directly from disk to confirm on-disk contents were untouched
        let onDiskManifest = try Data(contentsOf: manifestPath)
        let onDiskDoc = try Data(contentsOf: docPath)
        #expect(onDiskManifest == originalManifest)
        #expect(onDiskDoc == originalDoc)
    }

    @Test func testSaveMigratedDocumentPersistsV2ToDisk() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("MigratedSave.made")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let manifestPath = packageURL.appendingPathComponent("manifest.json")
        let docPath = packageURL.appendingPathComponent("document.json")
        let originalManifest = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        let originalDoc = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "def": {
                "kind": "box",
                "params": {
                  "width": 30.0,
                  "depth": 20.0,
                  "height": 10.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        try originalManifest.write(to: manifestPath)
        try originalDoc.write(to: docPath)

        let workspace = WorkspaceModel()
        let openResult = workspace.openDocument(at: packageURL)
        #expect(openResult)

        let saveResult = workspace.saveDocument()
        #expect(saveResult)

        // Verify on-disk files are now updated to current schema version (v2)
        let onDiskManifestData = try Data(contentsOf: manifestPath)
        let onDiskManifest = try JSONDecoder().decode(MadeManifest.self, from: onDiskManifestData)
        #expect(onDiskManifest.schemaVersion == MadeManifest.currentSchemaVersion)

        let onDiskDocData = try Data(contentsOf: docPath)
        let onDiskDoc = try DocumentModelCoder.decode(from: onDiskDocData)
        #expect(onDiskDoc.schemaVersion == DocumentData.currentSchemaVersion)
        #expect(onDiskDoc.features?.count == 1)
        #expect(onDiskDoc.objects.count == 1)
    }

    @Test func testFutureDocumentVersionInV1ManifestThrowsUnsupportedSchemaVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("FutureDoc.made")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let manifestData = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))
        let docData = "{\"schemaVersion\": 99, \"objects\": []}\n".data(using: .utf8)!
        try docData.write(to: packageURL.appendingPathComponent("document.json"))

        #expect(throws: MadeDocumentError.unsupportedSchemaVersion(99)) {
            _ = try MadePackage(directoryURL: packageURL)
        }
    }

    @Test func testUnversionedManifestMigratesGracefully() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("Unversioned.made")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let manifestData = "{\"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))
        let docData = "{\"objects\": []}\n".data(using: .utf8)!
        try docData.write(to: packageURL.appendingPathComponent("document.json"))

        let package = try MadePackage(directoryURL: packageURL)
        #expect(package.manifest.schemaVersion == MadeManifest.currentSchemaVersion)
        #expect(package.documentData.schemaVersion == DocumentData.currentSchemaVersion)
    }

    @Test func testMissingAssetsLoadsWithoutCrashing() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("MissingAsset.made")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let manifestData = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))

        // Reference an asset that does NOT exist in assets/
        let docData = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "imported-1",
              "name": "missing.step",
              "def": {
                "kind": "imported",
                "name": "missing.step",
                "assetPath": "assets/missing.step"
              }
            }
          ]
        }
        """.data(using: .utf8)!
        try docData.write(to: packageURL.appendingPathComponent("document.json"))

        let workspace = WorkspaceModel()
        let openResult = workspace.openDocument(at: packageURL)
        #expect(openResult)
        #expect(workspace.document.objects.count == 1)
        let obj = workspace.document.objects[0]
        #expect(obj.id == ObjectId("imported-1"))
        if case .imported(let name, _, let data) = obj.def {
            #expect(name == "missing.step")
            #expect(data == nil)
        } else {
            Issue.record("Expected imported def")
        }
    }

    @Test func testAutosaveDebounceExecution() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("AutosaveTest.made")

        let workspace = WorkspaceModel()
        // Save initial file so currentDocumentURL is set
        workspace.saveDocument(to: packageURL)
        #expect(!workspace.isDocumentModified)

        // Set short debounce interval for test (50ms)
        workspace.autosaveDebounceNanoseconds = 50_000_000

        // Perform edit
        workspace.addDefaultCylinder()
        #expect(workspace.isDocumentModified)

        // Wait for debounce interval + buffer with polling to accommodate CI scheduling latency
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while workspace.isDocumentModified && clock.now < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        // Verify autosave persisted and cleared modified state
        #expect(!workspace.isDocumentModified)

        // Re-read from disk to confirm changes saved
        let readPackage = try MadePackage(directoryURL: packageURL)
        #expect(readPackage.documentData.objects.contains(where: { $0.id.rawValue.starts(with: "cylinder-") }))
    }

    @Test func testFileMenuCommandsShortcutConstants() {
        #expect(WorkspaceModel.newDocumentShortcutKey == "n")
        #expect(WorkspaceModel.newDocumentShortcutModifiers == [.command])
        #expect(WorkspaceModel.openDocumentShortcutKey == "o")
        #expect(WorkspaceModel.openDocumentShortcutModifiers == [.command])
        #expect(WorkspaceModel.openPartShortcutKey == "o")
        #expect(WorkspaceModel.openPartShortcutModifiers == [.command, .option])
        #expect(WorkspaceModel.saveDocumentShortcutKey == "s")
        #expect(WorkspaceModel.saveDocumentShortcutModifiers == [.command])
        #expect(WorkspaceModel.saveAsDocumentShortcutKey == "s")
        #expect(WorkspaceModel.saveAsDocumentShortcutModifiers == [.command, .shift])
    }

    // MARK: - Document Settings Package Persistence Tests (BL-FND-11)

    @Test func testDocumentSettingsPersistenceInPackageManifest() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("SettingsTest.made")

        let customSettings = DocumentSettings(
            units: UnitSettings(lengthUnit: .inches, angleUnit: .radians, decimalPrecision: 4),
            tolerances: KernelTolerances(linearTolerance: 0.005, angularTolerance: 0.25, chordalTolerance: 0.02),
            defaultMaterial: MaterialAttributes(color: SIMD4<Float>(0.7, 0.3, 0.1, 1.0))
        )

        let workspace = WorkspaceModel()
        workspace.setDocumentSettings(customSettings)
        #expect(workspace.isDocumentModified)

        let saveResult = workspace.saveDocument(to: packageURL)
        #expect(saveResult)

        // Verify package on disk contains manifest with settings
        let readPackage = try MadePackage(directoryURL: packageURL)
        #expect(readPackage.manifest.units == customSettings.units)
        #expect(readPackage.manifest.tolerances == customSettings.tolerances)
        #expect(readPackage.manifest.defaultMaterial == customSettings.defaultMaterial)
        #expect(readPackage.manifest.documentSettings == customSettings)

        // Verify opening in fresh workspace restores document settings
        let workspace2 = WorkspaceModel()
        let openResult = workspace2.openDocument(at: packageURL)
        #expect(openResult)
        #expect(workspace2.document.settings == customSettings)
    }

    @Test func testPackageDecodingWithMissingDefaultMaterialFallback() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("LegacyManifest.made")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let legacyManifest = """
        {
          "schemaVersion": 2,
          "appVersion": "0.1",
          "units": {
            "lengthUnit": "cm",
            "angleUnit": "deg",
            "decimalPrecision": 3
          },
          "tolerances": {
            "linearTolerance": 0.002,
            "angularTolerance": 0.05,
            "chordalTolerance": 0.01
          }
        }
        """.data(using: .utf8)!
        try legacyManifest.write(to: packageURL.appendingPathComponent("manifest.json"))

        let docData = """
        {
          "schemaVersion": 2,
          "objects": []
        }
        """.data(using: .utf8)!
        try docData.write(to: packageURL.appendingPathComponent("document.json"))

        let package = try MadePackage(directoryURL: packageURL)
        #expect(package.manifest.units.lengthUnit == .centimeters)
        #expect(package.manifest.units.decimalPrecision == 3)
        #expect(package.manifest.tolerances.linearTolerance == 0.002)
        #expect(package.manifest.defaultMaterial == MaterialAttributes())

        let workspace = WorkspaceModel()
        let openResult = workspace.openDocument(at: packageURL)
        #expect(openResult)
        #expect(workspace.document.settings.units.lengthUnit == .centimeters)
        #expect(workspace.document.settings.defaultMaterial == MaterialAttributes())
    }
}
