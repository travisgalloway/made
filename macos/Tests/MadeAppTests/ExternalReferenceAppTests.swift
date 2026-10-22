import Testing
import SwiftUI
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct ExternalReferenceAppTests {

    @Test @MainActor func testLinkExternalStepFile() async throws {
        let model = WorkspaceModel()
        let initialCount = model.document.objects.count

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("external-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let exported = await model.exportStepFile(to: tempURL, selectedOnly: true)
        #expect(exported)

        let linkedId = await model.linkExternalFile(at: tempURL)
        guard let linkedId else {
            Issue.record("Failed to link external STEP file")
            return
        }

        #expect(model.document.objects.count == initialCount + 1)
        #expect(model.selectedId == linkedId)

        guard let obj = model.document.objects.first(where: { $0.id == linkedId }) else {
            Issue.record("Linked object not found in document")
            return
        }

        #expect(obj.isLinked == true)
        #expect(obj.linkedSourceURL == tempURL)
        #expect(model.linkStatus(for: linkedId) == .upToDate)
    }

    @Test @MainActor func testOutOfDateDetectionAndReload() async throws {
        let model = WorkspaceModel()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("updatable-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let exported = await model.exportStepFile(to: tempURL, selectedOnly: true)
        #expect(exported)

        guard let linkedId = await model.linkExternalFile(at: tempURL) else {
            Issue.record("Failed to link external STEP file")
            return
        }

        #expect(model.linkStatus(for: linkedId) == .upToDate)

        guard let recordedDate = ExternalReferenceDescriptor.modificationDate(of: tempURL) else {
            Issue.record("Failed to get initial modification date")
            return
        }

        // Advance timestamp on disk to simulate external tool edit
        let futureDate = recordedDate.addingTimeInterval(3.0)
        try FileManager.default.setAttributes([.modificationDate: futureDate], ofItemAtPath: tempURL.path)

        model.refreshLinkedReferenceStatuses()
        #expect(model.linkStatus(for: linkedId) == .outOfDate)

        // Update link on request
        let updated = await model.updateLinkedReference(linkedId)
        #expect(updated)
        #expect(model.linkStatus(for: linkedId) == .upToDate)
    }

    @Test @MainActor func testMissingFileStatusWhenDeleted() async throws {
        let model = WorkspaceModel()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("deletable-\(UUID().uuidString).step")

        let exported = await model.exportStepFile(to: tempURL, selectedOnly: true)
        #expect(exported)

        guard let linkedId = await model.linkExternalFile(at: tempURL) else {
            Issue.record("Failed to link external STEP file")
            return
        }

        #expect(model.linkStatus(for: linkedId) == .upToDate)

        // Delete file on disk
        try FileManager.default.removeItem(at: tempURL)

        model.refreshLinkedReferenceStatuses()
        #expect(model.linkStatus(for: linkedId) == .missingFile)

        // Updating missing link should fail gracefully without crashing
        let updated = await model.updateLinkedReference(linkedId)
        #expect(!updated)
    }

    @Test @MainActor func testEmbedLinkedReference() async throws {
        let model = WorkspaceModel()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("embed-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let exported = await model.exportStepFile(to: tempURL, selectedOnly: true)
        #expect(exported)

        guard let linkedId = await model.linkExternalFile(at: tempURL) else {
            Issue.record("Failed to link external STEP file")
            return
        }

        #expect(model.document.objects.first(where: { $0.id == linkedId })?.isLinked == true)

        model.embedLinkedReference(linkedId)

        guard let obj = model.document.objects.first(where: { $0.id == linkedId }) else {
            Issue.record("Object not found after embedding")
            return
        }

        #expect(obj.isLinked == false)
        if case .imported(let name, let sourceURL, let data, let isLinked, _, _) = obj.def {
            #expect(!isLinked)
            #expect(data != nil)
            #expect(name == tempURL.lastPathComponent)
            #expect(sourceURL?.path.contains("assets/") == true)
        } else {
            Issue.record("Expected object def to be embedded .imported")
        }
    }

    @Test @MainActor func testRelinkReference() async throws {
        let model = WorkspaceModel()
        let tempURL1 = FileManager.default.temporaryDirectory.appendingPathComponent("initial-\(UUID().uuidString).step")
        let tempURL2 = FileManager.default.temporaryDirectory.appendingPathComponent("replaced-\(UUID().uuidString).step")
        defer {
            try? FileManager.default.removeItem(at: tempURL1)
            try? FileManager.default.removeItem(at: tempURL2)
        }

        _ = await model.exportStepFile(to: tempURL1, selectedOnly: true)
        _ = await model.exportStepFile(to: tempURL2, selectedOnly: true)

        guard let linkedId = await model.linkExternalFile(at: tempURL1) else {
            Issue.record("Failed to link initial STEP file")
            return
        }

        #expect(model.document.objects.first(where: { $0.id == linkedId })?.linkedSourceURL == tempURL1)

        let relinked = await model.relinkReference(linkedId, to: tempURL2)
        #expect(relinked)

        let obj = model.document.objects.first(where: { $0.id == linkedId })
        #expect(obj?.linkedSourceURL == tempURL2)
        #expect(obj?.name == tempURL2.lastPathComponent)
        #expect(model.linkStatus(for: linkedId) == .upToDate)
    }

    @Test @MainActor func testLinkExternalMadePackage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let childPkgURL = tempDir.appendingPathComponent("SubAssembly.made")
        let childModel = WorkspaceModel()
        _ = childModel.saveDocument(to: childPkgURL)

        let mainModel = WorkspaceModel()
        let linkedId = await mainModel.linkExternalFile(at: childPkgURL)
        guard let linkedId else {
            Issue.record("Failed to link external .made package")
            return
        }

        let obj = mainModel.document.objects.first(where: { $0.id == linkedId })
        #expect(obj?.isLinked == true)
        #expect(obj?.linkedSourceURL == childPkgURL)
        #expect(mainModel.linkStatus(for: linkedId) == .upToDate)
    }

    @Test @MainActor func testPackageSaveAndReopenPreservesLinkedReference() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stepURL = tempDir.appendingPathComponent("library_part.step")
        let mainModel = WorkspaceModel()
        _ = await mainModel.exportStepFile(to: stepURL, selectedOnly: true)

        guard let linkedId = await mainModel.linkExternalFile(at: stepURL) else {
            Issue.record("Failed to link external file")
            return
        }

        let mainPkgURL = tempDir.appendingPathComponent("ParentDocument.made")
        let saveResult = mainModel.saveDocument(to: mainPkgURL)
        #expect(saveResult)

        // Check package directory contents: library_part.step should NOT be in assets/
        let pkg = try MadePackage(directoryURL: mainPkgURL)
        #expect(pkg.assets["library_part.step"] == nil)

        // Open in a new workspace
        let reloadedModel = WorkspaceModel()
        let opened = reloadedModel.openDocument(at: mainPkgURL)
        #expect(opened)

        guard let reloadedObj = reloadedModel.document.objects.first(where: { $0.id == linkedId }) else {
            Issue.record("Linked object not restored after reopening")
            return
        }

        #expect(reloadedObj.isLinked == true)
        #expect(reloadedObj.linkedSourceURL == stepURL)
        #expect(reloadedModel.linkStatus(for: linkedId) == .upToDate)
    }
}
