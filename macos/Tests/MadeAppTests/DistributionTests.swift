import Foundation
import Testing
@testable import MadeApp
import MadeCore

@Suite struct DistributionTests {
    static let macosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func testInfoPListIdentifiersAndConfig() throws {
        let appPlistURL = Self.macosRoot.appendingPathComponent("Support/MadeApp-Info.plist")
        let servicePlistURL = Self.macosRoot.appendingPathComponent("Support/MadeKernelService-Info.plist")

        #expect(FileManager.default.fileExists(atPath: appPlistURL.path))
        #expect(FileManager.default.fileExists(atPath: servicePlistURL.path))

        let appData = try Data(contentsOf: appPlistURL)
        let serviceData = try Data(contentsOf: servicePlistURL)

        guard let appDict = try PropertyListSerialization.propertyList(from: appData, options: [], format: nil) as? [String: Any],
              let serviceDict = try PropertyListSerialization.propertyList(from: serviceData, options: [], format: nil) as? [String: Any] else {
            Issue.record("Failed to deserialize Info.plist files")
            return
        }

        #expect(appDict["CFBundleIdentifier"] as? String == "com.made.app")
        #expect(appDict["CFBundlePackageType"] as? String == "APPL")
        #expect(appDict["LSMinimumSystemVersion"] as? String == "26.0")

        #expect(serviceDict["CFBundleIdentifier"] as? String == "com.made.app.kernel")
        #expect(serviceDict["CFBundlePackageType"] as? String == "XPC!")
        #expect(serviceDict["LSMinimumSystemVersion"] as? String == "26.0")
    }

    @Test func testAppVersionFormatting() {
        let version = AppVersion(marketingVersion: "0.2.1", buildNumber: "42")
        #expect(version.marketingVersion == "0.2.1")
        #expect(version.buildNumber == "42")
        #expect(version.displayString == "Version 0.2.1 (42)")

        let current = AppVersion.current
        #expect(!current.marketingVersion.isEmpty)
        #expect(!current.buildNumber.isEmpty)
        #expect(current.displayString.hasPrefix("Version "))
    }

    @Test @MainActor func testUserDefaultsPersistenceAcrossVersionUpdate() {
        let suiteName = "test.domain.\(UUID().uuidString)"
        guard let customDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test UserDefaults suite")
            return
        }
        defer { customDefaults.removePersistentDomain(forName: suiteName) }

        // Initialize workspace on "version 0.1" and set user preferences
        let v1Workspace = WorkspaceModel(defaults: customDefaults)
        v1Workspace.lengthUnit = .inches
        v1Workspace.angleUnit = .radians
        v1Workspace.decimalPrecision = 4
        v1Workspace.navigationPreset = .solidWorks
        v1Workspace.displayMode = .wireframe
        v1Workspace.showsGrid = false
        v1Workspace.showsAxes = false
        v1Workspace.showsGizmo = false
        v1Workspace.showsEdges = false
        v1Workspace.commandPanelPlacement = .inspector
        v1Workspace.kernelTolerances = KernelTolerances(linearTolerance: 0.05, angularTolerance: 0.5, chordalTolerance: 0.1)

        // Simulate app upgrade to "version 0.2": fresh workspace pointing to same UserDefaults domain
        let v2Workspace = WorkspaceModel(defaults: customDefaults)

        #expect(v2Workspace.lengthUnit == .inches)
        #expect(v2Workspace.angleUnit == .radians)
        #expect(v2Workspace.decimalPrecision == 4)
        #expect(v2Workspace.navigationPreset == .solidWorks)
        #expect(v2Workspace.displayMode == .wireframe)
        #expect(v2Workspace.showsGrid == false)
        #expect(v2Workspace.showsAxes == false)
        #expect(v2Workspace.showsGizmo == false)
        #expect(v2Workspace.showsEdges == false)
        #expect(v2Workspace.commandPanelPlacement == .inspector)
        #expect(v2Workspace.kernelTolerances.linearTolerance == 0.05)
        #expect(v2Workspace.kernelTolerances.angularTolerance == 0.5)
        #expect(v2Workspace.kernelTolerances.chordalTolerance == 0.1)
    }

    @Test @MainActor func testDocumentPackageBackwardCompatibility() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "name": "Legacy Box",
              "def": {
                "kind": "box",
                "params": {
                  "width": 50.0,
                  "depth": 25.0,
                  "height": 15.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyJSON)
        #expect(decoded.bodies?.count == 1)
        #expect(decoded.bodies?.first?.name == "Legacy Box")
        #expect(decoded.bodies?.first?.id == SolidId("box-1"))

        let doc = DocumentModel()
        try DocumentModelCoder.decode(into: doc, from: legacyJSON)
        #expect(doc.bodies.count == 1)
        #expect(doc.bodies.first?.name == "Legacy Box")
    }

    @Test func testEntitlementsPListSyntax() throws {
        let appEntitlementsURL = Self.macosRoot.appendingPathComponent("Support/MadeApp.entitlements")
        let serviceEntitlementsURL = Self.macosRoot.appendingPathComponent("Support/MadeKernelService.entitlements")

        #expect(FileManager.default.fileExists(atPath: appEntitlementsURL.path))
        #expect(FileManager.default.fileExists(atPath: serviceEntitlementsURL.path))

        let appData = try Data(contentsOf: appEntitlementsURL)
        let serviceData = try Data(contentsOf: serviceEntitlementsURL)

        guard let appDict = try PropertyListSerialization.propertyList(from: appData, options: [], format: nil) as? [String: Any],
              let serviceDict = try PropertyListSerialization.propertyList(from: serviceData, options: [], format: nil) as? [String: Any] else {
            Issue.record("Failed to deserialize entitlements property lists")
            return
        }

        #expect(appDict["com.apple.security.cs.allow-jit"] as? Bool == true)
        #expect(appDict["com.apple.security.cs.allow-unsigned-executable-memory"] as? Bool == false)
        #expect(appDict["com.apple.security.cs.disable-library-validation"] as? Bool == false)

        #expect(serviceDict["com.apple.security.cs.allow-jit"] as? Bool == false)
        #expect(serviceDict["com.apple.security.cs.allow-unsigned-executable-memory"] as? Bool == false)
        #expect(serviceDict["com.apple.security.cs.disable-library-validation"] as? Bool == false)
    }

    @Test func testPackageReleaseScriptHelp() throws {
        let scriptURL = Self.macosRoot.appendingPathComponent("scripts/package-release.sh")
        #expect(FileManager.default.fileExists(atPath: scriptURL.path))

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = ["--help"]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""

        #expect(stdoutString.contains("package-release.sh"))
        #expect(stdoutString.contains("--dry-run"))
        #expect(stdoutString.contains("--notarize"))
    }
}
