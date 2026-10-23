import Testing
import SwiftUI
@testable import MadeApp
import MadeCore

@Suite struct MaterialLibraryViewTests {

    @Test @MainActor func testWindowIdentifier() {
        #expect(MaterialLibraryView.windowID == "material-library")
    }

    @Test @MainActor func testCategoryFilterMappings() {
        #expect(MaterialLibraryView.CategoryFilter.allCases.count == 3)
        #expect(MaterialLibraryView.CategoryFilter.all.category == nil)
        #expect(MaterialLibraryView.CategoryFilter.metals.category == .metal)
        #expect(MaterialLibraryView.CategoryFilter.plastics.category == .plastic)
    }

    @Test @MainActor func testMaterialLibraryViewLoadsStandardMaterials() {
        let view = MaterialLibraryView()
        #expect(view.library.materials.count == 11)

        let steel = view.library.material(withId: "structural-steel-a36")
        #expect(steel != nil)
        #expect(steel?.name == "Structural Steel (A36 / S235)")

        // Custom initial material selection
        let aluminumView = MaterialLibraryView(initialMaterialID: "aluminum-6061-t6")
        #expect(aluminumView.library.materials.count == 11)
    }

    @Test @MainActor func testMaterialDetailFormatting() {
        let mat = StandardMaterials.aluminum7075T6

        #expect(mat.density.formattedValue.hasSuffix("kg/m³"))
        #expect(mat.youngsModulus.formattedValue.hasSuffix("GPa"))
        #expect(mat.poissonsRatio.formattedValue == "0.33")
        #expect(mat.yieldStrength.formattedValue.hasSuffix("MPa"))
        #expect(mat.ultimateStrength.formattedValue.hasSuffix("MPa"))
        #expect(mat.thermalConductivity.formattedValue.hasSuffix("W/(m·K)"))
        #expect(mat.thermalExpansion.formattedValue.hasSuffix("10⁻⁶/K"))
        #expect(mat.specificHeat.formattedValue.hasSuffix("J/(kg·K)"))
    }

    @Test @MainActor func testCopyPropertiesFormattedString() {
        let mat = StandardMaterials.titaniumTi6Al4V
        let summary = mat.formattedSummary()

        #expect(summary.contains("Material: Titanium Ti-6Al-4V (Grade 5)"))
        #expect(summary.contains("Category: Metal"))
        #expect(summary.contains("Mechanical Properties:"))
        #expect(summary.contains("Density: 4,430 kg/m³") || summary.contains("Density: 4430 kg/m³"))
        #expect(summary.contains("Young's Modulus: 113.8 GPa"))
        #expect(summary.contains("Poisson's Ratio: 0.342"))
        #expect(summary.contains("Yield Strength: 880 MPa"))
        #expect(summary.contains("Ultimate Tensile Strength: 950 MPa"))
        #expect(summary.contains("Thermal Properties:"))
        #expect(summary.contains("Thermal Conductivity: 6.7 W/(m·K)"))
        #expect(summary.contains("Thermal Expansion: 8.6 10⁻⁶/K"))
        #expect(summary.contains("Specific Heat Capacity: 526 J/(kg·K)"))
        #expect(summary.contains("Citations & Standards:"))
        #expect(summary.contains("MMPDS-01"))
        #expect(summary.contains("ASTM B265"))
    }

    @Test @MainActor func testViewInstantiationWithCustomLibrary() {
        let customMat = MaterialDefinition(
            id: "custom-alloy",
            name: "Custom Test Alloy",
            category: .metal,
            description: "Experimental lightweight metal.",
            color: SIMD4<Float>(0.9, 0.9, 0.9, 1.0),
            citations: [
                MaterialCitation(sourceName: "Lab", specification: "LAB-01", notes: "Internal test data")
            ],
            density: DensityQuantity(value: 3000, unit: .kgPerCubicMeter),
            youngsModulus: StressQuantity(value: 100, unit: .gigapascals),
            poissonsRatio: DimensionlessQuantity(value: 0.3, unit: .ratio),
            yieldStrength: StressQuantity(value: 300, unit: .megapascals),
            ultimateStrength: StressQuantity(value: 400, unit: .megapascals),
            thermalConductivity: ThermalConductivityQuantity(value: 50, unit: .wattsPerMeterKelvin),
            thermalExpansion: ThermalExpansionQuantity(value: 15, unit: .microstrainPerKelvin),
            specificHeat: SpecificHeatQuantity(value: 600, unit: .joulesPerKilogramKelvin)
        )

        let customLibrary = MaterialLibrary(materials: [customMat])
        let customView = MaterialLibraryView(library: customLibrary, initialMaterialID: "custom-alloy")
        #expect(customView.library.materials.count == 1)
        #expect(customView.library.materials.first?.name == "Custom Test Alloy")
    }

