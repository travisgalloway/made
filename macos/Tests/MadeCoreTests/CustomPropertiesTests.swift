import Testing
import Foundation
@testable import MadeCore

@Suite @MainActor struct CustomPropertiesTests {

    // MARK: - Constants and Dictionary Helpers

    @Test func testCustomPropertyKeyConstants() {
        #expect(CustomPropertyKey.partNumber == "partNumber")
        #expect(CustomPropertyKey.description == "description")
        #expect(CustomPropertyKey.revision == "revision")
        #expect(CustomPropertyKey.vendor == "vendor")
        #expect(CustomPropertyKey.standardKeys == ["partNumber", "description", "revision", "vendor"])
    }

    @Test func testDictionarySettingPropertyHelpers() {
        var dict: [String: String] = [:]

        // Add standard and custom properties
        dict = dict.settingProperty(key: "partNumber", value: "PN-100")
        dict = dict.settingProperty(key: " vendor ", value: "Acme Corp")
        dict = dict.settingProperty(key: "color", value: "blue")

        #expect(dict["partNumber"] == "PN-100")
        #expect(dict["vendor"] == "Acme Corp")
        #expect(dict["color"] == "blue")
        #expect(dict.property(forKey: "partNumber") == "PN-100")
        #expect(dict.property(forKey: " vendor ") == "Acme Corp")
        #expect(dict.property(forKey: "nonexistent") == nil)

        // Custom properties filter
        let custom = dict.customProperties
        #expect(custom.count == 1)
        #expect(custom["color"] == "blue")
        #expect(custom["partNumber"] == nil)
        #expect(custom["vendor"] == nil)

        // Whitespace-only and empty keys are rejected
        let unchanged = dict.settingProperty(key: "", value: "val")
        #expect(unchanged == dict)
        let unchanged2 = dict.settingProperty(key: "   \n\t ", value: "val")
        #expect(unchanged2 == dict)

        // Empty value or nil removes key
        dict = dict.settingProperty(key: "color", value: "")
        #expect(dict["color"] == nil)
        #expect(dict.customProperties.isEmpty)

        dict = dict.settingProperty(key: "partNumber", value: nil)
        #expect(dict["partNumber"] == nil)

        // Duplicate keys update values
        dict = dict.settingProperty(key: "material", value: "Steel")
        #expect(dict["material"] == "Steel")
        dict = dict.settingProperty(key: "material", value: "Aluminum")
        #expect(dict["material"] == "Aluminum")
    }

    // MARK: - MadeManifest Accessors and Serialization

    @Test func testMadeManifestAccessorsAndSerialization() throws {
        var manifest = MadeManifest(
            schemaVersion: 2,
            appVersion: "0.1",
            metadata: [
                CustomPropertyKey.partNumber: "BRK-001",
                CustomPropertyKey.description: "Mounting Bracket",
                CustomPropertyKey.revision: "B.2",
                CustomPropertyKey.vendor: "Fastenal",
                "Weight": "120g",
                "Finish": "Anodized"
            ]
        )

        #expect(manifest.partNumber == "BRK-001")
        #expect(manifest.itemDescription == "Mounting Bracket")
        #expect(manifest.revision == "B.2")
        #expect(manifest.vendor == "Fastenal")
        #expect(manifest.customProperties.count == 2)
        #expect(manifest.customProperties["Weight"] == "120g")
        #expect(manifest.customProperties["Finish"] == "Anodized")

        // Mutate through protocol accessors
        manifest.revision = "C.0"
        manifest.setProperty(key: "Finish", value: "Powder Coated")
        manifest.setProperty(key: "Weight", value: nil)

        #expect(manifest.revision == "C.0")
        #expect(manifest.customProperties["Finish"] == "Powder Coated")
        #expect(manifest.customProperties["Weight"] == nil)

        // Encode and decode round trip
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(manifest)
        let decoded = try decoder.decode(MadeManifest.self, from: data)

        #expect(decoded.schemaVersion == manifest.schemaVersion)
        #expect(decoded.partNumber == "BRK-001")
        #expect(decoded.itemDescription == "Mounting Bracket")
        #expect(decoded.revision == "C.0")
        #expect(decoded.vendor == "Fastenal")
        #expect(decoded.customProperties["Finish"] == "Powder Coated")
        #expect(decoded.customProperties["Weight"] == nil)
    }

