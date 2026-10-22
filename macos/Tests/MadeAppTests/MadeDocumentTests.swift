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
        #expect(workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError != nil)
        #expect(workspace.pendingOpenError?.documentURL == corruptPackageURL)
        #expect(workspace.pendingOpenError?.fileName == "Corrupt.made")
        #expect(!(workspace.pendingOpenError?.reason.isEmpty ?? true))
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
        #expect(workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError != nil)
        #expect(workspace.pendingOpenError?.documentURL == futurePackageURL)
        #expect(workspace.pendingOpenError?.fileName == "FutureVersion.made")
        #expect(workspace.pendingOpenError?.reason.contains("schema version 99") == true)
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
        if case .imported(let name, _, let data, _, _, _) = obj.def {
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

    // MARK: - Unreadable Source Error Tests (Issue #559)

    @Test func testSaveDocumentFailsWhenPartSourceUnreadable() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let packageURL = tempDir.appendingPathComponent("TestPart.made")
        let partsDir = packageURL.appendingPathComponent("parts")
        try FileManager.default.createDirectory(at: partsDir, withIntermediateDirectories: true)

        let widgetFile = partsDir.appendingPathComponent("widget.part.ts")
        let widgetContent = "export default { kind: 'box' };\n"
        try widgetContent.data(using: .utf8)!.write(to: widgetFile)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: widgetFile.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let manifest = MadeManifest(schemaVersion: MadeManifest.currentSchemaVersion, appVersion: "0.1")
        let partURL = URL(fileURLWithPath: "parts/widget.part.ts")
        let solidId = SolidId("part-1")
        let partFeature = Feature(name: "WidgetPart", operation: .part(PartFeatureData(url: partURL, shape: nil)), outputSolidId: solidId)
        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            features: [partFeature],
            objects: [SceneObject(id: solidId, def: .part(url: partURL))]
        )
        let initialPackage = MadePackage(
            manifest: manifest,
            documentData: docData,
            assets: [:],
            parts: ["widget.part.ts": widgetContent.data(using: .utf8)!]
        )
        try initialPackage.write(to: packageURL)

        let originalDocData = try Data(contentsOf: packageURL.appendingPathComponent("document.json"))
        let originalManifestData = try Data(contentsOf: packageURL.appendingPathComponent("manifest.json"))

        let workspace = WorkspaceModel()
        let openResult = workspace.openDocument(at: packageURL)
        #expect(openResult)
        #expect(workspace.currentDocumentURL == packageURL)

        // Mark document as modified
        workspace.addDefaultBox()
        #expect(workspace.isDocumentModified)

        // Set widget.part.ts permissions to 000 (unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: widgetFile.path)

        let saveResult = workspace.saveDocument()
        #expect(!saveResult)
        #expect(workspace.isDocumentModified)
        #expect(workspace.logs.contains { $0.level == .error && $0.subsystem == "Document" && $0.message.contains("widget.part.ts") })

        // Verify on-disk package remains completely intact and unchanged
        let currentDocData = try Data(contentsOf: packageURL.appendingPathComponent("document.json"))
        let currentManifestData = try Data(contentsOf: packageURL.appendingPathComponent("manifest.json"))
        #expect(currentDocData == originalDocData)
        #expect(currentManifestData == originalManifestData)
    }

    @Test func testSaveDocumentFailsWhenSTEPAssetUnreadable() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let stepFile = tempDir.appendingPathComponent("bracket.step")
        try "ISO-10303-21;".data(using: .utf8)!.write(to: stepFile)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stepFile.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let workspace = WorkspaceModel()
        workspace.newDocument()
        let importedFeature = Feature(
            name: "Bracket",
            operation: .imported(ImportedFeatureData(name: "Bracket", sourceURL: stepFile, data: nil))
        )
        workspace.document.reset(with: [importedFeature])
        workspace.addDefaultBox()

        // Set stepFile permissions to 000 (unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: stepFile.path)

        let destinationURL = tempDir.appendingPathComponent("SavedSTEP.made")
        let saveResult = workspace.saveDocument(to: destinationURL)

        #expect(!saveResult)
        #expect(workspace.isDocumentModified)
        #expect(workspace.logs.contains { $0.level == .error && $0.subsystem == "Document" && $0.message.contains("bracket.step") })
        #expect(!FileManager.default.fileExists(atPath: destinationURL.path))
    }

    @Test func testSaveDocumentPreservesRolledBackFeaturesAssetsAndParts() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stepFile = tempDir.appendingPathComponent("engine.step")
        let stepContent = "ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\nENDSEC;\nEND-ISO-10303-21;\n"
        try stepContent.data(using: .utf8)!.write(to: stepFile)

        let partFile = tempDir.appendingPathComponent("cog.part.ts")
        let partContent = "export default { kind: 'cylinder' };\n"
        try partContent.data(using: .utf8)!.write(to: partFile)

        let workspace = WorkspaceModel()
        workspace.newDocument()

        let baseBox = Feature(
            name: "BaseBox",
            operation: .primitive(PrimitiveFeatureData.box(BoxParams(width: 20, depth: 20, height: 20))),
            outputSolidId: SolidId("box-1")
        )
        let importedFeature = Feature(
            name: "Engine",
            operation: .imported(ImportedFeatureData(name: "Engine", sourceURL: stepFile, data: nil))
        )
        let partFeature = Feature(
            name: "Cog",
            operation: .part(PartFeatureData(url: partFile, shape: nil))
        )

        // Reset document with 3 features and rollback to index 1 (so Engine and Cog are rolled back)
        workspace.document.reset(with: [baseBox, importedFeature, partFeature], rollbackIndex: 1)
        #expect(workspace.document.isRolledBack)
        #expect(workspace.document.objects.count == 1)
        #expect(workspace.document.features.count == 3)

        let destinationURL = tempDir.appendingPathComponent("RolledBackProject.made")
        let saveResult = workspace.saveDocument(to: destinationURL)
        #expect(saveResult)

        // Read saved package from disk and verify assets/ and parts/ both contain rolled-back data
        let readPackage = try MadePackage(directoryURL: destinationURL)
        #expect(readPackage.assets["engine.step"] == stepContent.data(using: .utf8)!)
        #expect(readPackage.parts["cog.part.ts"] == partContent.data(using: .utf8)!)
    }

    @Test func testSaveDocumentFailsWhenSTEPAssetMissingAndNoData() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let workspace = WorkspaceModel()
        workspace.newDocument()
        let missingURL = tempDir.appendingPathComponent("nonexistent.step")
        let importedFeature = Feature(
            name: "Nonexistent",
            operation: .imported(ImportedFeatureData(name: "Nonexistent", sourceURL: missingURL, data: nil))
        )
        workspace.document.reset(with: [importedFeature])

        let destinationURL = tempDir.appendingPathComponent("TestMissing.made")
        let saveResult = workspace.saveDocument(to: destinationURL)
        #expect(!saveResult)
        #expect(workspace.logs.contains { $0.level == .error && $0.subsystem == "Document" && $0.message.contains("nonexistent.step") })
        #expect(!FileManager.default.fileExists(atPath: destinationURL.path))
    }

    @Test func testMovePackageDirectoryAndReloadPreservesPartsAndAssets() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDir) }

        let externalDir = rootDir.appendingPathComponent("ExternalSource")
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)

        let stepFile = externalDir.appendingPathComponent("bracket.step")
        let stepContent = "ISO-10303-21;\nHEADER;\nENDSEC;\nDATA;\nENDSEC;\nEND-ISO-10303-21;\n"
        try stepContent.data(using: .utf8)!.write(to: stepFile)

        let partFile = externalDir.appendingPathComponent("bracket.part.ts")
        let partContent = "export default { kind: 'box', width: 20, height: 10, depth: 30 };\n"
        try partContent.data(using: .utf8)!.write(to: partFile)

        let originalPackageURL = rootDir.appendingPathComponent("LocationA/MyModel.made")
        let movedPackageURL = rootDir.appendingPathComponent("LocationB/MyModelMoved.made")

        let workspace = WorkspaceModel()
        workspace.newDocument()

        let baseBox = Feature(
            name: "BaseBox",
            operation: .primitive(PrimitiveFeatureData.box(BoxParams(width: 20, depth: 20, height: 20))),
            outputSolidId: SolidId("box-1")
        )
        let importedFeature = Feature(
            name: "BracketSTEP",
            operation: .imported(ImportedFeatureData(name: "bracket.step", sourceURL: stepFile, data: nil)),
            outputSolidId: SolidId("imported-1")
        )
        let partFeature = Feature(
            name: "BracketPart",
            operation: .part(PartFeatureData(url: partFile, shape: nil)),
            outputSolidId: SolidId("part-1")
        )

        workspace.document.reset(with: [baseBox, importedFeature, partFeature])
        #expect(workspace.document.features.count == 3)
        #expect(workspace.document.objects.count == 3)

        // Save document to originalPackageURL
        try FileManager.default.createDirectory(at: originalPackageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let saveResult = workspace.saveDocument(to: originalPackageURL)
        #expect(saveResult)

        // Verify active in-memory document paths were rebased to package directory
        guard let inMemoryPartObj = workspace.document.objects.first(where: { $0.id == SolidId("part-1") }) else {
            Issue.record("Missing in-memory part object")
            return
        }
        if case .part(let url, _) = inMemoryPartObj.def {
            #expect(url == originalPackageURL.appendingPathComponent("parts/bracket.part.ts"))
        } else {
            Issue.record("Expected .part def")
        }

        // Verify saved document.json on disk contains relative paths, not absolute paths
        let docJSONURL = originalPackageURL.appendingPathComponent("document.json")
        let docJSONData = try Data(contentsOf: docJSONURL)
        let docJSONText = String(decoding: docJSONData, as: UTF8.self)
        #expect(docJSONText.contains("\"parts/bracket.part.ts\""))
        #expect(docJSONText.contains("\"assets/bracket.step\""))
        #expect(!docJSONText.contains(externalDir.path))

        // Delete external source directory so files only exist inside the package
        try FileManager.default.removeItem(at: externalDir)
        #expect(!FileManager.default.fileExists(atPath: stepFile.path))
        #expect(!FileManager.default.fileExists(atPath: partFile.path))

        // Move the package directory on disk to a new location
        try FileManager.default.createDirectory(at: movedPackageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: originalPackageURL, to: movedPackageURL)
        #expect(!FileManager.default.fileExists(atPath: originalPackageURL.path))
        #expect(FileManager.default.fileExists(atPath: movedPackageURL.path))

        // Open the moved package in a fresh workspace
        let reloadWorkspace = WorkspaceModel()
        let openResult = reloadWorkspace.openDocument(at: movedPackageURL)
        #expect(openResult)
        #expect(reloadWorkspace.currentDocumentURL == movedPackageURL)

        // Verify features and objects resolve paths against the new package directory
        let reloadedDoc = reloadWorkspace.document
        #expect(reloadedDoc.features.count == 3)
        #expect(reloadedDoc.objects.count == 3)

        guard let reloadedPartFeature = reloadedDoc.features.first(where: { $0.name == "BracketPart" }),
              case .part(let reloadedPartData) = reloadedPartFeature.operation else {
            Issue.record("Missing reloaded part feature")
            return
        }
        let expectedPartURL = movedPackageURL.appendingPathComponent("parts/bracket.part.ts")
        #expect(reloadedPartData.url == expectedPartURL)
        #expect(FileManager.default.fileExists(atPath: expectedPartURL.path))

        guard let reloadedImportedFeature = reloadedDoc.features.first(where: { $0.name == "BracketSTEP" }),
              case .imported(let reloadedImportedData) = reloadedImportedFeature.operation else {
            Issue.record("Missing reloaded imported feature")
            return
        }
        let expectedAssetURL = movedPackageURL.appendingPathComponent("assets/bracket.step")
        #expect(reloadedImportedData.sourceURL == expectedAssetURL)
        #expect(FileManager.default.fileExists(atPath: expectedAssetURL.path))

        // Verify objects projection matches
        guard let reloadedPartObj = reloadedDoc.objects.first(where: { $0.id == SolidId("part-1") }),
              case .part(let objPartURL, _) = reloadedPartObj.def else {
            Issue.record("Missing reloaded part object")
            return
        }
        #expect(objPartURL == expectedPartURL)

        guard let reloadedImpObj = reloadedDoc.objects.first(where: { $0.id == SolidId("imported-1") }),
              case .imported(_, let objImpURL, let objImpData, _, _, _) = reloadedImpObj.def else {
            Issue.record("Missing reloaded imported object")
            return
        }
        #expect(objImpURL == expectedAssetURL)
        #expect(objImpData == stepContent.data(using: .utf8)!)

        // Verify MadePackage(directoryURL:) direct reload also resolves without path leaks
        let directPackage = try MadePackage(directoryURL: movedPackageURL)
        #expect(directPackage.parts["bracket.part.ts"] == partContent.data(using: .utf8)!)
        #expect(directPackage.assets["bracket.step"] == stepContent.data(using: .utf8)!)
    }

    @Test func testSaveDocumentFailsWhenDestinationUnwritableShowsAlert() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let readOnlyDir = tempDir.appendingPathComponent("ReadOnlyDir")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let workspace = WorkspaceModel()
        workspace.newDocument()
        workspace.addDefaultBox()
        #expect(workspace.isDocumentModified)

        // Make directory unwritable (read and execute only)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)

        let destinationURL = readOnlyDir.appendingPathComponent("UnwritableDocument.made")
        let saveResult = workspace.saveDocument(to: destinationURL)

        #expect(!saveResult)
        #expect(workspace.isDocumentModified)
        #expect(workspace.isShowingSaveErrorAlert)
        #expect(workspace.pendingSaveError != nil)
        #expect(workspace.pendingSaveError?.destinationURL == destinationURL)
        #expect(workspace.pendingSaveError?.fileName == "UnwritableDocument.made")
        #expect(!(workspace.pendingSaveError?.reason.isEmpty ?? true))

        workspace.dismissSaveErrorAlert()
        #expect(!workspace.isShowingSaveErrorAlert)
        #expect(workspace.pendingSaveError == nil)
    }

    @Test func testSaveDocumentAlertStateClearedOnLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let readOnlyDir = tempDir.appendingPathComponent("ReadOnlyLifecycleDir")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let workspace = WorkspaceModel()
        workspace.newDocument()
        workspace.addDefaultBox()

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnlyDir.path)

        let unwritableURL = readOnlyDir.appendingPathComponent("Unwritable.made")
        let saveFailResult = workspace.saveDocument(to: unwritableURL)
        #expect(!saveFailResult)
        #expect(workspace.isShowingSaveErrorAlert)
        #expect(workspace.pendingSaveError != nil)

        // Reset via newDocument()
        workspace.newDocument()
        #expect(!workspace.isShowingSaveErrorAlert)
        #expect(workspace.pendingSaveError == nil)

        // Trigger failure again
        workspace.addDefaultBox()
        _ = workspace.saveDocument(to: unwritableURL)
        #expect(workspace.isShowingSaveErrorAlert)
        #expect(workspace.pendingSaveError != nil)

        // Reset via successful saveDocument
        let writableURL = tempDir.appendingPathComponent("ValidDocument.made")
        let saveSuccessResult = workspace.saveDocument(to: writableURL)
        #expect(saveSuccessResult)
        #expect(!workspace.isShowingSaveErrorAlert)
        #expect(workspace.pendingSaveError == nil)

        // Trigger failure again
        workspace.addDefaultBox()
        _ = workspace.saveDocument(to: unwritableURL)
        #expect(workspace.isShowingSaveErrorAlert)
        #expect(workspace.pendingSaveError != nil)

        // Reset via openDocument(at:)
        let openSuccessResult = workspace.openDocument(at: writableURL)
        #expect(openSuccessResult)
        #expect(!workspace.isShowingSaveErrorAlert)
        #expect(workspace.pendingSaveError == nil)
    }

    @Test func testOpenDocumentFailsWhenPackageCorruptShowsAlert() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let corruptPackageURL = tempDir.appendingPathComponent("CorruptPackage.made")
        try FileManager.default.createDirectory(at: corruptPackageURL, withIntermediateDirectories: true)
        let manifestData = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        try manifestData.write(to: corruptPackageURL.appendingPathComponent("manifest.json"))
        let corruptDocData = "INVALID_JSON".data(using: .utf8)!
        try corruptDocData.write(to: corruptPackageURL.appendingPathComponent("document.json"))

        let workspace = WorkspaceModel()
        let openResult = workspace.openDocument(at: corruptPackageURL)
        #expect(!openResult)
        #expect(workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError != nil)
        #expect(workspace.pendingOpenError?.documentURL == corruptPackageURL)
        #expect(workspace.pendingOpenError?.fileName == "CorruptPackage.made")
        #expect(!(workspace.pendingOpenError?.reason.isEmpty ?? true))

        workspace.dismissOpenErrorAlert()
        #expect(!workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError == nil)
    }

    @Test func testOpenDocumentAlertStateClearedOnLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let corruptPackageURL = tempDir.appendingPathComponent("CorruptPackage.made")
        try FileManager.default.createDirectory(at: corruptPackageURL, withIntermediateDirectories: true)
        let manifestData = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        try manifestData.write(to: corruptPackageURL.appendingPathComponent("manifest.json"))
        let corruptDocData = "INVALID_JSON".data(using: .utf8)!
        try corruptDocData.write(to: corruptPackageURL.appendingPathComponent("document.json"))

        let workspace = WorkspaceModel()
        workspace.newDocument()

        // Create a valid document package for open testing
        let validPackageURL = tempDir.appendingPathComponent("ValidPackage.made")
        let saveResult = workspace.saveDocument(to: validPackageURL)
        #expect(saveResult)

        // Trigger open failure
        let openFailResult = workspace.openDocument(at: corruptPackageURL)
        #expect(!openFailResult)
        #expect(workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError != nil)

        // Reset via newDocument()
        workspace.newDocument()
        #expect(!workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError == nil)

        // Trigger open failure again
        let openFailResult2 = workspace.openDocument(at: corruptPackageURL)
        #expect(!openFailResult2)
        #expect(workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError != nil)

        // Reset via successful openDocument(at:)
        let openSuccessResult = workspace.openDocument(at: validPackageURL)
        #expect(openSuccessResult)
        #expect(!workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError == nil)

        // Trigger open failure again
        let openFailResult3 = workspace.openDocument(at: corruptPackageURL)
        #expect(!openFailResult3)
        #expect(workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError != nil)

        // Reset via dismissOpenErrorAlert()
        workspace.dismissOpenErrorAlert()
        #expect(!workspace.isShowingOpenErrorAlert)
        #expect(workspace.pendingOpenError == nil)
    }
}

