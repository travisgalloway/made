import Foundation
import simd

/// Standardized input deck specification for external numerical CAE solvers (ADR-D5, #187).
public struct CAEDeck: Sendable, Codable, Equatable, Hashable {
    public var studyId: UUID
    public var jobName: String
    public var deckContent: String
    public var auxiliaryFiles: [String: String]

    public init(
        studyId: UUID,
        jobName: String,
        deckContent: String,
        auxiliaryFiles: [String: String] = [:]
    ) {
        self.studyId = studyId
        self.jobName = jobName
        self.deckContent = deckContent
        self.auxiliaryFiles = auxiliaryFiles
    }

    /// Generates a valid minimal CalculiX deck so any study can execute without waiting for downstream deck writers.
    public static func fixture(for study: SimulationStudy) -> CAEDeck {
        let cleanId = study.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let jobName = "study_\(cleanId)"

        let deckContent = """
*HEADING
CalculiX FEA Simulation Study - \(study.name)
*NODE, NSET=NALL
1, 0.0, 0.0, 0.0
2, 10.0, 0.0, 0.0
3, 0.0, 10.0, 0.0
4, 0.0, 0.0, 10.0
*ELEMENT, TYPE=C3D4, ELSET=EALL
1, 1, 2, 3, 4
*MATERIAL, NAME=STEEL
*ELASTIC
210000.0, 0.3
*SOLID SECTION, ELSET=EALL, MATERIAL=STEEL
*BOUNDARY
1, 1, 3, 0.0
2, 2, 3, 0.0
3, 3, 3, 0.0
*STEP
*STATIC
*CLOAD
4, 3, -1000.0
*NODE FILE
U
*EL FILE
S
*END STEP
"""
        return CAEDeck(
            studyId: study.id,
            jobName: jobName,
            deckContent: deckContent
        )
    }
}

/// Execution output and artifact collection resulting from a completed numerical solve.
public struct SolverRunResult: Sendable, Codable, Equatable, Hashable {
    public var status: SimulationExecutionStatus
    public var runtimeDuration: Double
    public var exitCode: Int32
    public var rawOutput: String
    public var resultFiles: [String: URL]
    public var errorMessage: String?

    public init(
        status: SimulationExecutionStatus,
        runtimeDuration: Double,
        exitCode: Int32,
        rawOutput: String,
        resultFiles: [String: URL] = [:],
        errorMessage: String? = nil
    ) {
        self.status = status
        self.runtimeDuration = runtimeDuration
        self.exitCode = exitCode
        self.rawOutput = rawOutput
        self.resultFiles = resultFiles
        self.errorMessage = errorMessage
    }
}

/// Lightweight summary metadata recorded into `summary.json` upon solve completion.
public struct SolverSummary: Sendable, Codable, Equatable, Hashable {
    public var studyId: UUID
    public var jobName: String
    public var status: SimulationExecutionStatus
    public var runtimeDuration: Double
    public var exitCode: Int32
    public var timestamp: Date

    public init(
        studyId: UUID,
        jobName: String,
        status: SimulationExecutionStatus,
        runtimeDuration: Double,
        exitCode: Int32,
        timestamp: Date = Date()
    ) {
        self.studyId = studyId
        self.jobName = jobName
        self.status = status
        self.runtimeDuration = runtimeDuration
        self.exitCode = exitCode
        self.timestamp = timestamp
    }
}

/// Engine-neutral contract for numerical solver execution backends (ADR-D5 §8).
public protocol SolverRunnerProtocol: Sendable {
    func run(
        deck: CAEDeck,
        configuration: SolverConfiguration,
        packageResultsURL: URL?,
        outputHandler: (@Sendable (String) -> Void)?
    ) async throws -> SolverRunResult

    func cancel(studyId: UUID) async
}

