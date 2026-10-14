import Foundation
import Testing
import simd
@testable import MadeCore

@MainActor
private final class PluginSkillTestMeshSink: SolidMeshSink {
    var installedMeshes: [SolidId: MeshPayload] = [:]
    var transforms: [SolidId: Transform] = [:]

    func installMesh(_ payload: MeshPayload, for id: SolidId, transform: Transform, color: SIMD4<Float>, isHidden: Bool) -> Bool {
        installedMeshes[id] = payload
        transforms[id] = transform
        return true
    }

    func updateTransform(_ transform: Transform, for id: SolidId) -> Bool {
        guard installedMeshes[id] != nil else { return false }
        transforms[id] = transform
        return true
    }

    func removeMesh(for id: SolidId) -> Bool {
        transforms.removeValue(forKey: id)
        return installedMeshes.removeValue(forKey: id) != nil
    }
}

@Suite("Claude Code Plugin and made-cad Skill Tests (#429)")
@MainActor
struct PluginSkillTests {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MadeCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // repo root
    }

    private static var pluginDir: URL {
        repoRoot.appendingPathComponent("plugins/made-cad", isDirectory: true)
    }

    private static var skillDir: URL {
        pluginDir.appendingPathComponent("skills/made-cad", isDirectory: true)
    }

    private func parseToolJSON(_ result: MCPToolCallResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        let data = try #require(text.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Plugin marketplace and plugin manifests are valid and resolve on disk")
    func testPluginManifestsAreValid() throws {
        let fm = FileManager.default
        let marketplaceURL = Self.repoRoot.appendingPathComponent(".claude-plugin/marketplace.json")
        let rootPluginURL = Self.repoRoot.appendingPathComponent(".claude-plugin/plugin.json")
        let nestedPluginURL = Self.pluginDir.appendingPathComponent(".claude-plugin/plugin.json")

        #expect(fm.fileExists(atPath: marketplaceURL.path))
        #expect(fm.fileExists(atPath: rootPluginURL.path))
        #expect(fm.fileExists(atPath: nestedPluginURL.path))

        let marketplaceData = try Data(contentsOf: marketplaceURL)
        let marketplace = try #require(
            try JSONSerialization.jsonObject(with: marketplaceData) as? [String: Any]
        )
        #expect(marketplace["name"] as? String == "made")
        let plugins = try #require(marketplace["plugins"] as? [[String: Any]])
        #expect(!plugins.isEmpty)

        let madeCadEntry = try #require(plugins.first { ($0["name"] as? String) == "made-cad" })
        let sourceRel = try #require(madeCadEntry["source"] as? String)
        let resolvedSource = Self.repoRoot.appendingPathComponent(sourceRel).standardizedFileURL
        #expect(resolvedSource == Self.pluginDir.standardizedFileURL)
        #expect(fm.fileExists(atPath: resolvedSource.path))

        let rootPluginData = try Data(contentsOf: rootPluginURL)
        let rootPlugin = try #require(
            try JSONSerialization.jsonObject(with: rootPluginData) as? [String: Any]
        )
        #expect(rootPlugin["name"] as? String == "made-cad")
        let skillsRel = try #require(rootPlugin["skills"] as? String)
        let resolvedSkills = Self.repoRoot.appendingPathComponent(skillsRel).standardizedFileURL
        #expect(fm.fileExists(atPath: resolvedSkills.path))

        let nestedPluginData = try Data(contentsOf: nestedPluginURL)
        let nestedPlugin = try #require(
            try JSONSerialization.jsonObject(with: nestedPluginData) as? [String: Any]
        )
        #expect(nestedPlugin["name"] as? String == "made-cad")
    }

    @Test("SKILL.md documents part format, expected block, MCP connection, all registered tools, and workflow")
    func testSkillDocumentCompleteness() throws {
        let skillURL = Self.skillDir.appendingPathComponent("SKILL.md")
        let content = try String(contentsOf: skillURL, encoding: .utf8)

        // Frontmatter checks
        #expect(content.hasPrefix("---\n"))
        #expect(content.contains("name: made-cad"))
        #expect(content.contains("description:"))

        // MCP endpoint and transport checks
        #expect(content.contains("127.0.0.1:9820"))
        #expect(content.contains("--mcp-stdio"))

        // .part.ts / .part.js format and expected block checks
        #expect(content.contains(".part.ts"))
        #expect(content.contains(".part.js"))
        #expect(content.contains("export const expected"))
        #expect(content.contains("ExpectedSpec"))
        #expect(content.contains("volume"))
        #expect(content.contains("area"))
        #expect(content.contains("surfaceArea"))
        #expect(content.contains("bounds"))
        #expect(content.contains("tolerance"))

        // Every registered MCP tool must be documented in SKILL.md
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        for tool in registry.tools {
            #expect(
                content.contains(tool.name),
                "SKILL.md is missing documentation for MCP tool \(tool.name)"
            )
        }

        // Snapshot view names must be documented
        for viewName in ["front", "top", "right", "isometric", "perspective"] {
            #expect(
                content.contains(viewName),
                "SKILL.md is missing snapshot view name \(viewName)"
            )
        }

        // Bundled references/made.d.ts must match PartRuntime.bundledTypeDefinitions()
        let refDtsURL = Self.skillDir.appendingPathComponent("references/made.d.ts")
        let refDts = try String(contentsOf: refDtsURL, encoding: .utf8)
        let runtimeDts = try PartRuntime.bundledTypeDefinitions()
        #expect(refDts == runtimeDts)
    }

    @Test("Every gallery example .part.ts builds cleanly and passes cad_verify with zero errors or warnings")
    func testGalleryExamplesBuildAndPassVerify() async throws {
        let examplesDir = Self.skillDir.appendingPathComponent("examples", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(
            at: examplesDir,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasSuffix(".part.ts") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        #expect(entries.count >= 6)

        let skillContent = try String(
            contentsOf: Self.skillDir.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )

        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let sink = PluginSkillTestMeshSink()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, meshSink: sink)
        defer { registry.partReloadController.stopAll() }

        for fileURL in entries {
            let fileName = fileURL.lastPathComponent
            #expect(
                skillContent.contains("examples/\(fileName)"),
                "SKILL.md should link to gallery example examples/\(fileName)"
            )

            let reloadResult = await registry.callTool(
                name: "cad_reload",
                arguments: ["file": .string(fileURL.path)]
            )
            #expect(
                reloadResult.isError == false,
                "cad_reload failed for \(fileName): \(reloadResult.content.first?.text ?? "")"
            )
            let reloadJSON = try parseToolJSON(reloadResult)
            let solidId = try #require(reloadJSON["id"] as? String)

            let diagResult = await registry.callTool(
                name: "cad_get_diagnostics",
                arguments: ["id": .string(solidId)]
            )
            #expect(diagResult.isError == false)
            let diagJSON = try parseToolJSON(diagResult)
            #expect(
                (diagJSON["errors"] as? [[String: Any]])?.isEmpty == true,
                "Expected 0 errors for \(fileName)"
            )
            #expect(
                (diagJSON["warnings"] as? [[String: Any]])?.isEmpty == true,
                "Expected 0 warnings for \(fileName)"
            )

            let verifyResult = await registry.callTool(
                name: "cad_verify",
                arguments: ["id": .string(solidId)]
            )
            let verifyJSON = try parseToolJSON(verifyResult)
            #expect(
                verifyResult.isError == false,
                "cad_verify failed for \(fileName): \(verifyResult.content.first?.text ?? "")"
            )
            #expect(verifyJSON["passed"] as? Bool == true)
            #expect(verifyJSON["valid"] as? Bool == true)
            #expect(verifyJSON["closed"] as? Bool == true)
            #expect(verifyJSON["manifold"] as? Bool == true)
            #expect(verifyJSON["positiveVolume"] as? Bool == true)

            let checks = try #require(verifyJSON["checks"] as? [String: Any])
            let volCheck = try #require(checks["volume"] as? [String: Any], "\(fileName) must verify expected volume")
            let areaCheck = try #require(checks["area"] as? [String: Any], "\(fileName) must verify expected area")
            let boundsCheck = try #require(checks["bounds"] as? [String: Any], "\(fileName) must verify expected bounds")
            #expect(volCheck["passed"] as? Bool == true, "volume check failed in \(fileName): \(volCheck)")
            #expect(areaCheck["passed"] as? Bool == true, "area check failed in \(fileName): \(areaCheck)")
            #expect(boundsCheck["passed"] as? Bool == true, "bounds check failed in \(fileName): \(boundsCheck)")
        }
    }

    @Test("Every evaluation set case and reference solution builds cleanly and passes cad_verify")
    func testEvaluationSetBuildsAndPassesVerify() async throws {
        let evalDir = Self.skillDir.appendingPathComponent("eval", isDirectory: true)
        let requestsURL = evalDir.appendingPathComponent("requests.json")
        let data = try Data(contentsOf: requestsURL)
        let manifest = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let cases = try #require(manifest["cases"] as? [[String: Any]])
        #expect(cases.count >= 5)

        let skillContent = try String(
            contentsOf: Self.skillDir.appendingPathComponent("SKILL.md"),
            encoding: .utf8
        )

        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let sink = PluginSkillTestMeshSink()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, meshSink: sink)
        defer { registry.partReloadController.stopAll() }

        for evalCase in cases {
            let caseId = try #require(evalCase["id"] as? String)
            let prompt = try #require(evalCase["prompt"] as? String)
            let solutionRel = try #require(evalCase["solution"] as? String)
            let expectedDict = try #require(evalCase["expected"] as? [String: Any])

            #expect(!caseId.isEmpty)
            #expect(!prompt.isEmpty)
            #expect(expectedDict["volume"] as? Double != nil)
            #expect(expectedDict["area"] as? Double != nil)
            #expect(expectedDict["bounds"] as? [String: Any] != nil)
            #expect(
                skillContent.contains(caseId),
                "SKILL.md should reference evaluation case \(caseId)"
            )

            let solutionURL = evalDir.appendingPathComponent(solutionRel)
            #expect(
                FileManager.default.fileExists(atPath: solutionURL.path),
                "Missing evaluation solution at \(solutionURL.path)"
            )

            let reloadResult = await registry.callTool(
                name: "cad_reload",
                arguments: ["file": .string(solutionURL.path)]
            )
            #expect(
                reloadResult.isError == false,
                "cad_reload failed for \(caseId): \(reloadResult.content.first?.text ?? "")"
            )
            let reloadJSON = try parseToolJSON(reloadResult)
            let solidId = try #require(reloadJSON["id"] as? String)

            let diagResult = await registry.callTool(
                name: "cad_get_diagnostics",
                arguments: ["id": .string(solidId)]
            )
            #expect(diagResult.isError == false)
            let diagJSON = try parseToolJSON(diagResult)
            #expect((diagJSON["errors"] as? [[String: Any]])?.isEmpty == true)
            #expect((diagJSON["warnings"] as? [[String: Any]])?.isEmpty == true)

            let verifyResult = await registry.callTool(
                name: "cad_verify",
                arguments: ["id": .string(solidId)]
            )
            #expect(
                verifyResult.isError == false,
                "cad_verify failed for \(caseId): \(verifyResult.content.first?.text ?? "")"
            )
            let verifyJSON = try parseToolJSON(verifyResult)
            #expect(verifyJSON["passed"] as? Bool == true)
            #expect(verifyJSON["valid"] as? Bool == true)
            #expect(verifyJSON["closed"] as? Bool == true)
            #expect(verifyJSON["manifold"] as? Bool == true)
            #expect(verifyJSON["positiveVolume"] as? Bool == true)

            let checks = try #require(verifyJSON["checks"] as? [String: Any])
            let volCheck = try #require(checks["volume"] as? [String: Any])
            let areaCheck = try #require(checks["area"] as? [String: Any])
            let boundsCheck = try #require(checks["bounds"] as? [String: Any])
            #expect(volCheck["passed"] as? Bool == true)
            #expect(areaCheck["passed"] as? Bool == true)
            #expect(boundsCheck["passed"] as? Bool == true)

            // Also verify that requests.json expected values match the measured solid within tolerance
            let measured = try #require(verifyJSON["measured"] as? [String: Any])
            let measuredVolume = try #require(measured["volume"] as? Double)
            let measuredArea = try #require(measured["area"] as? Double)
            let manifestVolume = try #require(expectedDict["volume"] as? Double)
            let manifestArea = try #require(expectedDict["area"] as? Double)
            let tolerance = (expectedDict["tolerance"] as? Double) ?? 0.01

            #expect(abs(measuredVolume - manifestVolume) <= abs(manifestVolume) * tolerance)
            #expect(abs(measuredArea - manifestArea) <= abs(manifestArea) * tolerance)
        }
    }

    @Test("Gallery and evaluation .part.ts files typecheck with tsc --noEmit against references/made.d.ts")
    func testGalleryAndEvalPartsTypecheckWithTSC() throws {
        let candidateTscPaths = [
            "/Users/travisgalloway/.npm/_npx/a5fa6ff2e59295e5/node_modules/.bin/tsc",
            "/usr/local/bin/tsc",
            "/opt/homebrew/bin/tsc"
        ]
        guard let tscPath = candidateTscPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return
        }

        let examplesDir = Self.skillDir.appendingPathComponent("examples", isDirectory: true)
        let solutionsDir = Self.skillDir.appendingPathComponent("eval/solutions", isDirectory: true)
        let refDtsURL = Self.skillDir.appendingPathComponent("references/made.d.ts")

        let exampleFiles = try FileManager.default.contentsOfDirectory(
            at: examplesDir,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasSuffix(".part.ts") }
        .map(\.path)

        let solutionFiles = try FileManager.default.contentsOfDirectory(
            at: solutionsDir,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasSuffix(".part.ts") }
        .map(\.path)

        let tscProc = Process()
        tscProc.executableURL = URL(fileURLWithPath: tscPath)
        tscProc.arguments = [
            "--noEmit",
            "--strict",
            "--target", "ES2022",
            "--module", "ES2022",
            refDtsURL.path,
        ] + exampleFiles + solutionFiles

        let pipe = Pipe()
        tscProc.standardOutput = pipe
        tscProc.standardError = pipe
        try tscProc.run()
        tscProc.waitUntilExit()

        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        #expect(
            tscProc.terminationStatus == 0,
            "tsc --noEmit failed:\n\(output)"
        )
    }

    @Test("End-to-end skill workflow loop over MCPServer: copy gallery example, reload, diagnose, verify, and capture snapshot views")
    func testSkillWorkflowLoopOverMCPServer() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("made-skill-workflow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceExample = Self.skillDir.appendingPathComponent("examples/mounting-bracket.part.ts")
        let workingPart = tempDir.appendingPathComponent("mounting-bracket.part.ts")
        try FileManager.default.copyItem(at: sourceExample, to: workingPart)

        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let sink = PluginSkillTestMeshSink()
        let snapshotProvider = PluginSkillSnapshotProvider()
        let registry = CADToolRegistry(
            document: doc,
            kernelClient: kernel,
            snapshotProvider: snapshotProvider,
            meshSink: sink
        )
        defer {
            _ = snapshotProvider
            registry.partReloadController.stopAll()
        }

        // Step 1: Reload copied gallery part
        let reloadRes = await registry.callTool(
            name: "cad_reload",
            arguments: ["file": .string(workingPart.path)]
        )
        #expect(reloadRes.isError == false)
        let reloadJSON = try parseToolJSON(reloadRes)
        let solidId = try #require(reloadJSON["id"] as? String)

        // Step 2: Check diagnostics (0 errors, 0 warnings)
        let diagRes = await registry.callTool(
            name: "cad_get_diagnostics",
            arguments: ["id": .string(solidId)]
        )
        #expect(diagRes.isError == false)
        let diagJSON = try parseToolJSON(diagRes)
        #expect((diagJSON["errors"] as? [[String: Any]])?.isEmpty == true)
        #expect((diagJSON["warnings"] as? [[String: Any]])?.isEmpty == true)

        // Step 3: Verify geometry and expected block
        let verifyRes = await registry.callTool(
            name: "cad_verify",
            arguments: ["id": .string(solidId)]
        )
        #expect(verifyRes.isError == false)
        let verifyJSON = try parseToolJSON(verifyRes)
        #expect(verifyJSON["passed"] as? Bool == true)
        #expect(verifyJSON["valid"] as? Bool == true)

        // Step 4: Capture snapshots across all documented views
        for view in ["isometric", "front", "top", "right", "perspective"] {
            let snapRes = await registry.callTool(
                name: "cad_capture_snapshot",
                arguments: ["view": .string(view)]
            )
            #expect(snapRes.isError == false)
            #expect(snapRes.content.first?.type == "image")
            #expect(snapRes.content.first?.mimeType == "image/png")
        }
    }
}

private final class PluginSkillSnapshotProvider: SnapshotProvider, @unchecked Sendable {
    func captureSnapshotPngBase64() async -> String? {
        await captureSnapshotPngBase64(view: nil)
    }

    func captureSnapshotPngBase64(view: ViewportPerspective?) async -> String? {
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    }
}

