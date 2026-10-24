import Testing
import Foundation
import simd
@testable import MadeCore

@Suite(.serialized) struct VolumeMesherTests {

    @Test func testGmshBinaryResolverEnvironmentVariableOverride() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeGmsh = tempDir.appendingPathComponent("custom-gmsh")
        try "#!/bin/sh\nexit 0\n".write(to: fakeGmsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGmsh.path)

        let resolver = GmshBinaryResolver(
            environment: ["MADE_GMSH_PATH": fakeGmsh.path],
            bundleURL: nil,
            customSearchPaths: []
        )

        let resolved = try resolver.resolveBinary()
        #expect(resolved.path == fakeGmsh.path)
    }

    @Test func testGmshBinaryResolverBundleHelper() throws {
        let tempBundle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TestApp.app")
        let helpersDir = tempBundle.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpersDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBundle) }

        let helperGmsh = helpersDir.appendingPathComponent("gmsh")
        try "#!/bin/sh\nexit 0\n".write(to: helperGmsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperGmsh.path)

        let resolver = GmshBinaryResolver(
            environment: [:],
            bundleURL: tempBundle,
            customSearchPaths: []
        )

        let resolved = try resolver.resolveBinary()
        #expect(resolved.path == helperGmsh.path)
    }

    @Test func testGmshBinaryResolverCustomSearchPaths() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let customGmsh = tempDir.appendingPathComponent("system-gmsh")
        try "#!/bin/sh\nexit 0\n".write(to: customGmsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: customGmsh.path)

        let resolver = GmshBinaryResolver(
            environment: [:],
            bundleURL: nil,
            customSearchPaths: [customGmsh.path]
        )

        let resolved = try resolver.resolveBinary()
        #expect(resolved.path == customGmsh.path)
    }

    @Test func testGmshBinaryResolverNotFoundThrowsTypedError() {
        let emptyDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nonexistent-\(UUID().uuidString)")
        let resolver = GmshBinaryResolver(
            environment: ["MADE_GMSH_PATH": emptyDir.appendingPathComponent("no-gmsh").path, "PATH": "/bin:/usr/bin"],
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
                #expect(solver == "Gmsh (gmsh)")
                #expect(!searchedPaths.isEmpty)
                #expect(error.localizedDescription.contains("Gmsh (gmsh)"))
            default:
                Issue.record("Expected solverBinaryNotFound but got \(error)")
            }
        }
    }

    @Test func testMSHParserParsesLinearC3D4AndSurfaceTriangles() throws {
        let content = VolumeMesherFixture.minimalMSHContent(order: .linear)
        let mesh = try MSHParser.parse(content: content)

        #expect(mesh.nodes.count == 4)
        #expect(mesh.elements.count == 1)
        #expect(mesh.surfaceTriangles.count == 1)

        let tet = mesh.elements[0]
        #expect(tet.id == 2)
        #expect(tet.order == .linear)
        #expect(tet.nodeIndices == [1, 2, 3, 4])

        let tri = mesh.surfaceTriangles[0]
        #expect(tri.id == 1)
        #expect(tri.order == .linear)
        #expect(tri.nodeIndices == [1, 2, 3])

        #expect(mesh.statistics.nodeCount == 4)
        #expect(mesh.statistics.elementCount == 1)
        #expect(mesh.statistics.minElementQuality > 0.0)
        #expect(mesh.statistics.avgElementQuality > 0.0)
        #expect(mesh.statistics.minElementQuality <= 1.0)
    }

    @Test func testMSHParserParsesQuadraticC3D10AndSurfaceTriangles() throws {
        let content = VolumeMesherFixture.minimalMSHContent(order: .quadratic)
        let mesh = try MSHParser.parse(content: content)

        #expect(mesh.nodes.count == 10)
        #expect(mesh.elements.count == 1)
        #expect(mesh.surfaceTriangles.count == 1)

        let tet = mesh.elements[0]
        #expect(tet.id == 2)
        #expect(tet.order == .quadratic)
        #expect(tet.nodeIndices.count == 10)

        let tri = mesh.surfaceTriangles[0]
        #expect(tri.id == 1)
        #expect(tri.order == .quadratic)
        #expect(tri.nodeIndices.count == 6)

        #expect(mesh.statistics.nodeCount == 10)
        #expect(mesh.statistics.elementCount == 1)
        #expect(mesh.statistics.minElementQuality > 0.0)
    }

    @Test func testMSHParserCorruptHeaderThrowsTypedError() {
        let corrupt = """
        $MeshFormat
        4.1 0 8
        $EndMeshFormat
        $Nodes
        0
        $EndNodes
        $Elements
        0
        $EndElements
        """

        #expect(throws: CAEErrorCode.self) {
            try MSHParser.parse(content: corrupt)
        }

        do {
            _ = try MSHParser.parse(content: corrupt)
            Issue.record("Expected MSHParser to reject version 4.1")
        } catch {
            switch error {
            case .resultParsingFailed(let details):
                #expect(details.contains("Unsupported MSH version") || details.contains("Expected MSH 2.x"))
            default:
                Issue.record("Expected resultParsingFailed but got \(error)")
            }
        }
    }

    @Test func testMSHParserTruncatedNodesThrowsTypedError() {
        let truncated = """
        $MeshFormat
        2.2 0 8
        $EndMeshFormat
        $Nodes
        4
        1 0.0 0.0 0.0
        $EndNodes
        $Elements
        0
        $EndElements
        """

        #expect(throws: CAEErrorCode.self) {
            try MSHParser.parse(content: truncated)
        }
    }

    @Test func testMSHParserTruncatedElementsThrowsTypedError() {
        let truncated = """
        $MeshFormat
        2.2 0 8
        $EndMeshFormat
        $Nodes
        1
        1 0.0 0.0 0.0
        $EndNodes
        $Elements
        3
        1 2 2 1 1 1 2 3
        $EndElements
        """

        #expect(throws: CAEErrorCode.self) {
            try MSHParser.parse(content: truncated)
        }
    }

    @Test func testVolumeMesherActorProcessStreamingAndCompletion() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let packageDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: packageDir)
        }

        let fakeGmsh = tempDir.appendingPathComponent("gmsh-mock")
        let mshContent = VolumeMesherFixture.minimalMSHContent(order: .linear)
        let script = """
        #!/bin/sh
        echo "Info    : Running Gmsh 4.12.0"
        echo "Info    : Reading geometry.step..."
        echo "Info    : Meshing 3D volume..."
        cat << 'EOF' > mesh.msh
        \(mshContent)
        EOF
        echo "Info    : 1 tetrahedron generated"
        exit 0
        """
        try script.write(to: fakeGmsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGmsh.path)

        let resolver = GmshBinaryResolver(
            environment: ["MADE_GMSH_PATH": fakeGmsh.path],
            bundleURL: nil
        )
        let actor = VolumeMesherActor(binaryResolver: resolver)

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

        let studyId = UUID()
        let result = try await actor.mesh(
            stepData: VolumeMesherFixture.minimalStepBoxData,
            specification: MeshSpecification(elementOrder: .linear, targetElementSize: 5.0),
            studyId: studyId,
            packageResultsURL: packageDir
        ) { line in
            collector.append(line)
        }

        #expect(result.exitCode == 0)
        #expect(result.mesh.elements.count == 1)
        #expect(result.mesh.nodes.count == 4)
        #expect(result.runtimeDuration >= 0)
        #expect(collector.lines.contains("Info    : Running Gmsh 4.12.0"))
        #expect(collector.lines.contains("Info    : 1 tetrahedron generated"))

        let committedMeshURL = packageDir.appendingPathComponent("mesh.msh")
        #expect(FileManager.default.fileExists(atPath: committedMeshURL.path))
        let committedContent = try String(contentsOf: committedMeshURL, encoding: .utf8)
        #expect(committedContent.contains("$MeshFormat"))
        #expect(committedContent.contains("$Nodes"))
    }

    @Test func testVolumeMesherActorNonZeroExitFails() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeGmsh = tempDir.appendingPathComponent("gmsh-fail")
        let script = """
        #!/bin/sh
        echo "Error   : Self-intersecting B-rep surface detected" >&2
        exit 33
        """
        try script.write(to: fakeGmsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGmsh.path)

        let resolver = GmshBinaryResolver(
            environment: ["MADE_GMSH_PATH": fakeGmsh.path],
            bundleURL: nil
        )
        let actor = VolumeMesherActor(binaryResolver: resolver)

        do {
            _ = try await actor.mesh(
                stepData: VolumeMesherFixture.minimalStepBoxData,
                specification: MeshSpecification(),
                studyId: UUID(),
                packageResultsURL: nil
            )
            Issue.record("Expected VolumeMesherActor to throw CAEErrorCode.meshingFailed")
        } catch let error as CAEErrorCode {
            switch error {
            case .meshingFailed(let reason, let exitCode):
                #expect(exitCode == 33)
                #expect(reason.contains("Self-intersecting B-rep surface detected"))
            default:
                Issue.record("Expected meshingFailed but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testVolumeMesherActorCancellation() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeGmsh = tempDir.appendingPathComponent("gmsh-sleep")
        let script = """
        #!/bin/sh
        sleep 15
        exit 0
        """
        try script.write(to: fakeGmsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGmsh.path)

        let resolver = GmshBinaryResolver(
            environment: ["MADE_GMSH_PATH": fakeGmsh.path],
            bundleURL: nil
        )
        let actor = VolumeMesherActor(binaryResolver: resolver)
        let studyId = UUID()

        let task = Task {
            try await actor.mesh(
                stepData: VolumeMesherFixture.minimalStepBoxData,
                specification: MeshSpecification(),
                studyId: studyId,
                packageResultsURL: nil
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        await actor.cancel(studyId: studyId)

        do {
            _ = try await task.value
            Issue.record("Expected task to fail with CAEErrorCode.executionCancelled")
        } catch let error as CAEErrorCode {
            #expect(error == .executionCancelled)
        } catch is CancellationError {
            // Task cancellation is acceptable
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(await !actor.isRunning(studyId: studyId))
    }

    @Test func testVolumeMesherActorEscalationToSIGKILL() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeGmsh = tempDir.appendingPathComponent("gmsh-unkillable")
        let script = """
        #!/bin/sh
        trap '' TERM
        while true; do
            sleep 1
        done
        """
        try script.write(to: fakeGmsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGmsh.path)

        let resolver = GmshBinaryResolver(
            environment: ["MADE_GMSH_PATH": fakeGmsh.path],
            bundleURL: nil
        )
        let actor = VolumeMesherActor(binaryResolver: resolver)
        let studyId = UUID()

        let task = Task {
            try await actor.mesh(
                stepData: VolumeMesherFixture.minimalStepBoxData,
                specification: MeshSpecification(),
                studyId: studyId,
                packageResultsURL: nil
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        await actor.cancel(studyId: studyId)

        // Wait up to 2 seconds for SIGKILL escalation to terminate the process
        for _ in 0..<40 {
            let running = await actor.isRunning(studyId: studyId)
            if !running { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(await !actor.isRunning(studyId: studyId))
        _ = try? await task.value
    }

    @Test func testVolumeMesherActorRapidCancellationBeforeLaunch() async throws {
        let resolver = GmshBinaryResolver(
            environment: ["MADE_GMSH_PATH": "/bin/echo"],
            bundleURL: nil
        )
        let actor = VolumeMesherActor(binaryResolver: resolver)
        let studyId = UUID()

        await actor.cancel(studyId: studyId)

        do {
            _ = try await actor.mesh(
                stepData: VolumeMesherFixture.minimalStepBoxData,
                specification: MeshSpecification(),
                studyId: studyId,
                packageResultsURL: nil
            )
            Issue.record("Expected immediate throw on pre-cancelled study")
        } catch let error as CAEErrorCode {
            #expect(error == .executionCancelled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testBuildGmshArgumentsLinearAndQuadraticOrder() {
        let linearSpec = MeshSpecification(elementOrder: .linear, targetElementSize: 4.0, minElementSize: 1.0)
        let linearArgs = VolumeMesherActor.buildGmshArguments(specification: linearSpec)
        #expect(linearArgs.contains("-order"))
        if let orderIdx = linearArgs.firstIndex(of: "-order"), orderIdx + 1 < linearArgs.count {
            #expect(linearArgs[orderIdx + 1] == "1")
        } else {
            Issue.record("Missing -order 1")
        }

        let quadraticSpec = MeshSpecification(elementOrder: .quadratic, targetElementSize: 4.0, minElementSize: 1.0)
        let quadraticArgs = VolumeMesherActor.buildGmshArguments(specification: quadraticSpec)
        if let orderIdx = quadraticArgs.firstIndex(of: "-order"), orderIdx + 1 < quadraticArgs.count {
            #expect(quadraticArgs[orderIdx + 1] == "2")
        } else {
            Issue.record("Missing -order 2")
        }
    }

    @Test func testBuildGmshArgumentsCurvatureRefinementDisabled() {
        let spec = MeshSpecification(curvatureRefinement: false)
        let args = VolumeMesherActor.buildGmshArguments(specification: spec)
        #expect(!args.contains("-clcurv"))
        #expect(!args.contains("Mesh.MeshSizeFromCurvature"))
    }

    @Test func testBuildGmshArgumentsCurvatureRefinementEnabled() {
        let spec = MeshSpecification(curvatureRefinement: true, curvatureElementsPerCircle: 18.0)
        let args = VolumeMesherActor.buildGmshArguments(specification: spec)
        #expect(args.contains("-clcurv"))
        if let setnumberIdx = args.firstIndex(of: "-setnumber"), setnumberIdx + 2 < args.count {
            #expect(args[setnumberIdx + 1] == "Mesh.MeshSizeFromCurvature")
            #expect(args[setnumberIdx + 2] == "18.0")
        } else {
            Issue.record("Missing -setnumber Mesh.MeshSizeFromCurvature 18.0")
        }
    }

    @Test func testBuildGmshArgumentsClampsMinGreaterThanTarget() {
        let spec = MeshSpecification(targetElementSize: 2.0, minElementSize: 5.0)
        let args = VolumeMesherActor.buildGmshArguments(specification: spec)
        guard let clmaxIdx = args.firstIndex(of: "-clmax"), clmaxIdx + 1 < args.count,
              let clminIdx = args.firstIndex(of: "-clmin"), clminIdx + 1 < args.count,
              let clmax = Double(args[clmaxIdx + 1]),
              let clmin = Double(args[clminIdx + 1]) else {
            Issue.record("Missing -clmax or -clmin arguments")
            return
        }
        #expect(clmax == 2.0)
        #expect(clmin == 2.0)
        #expect(clmin <= clmax)
    }
}
