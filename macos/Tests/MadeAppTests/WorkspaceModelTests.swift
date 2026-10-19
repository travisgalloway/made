import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct WorkspaceModelTests {
    @Test @MainActor func testSetTransformLogsConsoleEntry() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        let initialLogsCount = model.logs.count

        var newTransform = Transform()
        newTransform.position = SIMD3<Float>(15.0, 0.0, 0.0)
        newTransform.scale = SIMD3<Float>(2.0, 2.0, 2.0)

        model.setTransform(id, newTransform)

        #expect(model.logs.count == initialLogsCount + 1)
        guard let lastLog = model.logs.last else {
            Issue.record("Expected log entry")
            return
        }
        #expect(lastLog.subsystem == "Scene")
        #expect(lastLog.level == .info)
        #expect(lastLog.message.contains("box-1"))
        #expect(lastLog.message.contains("15.0"))
        #expect(lastLog.message.contains("2.0"))
    }

    @Test @MainActor func testSetTransformUnchangedValueAddsNoLogEntry() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        guard let current = model.document.objects.first(where: { $0.id == id }) else {
            Issue.record("Default box-1 not found")
            return
        }
        let initialLogsCount = model.logs.count

        model.setTransform(id, current.transform)

        #expect(model.logs.count == initialLogsCount)
    }

    @Test @MainActor func testSetTransformNonExistentIdAddsNoLogEntry() {
        let model = WorkspaceModel()
        let fakeId = ObjectId("nonexistent-solid-999")
        let initialLogsCount = model.logs.count

        model.setTransform(fakeId, Transform(position: SIMD3<Float>(10, 10, 10)))

        #expect(model.logs.count == initialLogsCount)
    }

    @Test @MainActor func testSetTransformLockedObjectAddsNoLogEntry() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        model.document.setLocked(id: id, isLocked: true)
        let initialLogsCount = model.logs.count

        model.setTransform(id, Transform(position: SIMD3<Float>(50, 0, 0)))

        #expect(model.logs.count == initialLogsCount)
    }

    @Test @MainActor func testTelemetryInitialEmptyState() {
        let model = WorkspaceModel()
        #expect(model.kernelStats == KernelStats())
        #expect(model.kernelStats.dispatched == 0)
        #expect(model.kernelStats.conflated == 0)
        #expect(model.kernelStats.dropped == 0)
        #expect(model.kernelStats.completed == 0)
        #expect(model.renderStats.renderCount == 0)
        #expect(model.renderStats.drawCalls == 0)
        #expect(model.renderStats.lastReason == "init")
    }

    @Test @MainActor func testTelemetryReadsFromRenderInstrumentationAndKernelClient() async {
        let model = WorkspaceModel()
        _ = await model.kernelClient.request(.makeBox(jobId: JobId("telemetry-read-box"), solidId: SolidId("t-box"), params: BoxParams(width: 10, depth: 10, height: 10)))
        await model.updateKernelStats()

        RenderInstrumentation.shared.reset()
        RenderInstrumentation.shared.recordRender(drawCalls: 7)
        RenderInstrumentation.shared.recordInvalidation(reason: .camera)

        model.updateStats()
        await model.updateKernelStats()

        #expect(model.renderStats.renderCount == 1)
        #expect(model.renderStats.drawCalls == 7)
        #expect(model.renderStats.lastReason == "camera")
        #expect(model.kernelStats.dispatched >= 1)
        #expect(model.kernelStats.completed >= 1)
    }

    @Test @MainActor func testTelemetryDrawerHiddenWhenCountersChange() async {
        let model = WorkspaceModel()
        model.isConsoleVisible = false

        _ = await model.kernelClient.request(.makeBox(jobId: JobId("drawer-hidden-box"), solidId: SolidId("dh-box"), params: BoxParams(width: 12, depth: 12, height: 12)))

        RenderInstrumentation.shared.reset()
        RenderInstrumentation.shared.recordRender(drawCalls: 4)
        RenderInstrumentation.shared.recordInvalidation(reason: .model)

        model.updateStats()
        await model.updateKernelStats()

        #expect(model.renderStats.renderCount == 1)
        #expect(model.renderStats.drawCalls == 4)
        #expect(model.renderStats.lastReason == "model")
        #expect(model.kernelStats.dispatched >= 1)

        model.toggleConsole()
        #expect(model.isConsoleVisible == true)
        #expect(model.renderStats.drawCalls == 4)
        #expect(model.kernelStats.dispatched >= 1)
    }

    @Test @MainActor func testTelemetryWhenViewportUnavailable() async {
        let model = WorkspaceModel()
        model.viewportManager.state = .unavailable(reason: .noDevice)
        #expect(model.viewportManager.state.isUnavailable)

        model.updateStats()
        await model.updateKernelStats()

        #expect(model.renderStats.lastReason != "")
        #expect(model.kernelStats.dispatched >= 0)
    }

    @Test @MainActor func testTelemetrySuppressesRedundantUpdates() async {
        let model = WorkspaceModel()
        RenderInstrumentation.shared.reset()
        RenderInstrumentation.shared.recordRender(drawCalls: 3)
        RenderInstrumentation.shared.recordInvalidation(reason: .interaction)

        model.updateStats()
        await model.updateKernelStats()

        let initialRenderStats = model.renderStats
        let initialKernelStats = model.kernelStats

        // Second update without changes
        model.updateStats()
        await model.updateKernelStats()

        #expect(model.renderStats == initialRenderStats)
        #expect(model.kernelStats == initialKernelStats)
    }

    @Test @MainActor func testRapidParameterEditsConflateAndDispatchInKernelStats() async throws {
        let model = WorkspaceModel()
        model.setUp()
        let id = ObjectId("box-1")

        // Allow initial setUp recomputes to settle
        try await Task.sleep(for: .milliseconds(150))
        await model.updateKernelStats()
        let initialConflated = model.kernelStats.conflated
        let initialDispatched = model.kernelStats.dispatched

        // Rapid setParam calls to trigger conflation (debounce is 60ms)
        model.setParam(id, "width", 25.0)
        model.setParam(id, "width", 30.0)
        model.setParam(id, "width", 35.0)

        // Await recomputes to settle
        try await Task.sleep(for: .milliseconds(250))
        await model.updateKernelStats()

        #expect(model.kernelStats.conflated > initialConflated)
        #expect(model.kernelStats.dispatched > initialDispatched)
    }

    @Test @MainActor func testToggleConsoleCyclesVisibility() {
        let model = WorkspaceModel()
        #expect(model.isConsoleVisible == false)

        model.toggleConsole()
        #expect(model.isConsoleVisible == true)

        model.toggleConsole()
        #expect(model.isConsoleVisible == false)
    }

    @Test @MainActor func testConsoleToggleTitlesAndShortcutConstants() {
        let model = WorkspaceModel()
        model.isConsoleVisible = false
        #expect(model.consoleToggleTitle == "Show Console")
        #expect(model.consoleToggleHelp == "Show Console (⇧⌘Y)")

        model.toggleConsole()
        #expect(model.consoleToggleTitle == "Hide Console")
        #expect(model.consoleToggleHelp == "Hide Console (⇧⌘Y)")

        #expect(WorkspaceModel.consoleShortcutKey == "y")
        #expect(WorkspaceModel.consoleShortcutModifiers == [.command, .shift])
    }

    // MARK: - Deletion Confirmation

    @Test @MainActor func testRequestDeleteObjectSetsPendingDeleteId() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        #expect(model.pendingDeleteId == nil)
        #expect(model.objectPendingDeletion == nil)

        model.requestDeleteObject(id)

        #expect(model.pendingDeleteId == id)
        #expect(model.objectPendingDeletion?.id == id)
        #expect(model.objectPendingDeletion?.name == "box-1")
    }

    @Test @MainActor func testCancelDeleteObjectClearsPendingAndPreservesSolidAndSelection() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        model.selectedId = id

        model.requestDeleteObject(id)
        #expect(model.pendingDeleteId == id)
        #expect(model.selectedId == id)

        model.cancelDeleteObject()

        #expect(model.pendingDeleteId == nil)
        #expect(model.objectPendingDeletion == nil)
        #expect(model.selectedId == id)
        #expect(model.document.objects.contains(where: { $0.id == id }))
    }

    @Test @MainActor func testConfirmDeleteObjectRemovesSolidAndClearsSelection() async {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        let unselectedId = ObjectId("cylinder-1")
        model.selectedId = id

        model.requestDeleteObject(id)
        #expect(model.pendingDeleteId == id)

        model.confirmDeleteObject()

        #expect(model.pendingDeleteId == nil)
        #expect(model.objectPendingDeletion == nil)
        #expect(model.selectedId == nil)
        #expect(!model.document.objects.contains(where: { $0.id == id }))

        // Confirming delete on an unselected solid preserves the selectedId
        model.addObject(.box(BoxParams(width: 20, depth: 20, height: 20)))
        guard let newBox = model.document.objects.first(where: { $0.id != unselectedId }) else {
            Issue.record("Failed to add temporary solid")
            return
        }
        model.selectedId = unselectedId
        model.requestDeleteObject(newBox.id)
        model.confirmDeleteObject()
        #expect(model.selectedId == unselectedId)
    }

    @Test @MainActor func testRequestDeleteLockedObjectIsRefused() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        model.document.setLocked(id: id, isLocked: true)

        model.requestDeleteObject(id)

        #expect(model.pendingDeleteId == nil)
        #expect(model.objectPendingDeletion == nil)
        #expect(model.document.objects.contains(where: { $0.id == id }))
    }

    @Test @MainActor func testTwoDeletesInARow() {
        let model = WorkspaceModel()
        let boxId = ObjectId("box-1")
        let cylinderId = ObjectId("cylinder-1")

        // Cancel first, delete second
        model.requestDeleteObject(boxId)
        #expect(model.pendingDeleteId == boxId)
        model.cancelDeleteObject()
        #expect(model.pendingDeleteId == nil)

        model.requestDeleteObject(cylinderId)
        #expect(model.pendingDeleteId == cylinderId)
        model.confirmDeleteObject()
        #expect(model.pendingDeleteId == nil)
        #expect(model.document.objects.contains(where: { $0.id == boxId }))
        #expect(!model.document.objects.contains(where: { $0.id == cylinderId }))

        // Retargeting while another delete is pending updates target cleanly
        model.addObject(.cylinder(CylinderParams(radius: 10, height: 20)))
        guard let newCylinder = model.document.objects.first(where: { $0.id != boxId }) else {
            Issue.record("Failed to add new cylinder")
            return
        }
        model.requestDeleteObject(boxId)
        #expect(model.pendingDeleteId == boxId)
        model.requestDeleteObject(newCylinder.id)
        #expect(model.pendingDeleteId == newCylinder.id)
        model.confirmDeleteObject()
        #expect(!model.document.objects.contains(where: { $0.id == newCylinder.id }))
        #expect(model.document.objects.contains(where: { $0.id == boxId }))

        // Second confirm removes the remaining solid
        model.requestDeleteObject(boxId)
        model.confirmDeleteObject()
        #expect(model.document.objects.isEmpty)
    }

    @Test @MainActor func testConfirmDeleteOnObjectDeletedExternallySafelyNoOps() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        model.requestDeleteObject(id)
        #expect(model.pendingDeleteId == id)

        // Object removed directly on document
        model.document.removeObject(id: id)
        #expect(!model.document.objects.contains(where: { $0.id == id }))

        // Confirming pending delete safely clears pendingDeleteId and no-ops
        model.confirmDeleteObject()
        #expect(model.pendingDeleteId == nil)
        #expect(model.objectPendingDeletion == nil)

        // Confirming when no delete is pending also safely no-ops
        model.confirmDeleteObject()
        #expect(model.pendingDeleteId == nil)
    }

    // MARK: - Menu Bar and Shortcuts (BL-MAC-04)

    @Test @MainActor func testAddDefaultSolids() {
        let model = WorkspaceModel()
        let initialCount = model.document.objects.count

        model.addDefaultBox()
        #expect(model.document.objects.count == initialCount + 1)
        guard let addedBox = model.selectedObject else {
            Issue.record("Expected newly added box to be selected")
            return
        }
        #expect(model.selectedId == addedBox.id)
        if case .box(let params) = addedBox.def {
            #expect(params == WorkspaceModel.defaultBoxParams)
            #expect(params.width == 30)
            #expect(params.depth == 30)
            #expect(params.height == 30)
        } else {
            Issue.record("Expected object def to be .box")
        }

        model.addDefaultCylinder()
        #expect(model.document.objects.count == initialCount + 2)
        guard let addedCylinder = model.selectedObject else {
            Issue.record("Expected newly added cylinder to be selected")
            return
        }
        #expect(model.selectedId == addedCylinder.id)
        if case .cylinder(let params) = addedCylinder.def {
            #expect(params == WorkspaceModel.defaultCylinderParams)
            #expect(params.radius == 12)
            #expect(params.height == 35)
        } else {
            Issue.record("Expected object def to be .cylinder")
        }

        model.addDefaultSphere()
        #expect(model.document.objects.count == initialCount + 3)
        guard let addedSphere = model.selectedObject else {
            Issue.record("Expected newly added sphere to be selected")
            return
        }
        #expect(model.selectedId == addedSphere.id)
        if case .sphere(let params) = addedSphere.def {
            #expect(params == WorkspaceModel.defaultSphereParams)
            #expect(params.radius == 15)
        } else {
            Issue.record("Expected object def to be .sphere")
        }

        model.addDefaultCone()
        #expect(model.document.objects.count == initialCount + 4)
        guard let addedCone = model.selectedObject else {
            Issue.record("Expected newly added cone to be selected")
            return
        }
        #expect(model.selectedId == addedCone.id)
        if case .cone(let params) = addedCone.def {
            #expect(params == WorkspaceModel.defaultConeParams)
            #expect(params.bottomRadius == 15)
            #expect(params.topRadius == 0)
            #expect(params.height == 30)
        } else {
            Issue.record("Expected object def to be .cone")
        }

        model.addDefaultTorus()
        #expect(model.document.objects.count == initialCount + 5)
        guard let addedTorus = model.selectedObject else {
            Issue.record("Expected newly added torus to be selected")
            return
        }
        #expect(model.selectedId == addedTorus.id)
        if case .torus(let params) = addedTorus.def {
            #expect(params == WorkspaceModel.defaultTorusParams)
            #expect(params.majorRadius == 20)
            #expect(params.minorRadius == 5)
        } else {
            Issue.record("Expected object def to be .torus")
        }

        model.addDefaultWedge()
        #expect(model.document.objects.count == initialCount + 6)
        guard let addedWedge = model.selectedObject else {
            Issue.record("Expected newly added wedge to be selected")
            return
        }
        #expect(model.selectedId == addedWedge.id)
        if case .wedge(let params) = addedWedge.def {
            #expect(params == WorkspaceModel.defaultWedgeParams)
            #expect(params.width == 30)
            #expect(params.depth == 30)
            #expect(params.height == 30)
            #expect(params.topWidth == 0)
        } else {
            Issue.record("Expected object def to be .wedge")
        }
    }

    @Test @MainActor func testImportStepFileAddsObjectAndRecomputes() throws {
        let model = WorkspaceModel()
        let initialCount = model.document.objects.count
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-part-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let dummyStepData = Data("ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('STEP AP214'),'1');\nFILE_NAME('test.step','2026-10-15',(''),(''),'','','');\nFILE_SCHEMA(('AUTOMOTIVE_DESIGN'));\nENDSEC;\nDATA;\nENDSEC;\nEND-ISO-10303-21;\n".utf8)
        try dummyStepData.write(to: tempURL)
        
        let importedId = model.importStepFile(at: tempURL)
        #expect(importedId != nil)
        #expect(model.document.objects.count == initialCount + 1)
        #expect(model.selectedId == importedId)
        
        guard let obj = model.selectedObject else {
            Issue.record("Expected imported object to be selected")
            return
        }
        #expect(obj.id == importedId)
        #expect(obj.name == tempURL.lastPathComponent)
        if case .imported(let name, let sourceURL, let data) = obj.def {
            #expect(name == tempURL.lastPathComponent)
            #expect(sourceURL == tempURL)
            #expect(data == dummyStepData)
        } else {
            Issue.record("Expected object def to be .imported")
        }
    }

    @Test @MainActor func testImportStepFileNonExistentURLReturnsNil() {
        let model = WorkspaceModel()
        let initialCount = model.document.objects.count
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non-existent-step-\(UUID().uuidString).step")
        
        let importedId = model.importStepFile(at: nonExistentURL)
        #expect(importedId == nil)
        #expect(model.document.objects.count == initialCount)
    }

    @Test @MainActor func testExportStepFileWritesFile() async throws {
        let model = WorkspaceModel()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-export-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let exported = await model.exportStepFile(to: tempURL, selectedOnly: false)
        #expect(exported)
        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        let contents = try String(contentsOf: tempURL, encoding: .utf8)
        #expect(contents.contains("ISO-10303-21"))
        #expect(contents.contains("HEADER;"))
        #expect(contents.contains("END-ISO-10303-21;"))
    }

    @Test @MainActor func testImportStepEmptyFileLeavesSceneUnchanged() throws {
        let model = WorkspaceModel()
        let initialCount = model.document.objects.count

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-empty-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try Data().write(to: tempURL)

        let resultId = model.importStepFile(at: tempURL)
        #expect(resultId == nil)
        #expect(model.document.objects.count == initialCount)
    }

    @Test @MainActor func testImportStepCorruptFileLeavesSceneUnchanged() async throws {
        let model = WorkspaceModel()
        let initialCount = model.document.objects.count

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-corrupt-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let corruptData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33])
        try corruptData.write(to: tempURL)

        let resultId = model.importStepFile(at: tempURL)
        #expect(resultId != nil)

        // Wait for recompute to fail with geometryFailed and roll back
        if let id = resultId, let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [id])
        }
        for _ in 0..<20 {
            if model.document.objects.count == initialCount { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(model.document.objects.count == initialCount)
        if let id = resultId {
            #expect(!model.document.objects.contains(where: { $0.id == id }))
        }
    }

    @Test @MainActor func testDeleteSelectedObjectAndEnablement() {
        let model = WorkspaceModel()
        let boxId = ObjectId("box-1")

        // 1. Unlocked object selected -> can delete, triggers pending delete
        model.selectedId = boxId
        #expect(model.canDeleteSelectedObject == true)
        #expect(model.pendingDeleteId == nil)
        model.deleteSelectedObject()
        #expect(model.pendingDeleteId == boxId)
        model.cancelDeleteObject()
        #expect(model.pendingDeleteId == nil)

        // 2. Locked object selected -> cannot delete, deleteSelectedObject no-ops
        model.document.setLocked(id: boxId, isLocked: true)
        #expect(model.canDeleteSelectedObject == false)
        model.deleteSelectedObject()
        #expect(model.pendingDeleteId == nil)

        // 3. No selection -> cannot delete, deleteSelectedObject no-ops
        model.selectedId = nil
        #expect(model.canDeleteSelectedObject == false)
        model.deleteSelectedObject()
        #expect(model.pendingDeleteId == nil)
    }

    @Test @MainActor func testToggleSelectedObjectVisibilityAndTitles() {
        let model = WorkspaceModel()
        let boxId = ObjectId("box-1")

        // No selection
        model.selectedId = nil
        #expect(model.hideToggleTitle == "Hide Solid")

        // Selected visible object
        model.selectedId = boxId
        #expect(model.selectedObject?.isVisible == true)
        #expect(model.hideToggleTitle == "Hide Solid")

        // Toggle to hidden
        model.toggleSelectedObjectVisibility()
        #expect(model.selectedObject?.isVisible == false)
        #expect(model.hideToggleTitle == "Show Solid")

        // Toggle back to visible
        model.toggleSelectedObjectVisibility()
        #expect(model.selectedObject?.isVisible == true)
        #expect(model.hideToggleTitle == "Hide Solid")
    }

    @Test @MainActor func testToggleSelectedObjectLockAndTitles() {
        let model = WorkspaceModel()
        let boxId = ObjectId("box-1")

        // No selection
        model.selectedId = nil
        #expect(model.lockToggleTitle == "Lock Solid")

        // Selected unlocked object
        model.selectedId = boxId
        #expect(model.selectedObject?.isLocked == false)
        #expect(model.lockToggleTitle == "Lock Solid")

        // Toggle to locked
        model.toggleSelectedObjectLock()
        #expect(model.selectedObject?.isLocked == true)
        #expect(model.lockToggleTitle == "Unlock Solid")

        // Toggle back to unlocked
        model.toggleSelectedObjectLock()
        #expect(model.selectedObject?.isLocked == false)
        #expect(model.lockToggleTitle == "Lock Solid")
    }

    @Test @MainActor func testSelectedPartIdAndReloadPart() {
        let model = WorkspaceModel()
        let boxId = ObjectId("box-1")

        // Primitive solid selected -> selectedPartId is nil, reload safely no-ops
        model.selectedId = boxId
        #expect(model.selectedPartId == nil)
        model.reloadSelectedPart()

        // No selection -> selectedPartId is nil, reload safely no-ops
        model.selectedId = nil
        #expect(model.selectedPartId == nil)
        model.reloadSelectedPart()

        // Part solid selected -> selectedPartId returns object id, reload runs
        let tempUrl = URL(fileURLWithPath: "/tmp/sample.part.ts")
        let partId = model.document.addPart(url: tempUrl)
        model.selectedId = partId
        #expect(model.selectedPartId == partId)
        model.reloadSelectedPart()
    }

    @Test @MainActor func testMCPServerToggleTitle() {
        let model = WorkspaceModel()

        model.isMCPServerRunning = false
        #expect(model.mcpServerToggleTitle == "Start MCP Server")

        model.isMCPServerRunning = true
        #expect(model.mcpServerToggleTitle == "Stop MCP Server")
    }

    @Test @MainActor func testMenuShortcutConstantsAndModifiers() {
        // Assert keys
        #expect(WorkspaceModel.undoShortcutKey == "z")
        #expect(WorkspaceModel.redoShortcutKey == "z")
        #expect(WorkspaceModel.deleteShortcutKey == .delete)
        #expect(WorkspaceModel.addBoxShortcutKey == "b")
        #expect(WorkspaceModel.addCylinderShortcutKey == "c")
        #expect(WorkspaceModel.hideSolidShortcutKey == "h")
        #expect(WorkspaceModel.lockSolidShortcutKey == "l")
        #expect(WorkspaceModel.reloadPartShortcutKey == "r")
        #expect(WorkspaceModel.zoomInShortcutKey == "=")
        #expect(WorkspaceModel.zoomOutShortcutKey == "-")
        #expect(WorkspaceModel.zoomToFitShortcutKey == "f")
        #expect(WorkspaceModel.resetViewShortcutKey == "0")
        #expect(WorkspaceModel.mcpServerShortcutKey == "m")
        #expect(WorkspaceModel.toolSelectShortcutKey == "1")
        #expect(WorkspaceModel.toolOrbitShortcutKey == "2")
        #expect(WorkspaceModel.toolPanShortcutKey == "3")
        #expect(WorkspaceModel.toolZoomShortcutKey == "4")
        #expect(WorkspaceModel.consoleShortcutKey == "y")
        #expect(WorkspaceModel.viewFrontShortcutKey == "1")
        #expect(WorkspaceModel.viewTopShortcutKey == "2")
        #expect(WorkspaceModel.viewRightShortcutKey == "3")
        #expect(WorkspaceModel.viewIsometricShortcutKey == "7")
        #expect(WorkspaceModel.viewNormalToShortcutKey == "8")
        #expect(WorkspaceModel.rollBackToSelectedShortcutKey == "[")
        #expect(WorkspaceModel.rollForwardToEndShortcutKey == "]")

        // Assert exact modifier combinations
        #expect(WorkspaceModel.undoShortcutModifiers == [.command])
        #expect(WorkspaceModel.redoShortcutModifiers == [.command, .shift])
        #expect(WorkspaceModel.deleteShortcutModifiers == [.command])
        #expect(WorkspaceModel.addBoxShortcutModifiers == [.command, .shift])
        #expect(WorkspaceModel.addCylinderShortcutModifiers == [.command, .shift])
        #expect(WorkspaceModel.hideSolidShortcutModifiers == [.command, .shift])
        #expect(WorkspaceModel.lockSolidShortcutModifiers == [.command, .shift])
        #expect(WorkspaceModel.reloadPartShortcutModifiers == [.control, .command])
        #expect(WorkspaceModel.zoomInShortcutModifiers == [.command])
        #expect(WorkspaceModel.zoomOutShortcutModifiers == [.command])
        #expect(WorkspaceModel.zoomToFitShortcutModifiers == [.command, .shift])
        #expect(WorkspaceModel.resetViewShortcutModifiers == [.command])
        #expect(WorkspaceModel.mcpServerShortcutModifiers == [.command, .shift])
        #expect(WorkspaceModel.toolShortcutModifiers == [.command, .option])
        #expect(WorkspaceModel.consoleShortcutModifiers == [.command, .shift])
        #expect(WorkspaceModel.viewShortcutModifiers == [.control])
        #expect(WorkspaceModel.rollBackToSelectedShortcutModifiers == [.command, .option])
        #expect(WorkspaceModel.rollForwardToEndShortcutModifiers == [.command, .option])

        // Verify Invariant 8: All menu shortcuts strictly include at least one modifier key (.command, .shift, .option, .control)
        // so they never collide with plain-key viewport tools (V, O, P, Z, F, H, =, -) or intercept text field editing.
        let allModifierSets: [EventModifiers] = [
            WorkspaceModel.undoShortcutModifiers,
            WorkspaceModel.redoShortcutModifiers,
            WorkspaceModel.deleteShortcutModifiers,
            WorkspaceModel.addBoxShortcutModifiers,
            WorkspaceModel.addCylinderShortcutModifiers,
            WorkspaceModel.hideSolidShortcutModifiers,
            WorkspaceModel.lockSolidShortcutModifiers,
            WorkspaceModel.reloadPartShortcutModifiers,
            WorkspaceModel.zoomInShortcutModifiers,
            WorkspaceModel.zoomOutShortcutModifiers,
            WorkspaceModel.zoomToFitShortcutModifiers,
            WorkspaceModel.resetViewShortcutModifiers,
            WorkspaceModel.mcpServerShortcutModifiers,
            WorkspaceModel.toolShortcutModifiers,
            WorkspaceModel.consoleShortcutModifiers,
            WorkspaceModel.viewShortcutModifiers,
            WorkspaceModel.rollBackToSelectedShortcutModifiers,
            WorkspaceModel.rollForwardToEndShortcutModifiers
        ]

        let standardModifiers: EventModifiers = [.command, .shift, .option, .control]
        for modifiers in allModifierSets {
            #expect(!modifiers.isEmpty)
            #expect(!modifiers.intersection(standardModifiers).isEmpty)
        }
    }

    @Test @MainActor func testCommandPanelPlacementPersistence() {
        let suiteName = "test.command.placement.\(UUID().uuidString)"
        guard let customDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        // Default placement is floatingHUD
        let model1 = WorkspaceModel(defaults: customDefaults)
        #expect(model1.commandPanelPlacement == .floatingHUD)

        // Change to inspector
        model1.commandPanelPlacement = .inspector
        #expect(customDefaults.string(forKey: WorkspaceModel.commandPanelPlacementDefaultsKey) == "Inspector")

        // New model with same defaults restores inspector placement
        let model2 = WorkspaceModel(defaults: customDefaults)
        #expect(model2.commandPanelPlacement == .inspector)

        // Switch back to floatingHUD
        model2.commandPanelPlacement = .floatingHUD
        #expect(customDefaults.string(forKey: WorkspaceModel.commandPanelPlacementDefaultsKey) == "Floating HUD")

        let model3 = WorkspaceModel(defaults: customDefaults)
        #expect(model3.commandPanelPlacement == .floatingHUD)
    }

    @Test @MainActor func testCommandLifecycleTransitions() {
        let model = WorkspaceModel()
        #expect(model.activeCommand == nil)

        var cancelCount = 0
        var commitCount = 0

        let cmd1 = CommandSession(
            title: "Cmd 1",
            onCommit: { commitCount += 1 },
            onCancel: { cancelCount += 1 }
        )

        model.startCommand(cmd1)
        #expect(model.activeCommand === cmd1)

        // Starting another command automatically cancels the active command
        let cmd2 = CommandSession(
            title: "Cmd 2",
            onCommit: { commitCount += 1 },
            onCancel: { cancelCount += 1 }
        )
        model.startCommand(cmd2)
        #expect(cancelCount == 1)
        #expect(model.activeCommand === cmd2)

        // cancelActiveCommand clears activeCommand and calls cancel
        model.cancelActiveCommand()
        #expect(cancelCount == 2)
        #expect(model.activeCommand == nil)

        // Calling cancelActiveCommand when nil safely no-ops
        model.cancelActiveCommand()
        #expect(cancelCount == 2)

        // startCommand and commitActiveCommand
        model.startCommand(cmd1)
        #expect(model.activeCommand === cmd1)
        model.commitActiveCommand()
        #expect(commitCount == 1)
        #expect(model.activeCommand == nil)
    }

    @Test @MainActor func testSelectObjectForActiveCommand() {
        let model = WorkspaceModel()
        let boxId = ObjectId("box-1")

        let cmd = CommandSession(
            title: "Slot Test",
            selectionSlots: [
                CommandSelectionSlot(id: "slot1", label: "Slot 1", isRequired: true, isActive: true)
            ]
        )
        model.startCommand(cmd)
        #expect(cmd.selectionSlots[0].selectedObjectId == nil)

        model.selectObjectForActiveCommand(boxId)
        #expect(cmd.selectionSlots[0].selectedObjectId == boxId)
        #expect(cmd.selectionSlots[0].selectedObjectName == "box-1")
    }

    @Test @MainActor func testCommandPanelTriggers() {
        let model = WorkspaceModel()

        #expect(model.activeCommand == nil)
        model.startAddBoxCommand()
        #expect(model.activeCommand?.title == "Add Box")

        model.startAddCylinderCommand()
        #expect(model.activeCommand?.title == "Add Cylinder")

        model.selectedId = ObjectId("box-1")
        model.startTransformCommand()
        #expect(model.activeCommand?.title == "Transform Solid")

        model.cancelActiveCommand()
        #expect(model.activeCommand == nil)
    }

    @Test @MainActor func testAlignNormalToWithSelectedSolidAndFlip() {
        let model = WorkspaceModel()
        model.setUp()
        let boxId = ObjectId("box-1")
        model.selectedId = boxId

        // Initial identity rotation -> transformed normal is worldUp +Z: (0, 0, 1)
        model.alignNormalTo()
        #expect(model.camera.target == model.selectedObject?.transform.position)
        #expect(model.camera.position.z > model.camera.target.z)
        let initialDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(initialDir.z > 0.99)

        // Second activation flips 180° to looking from -Z
        model.alignNormalTo()
        let flippedDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(flippedDir.z < -0.99)

        // Rotate object 90° around X axis (worldUp (0,0,1) rotates to (0, -1, 0))
        let rotX = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        model.setTransform(boxId, Transform(position: SIMD3<Float>(15, 25, 35), rotation: rotX))

        model.alignNormalTo()
        #expect(model.camera.target == SIMD3<Float>(15, 25, 35))
        let rotatedDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(abs(rotatedDir.x) < 1e-3)
        #expect(rotatedDir.y < -0.99) // Normal points along -Y
        #expect(abs(rotatedDir.z) < 1e-3)

        // Flip rotated normal
        model.alignNormalTo()
        let rotatedFlippedDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(rotatedFlippedDir.y > 0.99) // Normal flipped to +Y

        // Test unselected fallback to ground plane (0, 0, 1)
        model.selectedId = nil
        model.alignNormalTo()
        let groundDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(groundDir.z > 0.99)

        // Repeated unselected activation flips 180°
        model.alignNormalTo()
        let groundFlippedDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(groundFlippedDir.z < -0.99)
    }

    @Test @MainActor func testAlignNormalToWithSelectedFace() {
        let model = WorkspaceModel()
        model.setUp()
        let boxId = ObjectId("box-1")
        model.selectedId = boxId
        
        // Select face 0 (top face +Z, normal (0, 0, 1))
        model.document.selectedSubElement = SelectedSubElement(
            solidId: boxId,
            elementType: .face,
            elementId: 0
        )
        
        model.alignNormalTo()
        // Face 0 centroid for default box (40x30x20 at (-25, 0, 0)) -> (-25, 0, 10)
        let expectedCentroid = SIMD3<Float>(-25, 0, 10)
        #expect(abs(model.camera.target.x - expectedCentroid.x) < 1e-3)
        #expect(abs(model.camera.target.y - expectedCentroid.y) < 1e-3)
        #expect(abs(model.camera.target.z - expectedCentroid.z) < 1e-3)
        
        let viewDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(viewDir.z > 0.99)
        
        // Second activation flips 180°
        model.alignNormalTo()
        let flippedDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(flippedDir.z < -0.99)
        
        // Select face 2 (+X face, normal (1, 0, 0))
        model.document.selectedSubElement = SelectedSubElement(
            solidId: boxId,
            elementType: .face,
            elementId: 2
        )
        model.alignNormalTo()
        // Face 2 centroid for default box at (-25, 0, 0) with width 40 (half-width 20) -> (-25 + 20, 0, 0) = (-5, 0, 0)
        let expectedXCentroid = SIMD3<Float>(-5, 0, 0)
        #expect(abs(model.camera.target.x - expectedXCentroid.x) < 1e-3)
        #expect(abs(model.camera.target.y - expectedXCentroid.y) < 1e-3)
        #expect(abs(model.camera.target.z - expectedXCentroid.z) < 1e-3)
        let xDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(xDir.x > 0.99)
    }

    @Test @MainActor func testSnapCameraToFace() {
        let model = WorkspaceModel()
        model.setUp()
        let boxId = ObjectId("box-1")
        
        // Snap camera directly to face 0 (+Z top face)
        model.snapCameraToFace(solidId: boxId, faceId: 0)
        let expectedCentroid = SIMD3<Float>(-25, 0, 10)
        #expect(abs(model.camera.target.x - expectedCentroid.x) < 1e-3)
        #expect(abs(model.camera.target.y - expectedCentroid.y) < 1e-3)
        #expect(abs(model.camera.target.z - expectedCentroid.z) < 1e-3)
        
        let viewDir = simd_normalize(model.camera.position - model.camera.target)
        #expect(viewDir.z > 0.99)
        
        // Singular look-at protection: view matrix has valid finite numbers
        let lookAt = Orientation.makeLookAt(eye: model.camera.position, target: model.camera.target)
        #expect(!lookAt.columns.0.x.isNaN && !lookAt.columns.0.x.isInfinite)
        #expect(!lookAt.columns.3.w.isNaN && !lookAt.columns.3.w.isInfinite)
    }

    @Test @MainActor func testDoubleClickEmptySpaceDoesNothing() {
        let model = WorkspaceModel()
        model.setUp()
        
        let initialCamera = model.camera
        
        // When double-clicking empty space (non-existent solid or element), camera remains unchanged
        model.snapCameraToFace(solidId: SolidId("non-existent"), faceId: 0)
        #expect(model.camera.position == initialCamera.position)
        #expect(model.camera.target == initialCamera.target)
        
        // Animation cancellation test
        model.cancelCameraAnimation()
        #expect(model.camera.position == initialCamera.position)
    }

    @Test @MainActor func testApplyViewCubeRegion() {
        let model = WorkspaceModel()
        model.setUp()

        // Home region sets perspective view reset
        model.applyViewCubeRegion(.home)
        let resetCam = Camera.preset(.perspective)
        #expect(simd_length(model.camera.position - resetCam.position) <= 1e-2)

        // Face region sets orthogonal preset
        model.applyViewCubeRegion(.face(.top))
        #expect(model.perspective == .top)
        #expect(model.camera.position.z > model.camera.target.z)

        model.applyViewCubeRegion(.face(.front))
        #expect(model.perspective == .front)
        #expect(model.camera.position.y < model.camera.target.y)

        // Edge region
        model.applyViewCubeRegion(.edge(.top, .front))
        #expect(model.camera.position.z > model.camera.target.z)
        #expect(model.camera.position.y < model.camera.target.y)

        // Corner region
        model.applyViewCubeRegion(.corner(.top, .front, .right))
        #expect(model.camera.position.z > model.camera.target.z)
        #expect(model.camera.position.y < model.camera.target.y)
        #expect(model.camera.position.x > model.camera.target.x)
    }

    @Test @MainActor func testApplyViewCubeRegionWhenViewportUnavailable() {
        let model = WorkspaceModel()
        model.viewportManager.state = .unavailable(reason: .noDevice)
        model.viewportManager.renderer = nil

        // Home region sets perspective view reset even without renderer
        model.applyViewCubeRegion(.home)
        let resetCam = Camera.preset(.perspective)
        #expect(simd_length(model.camera.position - resetCam.position) <= 1e-2)

        // Face region sets orthogonal preset without renderer
        model.applyViewCubeRegion(.face(.top))
        #expect(model.perspective == .top)
        #expect(model.camera.position.z > model.camera.target.z)

        model.applyViewCubeRegion(.face(.front))
        #expect(model.perspective == .front)
        #expect(model.camera.position.y < model.camera.target.y)
    }

    @Test @MainActor func testAllSettingsUserDefaultsPersistenceRoundtrip() {
        let suiteName = "test.settings.all.\(UUID().uuidString)"
        guard let customDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        let model1 = WorkspaceModel(defaults: customDefaults)

        // Verify defaults
        #expect(model1.lengthUnit == .millimeters)
        #expect(model1.angleUnit == .degrees)
        #expect(model1.decimalPrecision == UnitSettings.defaultDecimalPrecision)
        #expect(model1.navigationPreset == .defaultPreset)
        #expect(model1.defaultProjection == .perspective)
        #expect(model1.defaultPerspective == .perspective)
        #expect(model1.showsGrid == true)
        #expect(model1.showsAxes == true)
        #expect(model1.showsGizmo == true)
        #expect(model1.showsEdges == true)
        #expect(model1.displayMode == .shadedWithEdges)
        #expect(model1.kernelTolerances == KernelTolerances.default)

        // Mutate all settings
        model1.lengthUnit = .inches
        model1.angleUnit = .radians
        model1.decimalPrecision = 4
        model1.navigationPreset = .solidWorks
        model1.defaultProjection = .orthographic
        model1.defaultPerspective = .top
        model1.showsGrid = false
        model1.showsAxes = false
        model1.showsGizmo = false
        model1.showsEdges = false
        model1.displayMode = .wireframe
        model1.kernelTolerances = KernelTolerances(linearTolerance: 0.005, angularTolerance: 0.5, chordalTolerance: 0.05)

        // Verify stored in customDefaults
        #expect(customDefaults.string(forKey: WorkspaceModel.lengthUnitDefaultsKey) == "in")
        #expect(customDefaults.string(forKey: WorkspaceModel.angleUnitDefaultsKey) == "rad")
        #expect(customDefaults.integer(forKey: WorkspaceModel.decimalPrecisionDefaultsKey) == 4)
        #expect(customDefaults.string(forKey: WorkspaceModel.navigationPresetDefaultsKey) == "SolidWorks")
        #expect(customDefaults.string(forKey: WorkspaceModel.defaultProjectionDefaultsKey) == "Orthographic")
        #expect(customDefaults.string(forKey: WorkspaceModel.defaultPerspectiveDefaultsKey) == "Top")
        #expect(customDefaults.bool(forKey: WorkspaceModel.showsGridDefaultsKey) == false)
        #expect(customDefaults.bool(forKey: WorkspaceModel.showsAxesDefaultsKey) == false)
        #expect(customDefaults.bool(forKey: WorkspaceModel.showsGizmoDefaultsKey) == false)
        #expect(customDefaults.bool(forKey: WorkspaceModel.showsEdgesDefaultsKey) == false)
        #expect(customDefaults.string(forKey: WorkspaceModel.displayModeDefaultsKey) == DisplayMode.wireframe.rawValue)
        #expect(customDefaults.double(forKey: WorkspaceModel.linearToleranceDefaultsKey) == 0.005)
        #expect(customDefaults.double(forKey: WorkspaceModel.angularToleranceDefaultsKey) == 0.5)
        #expect(customDefaults.double(forKey: WorkspaceModel.chordalToleranceDefaultsKey) == 0.05)

        // Restore into new WorkspaceModel instance
        let model2 = WorkspaceModel(defaults: customDefaults)
        #expect(model2.lengthUnit == .inches)
        #expect(model2.angleUnit == .radians)
        #expect(model2.decimalPrecision == 4)
        #expect(model2.navigationPreset == .solidWorks)
        #expect(model2.defaultProjection == .orthographic)
        #expect(model2.defaultPerspective == .top)
        #expect(model2.showsGrid == false)
        #expect(model2.showsAxes == false)
        #expect(model2.showsGizmo == false)
        #expect(model2.showsEdges == false)
        #expect(model2.displayMode == .wireframe)
        #expect(model2.kernelTolerances == KernelTolerances(linearTolerance: 0.005, angularTolerance: 0.5, chordalTolerance: 0.05))
    }

    @Test @MainActor func testResetSettingsToDefaults() {
        let suiteName = "test.settings.reset.\(UUID().uuidString)"
        guard let customDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        let model = WorkspaceModel(defaults: customDefaults)
        model.commandPanelPlacement = .inspector
        model.lengthUnit = .feet
        model.angleUnit = .radians
        model.decimalPrecision = 5
        model.navigationPreset = .fusion360
        model.defaultProjection = .orthographic
        model.defaultPerspective = .front
        model.showsGrid = false
        model.showsAxes = false
        model.showsGizmo = false
        model.showsEdges = false
        model.displayMode = .hiddenLineRemoved
        model.kernelTolerances = KernelTolerances(linearTolerance: 0.05, angularTolerance: 1.0, chordalTolerance: 0.1)

        // Reset
        model.resetSettingsToDefaults()

        #expect(model.commandPanelPlacement == .floatingHUD)
        #expect(model.lengthUnit == .millimeters)
        #expect(model.angleUnit == .degrees)
        #expect(model.decimalPrecision == UnitSettings.defaultDecimalPrecision)
        #expect(model.navigationPreset == .defaultPreset)
        #expect(model.defaultProjection == .perspective)
        #expect(model.defaultPerspective == .perspective)
        #expect(model.showsGrid == true)
        #expect(model.showsAxes == true)
        #expect(model.showsGizmo == true)
        #expect(model.showsEdges == true)
        #expect(model.displayMode == .shadedWithEdges)
        #expect(model.kernelTolerances == KernelTolerances.default)

        // Check fresh model picks up reset defaults
        let modelRestored = WorkspaceModel(defaults: customDefaults)
        #expect(modelRestored.commandPanelPlacement == .floatingHUD)
        #expect(modelRestored.lengthUnit == .millimeters)
        #expect(modelRestored.showsGrid == true)
        #expect(modelRestored.showsEdges == true)
        #expect(modelRestored.displayMode == .shadedWithEdges)
    }

    @Test @MainActor func testDisplayModePersistenceAndDefaults() {
        let suiteName = "test.display.mode.\(UUID().uuidString)"
        guard let customDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        let model = WorkspaceModel(defaults: customDefaults)
        #expect(model.displayMode == .shadedWithEdges)

        for mode in DisplayMode.allCases where mode != .shadedWithEdges {
            model.setDisplayMode(mode)
            #expect(model.displayMode == mode)
            #expect(customDefaults.string(forKey: WorkspaceModel.displayModeDefaultsKey) == mode.rawValue)

            let restored = WorkspaceModel(defaults: customDefaults)
            #expect(restored.displayMode == mode)
        }

        model.setDisplayMode(.shadedWithEdges)
        #expect(model.displayMode == .shadedWithEdges)
        #expect(customDefaults.string(forKey: WorkspaceModel.displayModeDefaultsKey) == DisplayMode.shadedWithEdges.rawValue)
        let restored = WorkspaceModel(defaults: customDefaults)
        #expect(restored.displayMode == .shadedWithEdges)
    }

    @Test @MainActor func testResetDisplaySettingsRestoresDisplayMode() {
        let suiteName = "test.display.reset.\(UUID().uuidString)"
        guard let customDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        let model = WorkspaceModel(defaults: customDefaults)
        model.setDisplayMode(.hiddenLinesVisible)
        model.showsEdges = false
        model.showsGrid = false
        #expect(model.displayMode == .hiddenLinesVisible)

        model.resetDisplaySettings()
        #expect(model.displayMode == .shadedWithEdges)
        #expect(model.showsEdges == true)
        #expect(model.showsGrid == true)
        #expect(customDefaults.string(forKey: WorkspaceModel.displayModeDefaultsKey) == DisplayMode.shadedWithEdges.rawValue)
    }

    @Test @MainActor func testResetTolerancesToDefaults() {
        let suiteName = "test.tolerances.reset.\(UUID().uuidString)"
        guard let customDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        let model = WorkspaceModel(defaults: customDefaults)
        model.kernelTolerances = KernelTolerances(linearTolerance: 0.02, angularTolerance: 2.5, chordalTolerance: 0.2)
        #expect(model.kernelTolerances != KernelTolerances.default)

        model.resetTolerancesToDefaults()
        #expect(model.kernelTolerances == KernelTolerances.default)
    }

    @Test @MainActor func testCorruptedUserDefaultsFallbackToDefaults() {
        let suiteName = "test.settings.corrupted.\(UUID().uuidString)"
        guard let customDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults suite")
            return
        }
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        // Populate corrupted values
        customDefaults.set("garbage_unit", forKey: WorkspaceModel.lengthUnitDefaultsKey)
        customDefaults.set("garbage_angle", forKey: WorkspaceModel.angleUnitDefaultsKey)
        customDefaults.set(999, forKey: WorkspaceModel.decimalPrecisionDefaultsKey)
        customDefaults.set("garbage_preset", forKey: WorkspaceModel.navigationPresetDefaultsKey)
        customDefaults.set("garbage_projection", forKey: WorkspaceModel.defaultProjectionDefaultsKey)
        customDefaults.set("garbage_perspective", forKey: WorkspaceModel.defaultPerspectiveDefaultsKey)
        customDefaults.set(-100.0, forKey: WorkspaceModel.linearToleranceDefaultsKey)
        customDefaults.set(Double.nan, forKey: WorkspaceModel.angularToleranceDefaultsKey)
        customDefaults.set(1000.0, forKey: WorkspaceModel.chordalToleranceDefaultsKey)

        let model = WorkspaceModel(defaults: customDefaults)
        #expect(model.lengthUnit == .millimeters)
        #expect(model.angleUnit == .degrees)
        #expect(model.decimalPrecision == UnitSettings.maxDecimalPrecision) // clamped to 6
        #expect(model.navigationPreset == .defaultPreset)
        #expect(model.defaultProjection == .perspective)
        #expect(model.defaultPerspective == .perspective)
        #expect(model.kernelTolerances.linearTolerance == KernelTolerances.minLinearTolerance) // clamped from -100
        #expect(model.kernelTolerances.angularTolerance == KernelTolerances.defaultAngularTolerance) // clamped from NaN
        #expect(model.kernelTolerances.chordalTolerance == KernelTolerances.maxChordalTolerance) // clamped from 1000
    }

    @Test @MainActor func testShortcutsCatalogCompleteness() {
        let model = WorkspaceModel()
        let shortcuts = model.shortcuts

        #expect(shortcuts.count == WorkspaceModel.standardShortcuts.count)
        #expect(shortcuts.count >= 20)

        // All categories represented
        let categories = Set(shortcuts.map(\.category))
        #expect(categories.contains(.tools))
        #expect(categories.contains(.navigation))
        #expect(categories.contains(.editing))
        #expect(categories.contains(.workspace))

        // All entries have non-empty fields
        for entry in shortcuts {
            #expect(!entry.id.isEmpty)
            #expect(!entry.title.isEmpty)
            #expect(!entry.shortcut.isEmpty)
            #expect(!entry.description.isEmpty)
        }

        #expect(shortcuts.contains(where: { $0.title == "Undo" && $0.shortcut == "⌘Z" }))
        #expect(shortcuts.contains(where: { $0.title == "Redo" && $0.shortcut == "⇧⌘Z" }))

        // Selection filter shortcuts (BL-SEL-06)
        #expect(shortcuts.contains(where: { $0.title == "Filter Faces" && $0.shortcut == "⌥F" }))
        #expect(shortcuts.contains(where: { $0.title == "Filter Edges" && $0.shortcut == "⌥E" }))
        #expect(shortcuts.contains(where: { $0.title == "Filter Vertices" && $0.shortcut == "⌥V" }))
        #expect(shortcuts.contains(where: { $0.title == "Filter Bodies" && $0.shortcut == "⌥B" }))
        #expect(shortcuts.contains(where: { $0.title == "Filter Sketch Entities" && $0.shortcut == "⌥S" }))
        #expect(shortcuts.contains(where: { $0.title == "Filter Components" && $0.shortcut == "⌥C" }))
        #expect(shortcuts.contains(where: { $0.title == "All Filters" && $0.shortcut == "⌥A" }))
    }

    @Test @MainActor func testSelectionFilterMutations() {
        let model = WorkspaceModel()
        #expect(model.selectionFilter == .all)

        // Toggle individual filter off
        model.toggleSelectionFilter(.faces, enabled: false)
        #expect(!model.selectionFilter.contains(.faces))
        #expect(model.selectionFilter.contains(.edges))

        // Toggle individual filter on
        model.toggleSelectionFilter(.faces, enabled: true)
        #expect(model.selectionFilter.contains(.faces))

        // Toggle without explicit boolean
        model.toggleSelectionFilter(.faces)
        #expect(!model.selectionFilter.contains(.faces))
        model.toggleSelectionFilter(.faces)
        #expect(model.selectionFilter.contains(.faces))

        // Empty set fallback to .all
        model.selectionFilter = [.faces]
        model.toggleSelectionFilter(.faces, enabled: false)
        #expect(model.selectionFilter == .all, "Empty filter set must automatically fall back to .all")

        // Isolate filter
        model.isolateSelectionFilter(.edges)
        #expect(model.selectionFilter == .edges)

        // Isolating again toggles back to .all
        model.isolateSelectionFilter(.edges)
        #expect(model.selectionFilter == .all)

        // Reset
        model.selectionFilter = [.vertices]
        model.resetSelectionFilters()
        #expect(model.selectionFilter == .all)

        // Verify static shortcut keys and modifiers
        #expect(WorkspaceModel.filterFaceShortcutKey == "f")
        #expect(WorkspaceModel.filterEdgeShortcutKey == "e")
        #expect(WorkspaceModel.filterVertexShortcutKey == "v")
        #expect(WorkspaceModel.filterBodyShortcutKey == "b")
        #expect(WorkspaceModel.filterSketchShortcutKey == "s")
        #expect(WorkspaceModel.filterComponentShortcutKey == "c")
        #expect(WorkspaceModel.filterAllShortcutKey == "a")
        #expect(WorkspaceModel.filterShortcutModifiers == [.option])
    }

    @Test @MainActor func testWorkspaceUndoRedoMenuCommands() {
        let model = WorkspaceModel()
        #expect(!model.canUndo)
        #expect(!model.canRedo)
        #expect(model.undoTitle == "Undo")
        #expect(model.redoTitle == "Redo")

        model.setParam(ObjectId("box-1"), "width", 60.0)
        #expect(model.canUndo)
        #expect(!model.canRedo)
        #expect(model.undoTitle == "Undo Change Width")

        model.undo()
        #expect(!model.canUndo)
        #expect(model.canRedo)
        #expect(model.redoTitle == "Redo Change Width")

        model.redo()
        #expect(model.canUndo)
        #expect(!model.canRedo)
        #expect(model.undoTitle == "Undo Change Width")
    }

    @Test @MainActor func testWorkspaceUndoRedoSelectiveRecompute() async throws {
        let model = WorkspaceModel()
        model.setUp()

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        // Settle initial setup recomputes
        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, cylId])
        }
        try await Task.sleep(for: .milliseconds(150))
        await model.updateKernelStats()
        let initialStats = await model.kernelClient.getStats()

        // Edit box-1 parameter
        model.setParam(boxId, "width", 55.0)

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, cylId])
        }
        try await Task.sleep(for: .milliseconds(150))
        await model.updateKernelStats()
        let afterEditStats = await model.kernelClient.getStats()
        #expect(afterEditStats.dispatched - initialStats.dispatched == 1)

        // Undo parameter edit: only box-1 should recompute
        model.undo()

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, cylId])
        }
        try await Task.sleep(for: .milliseconds(150))
        await model.updateKernelStats()
        let afterUndoStats = await model.kernelClient.getStats()
        #expect(afterUndoStats.dispatched - afterEditStats.dispatched == 1)
        #expect(afterUndoStats.completed - afterEditStats.completed == 1)

        // Redo parameter edit: only box-1 should recompute
        model.redo()

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, cylId])
        }
        try await Task.sleep(for: .milliseconds(150))
        await model.updateKernelStats()
        let afterRedoStats = await model.kernelClient.getStats()
        #expect(afterRedoStats.dispatched - afterUndoStats.dispatched == 1)
        #expect(afterRedoStats.completed - afterUndoStats.completed == 1)
    }

    @Test @MainActor func testWorkspaceUndoRedoTransformDoesNotDispatchKernel() async throws {
        let model = WorkspaceModel()
        model.setUp()

        let boxId = ObjectId("box-1")
        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId])
        }
        try await Task.sleep(for: .milliseconds(150))
        await model.updateKernelStats()
        let statsBefore = await model.kernelClient.getStats()

        var newTransform = Transform()
        newTransform.position = SIMD3<Float>(10, 20, 30)

        model.setTransform(boxId, newTransform)
        let statsAfterMove = await model.kernelClient.getStats()
        #expect(statsAfterMove.dispatched == statsBefore.dispatched)

        // Undo transform move
        model.undo()
        let statsAfterUndo = await model.kernelClient.getStats()
        #expect(statsAfterUndo.dispatched == statsBefore.dispatched)
        #expect(model.document.objects.first(where: { $0.id == boxId })?.transform != newTransform)

        // Redo transform move
        model.redo()
        let statsAfterRedo = await model.kernelClient.getStats()
        #expect(statsAfterRedo.dispatched == statsBefore.dispatched)
        #expect(model.document.objects.first(where: { $0.id == boxId })?.transform == newTransform)
    }

    @Test @MainActor func testEditingOperandParameterRecomputesDependentBooleanOnly() async throws {
        let model = WorkspaceModel()
        model.setUp()

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        // Add an independent box so we can verify it doesn't recompute
        let independentId = model.document.addObject(def: .box(BoxParams(width: 15, depth: 15, height: 15)))
        model.recomputeSolid(id: independentId)

        // Add a boolean object combining box-1 and cylinder-1
        let boolDef = ObjectDef.boolean(op: .subtract, solidA: boxId, solidB: cylId)
        let boolId = model.document.reserveId(for: boolDef)
        model.document.addObject(boolId, def: boolDef)
        model.recomputeSolid(id: boolId)

        // Settle initial recomputes
        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, cylId, independentId, boolId])
        }
        try await Task.sleep(for: .milliseconds(150))
        await model.updateKernelStats()
        let statsBefore = await model.kernelClient.getStats()

        // Edit box-1 parameter
        model.setParam(boxId, "width", 50.0)

        // Settle cascading recomputes
        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, boolId, independentId, cylId])
        }
        try await Task.sleep(for: .milliseconds(150))
        await model.updateKernelStats()
        let statsAfter = await model.kernelClient.getStats()

        // Exactly 2 dispatches should have occurred: boxId and boolId (not independentId or cylId)
        #expect(statsAfter.dispatched - statsBefore.dispatched == 2)
        #expect(statsAfter.completed - statsBefore.completed == 2)
    }

    @Test @MainActor func testRemovingOperandCausesDependentBooleanToFailWithUnknownSolid() async throws {
        let model = WorkspaceModel()
        model.setUp()

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        // Add a boolean object combining box-1 and cylinder-1
        let boolDef = ObjectDef.boolean(op: .subtract, solidA: boxId, solidB: cylId)
        let boolId = model.document.reserveId(for: boolDef)
        model.document.addObject(boolId, def: boolDef)
        model.recomputeSolid(id: boolId)

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, cylId, boolId])
        }
        try await Task.sleep(for: .milliseconds(150))

        // Remove cylinder-1
        await model.removeObject(cylId).value

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boolId])
        }

        var failureMsg = model.recomputeFailures.message(for: boolId)
        if failureMsg == nil {
            for _ in 0..<30 {
                try await Task.sleep(for: .milliseconds(100))
                if let msg = model.recomputeFailures.message(for: boolId) {
                    failureMsg = msg
                    break
                }
            }
        }

        // Dependent boolean should have failed with unknown-solid
        #expect(failureMsg != nil)
        #expect(failureMsg?.contains("unknown-solid") == true)
        #expect(failureMsg?.contains("Solid B 'cylinder-1' not found") == true)
    }

    @Test @MainActor func testRecomputeSolidFailureCascadesParentFailedToDependentBoolean() async throws {
        let model = WorkspaceModel()
        model.setUp()

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        // Add a boolean object combining box-1 and cylinder-1
        let boolDef = ObjectDef.boolean(op: .subtract, solidA: boxId, solidB: cylId)
        let boolId = model.document.reserveId(for: boolDef)
        model.document.addObject(boolId, def: boolDef)
        model.recomputeSolid(id: boolId)

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, cylId, boolId])
        }
        try await Task.sleep(for: .milliseconds(150))

        // Inject failure on next recompute of box-1
        await model.injectRecomputeFailure(code: .invalidParams)
        model.recomputeSolid(id: boxId)

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, boolId])
        }
        try await Task.sleep(for: .milliseconds(150))

        // Assert root box has errorState with invalid-params and .error severity
        let boxFeat = model.document.feature(for: boxId)
        #expect(boxFeat?.errorState?.code == "invalid-params")
        #expect(boxFeat?.errorState?.severity == .error)

        // Assert dependent boolean has parent-failed with .warning severity
        let boolFeat = model.document.feature(for: boolId)
        #expect(boolFeat?.errorState?.code == "parent-failed")
        #expect(boolFeat?.errorState?.message == "parent failed")
        #expect(boolFeat?.errorState?.severity == .warning)
    }

    @Test @MainActor func testRecomputeSolidRecoveryClearsParentFailedOnDependentBoolean() async throws {
        let model = WorkspaceModel()
        model.setUp()

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        // Add a boolean object combining box-1 and cylinder-1
        let boolDef = ObjectDef.boolean(op: .subtract, solidA: boxId, solidB: cylId)
        let boolId = model.document.reserveId(for: boolDef)
        model.document.addObject(boolId, def: boolDef)
        model.recomputeSolid(id: boolId)

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, cylId, boolId])
        }
        try await Task.sleep(for: .milliseconds(150))

        // Inject failure and fail box-1
        await model.injectRecomputeFailure(code: .invalidParams)
        model.recomputeSolid(id: boxId)

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, boolId])
        }
        try await Task.sleep(for: .milliseconds(150))

        #expect(model.document.feature(for: boolId)?.errorState?.code == "parent-failed")

        // Now recompute box-1 successfully without failure
        model.recomputeSolid(id: boxId)

        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId, boolId])
        }
        try await Task.sleep(for: .milliseconds(150))

        // Assert box-1 and boolId have both recovered and have nil errorState
        #expect(model.document.feature(for: boxId)?.errorState == nil)
        #expect(model.document.feature(for: boolId)?.errorState == nil)
    }

    @Test @MainActor func testWorkspaceRollBackAndRollForwardToEnd() {
        let model = WorkspaceModel()
        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        #expect(model.document.objects.count == 2)

        model.rollBack(to: 1)
        #expect(model.isRolledBack)
        #expect(model.document.rollbackIndex == 1)
        #expect(model.document.objects.count == 1)
        #expect(model.document.objects.first?.id == boxId)

        model.rollForwardToEnd()
        #expect(!model.isRolledBack)
        #expect(model.document.rollbackIndex == nil)
        #expect(model.document.objects.count == 2)
        #expect(model.document.objects.map(\.id) == [boxId, cylId])
    }

    @Test @MainActor func testWorkspacePackagePersistenceWithRollback() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("RollbackTest.made")

        let workspace = WorkspaceModel()
        #expect(workspace.document.features.count == 2)
        workspace.rollBack(to: 1)
        #expect(workspace.document.rollbackIndex == 1)
        #expect(workspace.document.objects.count == 1)

        let saveResult = workspace.saveDocument(to: packageURL)
        #expect(saveResult)

        let workspace2 = WorkspaceModel()
        let openResult = workspace2.openDocument(at: packageURL)
        #expect(openResult)
        #expect(workspace2.document.rollbackIndex == 1)
        #expect(workspace2.document.features.count == 2)
        #expect(workspace2.document.objects.count == 1)
        #expect(workspace2.isRolledBack)
    }

    // MARK: - Document Settings & UserDefaults Isolation Tests (BL-FND-11)

    @Test @MainActor func testOpenDocumentPreservesUserDefaultsSettings() throws {
        let suiteName = "com.made.test.isolation.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            testDefaults.removePersistentDomain(forName: suiteName)
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("CustomUnitsDoc.made")

        // Prepare a package with custom document settings (inches, radians, precision 4, custom tolerances)
        let customSettings = DocumentSettings(
            units: UnitSettings(lengthUnit: .inches, angleUnit: .radians, decimalPrecision: 4),
            tolerances: KernelTolerances(linearTolerance: 0.05, angularTolerance: 0.5, chordalTolerance: 0.05),
            defaultMaterial: MaterialAttributes(color: SIMD4<Float>(0.2, 0.4, 0.6, 1.0))
        )
        let manifest = MadeManifest(
            schemaVersion: MadeManifest.currentSchemaVersion,
            appVersion: "0.1",
            documentSettings: customSettings
        )
        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            objects: [
                SceneObject(id: ObjectId("box-1"), def: .box(BoxParams(width: 30, depth: 30, height: 30)))
            ]
        )
        let package = MadePackage(manifest: manifest, documentData: docData)
        try package.write(to: packageURL)

        // Initialize workspace with explicit global UserDefaults preferences (millimeters, degrees, precision 2)
        let model = WorkspaceModel(defaults: testDefaults)
        model.lengthUnit = .millimeters
        model.angleUnit = .degrees
        model.decimalPrecision = 2
        model.kernelTolerances = KernelTolerances.default

        #expect(testDefaults.string(forKey: WorkspaceModel.lengthUnitDefaultsKey) == LengthUnit.millimeters.rawValue)
        #expect(testDefaults.string(forKey: WorkspaceModel.angleUnitDefaultsKey) == AngleUnit.degrees.rawValue)
        #expect(testDefaults.integer(forKey: WorkspaceModel.decimalPrecisionDefaultsKey) == 2)

        // Open custom document
        let openResult = model.openDocument(at: packageURL)
        #expect(openResult)

        // Document model receives the document's settings
        #expect(model.document.settings.units.lengthUnit == .inches)
        #expect(model.document.settings.units.angleUnit == .radians)
        #expect(model.document.settings.units.decimalPrecision == 4)
        #expect(model.document.settings.tolerances.linearTolerance == 0.05)
        #expect(model.document.settings.defaultMaterial.color == SIMD4<Float>(0.2, 0.4, 0.6, 1.0))

        // Global UserDefaults preferences remain UNMODIFIED
        #expect(model.lengthUnit == .millimeters)
        #expect(model.angleUnit == .degrees)
        #expect(model.decimalPrecision == 2)
        #expect(testDefaults.string(forKey: WorkspaceModel.lengthUnitDefaultsKey) == LengthUnit.millimeters.rawValue)
        #expect(testDefaults.string(forKey: WorkspaceModel.angleUnitDefaultsKey) == AngleUnit.degrees.rawValue)
        #expect(testDefaults.integer(forKey: WorkspaceModel.decimalPrecisionDefaultsKey) == 2)
    }

    @Test @MainActor func testActiveDocumentSettingsMutators() {
        let model = WorkspaceModel()
        model.isDocumentModified = false

        let newUnits = UnitSettings(lengthUnit: .feet, angleUnit: .radians, decimalPrecision: 5)
        model.setDocumentUnits(newUnits)
        #expect(model.isDocumentModified)
        #expect(model.document.settings.units == newUnits)

        model.isDocumentModified = false
        let newTols = KernelTolerances(linearTolerance: 0.02, angularTolerance: 0.4, chordalTolerance: 0.02)
        model.setDocumentTolerances(newTols)
        #expect(model.isDocumentModified)
        #expect(model.document.settings.tolerances == newTols.clamped())

        model.isDocumentModified = false
        let newMat = MaterialAttributes(color: SIMD4<Float>(0.8, 0.1, 0.3, 1.0))
        model.setDocumentDefaultMaterial(newMat)
        #expect(model.isDocumentModified)
        #expect(model.document.settings.defaultMaterial == newMat)

        model.isDocumentModified = false
        let allSettings = DocumentSettings(
            units: UnitSettings(lengthUnit: .meters, angleUnit: .degrees, decimalPrecision: 3),
            tolerances: KernelTolerances(linearTolerance: 0.01, angularTolerance: 0.2, chordalTolerance: 0.01),
            defaultMaterial: MaterialAttributes(color: SIMD4<Float>(0.1, 0.2, 0.3, 1.0))
        )
        model.setDocumentSettings(allSettings)
        #expect(model.isDocumentModified)
        #expect(model.document.settings == allSettings)
    }

    // MARK: - Feature & Body Mutators and Hidden Solid Synchronization (BL-FND-13, #240)

    @Test @MainActor func testWorkspaceFeatureAndBodyMutators() {
        let model = WorkspaceModel()
        let boxId = ObjectId("box-1")
        let boxFeat = model.document.features[0]
        let boxFeatId = boxFeat.id

        model.selectedId = boxId
        #expect(model.selectedBody?.name == "box-1")
        #expect(model.selectedFeature?.name == "box-1")

        // Feature mutators
        model.setFeatureName(id: boxFeatId, name: "Workspace Box Feat")
        #expect(model.selectedFeature?.name == "Workspace Box Feat")
        #expect(model.isDocumentModified)

        model.isDocumentModified = false
        model.setFeatureVisibility(id: boxFeatId, isVisible: false)
        #expect(model.selectedFeature?.isVisible == false)
        #expect(model.isDocumentModified)

        model.toggleFeatureVisibility(boxFeatId)
        #expect(model.selectedFeature?.isVisible == true)

        // Body mutators
        model.isDocumentModified = false
        model.setBodyName(id: boxId, name: "Workspace Box Body")
        #expect(model.selectedBody?.name == "Workspace Box Body")
        #expect(model.isDocumentModified)

        model.isDocumentModified = false
        model.setBodyVisibility(id: boxId, isVisible: false)
        #expect(model.selectedBody?.isVisible == false)
        #expect(model.isDocumentModified)

        model.toggleBodyVisibility(boxId)
        #expect(model.selectedBody?.isVisible == true)
    }

    @Test @MainActor func testWorkspaceUndoRedoSyncsHiddenSolidIds() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        let boxId = ObjectId("box-1")
        #expect(!renderer.hiddenSolidIds.contains(boxId))

        // Hide solid via body mutator
        model.setBodyVisibility(id: boxId, isVisible: false)
        #expect(renderer.hiddenSolidIds.contains(boxId))
        #expect(model.document.body(for: boxId)?.isVisible == false)

        // Undo
        model.undo()
        #expect(!renderer.hiddenSolidIds.contains(boxId))
        #expect(model.document.body(for: boxId)?.isVisible == true)

        // Redo
        model.redo()
        #expect(renderer.hiddenSolidIds.contains(boxId))
        #expect(model.document.body(for: boxId)?.isVisible == false)
    }

    @Test @MainActor func testWorkspaceSelectionTracksDocumentSelection() {
        let model = WorkspaceModel()
        model.setUp()

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        #expect(model.selectedId == boxId)
        #expect(model.selectedObject?.id == boxId)
        #expect(model.selectedBody?.id == boxId)
        #expect(model.selectedFeature?.outputSolidId == boxId)

        // Select cylinder via document
        model.document.select(solidId: cylId)
        #expect(model.document.selection.count == 2)
        #expect(model.selectedId == boxId)

        // Clear selection via document
        model.document.clearSelection()
        #expect(model.selectedId == nil)
        #expect(model.selectedObject == nil)
        #expect(model.selectedBody == nil)
        #expect(model.selectedFeature == nil)

        // Set selectedId via workspace wrapper
        model.selectedId = cylId
        #expect(model.document.selection == [Reference.body(cylId)])
        #expect(model.selectedObject?.id == cylId)
        #expect(model.selectedBody?.id == cylId)
        #expect(model.selectedFeature?.outputSolidId == cylId)
    }

    // MARK: - Tree & Viewport Selection Sync (BL-SEL-10 / #342)

    @Test @MainActor func testTreeSelectionUpdatesViewportRendererAndInvalidates() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        RenderInstrumentation.shared.reset()
        let cylId = ObjectId("cylinder-1")
        model.selectedId = cylId

        #expect(renderer.selectedId == SolidId("cylinder-1"))
        #expect(RenderInstrumentation.shared.lastReason == .interaction)
    }

    @Test @MainActor func testTreeSelectionClearsSubElementHighlightInViewport() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        // Set a sub-element on box-1 in renderer and document
        let sub = SelectedSubElement(solidId: boxId, elementType: .face, elementId: 3)
        model.document.selectedSubElement = sub
        renderer.selectedSubElement = sub
        #expect(renderer.selectedSubElement != nil)

        // Switch selection to cylinder-1 via tree
        RenderInstrumentation.shared.reset()
        model.selectedId = cylId

        #expect(model.selectedId == cylId)
        #expect(renderer.selectedId == SolidId("cylinder-1"))
        #expect(model.document.selectedSubElement == nil)
        #expect(renderer.selectedSubElement == nil)
        #expect(RenderInstrumentation.shared.lastReason == .interaction)
    }

    @Test @MainActor func testTreeSelectionNoOpDoesNotInvalidateViewport() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        let boxId = ObjectId("box-1")
        #expect(model.selectedId == boxId)
        #expect(renderer.selectedId == boxId)

        // Reset instrumentation
        RenderInstrumentation.shared.reset()

        // Re-selecting the identical active solid should be a no-op (Invariant 2)
        model.selectedId = boxId

        #expect(RenderInstrumentation.shared.lastReason == nil, "No-op selection change must not invalidate (Invariant 2)")
    }

    @Test @MainActor func testTreeSelectionLockedObjectHidesGizmo() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        // Lock cylinder
        model.document.setLocked(id: cylId, isLocked: true)

        // Select box (unlocked) -> showsGizmo should be true
        model.selectedId = boxId
        #expect(renderer.selectedId == boxId)
        #expect(renderer.showsGizmo == true)

        // Select locked cylinder -> showsGizmo should become false, but selectedId is cylinder-1
        RenderInstrumentation.shared.reset()
        model.selectedId = cylId
        #expect(renderer.selectedId == cylId)
        #expect(renderer.showsGizmo == false)
        #expect(RenderInstrumentation.shared.lastReason == .interaction)
    }

    @Test @MainActor func testWorkspaceSetUpInitializesRendererSelection() {
        let model = WorkspaceModel()
        #expect(model.selectedId == ObjectId("box-1"))
        model.setUp()

        guard let renderer = model.viewportManager.renderer else { return }
        #expect(renderer.selectedId == SolidId("box-1"))
        #expect(renderer.showsGizmo == true)
        #expect(renderer.selectedSubElement == nil)
    }

    @Test @MainActor func testClearingTreeSelectionClearsViewportRenderer() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        #expect(renderer.selectedId == SolidId("box-1"))

        RenderInstrumentation.shared.reset()
        model.selectedId = nil

        #expect(renderer.selectedId == nil)
        #expect(renderer.selectedSubElement == nil)
        #expect(renderer.showsGizmo == true)
        #expect(RenderInstrumentation.shared.lastReason == .interaction)
    }

    @Test @MainActor func testSketchDOFStatusMutations() {
        let model = WorkspaceModel()
        #expect(model.sketchDOFStatus == .inactive)

        model.setSketchDOFStatus(.underConstrained(dof: 4))
        #expect(model.sketchDOFStatus == .underConstrained(dof: 4))

        model.setSketchDOFStatus(.fullyConstrained)
        #expect(model.sketchDOFStatus == .fullyConstrained)

        model.setSketchDOFStatus(.overConstrained())
        #expect(model.sketchDOFStatus == .overConstrained(dof: 0))

        model.setSketchDOFStatus(.inactive)
        #expect(model.sketchDOFStatus == .inactive)
    }

    @Test @MainActor func testRegenerationDurationRecordedOnRecompute() async throws {
        let model = WorkspaceModel()
        let boxId = ObjectId("box-1")
        #expect(model.lastRegenerationDuration == nil)

        model.recomputeSolid(id: boxId)
        if let registry = model.toolRegistry {
            await registry.settleRecomputes(for: [boxId])
        }

        // Wait briefly for the asynchronous recomputation Task to complete
        for _ in 0..<50 {
            if model.lastRegenerationDuration != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        guard let duration = model.lastRegenerationDuration else {
            Issue.record("Expected lastRegenerationDuration to be recorded after recomputeSolid")
            return
        }
        #expect(duration >= Duration.zero)
        #expect(model.formattedRegenerationDuration != "--")
    }

    // MARK: - Multi-Selection Tests (#552 / DOC-10)

    @Test @MainActor func testWorkspaceSelectedIdsUpdatesRendererAndSuppressesGizmo() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        #expect(renderer.selectedIds == [boxId])
        #expect(renderer.showsGizmo == true)

        RenderInstrumentation.shared.reset()
        model.selectedIds = [boxId, cylId]

        #expect(model.selectedIds == [boxId, cylId])
        #expect(model.document.selection.count == 2)
        #expect(renderer.selectedIds == [boxId, cylId])
        #expect(renderer.showsGizmo == false, "Gizmo must be suppressed when selectedIds.count > 1")
        #expect(RenderInstrumentation.shared.lastReason == .interaction)

        // Drop back to single selection -> gizmo is restored
        RenderInstrumentation.shared.reset()
        model.selectedIds = [boxId]

        #expect(model.selectedIds == [boxId])
        #expect(renderer.selectedIds == [boxId])
        #expect(renderer.showsGizmo == true)
        #expect(RenderInstrumentation.shared.lastReason == .interaction)
    }

    @Test @MainActor func testWorkspaceClearSelectionClearsRendererAndDocument() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")
        model.selectedIds = [boxId, cylId]

        #expect(!model.document.selection.isEmpty)
        #expect(!renderer.selectedIds.isEmpty)

        RenderInstrumentation.shared.reset()
        model.clearSelection()

        #expect(model.document.selection.isEmpty)
        #expect(model.selectedIds.isEmpty)
        #expect(model.selectedId == nil)
        #expect(renderer.selectedIds.isEmpty)
        #expect(renderer.selectedId == nil)
        #expect(renderer.showsGizmo == true)
        #expect(RenderInstrumentation.shared.lastReason == .interaction)
    }

    @Test @MainActor func testWorkspaceSelectAndToggleSelection() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        let boxId = ObjectId("box-1")
        let cylId = ObjectId("cylinder-1")

        #expect(model.selectedIds == [boxId])

        // select cylId
        model.select(solidId: cylId)
        #expect(model.selectedIds == [boxId, cylId])
        #expect(renderer.selectedIds == [boxId, cylId])
        #expect(renderer.showsGizmo == false)

        // toggleSelection boxId off
        model.toggleSelection(solidId: boxId)
        #expect(model.selectedIds == [cylId])
        #expect(renderer.selectedIds == [cylId])
        #expect(renderer.showsGizmo == true)

        // toggleSelection boxId on
        model.toggleSelection(solidId: boxId)
        #expect(model.selectedIds == [boxId, cylId])
        #expect(renderer.selectedIds == [boxId, cylId])
        #expect(renderer.showsGizmo == false)
    }

    @Test @MainActor func testWorkspaceBodyLockingAndColorMutators() {
        let model = WorkspaceModel()
        model.setUp()

        let boxId = ObjectId("box-1")
        #expect(model.document.body(for: boxId)?.isLocked == false)

        // Lock body via toggle
        model.toggleBodyLocked(boxId)
        #expect(model.document.body(for: boxId)?.isLocked == true)

        // Attempting to rename locked body is rejected
        let originalName = model.document.body(for: boxId)?.name ?? ""
        model.setBodyName(id: boxId, name: "BlockedRename")
        #expect(model.document.body(for: boxId)?.name == originalName)

        // Attempting to recolor locked body is rejected
        let originalColor = model.document.body(for: boxId)?.color ?? SIMD4<Float>(0, 0, 0, 0)
        let blockedColor = SIMD4<Float>(0.9, 0.2, 0.1, 1.0)
        model.setBodyColor(id: boxId, color: blockedColor)
        #expect(model.document.body(for: boxId)?.color == originalColor)

        // Unlock body via setBodyLocked
        model.setBodyLocked(id: boxId, isLocked: false)
        #expect(model.document.body(for: boxId)?.isLocked == false)

        // Rename succeeds
        model.setBodyName(id: boxId, name: "RenamedBox")
        #expect(model.document.body(for: boxId)?.name == "RenamedBox")

        // Whitespace-only name is rejected
        model.setBodyName(id: boxId, name: "   \n")
        #expect(model.document.body(for: boxId)?.name == "RenamedBox")

        // Recolor succeeds
        let newColor = SIMD4<Float>(0.1, 0.8, 0.3, 1.0)
        model.setBodyColor(id: boxId, color: newColor)
        #expect(model.document.body(for: boxId)?.color == newColor)
    }

    @Test @MainActor func testWorkspaceUndoRedoSyncsMaterials() {
        let model = WorkspaceModel()
        model.setUp()
        guard let renderer = model.viewportManager.renderer else { return }

        let boxId = ObjectId("box-1")
        let payload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 20, depth: 20, height: 20))
        let initialColor = model.document.body(for: boxId)?.color ?? SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
        _ = renderer.installMesh(payload, for: boxId, transform: .identity, color: initialColor, isHidden: false)
        #expect(renderer.meshes[boxId]?.color == initialColor)

        // Recolor via setBodyColor
        let newColor = SIMD4<Float>(1.0, 0.5, 0.2, 1.0)
        model.setBodyColor(id: boxId, color: newColor)
        #expect(model.document.body(for: boxId)?.color == newColor)
        #expect(renderer.meshes[boxId]?.color == newColor)

        // Undo recolor
        model.undo()
        #expect(model.document.body(for: boxId)?.color == initialColor)
        #expect(renderer.meshes[boxId]?.color == initialColor)

        // Redo recolor
        model.redo()
        #expect(model.document.body(for: boxId)?.color == newColor)
        #expect(renderer.meshes[boxId]?.color == newColor)
    }
}


