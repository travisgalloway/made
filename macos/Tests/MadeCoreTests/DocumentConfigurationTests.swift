import Testing
import Foundation
@testable import MadeCore

@Suite @MainActor struct DocumentConfigurationTests {

    private func performUndoable<T>(_ doc: DocumentModel, _ action: () throws -> T) rethrows -> T {
        doc.undoManager?.beginUndoGrouping()
        defer { doc.undoManager?.endUndoGrouping() }
        return try action()
    }

    // MARK: - Validation & Edge Cases (Edge Cases 1 & 2)

    @Test func testConfigurationNameValidation() {
        // Valid names
        #expect(throws: Never.self) {
            try DocumentConfiguration.validateName("Default")
            try DocumentConfiguration.validateName("Config-A")
            try DocumentConfiguration.validateName("Variant 1_rev2")
        }

        // Edge case 2: Empty or whitespace-only configuration names rejected
        #expect(throws: DocumentConfigurationError.emptyName) {
            try DocumentConfiguration.validateName("")
        }
        #expect(throws: DocumentConfigurationError.emptyName) {
            try DocumentConfiguration.validateName("   \n\t  ")
        }

        // Edge case 1: Duplicate configuration names rejected (case-insensitive)
        let existing = ["Default", "HighTorque", "LowPower"]
        #expect(throws: DocumentConfigurationError.duplicateName("Default")) {
            try DocumentConfiguration.validateName("Default", existingNames: existing)
        }
        #expect(throws: DocumentConfigurationError.duplicateName("default")) {
            try DocumentConfiguration.validateName("default", existingNames: existing)
        }
        #expect(throws: DocumentConfigurationError.duplicateName("HIGHTORQUE")) {
            try DocumentConfiguration.validateName("HIGHTORQUE", existingNames: existing)
        }
    }

    // MARK: - Configuration Lifecycle & Undo/Redo (Edge Case 7)

    @Test func testConfigurationCRUDAndUndoRedo() throws {
        let doc = DocumentModel()
        doc.undoManager = UndoManager()
        doc.undoManager?.groupsByEvent = false

        #expect(doc.configurations.isEmpty)
        #expect(doc.activeConfigurationId == nil)

        // 1. Add Configuration
        let config1 = DocumentConfiguration(name: "Config1", comment: "Base Variant", isDefault: true)
        let addResult = performUndoable(doc) {
            doc.addConfiguration(config1)
        }
        guard case .success(let added1) = addResult else {
            Issue.record("Failed to add configuration")
            return
        }
        #expect(doc.configurations.count == 1)
        #expect(doc.configurations[0].name == "Config1")
        #expect(doc.configurations[0].isDefault == true)

        // Duplicate name rejection on add
        let dupConfig = DocumentConfiguration(name: "config1")
        let dupResult = doc.addConfiguration(dupConfig)
        guard case .failure(let err) = dupResult else {
            Issue.record("Should have rejected duplicate configuration name")
            return
        }
        #expect(err == .invalidOperation("A configuration named 'config1' already exists."))

        // 2. Add second configuration
        let config2 = DocumentConfiguration(name: "Config2", comment: "Lightweight Variant")
        _ = performUndoable(doc) {
            doc.addConfiguration(config2)
        }
        #expect(doc.configurations.count == 2)

        // 3. Activate Configuration
        _ = performUndoable(doc) {
            doc.setActiveConfiguration(id: added1.id)
        }
        #expect(doc.activeConfigurationId == added1.id)
        #expect(doc.activeConfiguration?.name == "Config1")

        // 4. Update Configuration
        var updated1 = added1
        updated1.comment = "Updated Comment"
        let updateResult = performUndoable(doc) {
            doc.updateConfiguration(updated1)
        }
        #expect(updateResult == .success(()))
        #expect(doc.configuration(id: added1.id)?.comment == "Updated Comment")

        // 5. Duplicate Configuration
        let dupResult2 = performUndoable(doc) {
            doc.duplicateConfiguration(id: added1.id, newName: "Config1_Copy")
        }
        guard case .success(let copy) = dupResult2 else {
            Issue.record("Failed to duplicate configuration")
            return
        }
        #expect(doc.configurations.count == 3)
        #expect(copy.name == "Config1_Copy")
        #expect(copy.comment == "Updated Comment")

        // 6. Undo chain
        doc.undoManager?.undo() // Undo duplicate
        #expect(doc.configurations.count == 2)
        #expect(doc.configuration(named: "Config1_Copy") == nil)

        doc.undoManager?.undo() // Undo update
        #expect(doc.configuration(id: added1.id)?.comment == "Base Variant")

        doc.undoManager?.undo() // Undo activate
        #expect(doc.activeConfigurationId == nil)

        doc.undoManager?.undo() // Undo add Config2
        #expect(doc.configurations.count == 1)

        doc.undoManager?.undo() // Undo add Config1
        #expect(doc.configurations.isEmpty)

        // 7. Redo chain
        doc.undoManager?.redo() // Redo add Config1
        #expect(doc.configurations.count == 1)

        doc.undoManager?.redo() // Redo add Config2
        #expect(doc.configurations.count == 2)

        doc.undoManager?.redo() // Redo activate
        #expect(doc.activeConfigurationId == added1.id)

        doc.undoManager?.redo() // Redo update
        #expect(doc.configuration(id: added1.id)?.comment == "Updated Comment")

        doc.undoManager?.redo() // Redo duplicate
        #expect(doc.configurations.count == 3)
    }

    // MARK: - Edge Case 3: Deleting Active Configuration

    @Test func testDeletingActiveConfigurationRevertsSafely() {
        let doc = DocumentModel()
        doc.undoManager = UndoManager()
        doc.undoManager?.groupsByEvent = false

        let defConfig = DocumentConfiguration(name: "Default", isDefault: true)
        let altConfig = DocumentConfiguration(name: "Alternate", isDefault: false)

        _ = performUndoable(doc) { doc.addConfiguration(defConfig) }
        _ = performUndoable(doc) { doc.addConfiguration(altConfig) }

        // Activate Alternate
        _ = performUndoable(doc) { doc.setActiveConfiguration(id: altConfig.id) }
        #expect(doc.activeConfigurationId == altConfig.id)

        // Delete active alternate configuration -> falls back to default configuration
        _ = performUndoable(doc) { doc.deleteConfiguration(id: altConfig.id) }
        #expect(doc.activeConfigurationId == defConfig.id)

        // Delete default configuration -> falls back to nil
        _ = performUndoable(doc) { doc.deleteConfiguration(id: defConfig.id) }
        #expect(doc.activeConfigurationId == nil)
        #expect(doc.configurations.isEmpty)

        // Undo restores activeConfigurationId symmetrically
        doc.undoManager?.undo()
        #expect(doc.configurations.count == 1)
        #expect(doc.activeConfigurationId == defConfig.id)

        doc.undoManager?.undo()
        #expect(doc.configurations.count == 2)
        #expect(doc.activeConfigurationId == altConfig.id)
    }

    // MARK: - Parameter Overrides & Edge Case 4 (Stale Overrides)

    @Test func testParameterOverrideResolutionAndStaleOverrides() throws {
        let doc = DocumentModel()
        doc.undoManager = UndoManager()
        doc.undoManager?.groupsByEvent = false

        let p1 = DocumentParameter(name: "length", value: 100.0, unit: "mm")
        let p2 = DocumentParameter(name: "width", value: 50.0, unit: "mm")
        try performUndoable(doc) { try doc.addParameter(p1) }
        try performUndoable(doc) { try doc.addParameter(p2) }

        let config = DocumentConfiguration(name: "CustomSize")
        guard case .success(let added) = (performUndoable(doc) { doc.addConfiguration(config) }) else {
            Issue.record("Failed to add config")
            return
        }

        // Without active config, values match base parameters
        #expect(doc.effectiveParameterValue(named: "length") == 100.0)
        #expect(doc.effectiveParameterValue(named: "width") == 50.0)

        // Set override on config
        _ = performUndoable(doc) {
            doc.setParameterOverride(configurationId: added.id, parameterName: "length", value: 250.0)
        }
        #expect(doc.configuration(id: added.id)?.parameterOverrides["length"] == 250.0)

        // Inactive configuration doesn't affect effective values
        #expect(doc.effectiveParameterValue(named: "length") == 100.0)

        // Activate configuration
        _ = performUndoable(doc) { doc.setActiveConfiguration(id: added.id) }
        #expect(doc.effectiveParameterValue(named: "length") == 250.0)
        #expect(doc.effectiveParameterValue(named: "width") == 50.0)

        let effParams = doc.effectiveParameters
        #expect(effParams.first(where: { $0.name == "length" })?.value == 250.0)
        #expect(effParams.first(where: { $0.name == "width" })?.value == 50.0)

        // Remove override
        _ = performUndoable(doc) {
            doc.removeParameterOverride(configurationId: added.id, parameterName: "length")
        }
        #expect(doc.effectiveParameterValue(named: "length") == 100.0)

        // Undo restore override
        doc.undoManager?.undo()
        #expect(doc.effectiveParameterValue(named: "length") == 250.0)

        // Edge case 4: Delete parameter -> effectiveParameterValue ignores stale override
        try performUndoable(doc) { try doc.deleteParameter(id: p1.id) }
        #expect(doc.effectiveParameterValue(named: "length") == nil)
    }

    // MARK: - Feature Suppression Overrides & Edge Case 4

    @Test func testSuppressionOverrideResolutionAndStaleOverrides() {
        let doc = DocumentModel()
        doc.undoManager = UndoManager()
        doc.undoManager?.groupsByEvent = false

        let f1 = Feature.makeBox(params: BoxParams(width: 40, depth: 20, height: 30))
        let f2 = Feature.makeSphere(params: SphereParams(radius: 15))
        _ = performUndoable(doc) { doc.addFeature(f1) }
        _ = performUndoable(doc) { doc.addFeature(f2) }

        let config = DocumentConfiguration(name: "Unsuppressed")
        guard case .success(let added) = (performUndoable(doc) { doc.addConfiguration(config) }) else {
            Issue.record("Failed to add config")
            return
        }

        #expect(!doc.isFeatureSuppressedInActiveConfiguration(featureId: f2.id))

        // Set suppression override
        _ = performUndoable(doc) {
            doc.setSuppressionOverride(configurationId: added.id, featureId: f2.id, isSuppressed: true)
        }
        #expect(doc.configuration(id: added.id)?.suppressionOverrides[f2.id] == true)

        // When inactive, not suppressed
        #expect(!doc.isFeatureSuppressedInActiveConfiguration(featureId: f2.id))

        // When active, suppressed
        _ = performUndoable(doc) { doc.setActiveConfiguration(id: added.id) }
        #expect(doc.isFeatureSuppressedInActiveConfiguration(featureId: f2.id))

        // Edge case 4: Feature deleted from features -> returns false (ignored stale override)
        _ = performUndoable(doc) { doc.removeFeature(id: f2.id) }
        #expect(!doc.isFeatureSuppressedInActiveConfiguration(featureId: f2.id))
    }

    // MARK: - Component Instance Configurations (Edge Case 5)

    @Test func testComponentInstanceConfigurationAndFallback() {
        let doc = DocumentModel(documentType: .assembly)
        doc.undoManager = UndoManager()
        doc.undoManager?.groupsByEvent = false

        let configA = DocumentConfiguration(name: "Short")
        let configB = DocumentConfiguration(name: "Long", isDefault: true)
        _ = performUndoable(doc) { doc.addConfiguration(configA) }
        _ = performUndoable(doc) { doc.addConfiguration(configB) }

        let instance = ComponentInstance(
            name: "Pin 1",
            reference: .internalPart(name: "Pin"),
            transform: Transform.identity,
            configurationName: "Short",
            configurationId: configA.id
        )
        _ = performUndoable(doc) { doc.addComponentInstance(instance) }

        #expect(doc.componentInstances[0].configurationName == "Short")
        #expect(doc.componentInstances[0].configurationId == configA.id)

        // Mutate configuration on component instance
        _ = performUndoable(doc) {
            doc.setComponentInstanceConfiguration(id: instance.id, configurationName: "Long", configurationId: configB.id)
        }
        #expect(doc.componentInstances[0].configurationName == "Long")
        #expect(doc.componentInstances[0].configurationId == configB.id)

        // Undo mutation
        doc.undoManager?.undo()
        #expect(doc.componentInstances[0].configurationName == "Short")
        #expect(doc.componentInstances[0].configurationId == configA.id)

        // Redo mutation
        doc.undoManager?.redo()
        #expect(doc.componentInstances[0].configurationName == "Long")

        // Edge case 5: Component references a missing or unknown configuration name
        _ = performUndoable(doc) {
            doc.setComponentInstanceConfiguration(id: instance.id, configurationName: "NonExistent", configurationId: UUID())
        }
        let resolved = doc.configurations.first(where: { $0.id == doc.componentInstances[0].configurationId })
            ?? doc.configurations.first(where: { $0.name == doc.componentInstances[0].configurationName })
            ?? doc.configurations.first(where: { $0.isDefault })
        #expect(resolved?.name == "Long")
        #expect(resolved?.isDefault == true)
    }

    // MARK: - Serialization & Edge Case 6 (Legacy Document Decoding)

    @Test func testConfigurationSerializationRoundTrip() throws {
        let doc = DocumentModel(documentType: .part)
        let config1 = DocumentConfiguration(name: "VariantA", comment: "Test", parameterOverrides: ["width": 12.0], isDefault: true)
        let config2 = DocumentConfiguration(name: "VariantB", parameterOverrides: ["width": 24.0])
        _ = doc.addConfiguration(config1)
        _ = doc.addConfiguration(config2)
        _ = doc.setActiveConfiguration(id: config2.id)

        let encodedData = try DocumentModelCoder.encode(document: doc)
        let decodedDoc = DocumentModel()
        try DocumentModelCoder.decode(into: decodedDoc, from: encodedData)

        #expect(decodedDoc.configurations.count == 2)
        #expect(decodedDoc.configurations[0].name == "VariantA")
        #expect(decodedDoc.configurations[0].parameterOverrides["width"] == 12.0)
        #expect(decodedDoc.configurations[0].isDefault == true)
        #expect(decodedDoc.configurations[1].name == "VariantB")
        #expect(decodedDoc.configurations[1].parameterOverrides["width"] == 24.0)
        #expect(decodedDoc.activeConfigurationId == config2.id)
        #expect(decodedDoc.activeConfiguration?.name == "VariantB")
    }

    @Test func testLegacyDocumentDecodingWithoutConfigurations() throws {
        // Edge case 6: Legacy JSON document without configurations or activeConfigurationId
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "objects": [],
            "features": []
        }
        """.data(using: .utf8)!

        let decodedDoc = DocumentModel()
        try DocumentModelCoder.decode(into: decodedDoc, from: legacyJSON)
        #expect(decodedDoc.configurations.isEmpty)
        #expect(decodedDoc.activeConfigurationId == nil)
        #expect(decodedDoc.activeConfiguration == nil)
    }

    // MARK: - Bill of Materials Integration

    @Test func testBOMGroupingWithConfigurations() {
        let doc = DocumentModel(documentType: .assembly)

        let inst1 = ComponentInstance(
            name: "Hex Bolt 1",
            reference: .internalPart(name: "HexBolt"),
            transform: Transform.identity,
            configurationName: "M6x20",
            metadata: [CustomPropertyKey.partNumber: "HB-M6"]
        )
        let inst2 = ComponentInstance(
            name: "Hex Bolt 2",
            reference: .internalPart(name: "HexBolt"),
            transform: Transform.identity,
            configurationName: "M6x20",
            metadata: [CustomPropertyKey.partNumber: "HB-M6"]
        )
        let inst3 = ComponentInstance(
            name: "Hex Bolt 3",
            reference: .internalPart(name: "HexBolt"),
            transform: Transform.identity,
            configurationName: "M6x40",
            metadata: [CustomPropertyKey.partNumber: "HB-M6"]
        )

        _ = doc.addComponentInstance(inst1)
        _ = doc.addComponentInstance(inst2)
        _ = doc.addComponentInstance(inst3)

        let bom = BillOfMaterials.generate(from: doc.componentInstances, structure: .flat)
        #expect(bom.items.count == 2)

        let m6x20 = bom.items.first(where: { $0.configuration == "M6x20" })
        #expect(m6x20?.quantity == 2)

        let m6x40 = bom.items.first(where: { $0.configuration == "M6x40" })
        #expect(m6x40?.quantity == 1)
    }
}
