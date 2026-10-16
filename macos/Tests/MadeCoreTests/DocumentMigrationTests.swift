import Testing
import Foundation
@testable import MadeCore

@Suite struct DocumentMigrationTests {
    @Test func testMigratorRegistersAndExecutesV1ToV2Migration() throws {
        let v1Manifest = MadeManifest(schemaVersion: 1, appVersion: "0.1")
        let v1ManifestJSON = try DocumentModelCoder.makeJSONEncoder().encode(v1Manifest)

        let v1DocJSON = """
        {
          "objects" : [
            {
              "def" : {
                "kind" : "box",
                "params" : {
                  "depth" : 30,
                  "height" : 20,
                  "width" : 40
                }
              },
              "id" : "box-1",
              "isVisible" : true,
              "name" : "Box 1"
            }
          ],
          "schemaVersion" : 1
        }
        """.data(using: .utf8)!

        var package = DocumentPackageData(manifestData: v1ManifestJSON, documentData: v1DocJSON)
        let migrator = DocumentMigrator(migrations: [MigrationV1ToV2()])

        try migrator.migrate(package: &package, from: 1, to: 2)

        // Verify canonical formatting (trailing newline)
        #expect(package.manifestData.last == UInt8(ascii: "\n"))
        #expect(package.documentData.last == UInt8(ascii: "\n"))

        // Verify manifest migration
        let manifest = try JSONDecoder().decode(MadeManifest.self, from: package.manifestData)
        #expect(manifest.schemaVersion == 2)
        #expect(manifest.metadata.isEmpty)

        // Verify document migration and feature synthesis
        let docData = try DocumentModelCoder.decode(from: package.documentData)
        #expect(docData.schemaVersion == 2)
        #expect(docData.features?.count == 1)
        #expect(docData.objects.count == 1)
        #expect(docData.objects.first?.id == ObjectId("box-1"))
        #expect(docData.features?.first?.outputSolidId == SolidId("box-1"))
    }

    @Test func testMigratorChainingMultipleSteps() throws {
        struct MigrationV2ToV3: DocumentMigration {
            let sourceVersion: Int = 2
            let targetVersion: Int = 3

            func migrate(package: inout DocumentPackageData) throws {
                guard var manifestDict = try JSONSerialization.jsonObject(with: package.manifestData) as? [String: Any],
                      var docDict = try JSONSerialization.jsonObject(with: package.documentData) as? [String: Any] else {
                    throw MadeDocumentError.corruptDocument("Invalid JSON")
                }
                manifestDict["schemaVersion"] = 3
                manifestDict["v3Marker"] = true
                docDict["schemaVersion"] = 3
                docDict["v3Marker"] = true
                package.manifestData = try DocumentModelCoder.canonicalJSONData(from: manifestDict)
                package.documentData = try DocumentModelCoder.canonicalJSONData(from: docDict)
            }
        }

        let v1Manifest = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        let v1Doc = "{\"schemaVersion\": 1, \"objects\": []}\n".data(using: .utf8)!
        var package = DocumentPackageData(manifestData: v1Manifest, documentData: v1Doc)

        let migrator = DocumentMigrator(migrations: [MigrationV1ToV2()])
        migrator.register(MigrationV2ToV3())

        try migrator.migrate(package: &package, from: 1, to: 3)

        let manifestDict = try JSONSerialization.jsonObject(with: package.manifestData) as? [String: Any]
        #expect(manifestDict?["schemaVersion"] as? Int == 3)
        #expect(manifestDict?["v3Marker"] as? Bool == true)

        let docDict = try JSONSerialization.jsonObject(with: package.documentData) as? [String: Any]
        #expect(docDict?["schemaVersion"] as? Int == 3)
        #expect(docDict?["v3Marker"] as? Bool == true)
        #expect(docDict?["features"] != nil)
    }

