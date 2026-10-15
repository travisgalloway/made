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
        RenderInstrumentation.shared.reset()
        RenderInstrumentation.shared.recordRender(drawCalls: 7)
        RenderInstrumentation.shared.recordInvalidation(reason: .camera)

        _ = await model.kernelClient.request(.makeBox(jobId: JobId("telemetry-read-box"), solidId: SolidId("t-box"), params: BoxParams(width: 10, depth: 10, height: 10)))
        await model.updateKernelStats()
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

        RenderInstrumentation.shared.reset()
        RenderInstrumentation.shared.recordRender(drawCalls: 4)
        RenderInstrumentation.shared.recordInvalidation(reason: .model)
        _ = await model.kernelClient.request(.makeBox(jobId: JobId("drawer-hidden-box"), solidId: SolidId("dh-box"), params: BoxParams(width: 12, depth: 12, height: 12)))

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

        // Assert exact modifier combinations
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

        // Verify Invariant 8: All menu shortcuts strictly include at least one modifier key (.command, .shift, .option, .control)
        // so they never collide with plain-key viewport tools (V, O, P, Z, F, H, =, -) or intercept text field editing.
        let allModifierSets: [EventModifiers] = [
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
            WorkspaceModel.viewShortcutModifiers
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
        #expect(model.kernelTolerances == KernelTolerances.default)

        // Check fresh model picks up reset defaults
        let modelRestored = WorkspaceModel(defaults: customDefaults)
        #expect(modelRestored.commandPanelPlacement == .floatingHUD)
        #expect(modelRestored.lengthUnit == .millimeters)
        #expect(modelRestored.showsGrid == true)
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
    }
}