    @Test func testLegacyMadeManifestWithoutMetadataDecodesCleanly() throws {
        let json = """
        {
            "schemaVersion": 2,
            "appVersion": "0.1",
            "documentSettings": {
                "unitSettings": {
                    "lengthUnit": "millimeter",
                    "angleUnit": "degree",
                    "decimalPrecision": 3
                },
                "tolerances": {
                    "linearTolerance": 0.001,
                    "angularTolerance": 0.01,
                    "chordalTolerance": 0.005
                }
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let manifest = try decoder.decode(MadeManifest.self, from: json)
        #expect(manifest.metadata.isEmpty)
        #expect(manifest.partNumber == nil)
        #expect(manifest.itemDescription == nil)
        #expect(manifest.revision == nil)
        #expect(manifest.vendor == nil)
        #expect(manifest.customProperties.isEmpty)
    }

    // MARK: - DocumentModel Accessors and Undo / Redo

    @Test func testDocumentModelMetadataMutatorsAndUndoRedo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        undoManager.groupsByEvent = false

        #expect(doc.metadata.isEmpty)
        #expect(doc.partNumber == nil)

        // Set document properties
        undoManager.beginUndoGrouping()
        doc.setDocumentProperty(key: CustomPropertyKey.partNumber, value: "DOC-99")
        undoManager.endUndoGrouping()

        #expect(doc.partNumber == "DOC-99")
        #expect(doc.metadata[CustomPropertyKey.partNumber] == "DOC-99")

        undoManager.beginUndoGrouping()
        doc.setDocumentProperty(key: "Project", value: "Apollo")
        undoManager.endUndoGrouping()

        #expect(doc.property(forKey: "Project") == "Apollo")
        #expect(doc.customProperties["Project"] == "Apollo")

        // Undo setting custom property
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(doc.property(forKey: "Project") == nil)
        #expect(doc.partNumber == "DOC-99")

        // Redo setting custom property
        #expect(undoManager.canRedo)
        undoManager.redo()
        #expect(doc.property(forKey: "Project") == "Apollo")

        // Undo setting standard property
        undoManager.undo()
        undoManager.undo()
        #expect(doc.partNumber == nil)
        #expect(doc.metadata.isEmpty)

        // Redo both
        undoManager.redo()
        #expect(doc.partNumber == "DOC-99")
        undoManager.redo()
        #expect(doc.partNumber == "DOC-99")
        #expect(doc.property(forKey: "Project") == "Apollo")
    }

    @Test func testDocumentModelMetadataSetAllAndUndoRedo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        undoManager.groupsByEvent = false

        let initial: [String: String] = [
            CustomPropertyKey.partNumber: "BASE-01",
            "Tag": "Prototype"
        ]

        undoManager.beginUndoGrouping()
        doc.setDocumentMetadata(initial)
        undoManager.endUndoGrouping()

        #expect(doc.partNumber == "BASE-01")
        #expect(doc.property(forKey: "Tag") == "Prototype")

        let updated: [String: String] = [
            CustomPropertyKey.partNumber: "BASE-02",
            CustomPropertyKey.revision: "A",
            "Tag": "Production"
        ]

        undoManager.beginUndoGrouping()
        doc.setDocumentMetadata(updated)
        undoManager.endUndoGrouping()

        #expect(doc.partNumber == "BASE-02")
        #expect(doc.revision == "A")
        #expect(doc.property(forKey: "Tag") == "Production")

        undoManager.undo()
        #expect(doc.partNumber == "BASE-01")
        #expect(doc.revision == nil)
        #expect(doc.property(forKey: "Tag") == "Prototype")

        undoManager.redo()
        #expect(doc.partNumber == "BASE-02")
        #expect(doc.revision == "A")
        #expect(doc.property(forKey: "Tag") == "Production")
    }

    // MARK: - Feature Metadata, Propagation, and Undo / Redo

    @Test func testFeatureMetadataAndPropagationToSceneObject() {
        let featureId = UUID()
        let solidId = ObjectId("solid-1")
        let feature = Feature(
            id: featureId,
            name: "Box 1",
            operation: .primitive(.box(BoxParams(width: 10, depth: 10, height: 10))),
            outputSolidId: solidId,
            metadata: [
                CustomPropertyKey.partNumber: "PART-EXT-1",
                CustomPropertyKey.description: "Extruded Solid",
                "ColorCode": "#FF5733"
            ]
        )

        #expect(feature.partNumber == "PART-EXT-1")
        #expect(feature.itemDescription == "Extruded Solid")
        #expect(feature.customProperties["ColorCode"] == "#FF5733")

        let sceneObj = feature.toSceneObject()
        #expect(sceneObj != nil)
        #expect(sceneObj?.metadata[CustomPropertyKey.partNumber] == "PART-EXT-1")
        #expect(sceneObj?.metadata[CustomPropertyKey.description] == "Extruded Solid")
        #expect(sceneObj?.metadata["ColorCode"] == "#FF5733")

        let body = Body(from: sceneObj!)
        #expect(body.metadata[CustomPropertyKey.partNumber] == "PART-EXT-1")
        #expect(body.customProperties["ColorCode"] == "#FF5733")

        let roundTripObj = body.toSceneObject(def: sceneObj!.def)
        #expect(roundTripObj.metadata[CustomPropertyKey.partNumber] == "PART-EXT-1")
        #expect(roundTripObj.metadata["ColorCode"] == "#FF5733")
    }

    @Test func testDocumentModelFeaturePropertyMutationAndUndoRedo() {
        let featureId = UUID()
        let solidId = ObjectId("solid-1")
        let feature = Feature(
            id: featureId,
            name: "Box 1",
            operation: .primitive(.box(BoxParams(width: 10, depth: 10, height: 10))),
            outputSolidId: solidId,
            metadata: [CustomPropertyKey.partNumber: "INITIAL-PN"]
        )

        let doc = DocumentModel(features: [feature])
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        undoManager.groupsByEvent = false

        #expect(doc.objects.first?.metadata[CustomPropertyKey.partNumber] == "INITIAL-PN")

        // Mutate feature property
        undoManager.beginUndoGrouping()
        doc.setFeatureProperty(id: featureId, key: CustomPropertyKey.partNumber, value: "UPDATED-PN")
        undoManager.endUndoGrouping()

        #expect(doc.features[0].metadata[CustomPropertyKey.partNumber] == "UPDATED-PN")
        #expect(doc.objects.first?.metadata[CustomPropertyKey.partNumber] == "UPDATED-PN")

        // Add custom property via setBodyProperty
        undoManager.beginUndoGrouping()
        doc.setBodyProperty(id: solidId, key: "Vendor", value: "SteelCo")
        undoManager.endUndoGrouping()

        #expect(doc.features[0].metadata["Vendor"] == "SteelCo")
        #expect(doc.objects.first?.metadata["Vendor"] == "SteelCo")

        // Undo custom property
        undoManager.undo()
        #expect(doc.features[0].metadata["Vendor"] == nil)
        #expect(doc.objects.first?.metadata["Vendor"] == nil)
        #expect(doc.features[0].metadata[CustomPropertyKey.partNumber] == "UPDATED-PN")

        // Undo standard property update
        undoManager.undo()
        #expect(doc.features[0].metadata[CustomPropertyKey.partNumber] == "INITIAL-PN")
        #expect(doc.objects.first?.metadata[CustomPropertyKey.partNumber] == "INITIAL-PN")

        // Redo both
        undoManager.redo()
        #expect(doc.features[0].metadata[CustomPropertyKey.partNumber] == "UPDATED-PN")
        undoManager.redo()
        #expect(doc.features[0].metadata["Vendor"] == "SteelCo")
    }

    // MARK: - Component Instance Metadata and Undo / Redo

    @Test func testComponentInstanceMetadataAndUndoRedo() {
        let compId = ComponentInstanceId()
        let comp = ComponentInstance(
            id: compId,
            name: "Bracket Inst 1",
            reference: .internalPart(name: "Bracket", bodyId: ObjectId("body-b")),
            metadata: [
                CustomPropertyKey.partNumber: "COMP-BRK-01",
                CustomPropertyKey.vendor: "Supplier X"
            ]
        )

        #expect(comp.partNumber == "COMP-BRK-01")
        #expect(comp.vendor == "Supplier X")

        let doc = DocumentModel(documentType: .assembly, componentInstances: [comp])
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        undoManager.groupsByEvent = false

        let sceneObj = doc.objects.first(where: { $0.id == comp.solidId })
        #expect(sceneObj?.metadata[CustomPropertyKey.partNumber] == "COMP-BRK-01")

        // Mutate component property
        undoManager.beginUndoGrouping()
        doc.setComponentInstanceProperty(id: compId, key: CustomPropertyKey.revision, value: "Rev-2")
        undoManager.endUndoGrouping()

        #expect(doc.componentInstances[0].metadata[CustomPropertyKey.revision] == "Rev-2")
        #expect(doc.objects.first(where: { $0.id == comp.solidId })?.metadata[CustomPropertyKey.revision] == "Rev-2")

        // Mutate via setBodyProperty
        undoManager.beginUndoGrouping()
        doc.setBodyProperty(id: comp.solidId, key: "Batch", value: "B-404")
        undoManager.endUndoGrouping()

        #expect(doc.componentInstances[0].metadata["Batch"] == "B-404")

        // Undo
        undoManager.undo()
        #expect(doc.componentInstances[0].metadata["Batch"] == nil)
        #expect(doc.componentInstances[0].metadata[CustomPropertyKey.revision] == "Rev-2")

        undoManager.undo()
        #expect(doc.componentInstances[0].metadata[CustomPropertyKey.revision] == nil)

        // Redo
        undoManager.redo()
        #expect(doc.componentInstances[0].metadata[CustomPropertyKey.revision] == "Rev-2")
        undoManager.redo()
        #expect(doc.componentInstances[0].metadata["Batch"] == "B-404")
    }

    // MARK: - Edge Cases and Unicode Round-Trip

    @Test func testEdgeCasesAndUnicodeMetadata() throws {
        let unicodeDoc = DocumentModel()
        let key = "零件编号 🚀"
        let val = "测试值 123 — 🌟"

        unicodeDoc.setDocumentProperty(key: key, value: val)
        #expect(unicodeDoc.property(forKey: key) == val)
        #expect(unicodeDoc.customProperties[key] == val)

        // Special characters in keys and values
        let specialKey = "Key:With/Special=Chars#&?"
        let specialVal = "Value: \"Quotes\", newline\n, tab\t"
        unicodeDoc.setDocumentProperty(key: specialKey, value: specialVal)
        #expect(unicodeDoc.property(forKey: specialKey) == specialVal)

        // Whitespace trimming in key
        unicodeDoc.setDocumentProperty(key: "  PaddedKey  ", value: "Trimmed")
        #expect(unicodeDoc.property(forKey: "PaddedKey") == "Trimmed")
        #expect(unicodeDoc.property(forKey: "  PaddedKey  ") == "Trimmed")

        // Empty key rejection
        unicodeDoc.setDocumentProperty(key: "", value: "EmptyKey")
        #expect(unicodeDoc.property(forKey: "") == nil)
        unicodeDoc.setDocumentProperty(key: "   ", value: "WhitespaceKey")
        #expect(unicodeDoc.property(forKey: "   ") == nil)

        // Empty value removes key
        unicodeDoc.setDocumentProperty(key: "PaddedKey", value: "")
        #expect(unicodeDoc.property(forKey: "PaddedKey") == nil)

        // Encode manifest with unicode and special characters
        let manifest = MadeManifest(
            schemaVersion: 2,
            appVersion: "0.1",
            metadata: unicodeDoc.metadata
        )
        let data = try JSONEncoder().encode(manifest)
        let decodedManifest = try JSONDecoder().decode(MadeManifest.self, from: data)
        #expect(decodedManifest.property(forKey: key) == val)
        #expect(decodedManifest.property(forKey: specialKey) == specialVal)
    }

    // MARK: - Package Round-Trip Verification

    @Test func testPackageSerializationWithMetadataRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("TestPart.made")

        let featureId = UUID()
        let solidId = ObjectId("solid-box")
        let feature = Feature(
            id: featureId,
            name: "Box Feature",
            operation: .primitive(.box(BoxParams(width: 10, depth: 10, height: 10))),
            outputSolidId: solidId,
            metadata: [
                CustomPropertyKey.partNumber: "BOX-001",
                CustomPropertyKey.vendor: "BoxCorp",
                "Weight": "500g"
            ]
        )

        let manifest = MadeManifest(
            schemaVersion: MadeManifest.currentSchemaVersion,
            appVersion: "0.1",
            metadata: [
                CustomPropertyKey.partNumber: "DOC-BOX-MAIN",
                CustomPropertyKey.description: "Main Box Document",
                "Project": "Cube"
            ]
        )

        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            features: [feature],
            objects: [feature.toSceneObject()!],
            bodies: [Body(from: feature.toSceneObject()!)]
        )

        let package = MadePackage(
            manifest: manifest,
            documentData: docData,
            assets: [:]
        )

        let fileWrapper = try package.makeFileWrapper(packageURL: packageURL)
        try fileWrapper.write(to: packageURL, options: .atomic, originalContentsURL: nil)

        let readPackage = try MadePackage(directoryURL: packageURL)

        #expect(readPackage.manifest.partNumber == "DOC-BOX-MAIN")
        #expect(readPackage.manifest.itemDescription == "Main Box Document")
        #expect(readPackage.manifest.customProperties["Project"] == "Cube")

        let readFeatures = readPackage.documentData.features
        #expect(readFeatures?.count == 1)
        let readFeature = readFeatures?[0]
        #expect(readFeature?.partNumber == "BOX-001")
        #expect(readFeature?.vendor == "BoxCorp")
        #expect(readFeature?.customProperties["Weight"] == "500g")
    }
}
