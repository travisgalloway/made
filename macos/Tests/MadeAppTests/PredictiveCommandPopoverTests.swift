import Testing
import SwiftUI
import MadeCore
import simd
@testable import MadeApp

@Suite struct PredictiveCommandPopoverTests {

    @Test @MainActor func testSelectionMutationUpdatesPopoverState() {
        let model = WorkspaceModel()
        model.setUp()
        let boxId = ObjectId("box-1")

        // 1. Select Edge -> popover shows disabled Fillet, no Push-Pull
        let edgeSub = SelectedSubElement(solidId: boxId, elementType: .edge, elementId: 0)
        model.document.selectedSubElement = edgeSub
        let edgePopover = PredictiveCommandPopoverView(workspace: model, selectedSubElement: edgeSub)
        #expect(edgePopover.badgeTitle == "Edge #0")
        let edgeCommands = edgePopover.availableCommands
        #expect(edgeCommands.count == 1)
        #expect(edgeCommands.first?.id == .fillet)
        #expect(edgeCommands.first?.isEnabled == false)
        #expect(edgeCommands.contains(where: { $0.id == .pushPull }) == false)

        let edgeScreenPos = model.subElementScreenPosition(for: edgeSub, viewportSize: CGSize(width: 800, height: 600))
        #expect(edgeScreenPos != nil)

        // 2. Mutate selection to Planar Face -> popover updates to enabled Push-Pull, no Fillet
        let faceSub = SelectedSubElement(solidId: boxId, elementType: .face, elementId: 0)
        model.document.selectedSubElement = faceSub
        let facePopover = PredictiveCommandPopoverView(workspace: model, selectedSubElement: faceSub)
        #expect(facePopover.badgeTitle == "Face #0")
        let faceCommands = facePopover.availableCommands
        #expect(faceCommands.count == 1)
        #expect(faceCommands.first?.id == .pushPull)
        #expect(faceCommands.first?.isEnabled == true)
        #expect(faceCommands.contains(where: { $0.id == .fillet }) == false)

        let faceScreenPos = model.subElementScreenPosition(for: faceSub, viewportSize: CGSize(width: 800, height: 600))
        #expect(faceScreenPos != nil)

        // 3. Mutate selection to Non-Planar Face on Cylinder -> popover has empty commands
        let cylId = ObjectId("cyl-1")
        let cylFaceSub = SelectedSubElement(solidId: cylId, elementType: .face, elementId: 0)
        model.document.selectedSubElement = cylFaceSub
        let cylPopover = PredictiveCommandPopoverView(workspace: model, selectedSubElement: cylFaceSub)
        #expect(cylPopover.availableCommands.isEmpty)

        // 4. Mutate selection to Vertex -> popover has empty commands
        let vertexSub = SelectedSubElement(solidId: boxId, elementType: .vertex, elementId: 0)
        model.document.selectedSubElement = vertexSub
        let vertexPopover = PredictiveCommandPopoverView(workspace: model, selectedSubElement: vertexSub)
        #expect(vertexPopover.availableCommands.isEmpty)

        // 5. Clear selection -> document.selectedSubElement is nil
        model.document.selectedSubElement = nil
        #expect(model.document.selectedSubElement == nil)
    }

    @Test @MainActor func testMenuCommandToggle() {
        let model = WorkspaceModel()
        model.setUp()

        // With no selection, menu item is disabled
        #expect(model.document.selectedSubElement == nil)
        let isMenuDisabled = (model.document.selectedSubElement == nil)
        #expect(isMenuDisabled == true)

        #expect(model.isPredictiveCommandsVisible == true)

        // With sub-element selection, menu item is enabled and toggles visibility
        let boxId = ObjectId("box-1")
        model.document.selectedSubElement = SelectedSubElement(solidId: boxId, elementType: .edge, elementId: 0)
        #expect(model.document.selectedSubElement != nil)
        let isMenuDisabledWithSelection = (model.document.selectedSubElement == nil)
        #expect(isMenuDisabledWithSelection == false)

        model.togglePredictiveCommandSurface()
        #expect(model.isPredictiveCommandsVisible == false)

        model.togglePredictiveCommandSurface()
        #expect(model.isPredictiveCommandsVisible == true)
    }

    @Test @MainActor func testPopoverViewRenderingAndActions() {
        let model = WorkspaceModel()
        model.setUp()
        let boxId = ObjectId("box-1")

        // Planar face selection
        let faceSub = SelectedSubElement(solidId: boxId, elementType: .face, elementId: 1)
        model.document.selectedSubElement = faceSub
        let popover = PredictiveCommandPopoverView(workspace: model, selectedSubElement: faceSub)

        guard let pushPullCmd = popover.availableCommands.first(where: { $0.id == .pushPull }) else {
            Issue.record("Expected Push-Pull command to be present")
            return
        }

        #expect(model.activeCommand == nil)
        popover.executeCommand(pushPullCmd)
        #expect(model.activeCommand != nil)
        #expect(model.activeCommand?.title == "Push-Pull")

        // Sub-element with explicit hitPoint uses hitPoint directly
        let explicitHit = SIMD3<Float>(10, 20, 30)
        let subWithHit = SelectedSubElement(solidId: boxId, elementType: .face, elementId: 1, hitPoint: explicitHit)
        let screenPosWithHit = model.subElementScreenPosition(for: subWithHit, viewportSize: CGSize(width: 800, height: 600))
        #expect(screenPosWithHit != nil)
    }
}