    @Test @MainActor func testMaterialScopeEnum() {
        let scopes = MaterialLibraryView.MaterialScope.allCases
        #expect(scopes.count == 4)
        #expect(scopes.map(\.rawValue) == ["All", "Standard", "Document", "User Library"])
    }

    @Test @MainActor func testCustomMaterialEditorValidation() {
        // Default init has empty name -> invalid
        let editorEmptyName = CustomMaterialEditorView()
        #expect(!editorEmptyName.isValid)
        #expect(editorEmptyName.validationError == "Material name is required.")

        // Prepopulated with valid material -> valid
        let validMat = StandardMaterials.aluminum6061T6
        let editorValid = CustomMaterialEditorView(materialToEdit: validMat)
        #expect(editorValid.isValid)
        #expect(editorValid.validationError == nil)
    }

    @Test @MainActor func testWorkspaceModelMaterialDelegates() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MadeAppWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("test-user-materials.json")
        let userStore = UserMaterialStore(fileURL: storeURL)
        let workspace = WorkspaceModel(userMaterialStore: userStore)

        #expect(workspace.userMaterials.isEmpty)
        #expect(workspace.document.customMaterials.isEmpty)

        let testMat = MaterialDefinition(
            id: "ws-test-mat",
            name: "Workspace Test Alloy",
            category: .metal,
            description: "Testing workspace integration",
            color: SIMD4<Float>(0.1, 0.2, 0.3, 1.0),
            citations: [],
            density: DensityQuantity(value: 5000, unit: .kgPerCubicMeter),
            youngsModulus: StressQuantity(value: 120, unit: .gigapascals),
            poissonsRatio: DimensionlessQuantity(value: 0.31, unit: .ratio),
            yieldStrength: StressQuantity(value: 400, unit: .megapascals),
            ultimateStrength: StressQuantity(value: 550, unit: .megapascals),
            thermalConductivity: ThermalConductivityQuantity(value: 20, unit: .wattsPerMeterKelvin),
            thermalExpansion: ThermalExpansionQuantity(value: 10, unit: .microstrainPerKelvin),
            specificHeat: SpecificHeatQuantity(value: 450, unit: .joulesPerKilogramKelvin)
        )

        // 1. Document custom materials
        let addDocRes = workspace.addDocumentCustomMaterial(testMat)
        #expect(addDocRes == .success(()))
        #expect(workspace.document.customMaterials.count == 1)
        #expect(workspace.isDocumentModified)

        var updatedDocMat = testMat
        updatedDocMat.name = "Updated Workspace Alloy"
        let updateDocRes = workspace.updateDocumentCustomMaterial(updatedDocMat)
        #expect(updateDocRes == .success(()))
        #expect(workspace.document.customMaterials.first?.name == "Updated Workspace Alloy")

        let removeDocRes = workspace.removeDocumentCustomMaterial(id: "ws-test-mat")
        #expect(removeDocRes == .success(()))
        #expect(workspace.document.customMaterials.isEmpty)

        // 2. User library custom materials
        try workspace.addUserMaterial(testMat)
        #expect(workspace.userMaterials.count == 1)
        #expect(workspace.userMaterials.first?.id == "ws-test-mat")

        var updatedUserMat = testMat
        updatedUserMat.description = "Updated User Material Desc"
        try workspace.updateUserMaterial(updatedUserMat)
        #expect(workspace.userMaterials.first?.description == "Updated User Material Desc")

        try workspace.removeUserMaterial(id: "ws-test-mat")
        #expect(workspace.userMaterials.isEmpty)

        // 3. Apply material definition to body
        guard let firstBody = workspace.document.bodies.first else {
            Issue.record("Expected bodies in workspace document")
            return
        }

        workspace.applyMaterialDefinition(testMat, to: firstBody.id)
        let bodyAfter = workspace.document.body(for: firstBody.id)
        #expect(bodyAfter?.material.materialDefinitionId == "ws-test-mat")
        #expect(bodyAfter?.material.materialName == "Workspace Test Alloy")
        #expect(bodyAfter?.material.color == testMat.color)
    }
}
