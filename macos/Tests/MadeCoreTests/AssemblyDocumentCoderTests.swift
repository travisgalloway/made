import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct AssemblyDocumentCoderTests {

    @Test func testManifestDocumentTypeRoundTrip() throws {
        var manifest = MadeManifest(documentType: .assembly)
        #expect(manifest.documentType == .assembly)

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(MadeManifest.self, from: data)
        #expect(decoded.documentType == .assembly)

        manifest.documentType = .part
        let partData = try JSONEncoder().encode(manifest)
        let decodedPart = try JSONDecoder().decode(MadeManifest.self, from: partData)
        #expect(decodedPart.documentType == .part)
    }

    @Test func testManifestBackwardCompatibilityDefaultsToPart() throws {
        let legacyManifestJSON = """
        {
          "formatVersion": 2,
          "appVersion": "1.0.0",
          "createdAt": "2026-01-01T00:00:00Z",
          "modifiedAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MadeManifest.self, from: legacyManifestJSON)
        #expect(decoded.documentType == .part)
    }

    @Test func testDocumentDataAssemblyRoundTrip() throws {
        let instance = ComponentInstance(
            name: "Mount Bracket",
            reference: .internalPart(name: "BracketPart"),
            transform: Transform(
                position: SIMD3<Float>(12.5, -45.0, 78.0),
                rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(15, 30, 45)),
                scale: SIMD3<Float>(1, 1, 1)
            )
        )

        let doc = DocumentModel(
            documentType: .assembly,
            componentInstances: [instance]
        )

        let encoded = try DocumentModelCoder.encode(document: doc)
        let decoded = try DocumentModelCoder.decode(from: encoded)

        #expect(decoded.documentType == DocumentType.assembly)
        #expect(decoded.componentInstances?.count == 1)
        #expect(decoded.componentInstances?.first?.name == "Mount Bracket")
        #expect(decoded.componentInstances?.first?.transform.position == SIMD3<Float>(12.5, -45.0, 78.0))
    }

    @Test func testDecodeIntoDocumentModelRestoresAssembly() throws {
        let instance = ComponentInstance(
            name: "Coupling",
            reference: .externalDocument(url: URL(fileURLWithPath: "/parts/coupling.made")),
            transform: Transform(position: SIMD3<Float>(0, 10, 20))
        )

        let sourceDoc = DocumentModel(
            documentType: .assembly,
            componentInstances: [instance]
        )

        let encoded = try DocumentModelCoder.encode(document: sourceDoc)

        let targetDoc = DocumentModel()
        #expect(targetDoc.documentType == .part)
        #expect(targetDoc.componentInstances.isEmpty)

        try DocumentModelCoder.decode(into: targetDoc, from: encoded)

        #expect(targetDoc.documentType == .assembly)
        #expect(targetDoc.componentInstances.count == 1)
        #expect(targetDoc.componentInstances.first?.name == "Coupling")
        #expect(targetDoc.objects.contains(where: { $0.id == instance.solidId }))
    }

    @Test func testLegacyDocumentDataWithoutDocumentTypeDefaultsToPart() throws {
        let legacyDocJSON = """
        {
          "schemaVersion": 2,
          "objects": []
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyDocJSON)
        #expect(decoded.documentType == nil || decoded.documentType == .part)
        #expect(decoded.componentInstances == nil || decoded.componentInstances?.isEmpty == true)

        let targetDoc = DocumentModel()
        try DocumentModelCoder.decode(into: targetDoc, from: legacyDocJSON)
        #expect(targetDoc.documentType == .part)
        #expect(targetDoc.componentInstances.isEmpty)
    }

    @Test func testMadePackageAssemblyFileWrapperRoundTrip() throws {
        let instance = ComponentInstance(
            name: "Rotor",
            reference: .internalPart(name: "RotorPart"),
            transform: Transform(position: SIMD3<Float>(5, 15, 25))
        )

        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            objects: [instance.toSceneObject()],
            documentType: .assembly,
            componentInstances: [instance]
        )

        let manifest = MadeManifest(documentType: .assembly)
        let package = MadePackage(manifest: manifest, documentData: docData)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AssemblyPackage-\(UUID().uuidString).made")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileWrapper = try package.makeFileWrapper()
        try fileWrapper.write(to: tempDir, options: .atomic, originalContentsURL: nil)

        let reopened = try MadePackage(directoryURL: tempDir)
        #expect(reopened.manifest.documentType == .assembly)

        let reopenedDoc = DocumentModel()
        let encodedData = try DocumentModelCoder.encode(reopened.documentData)
        try DocumentModelCoder.decode(into: reopenedDoc, from: encodedData)

        #expect(reopenedDoc.documentType == .assembly)
        #expect(reopenedDoc.componentInstances.count == 1)
        #expect(reopenedDoc.componentInstances.first?.name == "Rotor")
        #expect(reopenedDoc.componentInstances.first?.transform.position == SIMD3<Float>(5, 15, 25))
        #expect(reopenedDoc.objects.contains(where: { $0.id == instance.solidId }))
    }
}
