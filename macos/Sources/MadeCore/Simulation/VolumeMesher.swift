import Foundation
import simd

/// Engine-neutral contract for finite element tetrahedral volume meshing backends (ADR-D5 §8, #188).
public protocol VolumeMesherProtocol: Sendable {
    func mesh(
        stepData: Data,
        specification: MeshSpecification,
        studyId: UUID,
        packageResultsURL: URL?,
        outputHandler: (@Sendable (String) -> Void)?
    ) async throws -> VolumeMeshResult

    func cancel(studyId: UUID) async
}

/// Resolves the Gmsh `gmsh` binary path following ADR-D5 §6 priority order.
public struct GmshBinaryResolver: Sendable {
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

        // 1. Environment Variable Override (MADE_GMSH_PATH)
        if let envPath = environment["MADE_GMSH_PATH"], !envPath.isEmpty {
            searchedPaths.append(envPath)
            if isExecutable(atPath: envPath) {
                return URL(fileURLWithPath: envPath)
            }
        }

        // 2. Application Bundle Helpers (Contents/Helpers/gmsh)
        if let bundle = bundleURL {
            let helperPath = bundle.appendingPathComponent("Contents/Helpers/gmsh").path
            searchedPaths.append(helperPath)
            if isExecutable(atPath: helperPath) {
                return URL(fileURLWithPath: helperPath)
            }
        }

        // 3. Custom search paths (if provided for testing)
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

