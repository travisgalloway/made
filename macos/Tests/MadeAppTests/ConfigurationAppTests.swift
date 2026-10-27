import Testing
import Foundation
import SwiftUI
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct ConfigurationAppTests {

    // MARK: - WorkspaceModel Configuration Operations

    @Test func testWorkspaceModelConfigurationOperations() {
        let ws = WorkspaceModel()
        ws.setUp()
        ws.newDocument()

        #expect(ws.configurations.isEmpty)
        #expect(ws.activeConfigurationId == nil)
        #expect(ws.activeConfiguration == nil)

        // Add configuration
        let config1 = ws.addConfiguration(name: "Standard", comment: "Base Configuration", isDefault: true)
        #expect(config1 != nil)
        #expect(ws.configurations.count == 1)
        #expect(ws.isDocumentModified)

        // Duplicate name rejected
        let configDup = ws.addConfiguration(name: "Standard")
        #expect(configDup == nil)

        // Add second configuration
        let config2 = ws.addConfiguration(name: "Extended")
        #expect(config2 != nil)
        #expect(ws.configurations.count == 2)

        // Update configuration
        if var c2 = config2 {
            c2.comment = "Long stroke variant"
            let updated = ws.updateConfiguration(c2)
            #expect(updated == true)
            #expect(ws.document.configuration(id: c2.id)?.comment == "Long stroke variant")
        }

        // Duplicate configuration
        let duplicated = ws.duplicateConfiguration(id: config1!.id, newName: "Standard_Copy")
        #expect(duplicated != nil)
        #expect(ws.configurations.count == 3)

        // Set active configuration
        let activated = ws.setActiveConfiguration(id: config2!.id)
        #expect(activated == true)
        #expect(ws.activeConfigurationId == config2!.id)
        #expect(ws.activeConfiguration?.name == "Extended")

        // Overrides
        let pSet = ws.setParameterOverride(configurationId: config2!.id, parameterName: "stroke", value: 500.0)
        #expect(pSet == true)
        #expect(ws.document.configuration(id: config2!.id)?.parameterOverrides["stroke"] == 500.0)

        let pRemoved = ws.removeParameterOverride(configurationId: config2!.id, parameterName: "stroke")
        #expect(pRemoved == true)
        #expect(ws.document.configuration(id: config2!.id)?.parameterOverrides["stroke"] == nil)

        let dummyFeatureId = UUID()
        let sSet = ws.setSuppressionOverride(configurationId: config2!.id, featureId: dummyFeatureId, isSuppressed: true)
        #expect(sSet == true)
        #expect(ws.document.configuration(id: config2!.id)?.suppressionOverrides[dummyFeatureId] == true)

        let sRemoved = ws.removeSuppressionOverride(configurationId: config2!.id, featureId: dummyFeatureId)
        #expect(sRemoved == true)
        #expect(ws.document.configuration(id: config2!.id)?.suppressionOverrides[dummyFeatureId] == nil)

        // Delete active configuration -> falls back to default configuration (Standard)
        let deleted = ws.deleteConfiguration(id: config2!.id)
        #expect(deleted == true)
        #expect(ws.configurations.count == 2)
        #expect(ws.activeConfigurationId == config1!.id)

        // Deactivate configuration
        _ = ws.setActiveConfiguration(id: nil)
        #expect(ws.activeConfigurationId == nil)
    }

    // MARK: - Assembly Component Instance Configuration

    @Test func testWorkspaceAssemblyComponentInstanceConfiguration() {
        let ws = WorkspaceModel()
        ws.setUp()
        ws.newAssemblyDocument()

        let cfg = ws.addConfiguration(name: "Compact", isDefault: false)
        #expect(cfg != nil)

        let inst = ws.addComponentInstance(
            name: "Motor",
            reference: .internalPart(name: "MotorPart"),
            transform: Transform.identity
        )

        #expect(inst.configurationName == nil)
        #expect(inst.configurationId == nil)

        let assigned = ws.setComponentInstanceConfiguration(id: inst.id, configurationName: "Compact", configurationId: cfg?.id)
        #expect(assigned == true)

        let updatedInst = ws.document.componentInstances.first(where: { $0.id == inst.id })
        #expect(updatedInst?.configurationName == "Compact")
        #expect(updatedInst?.configurationId == cfg?.id)

        // Reset to default
        let cleared = ws.setComponentInstanceConfiguration(id: inst.id, configurationName: nil, configurationId: nil)
        #expect(cleared == true)
        let clearedInst = ws.document.componentInstances.first(where: { $0.id == inst.id })
        #expect(clearedInst?.configurationName == nil)
        #expect(clearedInst?.configurationId == nil)
    }

    // MARK: - UI Views Instantiation

    @Test func testConfigurationViewsInstantiation() {
        let ws = WorkspaceModel()
        ws.setUp()
        ws.newAssemblyDocument()

        let config = ws.addConfiguration(name: "Main Variant", comment: "Primary variant", isDefault: true)!
        _ = ws.setActiveConfiguration(id: config.id)

        let inst = ws.addComponentInstance(
            name: "Bracket",
            reference: .internalPart(name: "BracketPart"),
            transform: Transform.identity
        )

        // Instantiate Inspector and Navigator views to verify SwiftUI hierarchies build without runtime issues
        let docInspector = DocumentSettingsInspectorView().environment(ws)
        _ = docInspector

        let configRow = DocumentConfigurationRowView(config: config).environment(ws)
        _ = configRow

        let compInspector = InspectorComponentInstanceView(component: inst).environment(ws)
        _ = compInspector

        let navConfigRow = NavigatorConfigurationRow(config: config).environment(ws)
        _ = navConfigRow
    }
}
