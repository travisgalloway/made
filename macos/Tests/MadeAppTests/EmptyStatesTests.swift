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

    @Test @MainActor func testNavigatorFilteringWithKindAndParameterSummary() {
        let workspace = WorkspaceModel()
        let objects = workspace.document.objects

        // Kind matching
        let cylinderFilter = NavigatorSidebarView.filter(objects: objects, query: "cylinder")
        #expect(cylinderFilter.count == 1)
        #expect(cylinderFilter.first?.id == cylinderSolidId)

        let boxFilter = NavigatorSidebarView.filter(objects: objects, query: "box")
        #expect(boxFilter.count == 1)
        #expect(boxFilter.first?.id == boxSolidId)

        // Parameter summary matching
        let radiusFilter = NavigatorSidebarView.filter(objects: objects, query: "r 15")
        #expect(radiusFilter.count == 1)
        #expect(radiusFilter.first?.id == cylinderSolidId)

        let dimFilter = NavigatorSidebarView.filter(objects: objects, query: "40 × 30")
        #expect(dimFilter.count == 1)
        #expect(dimFilter.first?.id == boxSolidId)

        // Raw ID matching
        let idFilter = NavigatorSidebarView.filter(objects: objects, query: "box-1")
        #expect(idFilter.count == 1)
        #expect(idFilter.first?.id == boxSolidId)

        // Empty query returns all objects
        #expect(NavigatorSidebarView.filter(objects: objects, query: "").count == objects.count)
        #expect(NavigatorSidebarView.filter(objects: objects, query: "   ").count == objects.count)

        // No match returns empty
        #expect(NavigatorSidebarView.filter(objects: objects, query: "nonexistent-query-404").isEmpty)
    }

    @Test @MainActor func testViewInstantiationUnderEmptyAndPopulatedStates() {
        let emptyModel = WorkspaceModel()
        for obj in emptyModel.document.objects {
            emptyModel.removeObject(obj.id)
        }
        emptyModel.selectedId = nil
        emptyModel.clearLogs()

        let populatedModel = WorkspaceModel()

        let largeModel = WorkspaceModel()
        for i in 1...500 {
            largeModel.document.addObject(def: .box(BoxParams(width: Float(i % 50 + 10), depth: 30, height: 20)))
        }

        for model in [emptyModel, populatedModel, largeModel] {
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

    @Test @MainActor func testViewInstantiationWithFeatureErrorAndWarningStates() {
        let workspace = WorkspaceModel()

        // Give box-1 an error state
        if let boxFeat = workspace.document.features.first(where: { $0.outputSolidId == boxSolidId }) {
            workspace.document.setFeatureError(
                id: boxFeat.id,
                error: FeatureErrorState(code: "invalid-params", message: "Invalid box parameter", severity: .error)
            )
        }

        // Give cylinder-1 a warning state
        if let cylFeat = workspace.document.features.first(where: { $0.outputSolidId == cylinderSolidId }) {
            workspace.document.setFeatureError(
                id: cylFeat.id,
                error: FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
            )
        }

        workspace.selectedId = boxSolidId

        let viewsWithBoxSelected: [any View] = [
            NavigatorSidebarView().environment(workspace),
            InspectorPanelView().environment(workspace)
        ]
        #expect(viewsWithBoxSelected.count == 2)

        // Select cylinder-1 to test Inspector under warning state
        workspace.selectedId = cylinderSolidId
        let viewsWithCylinderSelected: [any View] = [
            NavigatorSidebarView().environment(workspace),
            InspectorPanelView().environment(workspace)
        ]
        #expect(viewsWithCylinderSelected.count == 2)
    }
}