        // 4. Standard System Paths (/opt/homebrew/bin/gmsh, /usr/local/bin/gmsh)
        let standardSystemPaths = [
            "/opt/homebrew/bin/gmsh",
            "/usr/local/bin/gmsh"
        ]
        for path in standardSystemPaths {
            if !searchedPaths.contains(path) {
                searchedPaths.append(path)
            }
            if isExecutable(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // 5. System PATH search
        if let pathEnv = environment["PATH"] {
            let dirs = pathEnv.split(separator: ":").map(String.init)
            for dir in dirs {
                let candidate = (dir as NSString).appendingPathComponent("gmsh")
                if !searchedPaths.contains(candidate) {
                    searchedPaths.append(candidate)
                }
                if isExecutable(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }

        // 6. Typed Failure
        throw CAEErrorCode.solverBinaryNotFound(
            solver: "Gmsh (gmsh)",
            searchedPaths: searchedPaths
        )
    }
}

/// Background actor executing Gmsh CLI subprocesses with process group isolation and cancellation (ADR-D5 §9, #188).
public actor VolumeMesherActor: VolumeMesherProtocol {
    public static let shared = VolumeMesherActor()
    public let binaryResolver: GmshBinaryResolver

    private var activeProcesses: [UUID: Process] = [:]
    private var activeProcessGroups: [UUID: pid_t] = [:]
    private var cancelledStudyIds: Set<UUID> = []

    public init(binaryResolver: GmshBinaryResolver = GmshBinaryResolver()) {
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

    public func mesh(
        stepData: Data,
        specification: MeshSpecification,
        studyId: UUID,
        packageResultsURL: URL? = nil,
        outputHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> VolumeMeshResult {
        if cancelledStudyIds.contains(studyId) || Task.isCancelled {
            cancelledStudyIds.remove(studyId)
            throw CAEErrorCode.executionCancelled
        }

        let binaryURL = try binaryResolver.resolveBinary()

        let baseDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("made-cae", isDirectory: true)
        let jobDir = baseDir.appendingPathComponent("mesh-\(studyId.uuidString)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)

        let stepURL = jobDir.appendingPathComponent("geometry.step")
        try stepData.write(to: stepURL, options: .atomic)

        if cancelledStudyIds.contains(studyId) || Task.isCancelled {
            cancelledStudyIds.remove(studyId)
            throw CAEErrorCode.executionCancelled
        }

        var arguments: [String] = [
            "-3",
            "-format", "msh2",
            "-o", "mesh.msh",
            "-clmax", "\(specification.targetElementSize)",
            "-clmin", "\(specification.minElementSize)"
        ]
        if specification.elementOrder == .quadratic {
            arguments.append(contentsOf: ["-order", "2"])
        } else {
            arguments.append(contentsOf: ["-order", "1"])
        }
        arguments.append("geometry.step")

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
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

        // Non-blocking line streaming
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
            let reason = !trimmedStderr.isEmpty ? trimmedStderr : (!trimmedStdout.isEmpty ? trimmedStdout : "Mesher process exited with code \(exitCode)")
            throw CAEErrorCode.meshingFailed(reason: reason, exitCode: exitCode)
        }

        let outputMeshURL = jobDir.appendingPathComponent("mesh.msh")
        guard FileManager.default.fileExists(atPath: outputMeshURL.path) else {
            throw CAEErrorCode.meshingFailed(reason: "Mesher process completed successfully but output mesh.msh was not found", exitCode: exitCode)
        }

        let parsedMesh = try MSHParser.parse(fileURL: outputMeshURL)

        // Commit package results if requested
        var destinationURL: URL? = nil
        if let packageURL = packageResultsURL {
            try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
            let targetMeshURL = packageURL.appendingPathComponent("mesh.msh")
            if FileManager.default.fileExists(atPath: targetMeshURL.path) {
                try FileManager.default.removeItem(at: targetMeshURL)
            }
            try FileManager.default.copyItem(at: outputMeshURL, to: targetMeshURL)
            destinationURL = targetMeshURL
        }

        return VolumeMeshResult(
            mesh: parsedMesh,
            meshFileURL: destinationURL ?? outputMeshURL,
            runtimeDuration: elapsedSeconds,
            exitCode: exitCode,
            rawOutput: rawOutput
        )
    }
}

/// Minimal geometric test fixtures for volume meshing.
public enum VolumeMesherFixture {
    /// Standard minimal ISO-10303-21 STEP fixture representing an analytic unit cube.
    public static var minimalStepBoxData: Data {
        let content = """
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION(('Open CASCADE Model'),'2;1');
        FILE_NAME('Cube','2026-10-23T00:00:00',('Made'),('Made'),'Open CASCADE 8.0','Open CASCADE 8.0','');
        FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));
        ENDSEC;
        DATA;
        #1 = APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,#2);
        #2 = APPLICATION_CONTEXT('core data for automotive mechanical design processes');
        #3 = SHAPE_DEFINITION_REPRESENTATION(#4,#10);
        #4 = PRODUCT_DEFINITION_SHAPE('','',#5);
        #5 = PRODUCT_DEFINITION('design','',#6,#9);
        #6 = PRODUCT_DEFINITION_FORMATION('','',#7);
        #7 = PRODUCT('Cube','Cube','',(#8));
        #8 = PRODUCT_CONTEXT('',#2,'mechanical');
        #9 = PRODUCT_DEFINITION_CONTEXT('part definition',#2,'design');
        #10 = ADVANCED_BREP_SHAPE_REPRESENTATION('',(#11,#15),#345);
        #11 = AXIS2_PLACEMENT_3D('',#12,#13,#14);
        #12 = CARTESIAN_POINT('',(0.,0.,0.));
        #13 = DIRECTION('',(0.,0.,1.));
        #14 = DIRECTION('',(1.,0.,0.));
        #15 = MANIFOLD_SOLID_BREP('',#16);
        #16 = CLOSED_SHELL('',(#17));
        #17 = ADVANCED_FACE('',(#18),#22,.T.);
        #18 = FACE_BOUND('',#19,.T.);
        #19 = EDGE_LOOP('',(#20));
        #20 = ORIENTED_EDGE('',*,*,#21,.T.);
        #21 = EDGE_CURVE('',#23,#23,#24,.T.);
        #22 = PLANE('',#11);
        #23 = VERTEX_POINT('',#12);
        #24 = SURFACE_CURVE('',#25,(#26),.PCURVE_S1.);
        #25 = LINE('',#12,#13);
        #26 = PCURVE('',#22,#27);
        #27 = DEFINITIONAL_REPRESENTATION('',(#28),#29);
        #28 = LINE('',#30,#31);
        #29 = ( GEOMETRIC_REPRESENTATION_CONTEXT(2) PARAMETRIC_REPRESENTATION_CONTEXT() REPRESENTATION_CONTEXT('2D SPACE','') );
        #30 = CARTESIAN_POINT('',(0.,0.));
        #31 = DIRECTION('',(1.,0.));
        #345 = ( GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#349)) GLOBAL_UNIT_ASSIGNED_CONTEXT((#346,#347,#348)) REPRESENTATION_CONTEXT('Context #1','3D') );
        #346 = ( LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.) );
        #347 = ( NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.) );
        #348 = ( NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT() );
        #349 = UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-07),#346,'distance_accuracy_value','confusion accuracy');
        ENDSEC;
        END-ISO-10303-21;
        """
        return Data(content.utf8)
    }

    /// Generates minimal MSH 2.2 ASCII content with a single tetrahedron.
    public static func minimalMSHContent(order: MeshElementOrder = .linear) -> String {
        switch order {
        case .linear:
            return """
            $MeshFormat
            2.2 0 8
            $EndMeshFormat
            $Nodes
            4
            1 0.0 0.0 0.0
            2 10.0 0.0 0.0
            3 0.0 10.0 0.0
            4 0.0 0.0 10.0
            $EndNodes
            $Elements
            2
            1 2 2 1 1 1 2 3
            2 4 2 1 1 1 2 3 4
            $EndElements
            """
        case .quadratic:
            return """
            $MeshFormat
            2.2 0 8
            $EndMeshFormat
            $Nodes
            10
            1 0.0 0.0 0.0
            2 10.0 0.0 0.0
            3 0.0 10.0 0.0
            4 0.0 0.0 10.0
            5 5.0 0.0 0.0
            6 5.0 5.0 0.0
            7 0.0 5.0 0.0
            8 0.0 0.0 5.0
            9 5.0 0.0 5.0
            10 0.0 5.0 5.0
            $EndNodes
            $Elements
            2
            1 9 2 1 1 1 2 3 5 6 7
            2 11 2 1 1 1 2 3 4 5 6 7 8 9 10
            $EndElements
            """
        }
    }
}
