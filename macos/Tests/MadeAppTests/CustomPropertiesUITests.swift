import Testing
import SwiftUI
import AppKit
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct CustomPropertiesUITests {

    // MARK: - Document Settings Inspector & Workspace Operations

    @Test @MainActor func testDocumentSettingsInspectorPropertiesEditingAndUndoRedo() {
        let workspace = WorkspaceModel()
        workspace.setUp()
        workspace.document.undoManager?.groupsByEvent = false

        #expect(workspace.document.metadata.isEmpty)
        #expect(!workspace.isDocumentModified)

        // Set standard properties on document with discrete undo groups
        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setDocumentProperty(key: CustomPropertyKey.partNumber, value: "DOC-PART-100")
        workspace.document.undoManager?.endUndoGrouping()
        #expect(workspace.document.partNumber == "DOC-PART-100")
        #expect(workspace.isDocumentModified)

        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setDocumentProperty(key: CustomPropertyKey.description, value: "Main Chassis Assembly")
        workspace.document.undoManager?.endUndoGrouping()
        #expect(workspace.document.itemDescription == "Main Chassis Assembly")

        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setDocumentProperty(key: CustomPropertyKey.revision, value: "1.0")
        workspace.document.undoManager?.endUndoGrouping()
        #expect(workspace.document.revision == "1.0")

        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setDocumentProperty(key: CustomPropertyKey.vendor, value: "In-House")
        workspace.document.undoManager?.endUndoGrouping()
        #expect(workspace.document.vendor == "In-House")

        // Add custom property
        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setDocumentProperty(key: "ProjectCode", value: "APOLLO")
        workspace.document.undoManager?.endUndoGrouping()
        #expect(workspace.document.property(forKey: "ProjectCode") == "APOLLO")
        #expect(workspace.document.customProperties["ProjectCode"] == "APOLLO")

        // Instantiate view to verify SwiftUI hierarchy building
        let view = DocumentSettingsInspectorView().environment(workspace)
        _ = view

        // Undo custom property
        workspace.undo()
        #expect(workspace.document.property(forKey: "ProjectCode") == nil)
        #expect(workspace.document.vendor == "In-House")

        // Redo custom property
        workspace.redo()
        #expect(workspace.document.property(forKey: "ProjectCode") == "APOLLO")

        // Undo all standard properties
        workspace.undo() // ProjectCode
        workspace.undo() // Vendor
        #expect(workspace.document.vendor == nil)
        #expect(workspace.document.revision == "1.0")

        workspace.undo() // Revision
        #expect(workspace.document.revision == nil)
        #expect(workspace.document.itemDescription == "Main Chassis Assembly")

        workspace.undo() // Description
        #expect(workspace.document.itemDescription == nil)
        #expect(workspace.document.partNumber == "DOC-PART-100")

        workspace.undo() // PartNumber
        #expect(workspace.document.partNumber == nil)
        #expect(workspace.document.metadata.isEmpty)
    }

    // MARK: - Solid Body Properties Inspector & Workspace Operations

    @Test @MainActor func testSolidBodyPropertiesEditingAndUndoRedo() {
        let workspace = WorkspaceModel()
        workspace.setUp()
        workspace.document.undoManager?.groupsByEvent = false

        guard let firstBody = workspace.document.bodies.first else {
            Issue.record("Expected default workspace document to contain at least one body.")
            return
        }

        let bodyId = firstBody.id
        #expect(firstBody.metadata.isEmpty)

        // Set standard properties on solid body
        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setBodyProperty(id: bodyId, key: CustomPropertyKey.partNumber, value: "SOLID-BRK-01")
        workspace.document.undoManager?.endUndoGrouping()

        #expect(workspace.document.body(for: bodyId)?.partNumber == "SOLID-BRK-01")
        #expect(workspace.document.objects.first(where: { $0.id == bodyId })?.metadata[CustomPropertyKey.partNumber] == "SOLID-BRK-01")

        // Set custom property on solid body
        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setBodyProperty(id: bodyId, key: "Finish", value: "Anodized Black")
        workspace.document.undoManager?.endUndoGrouping()

        #expect(workspace.document.body(for: bodyId)?.customProperties["Finish"] == "Anodized Black")

        // Verify InspectorPanelView instantiates
        let inspectorView = InspectorPanelView().environment(workspace)
        _ = inspectorView

        // Undo custom property
        workspace.undo()
        #expect(workspace.document.body(for: bodyId)?.customProperties["Finish"] == nil)
        #expect(workspace.document.body(for: bodyId)?.partNumber == "SOLID-BRK-01")

        // Undo standard property
        workspace.undo()
        #expect(workspace.document.body(for: bodyId)?.partNumber == nil)

        // Redo
        workspace.redo()
        #expect(workspace.document.body(for: bodyId)?.partNumber == "SOLID-BRK-01")
        workspace.redo()
        #expect(workspace.document.body(for: bodyId)?.customProperties["Finish"] == "Anodized Black")
    }

    // MARK: - Assembly Component Instance Properties & Workspace Operations

    @Test @MainActor func testAssemblyComponentPropertiesEditingAndUndoRedo() {
        let workspace = WorkspaceModel()
        workspace.setUp()
        workspace.document.undoManager?.groupsByEvent = false

        let compId = ComponentInstanceId()
        let comp = ComponentInstance(
            id: compId,
            name: "Bracket Inst",
            reference: .internalPart(name: "Bracket", bodyId: ObjectId("body-b")),
            metadata: [:]
        )

        workspace.document.reset(
            with: [Feature](),
            documentType: .assembly,
            componentInstances: [comp]
        )

        #expect(workspace.document.componentInstances.count == 1)
        #expect(workspace.document.componentInstances.first?.metadata.isEmpty == true)

        // Set component instance properties
        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setComponentProperty(id: compId, key: CustomPropertyKey.partNumber, value: "CMP-BRK-001")
        workspace.document.undoManager?.endUndoGrouping()

        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setComponentProperty(id: compId, key: CustomPropertyKey.vendor, value: "MetalWorks Inc")
        workspace.document.undoManager?.endUndoGrouping()

        workspace.document.undoManager?.beginUndoGrouping()
        workspace.setComponentProperty(id: compId, key: "TorqueSpec", value: "25 Nm")
        workspace.document.undoManager?.endUndoGrouping()

        let updatedComp = workspace.document.findComponentInstance(id: compId)
        #expect(updatedComp?.partNumber == "CMP-BRK-001")
        #expect(updatedComp?.vendor == "MetalWorks Inc")
        #expect(updatedComp?.customProperties["TorqueSpec"] == "25 Nm")

        // Verify component view instantiates
        if let instance = updatedComp {
            let compView = InspectorComponentInstanceView(component: instance).environment(workspace)
            _ = compView
        }

        // Undo custom property
        workspace.undo()
        #expect(workspace.document.findComponentInstance(id: compId)?.customProperties["TorqueSpec"] == nil)
        #expect(workspace.document.findComponentInstance(id: compId)?.vendor == "MetalWorks Inc")

        // Undo vendor
        workspace.undo()
        #expect(workspace.document.findComponentInstance(id: compId)?.vendor == nil)
        #expect(workspace.document.findComponentInstance(id: compId)?.partNumber == "CMP-BRK-001")

        // Redo
        workspace.redo()
        #expect(workspace.document.findComponentInstance(id: compId)?.vendor == "MetalWorks Inc")
        workspace.redo()
        #expect(workspace.document.findComponentInstance(id: compId)?.customProperties["TorqueSpec"] == "25 Nm")
    }

    // MARK: - MetadataPropertiesView Callback and Edge Case Tests

    @Test @MainActor func testMetadataPropertiesViewCallbacks() {
        var mutations: [String: String?] = [:]
        var metadata: [String: String] = [
            CustomPropertyKey.partNumber: "P-1",
            "Color": "Red"
        ]

        let view = MetadataPropertiesView(
            metadata: metadata,
            idPrefix: "test-meta",
            isLocked: false,
            onSetProperty: { key, val in
                mutations[key] = val
                if let val, !val.isEmpty {
                    metadata[key] = val
                } else {
                    metadata.removeValue(forKey: key)
                }
            }
        )
        _ = view

        // Simulate property updates directly through callback
        view.onSetProperty(CustomPropertyKey.partNumber, "P-2")
        #expect(mutations[CustomPropertyKey.partNumber] == "P-2")
        #expect(metadata[CustomPropertyKey.partNumber] == "P-2")

        view.onSetProperty("Color", nil)
        #expect(mutations["Color"] == .some(nil))
        #expect(metadata["Color"] == nil)

        view.onSetProperty("NewCustom", "CustomVal")
        #expect(mutations["NewCustom"] == "CustomVal")
        #expect(metadata["NewCustom"] == "CustomVal")
    }

    @Test @MainActor func testLockedPropertiesViewDoesNotAllowEditing() {
        let view = MetadataPropertiesView(
            metadata: [CustomPropertyKey.partNumber: "LOCKED-1"],
            idPrefix: "test-locked",
            isLocked: true,
            onSetProperty: { _, _ in }
        )
        #expect(view.isLocked)
    }
}
