import Testing
import Foundation
@testable import MadeCore

@Suite struct DocumentCustomMaterialsTests {

    private func sampleMaterial(id: String = "doc-mat-1", name: String = "Document Steel") -> MaterialDefinition {
        MaterialDefinition(
            id: id,
            name: name,
            category: .metal,
            description: "Custom steel for active document",
            color: SIMD4<Float>(0.2, 0.4, 0.8, 1.0),
            citations: [
                MaterialCitation(sourceName: "Standard", specification: "STD-100", notes: "Project standard")
            ],
            density: DensityQuantity(value: 7800, unit: .kgPerCubicMeter),
            youngsModulus: StressQuantity(value: 205, unit: .gigapascals),
            poissonsRatio: DimensionlessQuantity(value: 0.29, unit: .ratio),
            yieldStrength: StressQuantity(value: 350, unit: .megapascals),
            ultimateStrength: StressQuantity(value: 500, unit: .megapascals),
            thermalConductivity: ThermalConductivityQuantity(value: 45.0, unit: .wattsPerMeterKelvin),
            thermalExpansion: ThermalExpansionQuantity(value: 11.5, unit: .microstrainPerKelvin),
            specificHeat: SpecificHeatQuantity(value: 480, unit: .joulesPerKilogramKelvin)
        )
    }

    @Test @MainActor func testAddUpdateRemoveCustomMaterial() {
        let doc = DocumentModel()
        #expect(doc.customMaterials.isEmpty)

        let mat1 = sampleMaterial(id: "doc-1", name: "Doc Material 1")
        let addResult = doc.addCustomMaterial(mat1)
        #expect(addResult == .success(()))
        #expect(doc.customMaterials.count == 1)
        #expect(doc.customMaterial(withId: "doc-1")?.name == "Doc Material 1")

        // Reject duplicate ID
        let duplicateResult = doc.addCustomMaterial(mat1)
        #expect(duplicateResult == .failure(.invalidOperation("Material with ID 'doc-1' already exists")))

        // Reject empty name
        let emptyMat = sampleMaterial(id: "doc-empty", name: "   ")
        let emptyResult = doc.addCustomMaterial(emptyMat)
        #expect(emptyResult == .failure(.invalidOperation("Material name cannot be empty")))

        // Update material
        var updated = mat1
        updated.name = "Updated Doc Material 1"
        let updateResult = doc.updateCustomMaterial(updated)
        #expect(updateResult == .success(()))
        #expect(doc.customMaterial(withId: "doc-1")?.name == "Updated Doc Material 1")

        // Reject update of missing material
        let missing = sampleMaterial(id: "missing", name: "Valid")
        let missingUpdateResult = doc.updateCustomMaterial(missing)
        #expect(missingUpdateResult == .failure(.invalidOperation("Material with ID 'missing' not found")))

        // Remove material
        let removeResult = doc.removeCustomMaterial(id: "doc-1")
        #expect(removeResult == .success(()))
        #expect(doc.customMaterials.isEmpty)
        #expect(doc.customMaterial(withId: "doc-1") == nil)

        // Reject removing missing material
        let removeAgain = doc.removeCustomMaterial(id: "doc-1")
        #expect(removeAgain == .failure(.invalidOperation("Material with ID 'doc-1' not found")))
    }

    @Test @MainActor func testUndoRedoCustomMaterials() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let mat1 = sampleMaterial(id: "doc-undo-1", name: "Initial Material")

        // 1. Add material
        _ = doc.addCustomMaterial(mat1)
        #expect(doc.customMaterials.count == 1)

        // Undo add -> customMaterials becomes empty
        undoManager.undo()
        #expect(doc.customMaterials.isEmpty)

        // Redo add -> customMaterials has mat1
        undoManager.redo()
        #expect(doc.customMaterials.count == 1)
        #expect(doc.customMaterials.first?.name == "Initial Material")

        // 2. Update material
        var updated = mat1
        updated.name = "Modified Material"
        _ = doc.updateCustomMaterial(updated)
        #expect(doc.customMaterials.first?.name == "Modified Material")

        // Undo update -> reverts to initial name
        undoManager.undo()
        #expect(doc.customMaterials.first?.name == "Initial Material")