    @Test func testMigratorMissingPathThrowsUnsupportedSchemaVersion() throws {
        struct MigrationV3ToV4: DocumentMigration {
            let sourceVersion: Int = 3
            let targetVersion: Int = 4
            func migrate(package: inout DocumentPackageData) throws {}
        }

        let v1Manifest = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        let v1Doc = "{\"schemaVersion\": 1, \"objects\": []}\n".data(using: .utf8)!
        var package = DocumentPackageData(manifestData: v1Manifest, documentData: v1Doc)

        let migrator = DocumentMigrator(migrations: [MigrationV1ToV2(), MigrationV3ToV4()])

        #expect(throws: MadeDocumentError.unsupportedSchemaVersion(1)) {
            try migrator.migrate(package: &package, from: 1, to: 4)
        }
    }

    @Test func testMigratorSameVersionIsNoOp() throws {
        let manifestData = "{\"schemaVersion\": 2, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        let docData = "{\"schemaVersion\": 2, \"objects\": []}\n".data(using: .utf8)!
        var package = DocumentPackageData(manifestData: manifestData, documentData: docData)

        let migrator = DocumentMigrator(migrations: [MigrationV1ToV2()])
        try migrator.migrate(package: &package, from: 2, to: 2)

        #expect(package.manifestData == manifestData)
        #expect(package.documentData == docData)
    }

    @Test func testMigratorBackwardVersionThrowsUnsupportedSchemaVersion() throws {
        let manifestData = "{\"schemaVersion\": 2}\n".data(using: .utf8)!
        let docData = "{\"schemaVersion\": 2}\n".data(using: .utf8)!
        var package = DocumentPackageData(manifestData: manifestData, documentData: docData)

        let migrator = DocumentMigrator(migrations: [MigrationV1ToV2()])
        #expect(throws: MadeDocumentError.unsupportedSchemaVersion(2)) {
            try migrator.migrate(package: &package, from: 2, to: 1)
        }
    }

    @Test func testMigratorRejectsCorruptJSONDuringMigration() throws {
        let migrator = DocumentMigrator(migrations: [MigrationV1ToV2()])

        // Corrupt manifest
        var corruptManifestPackage = DocumentPackageData(
            manifestData: "NOT_VALID_JSON".data(using: .utf8)!,
            documentData: "{\"schemaVersion\": 1, \"objects\": []}\n".data(using: .utf8)!
        )
        #expect {
            try migrator.migrate(package: &corruptManifestPackage, from: 1, to: 2)
        } throws: { error in
            guard case .corruptDocument(let details) = error as? MadeDocumentError else { return false }
            return details.contains("manifest.json is invalid")
        }

        // Corrupt document
        var corruptDocPackage = DocumentPackageData(
            manifestData: "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!,
            documentData: "NOT_VALID_JSON".data(using: .utf8)!
        )
        #expect {
            try migrator.migrate(package: &corruptDocPackage, from: 1, to: 2)
        } throws: { error in
            guard case .corruptDocument(let details) = error as? MadeDocumentError else { return false }
            return details.contains("document.json is invalid")
        }
    }

    @Test func testMigrationV1ToV2PreservesExistingFeatures() throws {
        let feature = Feature.makeBox(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            solidId: SolidId("box-1"),
            params: BoxParams(width: 30, depth: 20, height: 10)
        )
        let initialDocData = DocumentData(
            schemaVersion: 1,
            features: [feature],
            objects: [
                SceneObject(id: ObjectId("box-1"), def: .box(BoxParams(width: 30, depth: 20, height: 10)))
            ]
        )
        let docJSONWithFeatures = try DocumentModelCoder.encode(initialDocData)

        let manifestJSON = "{\"schemaVersion\": 1, \"appVersion\": \"0.1\"}\n".data(using: .utf8)!
        var package = DocumentPackageData(manifestData: manifestJSON, documentData: docJSONWithFeatures)

        let migrator = DocumentMigrator(migrations: [MigrationV1ToV2()])
        try migrator.migrate(package: &package, from: 1, to: 2)

        let docData = try DocumentModelCoder.decode(from: package.documentData)
        #expect(docData.schemaVersion == 2)
        #expect(docData.features?.count == 1)
        #expect(docData.features?.first?.name == feature.name)
        #expect(docData.features?.first?.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    }
}