/// Resolves the CalculiX `ccx` binary path following ADR-D5 §6 priority order.
public struct CalculiXBinaryResolver: Sendable {
    public var environment: [String: String]
    public var bundleURL: URL?
    public var customSearchPaths: [String]?
    public var isExecutableHandler: (@Sendable (String) -> Bool)?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL? = Bundle.main.bundleURL,
        customSearchPaths: [String]? = nil,
        isExecutableHandler: (@Sendable (String) -> Bool)? = nil
    ) {
        self.environment = environment
        self.bundleURL = bundleURL
        self.customSearchPaths = customSearchPaths
        self.isExecutableHandler = isExecutableHandler
    }

    private func isExecutable(atPath path: String) -> Bool {
        if let handler = isExecutableHandler {
            return handler(path)
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    public func resolveBinary() throws(CAEErrorCode) -> URL {
        var searchedPaths: [String] = []

        // 1. Environment Variable Override (MADE_CALCULIX_PATH)
        if let envPath = environment["MADE_CALCULIX_PATH"], !envPath.isEmpty {
            searchedPaths.append(envPath)
            if isExecutable(atPath: envPath) {
                return URL(fileURLWithPath: envPath)
            }
        }

        // 2. Application Bundle Helpers (Contents/Helpers/ccx)
        if let bundle = bundleURL {
            let helperPath = bundle.appendingPathComponent("Contents/Helpers/ccx").path
            searchedPaths.append(helperPath)
            if isExecutable(atPath: helperPath) {
                return URL(fileURLWithPath: helperPath)
            }
        }

        // Custom search paths (if provided for testing)
        if let customSearchPaths {
            for path in customSearchPaths {
                if !searchedPaths.contains(path) {
                    searchedPaths.append(path)
                }
                if isExecutable(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }

        // 3. System Paths (/opt/homebrew/bin/ccx, /usr/local/bin/ccx, PATH)
        let standardSystemPaths = [
            "/opt/homebrew/bin/ccx",
            "/usr/local/bin/ccx"
        ]
        for path in standardSystemPaths {
            if !searchedPaths.contains(path) {
                searchedPaths.append(path)
            }
            if isExecutable(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        if let pathEnv = environment["PATH"] {
            let dirs = pathEnv.split(separator: ":").map(String.init)
            for dir in dirs {
                let candidate = (dir as NSString).appendingPathComponent("ccx")
                if !searchedPaths.contains(candidate) {
                    searchedPaths.append(candidate)
                }
                if isExecutable(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }

        // 4. Typed Failure
        throw CAEErrorCode.solverBinaryNotFound(
            solver: "CalculiX (ccx)",
            searchedPaths: searchedPaths
        )
    }
}

/// Background actor responsible for sandboxed execution of external numerical solvers (ADR-D5 §9).
public actor SolverRunnerActor: SolverRunnerProtocol {
    public static let shared = SolverRunnerActor()
    public let binaryResolver: CalculiXBinaryResolver

    private var activeProcesses: [UUID: Process] = [:]
    private var activeProcessGroups: [UUID: pid_t] = [:]
    private var cancelledStudyIds: Set<UUID> = []

    public init(binaryResolver: CalculiXBinaryResolver = CalculiXBinaryResolver()) {
        self.binaryResolver = binaryResolver
    }

    public func isRunning(studyId: UUID) -> Bool {
        guard let process = activeProcesses[studyId] else { return false }
        return process.isRunning
    }

    public func cancel(studyId: UUID) {
        cancelledStudyIds.insert(studyId)
        guard let process = activeProcesses[studyId] else { return }
        let pid = process.processIdentifier
        let pgid = activeProcessGroups[studyId] ?? pid

        if pgid > 0 {
            kill(-pgid, SIGTERM)
        }
        if pid > 0 {
            kill(pid, SIGTERM)
        }
        process.terminate()

        Task.detached { [weak process] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let process, process.isRunning else { return }
            if pgid > 0 {
                kill(-pgid, SIGKILL)
            }
            if pid > 0 {
                kill(pid, SIGKILL)
            }
        }
    }

    public func run(
        deck: CAEDeck,
        configuration: SolverConfiguration,
        packageResultsURL: URL? = nil,
        outputHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> SolverRunResult {
        let studyId = deck.studyId
        if cancelledStudyIds.contains(studyId) || Task.isCancelled {
            cancelledStudyIds.remove(studyId)
            throw CAEErrorCode.executionCancelled
        }

        let binaryURL = try binaryResolver.resolveBinary()

        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("made-cae", isDirectory: true)
        let jobDir = baseDir.appendingPathComponent("\(studyId.uuidString)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)

        let deckURL = jobDir.appendingPathComponent("\(deck.jobName).inp")
        try deck.deckContent.write(to: deckURL, atomically: true, encoding: .utf8)
        for (filename, content) in deck.auxiliaryFiles {
            let auxURL = jobDir.appendingPathComponent(filename)
            try content.write(to: auxURL, atomically: true, encoding: .utf8)
        }

        if cancelledStudyIds.contains(studyId) || Task.isCancelled {
            cancelledStudyIds.remove(studyId)
            throw CAEErrorCode.executionCancelled
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [deck.jobName]
        process.currentDirectoryURL = jobDir
        process.qualityOfService = .userInitiated

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = ContinuousClock.now

        try process.run()
        let pid = process.processIdentifier
        _ = setpgid(pid, pid)
        activeProcesses[studyId] = process
        activeProcessGroups[studyId] = pid

        defer {
            activeProcesses.removeValue(forKey: studyId)
            activeProcessGroups.removeValue(forKey: studyId)
            cancelledStudyIds.remove(studyId)
        }

        if cancelledStudyIds.contains(studyId) || Task.isCancelled {
            cancel(studyId: studyId)
            throw CAEErrorCode.executionCancelled
        }

        // Start non-blocking line streaming
        let stdoutTask = Task.detached {
            var lines: [String] = []
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    lines.append(line)
                    outputHandler?(line)
                }
            } catch {}
            return lines.joined(separator: "\n")
        }

        let stderrTask = Task.detached {
            var lines: [String] = []
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    lines.append(line)
                    outputHandler?(line)
                }
            } catch {}
            return lines.joined(separator: "\n")
        }

        // Await process termination without thread stalling
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                final class ResumeGate: @unchecked Sendable {
                    var resumed = false
                    let lock = NSLock()
                }
                let gate = ResumeGate()
                process.terminationHandler = { _ in
                    gate.lock.lock()
                    defer { gate.lock.unlock() }
                    if !gate.resumed {
                        gate.resumed = true
                        continuation.resume()
                    }
                }
                gate.lock.lock()
                if !process.isRunning && !gate.resumed {
                    gate.resumed = true
                    gate.lock.unlock()
                    continuation.resume()
                } else {
                    gate.lock.unlock()
                }
            }
        } onCancel: {
            Task {
                await self.cancel(studyId: studyId)
            }
        }

        let stdoutString = await stdoutTask.value
        let stderrString = await stderrTask.value
        let duration = startTime.duration(to: .now)
        let elapsedSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18

        let exitCode = process.terminationStatus
        let rawOutput: String
        if stdoutString.isEmpty {
            rawOutput = stderrString
        } else if stderrString.isEmpty {
            rawOutput = stdoutString
        } else {
            rawOutput = stdoutString + "\n" + stderrString
        }

        if cancelledStudyIds.contains(studyId) || Task.isCancelled {
            throw CAEErrorCode.executionCancelled
        }

        if exitCode != 0 {
            let trimmedStderr = stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedStdout = stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = !trimmedStderr.isEmpty ? trimmedStderr : (!trimmedStdout.isEmpty ? trimmedStdout : "Solver process exited with code \(exitCode)")
            throw CAEErrorCode.solverFailed(reason: reason, exitCode: exitCode)
        }

        // Commit package results
        var resultFiles: [String: URL] = [:]
        let summary = SolverSummary(
            studyId: studyId,
            jobName: deck.jobName,
            status: .completed,
            runtimeDuration: elapsedSeconds,
            exitCode: exitCode,
            timestamp: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let summaryData = try encoder.encode(summary)

        let localSummaryURL = jobDir.appendingPathComponent("summary.json")
        try summaryData.write(to: localSummaryURL, options: .atomic)

        if let packageURL = packageResultsURL {
            try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

            let targetDeckURL = packageURL.appendingPathComponent("deck.inp")
            if FileManager.default.fileExists(atPath: deckURL.path) {
                if FileManager.default.fileExists(atPath: targetDeckURL.path) {
                    try FileManager.default.removeItem(at: targetDeckURL)
                }
                try FileManager.default.copyItem(at: deckURL, to: targetDeckURL)
                resultFiles["deck.inp"] = targetDeckURL
            }

            let frdLocal = jobDir.appendingPathComponent("\(deck.jobName).frd")
            let targetFrdURL = packageURL.appendingPathComponent("results.frd")
            if FileManager.default.fileExists(atPath: frdLocal.path) {
                if FileManager.default.fileExists(atPath: targetFrdURL.path) {
                    try FileManager.default.removeItem(at: targetFrdURL)
                }
                try FileManager.default.copyItem(at: frdLocal, to: targetFrdURL)
                resultFiles["results.frd"] = targetFrdURL
            }

            let targetSummaryURL = packageURL.appendingPathComponent("summary.json")
            if FileManager.default.fileExists(atPath: targetSummaryURL.path) {
                try FileManager.default.removeItem(at: targetSummaryURL)
            }
            try FileManager.default.copyItem(at: localSummaryURL, to: targetSummaryURL)
            resultFiles["summary.json"] = targetSummaryURL
        } else {
            resultFiles["deck.inp"] = deckURL
            let frdLocal = jobDir.appendingPathComponent("\(deck.jobName).frd")
            if FileManager.default.fileExists(atPath: frdLocal.path) {
                resultFiles["results.frd"] = frdLocal
            }
            resultFiles["summary.json"] = localSummaryURL
        }

        return SolverRunResult(
            status: .completed,
            runtimeDuration: elapsedSeconds,
            exitCode: exitCode,
            rawOutput: rawOutput,
            resultFiles: resultFiles,
            errorMessage: nil
        )
    }
}