        // Redo update -> reapplies modified name
        undoManager.redo()
        #expect(doc.customMaterials.first?.name == "Modified Material")

        // 3. Remove material
        _ = doc.removeCustomMaterial(id: "doc-undo-1")
        #expect(doc.customMaterials.isEmpty)

        // Undo remove -> material restored
        undoManager.undo()
        #expect(doc.customMaterials.count == 1)
        #expect(doc.customMaterials.first?.name == "Modified Material")

        // Redo remove -> material removed again
        undoManager.redo()
        #expect(doc.customMaterials.isEmpty)
    }

    @Test @MainActor func testDocumentSerializationRoundTrip() throws {
        let doc = DocumentModel()
        let mat = sampleMaterial(id: "roundtrip-mat", name: "Roundtrip Alloy")
        _ = doc.addCustomMaterial(mat)

        let encodedData = try DocumentModelCoder.encode(document: doc)

        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encodedData)

        #expect(restoredDoc.customMaterials.count == 1)
        let restoredMat = restoredDoc.customMaterials.first
        #expect(restoredMat?.id == "roundtrip-mat")
        #expect(restoredMat?.name == "Roundtrip Alloy")
        #expect(restoredMat?.densityKgPerM3 == 7800)
    }

    @Test @MainActor func testLegacyDocumentWithoutCustomMaterialsDecodesCleanly() throws {
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "objects": []
        }
        """
        let data = Data(legacyJSON.utf8)
        let doc = DocumentModel()
        try DocumentModelCoder.decode(into: doc, from: data)

        #expect(doc.customMaterials.isEmpty)
    }

    @Test func testMaterialAttributesBackwardCompatibility() throws {
        // Legacy JSON without materialDefinitionId or materialName
        let legacyJSON = """
        {
            "color": [0.5, 0.5, 0.5, 1.0]
        }
        """
        let decoder = JSONDecoder()
        let legacyAttr = try decoder.decode(MaterialAttributes.self, from: Data(legacyJSON.utf8))
        #expect(legacyAttr.color == SIMD4<Float>(0.5, 0.5, 0.5, 1.0))
        #expect(legacyAttr.materialDefinitionId == nil)
        #expect(legacyAttr.materialName == nil)

        // Modern JSON with definition ID and name
        let modernJSON = """
        {
            "color": [0.2, 0.4, 0.8, 1.0],
            "materialDefinitionId": "custom-1",
            "materialName": "Custom Alloy"
        }
        """
        let modernAttr = try decoder.decode(MaterialAttributes.self, from: Data(modernJSON.utf8))
        #expect(modernAttr.color == SIMD4<Float>(0.2, 0.4, 0.8, 1.0))
        #expect(modernAttr.materialDefinitionId == "custom-1")
        #expect(modernAttr.materialName == "Custom Alloy")

        // Roundtrip encode
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(modernAttr)
        let roundtripAttr = try decoder.decode(MaterialAttributes.self, from: encodedData)
        #expect(roundtripAttr == modernAttr)
    }

    @Test @MainActor func testDeletingCustomMaterialPreservesBodyColor() {
        let doc = DocumentModel()
        let customMat = sampleMaterial(id: "body-mat-1", name: "Body Alloy")
        _ = doc.addCustomMaterial(customMat)

        guard let firstBody = doc.bodies.first else {
            Issue.record("Expected default bodies in DocumentModel")
            return
        }

        let attributes = MaterialAttributes(
            color: customMat.color,
            materialDefinitionId: customMat.id,
            materialName: customMat.name
        )
        let setResult = doc.setBodyMaterial(id: firstBody.id, material: attributes)
        #expect(setResult == .success(()))

        // Check assigned material
        let assignedBody = doc.body(for: firstBody.id)
        #expect(assignedBody?.material.materialDefinitionId == "body-mat-1")
        #expect(assignedBody?.material.color == customMat.color)

        // Delete the custom material
        let removeResult = doc.removeCustomMaterial(id: "body-mat-1")
        #expect(removeResult == .success(()))
        #expect(doc.customMaterials.isEmpty)

        // Verify body still preserves visual appearance and color
        let bodyAfterDeletion = doc.body(for: firstBody.id)
        #expect(bodyAfterDeletion != nil)
        #expect(bodyAfterDeletion?.material.color == customMat.color)
    }
}
