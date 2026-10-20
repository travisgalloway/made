import XCTest

class MadeUITestCase: XCTestCase {
    private var temporaryRecoveryURL: URL?
    private var app: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if let app {
            app.terminate()
            self.app = nil
        }
        if let temporaryRecoveryURL {
            try? FileManager.default.removeItem(at: temporaryRecoveryURL)
            self.temporaryRecoveryURL = nil
        }
        let savedStateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Saved Application State/com.made.app.savedState", isDirectory: true)
        try? FileManager.default.removeItem(at: savedStateURL)
    }

    func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let appURL: URL
        if let envPath = ProcessInfo.processInfo.environment["MADE_APP_PATH"], !envPath.isEmpty {
            appURL = URL(fileURLWithPath: envPath, isDirectory: true)
        } else {
            let thisFile = URL(fileURLWithPath: #filePath)
            // #filePath is macos/UITests/MadeUITestCase.swift -> deletingLastPathComponent gives macos/UITests -> deletingLastPathComponent gives macos
            let macosDir = thisFile.deletingLastPathComponent().deletingLastPathComponent()
            appURL = macosDir
                .appendingPathComponent(".build", isDirectory: true)
                .appendingPathComponent("Made.app", isDirectory: true)
        }

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            XCTFail("Made.app not found at \(appURL.path). Run 'make bundle' first.")
            return XCUIApplication()
        }

        let savedStateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Saved Application State/com.made.app.savedState", isDirectory: true)
        try? FileManager.default.removeItem(at: savedStateURL)

        let recoveryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("made-uitest-recovery-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: recoveryURL, withIntermediateDirectories: true)
        self.temporaryRecoveryURL = recoveryURL

        let app = XCUIApplication(url: appURL)
        self.app = app
        app.launchArguments = ["--ui-testing"] + extraArguments
        app.launchEnvironment["MADE_RECOVERY_DIR"] = recoveryURL.path
        app.launch()
        return app
    }
}
