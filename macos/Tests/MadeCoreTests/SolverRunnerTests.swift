import Testing
import Foundation
@testable import MadeCore

@Suite(.serialized) struct SolverRunnerTests {

    @Test func testBinaryResolverEnvironmentVariableOverride() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeCCX = tempDir.appendingPathComponent("custom-ccx")
        try "#!/bin/sh\nexit 0\n".write(to: fakeCCX, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCCX.path)

        let resolver = CalculiXBinaryResolver(
            environment: ["MADE_CALCULIX_PATH": fakeCCX.path],
            bundleURL: nil,
            customSearchPaths: []
        )

        let resolved = try resolver.resolveBinary()
        #expect(resolved.path == fakeCCX.path)
    }

    @Test func testBinaryResolverBundleHelper() throws {
        let tempBundle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TestApp.app")
        let helpersDir = tempBundle.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpersDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        let helperCCX = helpersDir.appendingPathComponent("ccx")
        try "#!/bin/sh\nexit 0\n".write(to: helperCCX, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperCCX.path)

        let resolver = CalculiXBinaryResolver(
            environment: [:],
            bundleURL: tempBundle,
            customSearchPaths: []
        )

        let resolved = try resolver.resolveBinary()
        #expect(resolved.path == helperCCX.path)
    }

    @Test func testBinaryResolverCustomSearchPaths() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let customCCX = tempDir.appendingPathComponent("system-ccx")
        try "#!/bin/sh\nexit 0\n".write(to: customCCX, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: customCCX.path)

        let resolver = CalculiXBinaryResolver(
            environment: [:],
            bundleURL: nil,
            customSearchPaths: [customCCX.path]
        )

        let resolved = try resolver.resolveBinary()
        #expect(resolved.path == customCCX.path)
    }

    @Test func testBinaryResolverNotFoundThrowsTypedError() {
        let emptyDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let resolver = CalculiXBinaryResolver(
            environment: ["MADE_CALCULIX_PATH": emptyDir.appendingPathComponent("no-ccx").path, "PATH": "/bin:/usr/bin"],
            bundleURL: emptyDir,
            customSearchPaths: []
        )

        #expect(throws: CAEErrorCode.self) {
            try resolver.resolveBinary()
        }

        do {
            _ = try resolver.resolveBinary()
            Issue.record("Expected resolveBinary to throw CAEErrorCode.solverBinaryNotFound")
        } catch {
            switch error {
            case .solverBinaryNotFound(let solver, let searchedPaths):
                #expect(solver == "CalculiX (ccx)")
                #expect(!searchedPaths.isEmpty)
                #expect(error.localizedDescription.contains("CalculiX (ccx)"))
            default:
                Issue.record("Expected solverBinaryNotFound but got \(error)")
            }
        }
    }

    @Test func testCAEDeckFixtureFormatting() {
        let study = SimulationStudy(
            name: "Cantilever Beam",
            studyType: .linearStatic
        )

        let deck = CAEDeck.fixture(for: study)
        #expect(deck.studyId == study.id)
        #expect(deck.jobName.hasPrefix("study_"))

        let content = deck.deckContent
        #expect(content.contains("*HEADING"))
        #expect(content.contains("CalculiX FEA Simulation Study - Cantilever Beam"))
        #expect(content.contains("*NODE, NSET=NALL"))
        #expect(content.contains("*ELEMENT, TYPE=C3D4, ELSET=EALL"))
        #expect(content.contains("*MATERIAL, NAME=STEEL"))
        #expect(content.contains("*ELASTIC"))
        #expect(content.contains("*SOLID SECTION, ELSET=EALL, MATERIAL=STEEL"))
        #expect(content.contains("*BOUNDARY"))
        #expect(content.contains("*STEP"))
        #expect(content.contains("*STATIC"))
        #expect(content.contains("*CLOAD"))
        #expect(content.contains("*NODE FILE"))
        #expect(content.contains("*EL FILE"))
        #expect(content.contains("*END STEP"))
    }

    @Test func testProcessExecutionStreamingAndCompletion() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let packageDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("package-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: packageDir)
        }

        let fakeCCX = tempDir.appendingPathComponent("ccx")
        // Script mimics CalculiX writing stdout progress and creating <jobName>.frd
        let script = """
#!/bin/sh
JOB="$1"
echo "CalculiX Version 2.21"
echo "STEP 1"
echo "ITERATION 1 RESIDUAL 1.2e-5"
echo "Job finished successfully"
echo "RESULTS DATA" > "${JOB}.frd"
exit 0
"""
        try script.write(to: fakeCCX, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCCX.path)

        let resolver = CalculiXBinaryResolver(
            environment: ["MADE_CALCULIX_PATH": fakeCCX.path],
            bundleURL: nil
        )
        let runner = SolverRunnerActor(binaryResolver: resolver)

        let study = SimulationStudy(name: "Test Study")
        let deck = CAEDeck.fixture(for: study)

        final class LineCollector: @unchecked Sendable {
            var lines: [String] = []
            let lock = NSLock()
            func append(_ line: String) {
                lock.lock()
                defer { lock.unlock() }
                lines.append(line)
            }
        }
        let collector = LineCollector()

        let result = try await runner.run(
            deck: deck,
            configuration: SolverConfiguration(),
            packageResultsURL: packageDir
        ) { line in
            collector.append(line)
        }

        #expect(result.status == .completed)
        #expect(result.exitCode == 0)
        #expect(result.runtimeDuration >= 0)
        #expect(result.rawOutput.contains("CalculiX Version 2.21"))
        #expect(result.rawOutput.contains("Job finished successfully"))

        #expect(collector.lines.contains("STEP 1"))
        #expect(collector.lines.contains("ITERATION 1 RESIDUAL 1.2e-5"))

        // Verify package cache commitments
        let committedDeck = packageDir.appendingPathComponent("deck.inp")
        let committedFRD = packageDir.appendingPathComponent("results.frd")
        let committedSummary = packageDir.appendingPathComponent("summary.json")

        #expect(FileManager.default.fileExists(atPath: committedDeck.path))
        #expect(FileManager.default.fileExists(atPath: committedFRD.path))
        #expect(FileManager.default.fileExists(atPath: committedSummary.path))

        let summaryData = try Data(contentsOf: committedSummary)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summary = try decoder.decode(SolverSummary.self, from: summaryData)
        #expect(summary.studyId == study.id)
        #expect(summary.jobName == deck.jobName)
        #expect(summary.status == .completed)
        #expect(summary.exitCode == 0)
    }

    @Test func testProcessExecutionNonZeroExitFails() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeCCX = tempDir.appendingPathComponent("ccx-fail")
        let script = """
#!/bin/sh
echo "Fatal error: boundary condition matrix singular" >&2
exit 42
"""
        try script.write(to: fakeCCX, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCCX.path)

        let resolver = CalculiXBinaryResolver(
            environment: ["MADE_CALCULIX_PATH": fakeCCX.path],
            bundleURL: nil
        )
        let runner = SolverRunnerActor(binaryResolver: resolver)
        let study = SimulationStudy(name: "Failing Study")
        let deck = CAEDeck.fixture(for: study)

        do {
            _ = try await runner.run(
                deck: deck,
                configuration: SolverConfiguration(),
                packageResultsURL: nil
            )
            Issue.record("Expected solver runner to throw CAEErrorCode.solverFailed")
        } catch let error as CAEErrorCode {
            switch error {
            case .solverFailed(let reason, let exitCode):
                #expect(exitCode == 42)
                #expect(reason.contains("Fatal error: boundary condition matrix singular"))
            default:
                Issue.record("Expected solverFailed but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testProcessGroupCancellation() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeCCX = tempDir.appendingPathComponent("ccx-sleep")
        let script = """
#!/bin/sh
sleep 15
exit 0
"""
        try script.write(to: fakeCCX, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCCX.path)

        let resolver = CalculiXBinaryResolver(
            environment: ["MADE_CALCULIX_PATH": fakeCCX.path],
            bundleURL: nil
        )
        let runner = SolverRunnerActor(binaryResolver: resolver)
        let study = SimulationStudy(name: "Cancelled Study")
        let deck = CAEDeck.fixture(for: study)

        let runTask = Task {
            try await runner.run(
                deck: deck,
                configuration: SolverConfiguration(),
                packageResultsURL: nil
            )
        }

        // Wait until runner starts the process
        for _ in 0..<50 {
            if await runner.isRunning(studyId: study.id) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        await runner.cancel(studyId: study.id)

        do {
            _ = try await runTask.value
            Issue.record("Expected runTask to throw CAEErrorCode.executionCancelled")
        } catch let error as CAEErrorCode {
            #expect(error == .executionCancelled)
        } catch {
            Issue.record("Unexpected error on cancel: \(error)")
        }

        let stillRunning = await runner.isRunning(studyId: study.id)
        #expect(!stillRunning)
    }

    @Test func testProcessEscalationToSIGKILL() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeCCX = tempDir.appendingPathComponent("ccx-stubborn")
        // Script traps and ignores SIGTERM so only SIGKILL can terminate it
        let script = """
#!/bin/sh
trap '' TERM
sleep 15
exit 0
"""
        try script.write(to: fakeCCX, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCCX.path)

        let resolver = CalculiXBinaryResolver(
            environment: ["MADE_CALCULIX_PATH": fakeCCX.path],
            bundleURL: nil
        )
        let runner = SolverRunnerActor(binaryResolver: resolver)
        let study = SimulationStudy(name: "Stubborn Study")
        let deck = CAEDeck.fixture(for: study)

        let runTask = Task {
            try await runner.run(
                deck: deck,
                configuration: SolverConfiguration(),
                packageResultsURL: nil
            )
        }

        for _ in 0..<50 {
            if await runner.isRunning(studyId: study.id) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        await runner.cancel(studyId: study.id)

        do {
            _ = try await runTask.value
            Issue.record("Expected runTask to throw CAEErrorCode.executionCancelled")
        } catch let error as CAEErrorCode {
            #expect(error == .executionCancelled)
        } catch {
            Issue.record("Unexpected error on cancel: \(error)")
        }

        let stillRunning = await runner.isRunning(studyId: study.id)
        #expect(!stillRunning)
    }

    @Test func testRapidCancellationBeforeLaunch() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeCCX = tempDir.appendingPathComponent("ccx-rapid")
        try "#!/bin/sh\nexit 0\n".write(to: fakeCCX, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCCX.path)

        let resolver = CalculiXBinaryResolver(
            environment: ["MADE_CALCULIX_PATH": fakeCCX.path],
            bundleURL: nil
        )
        let runner = SolverRunnerActor(binaryResolver: resolver)
        let study = SimulationStudy(name: "Precancelled Study")
        let deck = CAEDeck.fixture(for: study)

        // Cancel before run
        await runner.cancel(studyId: study.id)

        await #expect(throws: CAEErrorCode.self) {
            try await runner.run(
                deck: deck,
                configuration: SolverConfiguration(),
                packageResultsURL: nil
            )
        }
    }

    @Test func testUnsavedDocumentPreservesScratchFiles() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeCCX = tempDir.appendingPathComponent("ccx-unsaved")
        let script = """
#!/bin/sh
JOB="$1"
echo "SUCCESS"
echo "FRD" > "${JOB}.frd"
exit 0
"""
        try script.write(to: fakeCCX, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCCX.path)

        let resolver = CalculiXBinaryResolver(
            environment: ["MADE_CALCULIX_PATH": fakeCCX.path],
            bundleURL: nil
        )
        let runner = SolverRunnerActor(binaryResolver: resolver)
        let study = SimulationStudy(name: "Unsaved Study")
        let deck = CAEDeck.fixture(for: study)

        let result = try await runner.run(
            deck: deck,
            configuration: SolverConfiguration(),
            packageResultsURL: nil
        )

        #expect(result.status == .completed)
        if let deckURL = result.resultFiles["deck.inp"] {
            #expect(FileManager.default.fileExists(atPath: deckURL.path))
        } else {
            Issue.record("Missing deck.inp URL in resultFiles")
        }
        if let summaryURL = result.resultFiles["summary.json"] {
            #expect(FileManager.default.fileExists(atPath: summaryURL.path))
        } else {
            Issue.record("Missing summary.json URL in resultFiles")
        }
    }
}
