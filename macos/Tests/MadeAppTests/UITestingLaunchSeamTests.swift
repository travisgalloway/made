import Testing
import Foundation
@testable import MadeApp
import MadeCore

@Suite struct UITestingLaunchSeamTests {
    @Test @MainActor func testDefaultLaunchUsesStandardConfiguration() {
        let model = MadeApp.makeWorkspace(arguments: [], environment: [:])
        #expect(model.recoveryStore.recoveryDirectoryURL == CrashRecoveryStore.defaultRecoveryDirectoryURL)
        #expect(model.defaults == UserDefaults.standard)
    }

    @Test @MainActor func testUITestingLaunchWithCustomRecoveryDir() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("custom-recovery-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let model = MadeApp.makeWorkspace(
            arguments: ["--ui-testing"],
            environment: ["MADE_RECOVERY_DIR": tempDir.path]
        )

        #expect(model.recoveryStore.recoveryDirectoryURL.standardizedFileURL.path == tempDir.standardizedFileURL.path)
        #expect(model.defaults != UserDefaults.standard)
        #expect(FileManager.default.fileExists(atPath: tempDir.path))
    }

    @Test @MainActor func testUITestingLaunchWithDefaultEphemeralRecoveryDir() {
        let model = MadeApp.makeWorkspace(
            arguments: ["--ui-testing"],
            environment: [:]
        )

        #expect(model.recoveryStore.recoveryDirectoryURL != CrashRecoveryStore.defaultRecoveryDirectoryURL)
        #expect(model.defaults != UserDefaults.standard)
        #expect(FileManager.default.fileExists(atPath: model.recoveryStore.recoveryDirectoryURL.path))

        // Clean up ephemeral test directory
        try? FileManager.default.removeItem(at: model.recoveryStore.recoveryDirectoryURL)
    }

    @Test @MainActor func testUITestingClearsPersistentDomain() {
        let suiteName = "com.made.app.uitesting"
        let testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults?.set("stale_value", forKey: "test_key")
        #expect(testDefaults?.string(forKey: "test_key") == "stale_value")

        let model = MadeApp.makeWorkspace(
            arguments: ["--ui-testing"],
            environment: [:]
        )

        #expect(model.defaults.string(forKey: "test_key") == nil)

        // Clean up ephemeral test directory
        try? FileManager.default.removeItem(at: model.recoveryStore.recoveryDirectoryURL)
    }
}
