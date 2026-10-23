import Testing
import Foundation
@testable import MadeCore

@Suite struct UserMaterialStoreTests {

    private func makeTemporaryStore() -> (store: UserMaterialStore, directoryURL: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MadeTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("test-materials.json", isDirectory: false)
        return (UserMaterialStore(fileURL: fileURL), tempDir)
    }

    private func cleanup(directoryURL: URL) {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func sampleMaterial(id: String = "test-custom-1", name: String = "Custom Titanium") -> MaterialDefinition {
        MaterialDefinition(
            id: id,
            name: name,
            category: .metal,
            description: "Custom titanium test alloy",
            color: SIMD4<Float>(0.7, 0.7, 0.75, 1.0),
            citations: [
                MaterialCitation(sourceName: "Internal Spec", specification: "SPEC-001", notes: "Lab tested")
            ],
            density: DensityQuantity(value: 4500, unit: .kgPerCubicMeter),
            youngsModulus: StressQuantity(value: 110, unit: .gigapascals),
            poissonsRatio: DimensionlessQuantity(value: 0.33, unit: .ratio),
            yieldStrength: StressQuantity(value: 800, unit: .megapascals),
            ultimateStrength: StressQuantity(value: 900, unit: .megapascals),
            thermalConductivity: ThermalConductivityQuantity(value: 7.0, unit: .wattsPerMeterKelvin),
            thermalExpansion: ThermalExpansionQuantity(value: 8.5, unit: .microstrainPerKelvin),
            specificHeat: SpecificHeatQuantity(value: 520, unit: .joulesPerKilogramKelvin)
        )
    }

    @Test func testMissingFileReturnsEmptyArray() {
        let (store, tempDir) = makeTemporaryStore()
        defer { cleanup(directoryURL: tempDir) }

        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        let loaded = store.loadMaterials()
        #expect(loaded.isEmpty)
    }

    @Test func testSaveAndLoadMaterials() throws {
        let (store, tempDir) = makeTemporaryStore()
        defer { cleanup(directoryURL: tempDir) }

        let mat1 = sampleMaterial(id: "custom-1", name: "Custom Alloy 1")
        let mat2 = sampleMaterial(id: "custom-2", name: "Custom Resin 2")

        try store.saveMaterials([mat1, mat2])

        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        let loaded = store.loadMaterials()
        #expect(loaded.count == 2)
        #expect(loaded[0].id == "custom-1")
        #expect(loaded[0].name == "Custom Alloy 1")
        #expect(loaded[1].id == "custom-2")
        #expect(loaded[1].name == "Custom Resin 2")
    }

    @Test func testAddUpdateAndRemoveMaterial() throws {
        let (store, tempDir) = makeTemporaryStore()
        defer { cleanup(directoryURL: tempDir) }

        let mat1 = sampleMaterial(id: "custom-1", name: "Original Name")
        try store.addMaterial(mat1)

        #expect(store.loadMaterials().count == 1)
        #expect(store.material(withId: "custom-1")?.name == "Original Name")

        // Reject duplicate ID
        #expect(throws: UserMaterialStoreError.duplicateIdentifier("custom-1")) {
            try store.addMaterial(mat1)
        }

        // Reject empty name on add
        var emptyNameMat = sampleMaterial(id: "custom-empty", name: "   ")
        #expect(throws: UserMaterialStoreError.emptyName) {
            try store.addMaterial(emptyNameMat)
        }

        // Update material
        var updated = mat1
        updated.name = "Updated Name"
        updated.description = "Updated description"
        try store.updateMaterial(updated)

        let loadedUpdated = store.material(withId: "custom-1")
        #expect(loadedUpdated?.name == "Updated Name")
        #expect(loadedUpdated?.description == "Updated description")

        // Reject update with empty name
        emptyNameMat.id = "custom-1"
        #expect(throws: UserMaterialStoreError.emptyName) {
            try store.updateMaterial(emptyNameMat)
        }

        // Reject update of non-existent material
        let nonExistent = sampleMaterial(id: "does-not-exist", name: "Valid")
        #expect(throws: UserMaterialStoreError.materialNotFound("does-not-exist")) {
            try store.updateMaterial(nonExistent)
        }

        // Remove material
        try store.removeMaterial(id: "custom-1")
        #expect(store.loadMaterials().isEmpty)
        #expect(store.material(withId: "custom-1") == nil)

        // Reject removal of non-existent material
        #expect(throws: UserMaterialStoreError.materialNotFound("custom-1")) {
            try store.removeMaterial(id: "custom-1")
        }
    }

    @Test func testCorruptedFileRecoversGracefully() throws {
        let (store, tempDir) = makeTemporaryStore()
        defer { cleanup(directoryURL: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let corruptData = Data("{\"not_a_valid_material_array\": true}".utf8)
        try corruptData.write(to: store.fileURL)

        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        let loaded = store.loadMaterials()
        #expect(loaded.isEmpty)
    }
}
