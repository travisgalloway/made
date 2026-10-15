import Testing
import SwiftUI
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct EmptyStatesTests {
    @Test @MainActor func testEmptyDocumentDetectionAndCreationTransitions() {
        let workspace = WorkspaceModel()
        for obj in workspace.document.objects {
            workspace.removeObject(obj.id)
        }
        workspace.selectedId = nil

        #expect(workspace.document.objects.isEmpty)
        #expect(workspace.selectedObject == nil)

        // Adding default box transitions document out of empty state
        workspace.addDefaultBox()
        #expect(!workspace.document.objects.isEmpty)
        #expect(workspace.document.objects.count == 1)
        #expect(workspace.selectedId != nil)
        #expect(workspace.selectedObject?.name == "box-2")

        // Requesting and confirming deletion restores empty state
        if let id = workspace.selectedId {
            workspace.requestDeleteObject(id)
            workspace.confirmDeleteObject()
        }
        #expect(workspace.document.objects.isEmpty)
        #expect(workspace.selectedObject == nil)
    }

    @Test @MainActor func testAddDefaultCylinderTransition() {
        let workspace = WorkspaceModel()
        for obj in workspace.document.objects {
            workspace.removeObject(obj.id)
        }
        workspace.selectedId = nil
        #expect(workspace.document.objects.isEmpty)

        // Adding default cylinder transitions document out of empty state
        workspace.addDefaultCylinder()
        #expect(!workspace.document.objects.isEmpty)
        #expect(workspace.document.objects.count == 1)
        #expect(workspace.selectedId != nil)
        guard let obj = workspace.selectedObject else {
            Issue.record("Expected selectedObject after adding cylinder")
            return
        }
        #expect(obj.name == "cylinder-2")
        if case .cylinder(let params) = obj.def {
            #expect(params.radius == WorkspaceModel.defaultCylinderParams.radius)
            #expect(params.height == WorkspaceModel.defaultCylinderParams.height)
        } else {
            Issue.record("Expected cylinder definition")
        }
    }

    @Test @MainActor func testSelectionStateTransitions() {
        let workspace = WorkspaceModel()
        #expect(!workspace.document.objects.isEmpty)

        // Clear selection while objects remain present
        workspace.selectedId = nil
        #expect(!workspace.document.objects.isEmpty)
        #expect(workspace.selectedObject == nil)

        // Select the first object
        if let first = workspace.document.objects.first {
            workspace.selectedId = first.id
            #expect(workspace.selectedObject?.id == first.id)
        }
    }

    @Test @MainActor func testConsoleDrawerLogFiltering() {
        let workspace = WorkspaceModel()
        #expect(!workspace.logs.isEmpty)

        let initialCount = workspace.logs.count
        workspace.log(.info, "TestSubsystem", "Sample message for filtering")
        #expect(workspace.logs.count == initialCount + 1)

        // Filter matching message
        let matchMessage = workspace.logs.filter {
            $0.message.localizedCaseInsensitiveContains("Sample message")
                || $0.subsystem.localizedCaseInsensitiveContains("Sample message")
                || $0.level.rawValue.localizedCaseInsensitiveContains("Sample message")
        }
        #expect(matchMessage.count == 1)

        // Filter matching subsystem
        let matchSubsystem = workspace.logs.filter {
            $0.message.localizedCaseInsensitiveContains("TestSubsystem")
                || $0.subsystem.localizedCaseInsensitiveContains("TestSubsystem")
                || $0.level.rawValue.localizedCaseInsensitiveContains("TestSubsystem")
        }
        #expect(matchSubsystem.count == 1)

        // Filter matching level
        let matchLevel = workspace.logs.filter {
            $0.message.localizedCaseInsensitiveContains("info")
                || $0.subsystem.localizedCaseInsensitiveContains("info")
                || $0.level.rawValue.localizedCaseInsensitiveContains("info")
        }
        #expect(matchLevel.count >= 1)

        // Filter matching nothing yielding empty list
        let noMatch = workspace.logs.filter {
            $0.message.localizedCaseInsensitiveContains("NonexistentQuery123456789")
                || $0.subsystem.localizedCaseInsensitiveContains("NonexistentQuery123456789")
                || $0.level.rawValue.localizedCaseInsensitiveContains("NonexistentQuery123456789")
        }
        #expect(noMatch.isEmpty)

        // Clearing logs results in empty logs
        workspace.clearLogs()
        #expect(workspace.logs.isEmpty)
    }

    @Test @MainActor func testViewInstantiationUnderEmptyAndPopulatedStates() {
        let emptyModel = WorkspaceModel()
        for obj in emptyModel.document.objects {
            emptyModel.removeObject(obj.id)
        }
        emptyModel.selectedId = nil
        emptyModel.clearLogs()

        let populatedModel = WorkspaceModel()

        for model in [emptyModel, populatedModel] {
            let views: [any View] = [
                EmptySceneGuidanceOverlayView().environment(model),
                ViewportCanvasView().environment(model),
                NavigatorSidebarView().environment(model),
                InspectorPanelView().environment(model),
                ConsoleDrawerView().environment(model)
            ]
            #expect(views.count == 5)
        }
    }
}
