import Testing
import Foundation
import Metal
import simd
@testable import MadeCore

private final class RecordingViewSnapshotProvider: SnapshotProvider, @unchecked Sendable {
    var recordedViews: [ViewportPerspective?] = []
    var shouldFailCapture = false

    func captureSnapshotPngBase64() async -> String? {
        await captureSnapshotPngBase64(view: nil)
    }

    func captureSnapshotPngBase64(view: ViewportPerspective?) async -> String? {
        recordedViews.append(view)
        guard !shouldFailCapture else { return nil }
        return "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    }
}

@MainActor
private final class RecordingPartMeshSink: SolidMeshSink {
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

@Suite("Part Reload, Diagnostics, Verification, and Snapshot Views MCP Tests (#428)")
@MainActor
struct PartVerificationMCPTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("made-issue428-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func parseJSON(_ result: MCPToolCallResult) throws -> [String: Any] {
        let text = try #require(result.content.first?.text)
        let data = try #require(text.data(using: .utf8))
        let obj = try JSONSerialization.jsonObject(with: data)
        return try #require(obj as? [String: Any])
    }

    @Test func testToolsListIncludesReloadDiagnosticsVerifyAndSnapshotViews() {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let toolNames = Set(registry.tools.map(\.name))
        #expect(toolNames.contains("cad_reload"))
        #expect(toolNames.contains("cad_get_diagnostics"))
        #expect(toolNames.contains("cad_verify"))
        #expect(toolNames.contains("cad_capture_snapshot"))
        #expect(registry.tools.count == 11)

        let snapshotTool = registry.tools.first { $0.name == "cad_capture_snapshot" }
        let viewProp = snapshotTool?.inputSchema.properties["view"]
        #expect(viewProp?.type == "string")
        #expect(viewProp?.enum == ["front", "top", "right", "isometric", "perspective"])
    }

    @Test func testReloadOpensAndEvaluatesPartByFileAndByIdAndReloadsAll() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let partURL = tempDir.appendingPathComponent("plate.part.ts")
        try """
        import { Box } from 'made';
        export default Box({ width: 20, depth: 15, height: 10 });
        export const expected = { volume: 3000, tolerance: 0.01 };
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let sink = RecordingPartMeshSink()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, meshSink: sink)
        defer { registry.partReloadController.stopAll() }

        // 1. Calling cad_reload with no open parts returns isError: true
        let emptyReload = await registry.callTool(name: "cad_reload", arguments: [:])
        #expect(emptyReload.isError == true)
        #expect(emptyReload.content.first?.text?.contains("No part files") == true)

        // 2. Calling cad_reload with "file" opens and evaluates the part
        let openResult = await registry.callTool(
            name: "cad_reload",
            arguments: ["file": .string(partURL.path)]
        )
        #expect(openResult.isError == false)
        let openJSON = try parseJSON(openResult)
        #expect(openJSON["passed"] as? Bool == true)
        #expect(openJSON["status"] as? String == "ok")
        #expect(openJSON["hasExpected"] as? Bool == true)
        let partIdStr = try #require(openJSON["id"] as? String)
        let partId = SolidId(partIdStr)
        #expect(sink.installedMeshes[partId] != nil)
        #expect((openJSON["triangleCount"] as? Int ?? 0) >= 12)

        // 3. Edit the file and reload by "id"
        try """
        import { Box } from 'made';
        export default Box({ width: 40, depth: 20, height: 10 });
        export const expected = { volume: 8000, tolerance: 0.01 };
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let reloadById = await registry.callTool(
            name: "cad_reload",
            arguments: ["id": .string(partIdStr)]
        )
        #expect(reloadById.isError == false)
        let byIdJSON = try parseJSON(reloadById)
        #expect(byIdJSON["passed"] as? Bool == true)
        #expect(byIdJSON["id"] as? String == partIdStr)

        // 4. Reload all open parts with empty arguments
        let reloadAll = await registry.callTool(name: "cad_reload", arguments: [:])
        #expect(reloadAll.isError == false)
        let allJSON = try parseJSON(reloadAll)
        #expect(allJSON["passed"] as? Bool == true)
        let partsArr = try #require(allJSON["parts"] as? [[String: Any]])
        #expect(partsArr.count == 1)

        // 5. Edge cases: unknown id, non-part solid id, mismatched file, non-string id
        let unknownId = await registry.callTool(name: "cad_reload", arguments: ["id": .string("part-999")])
        #expect(unknownId.isError == true)
        #expect(unknownId.content.first?.text?.contains("not found") == true)

        let nonPartId = await registry.callTool(name: "cad_reload", arguments: ["id": .string("box-1")])
        #expect(nonPartId.isError == true)
        #expect(nonPartId.content.first?.text?.contains("not a reloadable part file") == true)

        let mismatchedFile = await registry.callTool(
            name: "cad_reload",
            arguments: [
                "id": .string(partIdStr),
                "file": .string(tempDir.appendingPathComponent("other.part.ts").path)
            ]
        )
        #expect(mismatchedFile.isError == true)
        #expect(mismatchedFile.content.first?.text?.contains("does not match") == true)

        let badIdType = await registry.callTool(name: "cad_reload", arguments: ["id": .int(42)])
        #expect(badIdType.isError == true)
    }

    @Test func testDiagnosticsAndReloadReportExactFileLineColumnForErrorsAndWarnings() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let helperURL = tempDir.appendingPathComponent("dims.ts")
        let partURL = tempDir.appendingPathComponent("widget.part.ts")

        try """
        export function computeHeight(scale: number): number {
          return scale * 10;
        }
        """.write(to: helperURL, atomically: true, encoding: .utf8)

        try """
        import { Box } from 'made';
        import { computeHeight } from './dims';
        console.warn('draft thickness warning');
        export default Box({ width: 20, depth: 20, height: computeHeight(1) });
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        defer { registry.partReloadController.stopAll() }

        // Initial reload succeeds with 1 warning on line 3 of widget.part.ts
        let initialReload = await registry.callTool(name: "cad_reload", arguments: ["file": .string(partURL.path)])
        #expect(initialReload.isError == false)
        let initJSON = try parseJSON(initialReload)
        let partIdStr = try #require(initJSON["id"] as? String)
        let warnings = try #require(initJSON["warnings"] as? [[String: Any]])
        #expect(warnings.count == 1)
        #expect((warnings[0]["file"] as? String)?.hasSuffix("widget.part.ts") == true)
        #expect(warnings[0]["line"] as? Int == 3)
        #expect((warnings[0]["column"] as? Int ?? 0) >= 1)
        #expect(warnings[0]["message"] as? String == "draft thickness warning")

        // cad_get_diagnostics returns the same warning and 0 errors
        let diagResult1 = await registry.callTool(name: "cad_get_diagnostics", arguments: ["id": .string(partIdStr)])
        #expect(diagResult1.isError == false)
        let diagJSON1 = try parseJSON(diagResult1)
        #expect((diagJSON1["errors"] as? [[String: Any]])?.isEmpty == true)
        let diagWarnings1 = try #require(diagJSON1["warnings"] as? [[String: Any]])
        #expect(diagWarnings1.count == 1)
        #expect(diagWarnings1[0]["line"] as? Int == 3)
        #expect(diagWarnings1[0]["message"] as? String == "draft thickness warning")

        // Introduce a runtime error on line 2 of dims.ts
        try """
        export function computeHeight(scale: number): number {
          throw new Error('negative clearance in helper');
        }
        """.write(to: helperURL, atomically: true, encoding: .utf8)

        let failedReload = await registry.callTool(name: "cad_reload", arguments: ["id": .string(partIdStr)])
        #expect(failedReload.isError == true)
        let failedJSON = try parseJSON(failedReload)
        #expect(failedJSON["passed"] as? Bool == false)
        let reloadErrors = try #require(failedJSON["errors"] as? [[String: Any]])
        #expect(reloadErrors.count == 1)
        #expect((reloadErrors[0]["file"] as? String)?.hasSuffix("dims.ts") == true)
        #expect(reloadErrors[0]["line"] as? Int == 2)
        #expect((reloadErrors[0]["column"] as? Int ?? 0) >= 1)
        #expect((reloadErrors[0]["message"] as? String)?.contains("negative clearance in helper") == true)

        // cad_get_diagnostics returns the exact same error diagnostic
        let diagResult2 = await registry.callTool(name: "cad_get_diagnostics", arguments: ["file": .string(partURL.path)])
        #expect(diagResult2.isError == false)
        let diagJSON2 = try parseJSON(diagResult2)
        let diagErrors2 = try #require(diagJSON2["errors"] as? [[String: Any]])
        #expect(diagErrors2.count == 1)
        #expect(diagErrors2[0]["file"] as? String == reloadErrors[0]["file"] as? String)
        #expect(diagErrors2[0]["line"] as? Int == reloadErrors[0]["line"] as? Int)
        #expect(diagErrors2[0]["column"] as? Int == reloadErrors[0]["column"] as? Int)
        #expect(diagErrors2[0]["message"] as? String == reloadErrors[0]["message"] as? String)

        // Filtering diagnostics by unknown id or unopened file returns isError: true
        let unknownDiag = await registry.callTool(name: "cad_get_diagnostics", arguments: ["id": .string("missing-id")])
        #expect(unknownDiag.isError == true)
        let unopenedDiag = await registry.callTool(
            name: "cad_get_diagnostics",
            arguments: ["file": .string(tempDir.appendingPathComponent("unopened.part.ts").path)]
        )
        #expect(unopenedDiag.isError == true)
    }

    @Test func testVerifyChecksClosedManifoldPositiveVolumeAndExpectedBlock() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let partURL = tempDir.appendingPathComponent("block.part.ts")
        // 20 x 30 x 10 box: volume = 6000, area = 2*(600 + 300 + 200) = 2200, bounds = [0, 0, 0]..[20, 30, 10]
        try """
        import { Box } from 'made';
        export default Box({ width: 20, depth: 30, height: 10, center: false });
        export const expected = {
          volume: 6000,
          area: 2200,
          bounds: { min: [0, 0, 0], max: [20, 30, 10] },
          tolerance: 0.01
        };
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        defer { registry.partReloadController.stopAll() }

        let reloadRes = await registry.callTool(name: "cad_reload", arguments: ["file": .string(partURL.path)])
        #expect(reloadRes.isError == false)
        let partIdStr = try #require(try parseJSON(reloadRes)["id"] as? String)

        // Verify the part when expected matches
        let verifyPass = await registry.callTool(name: "cad_verify", arguments: ["id": .string(partIdStr)])
        #expect(verifyPass.isError == false)
        let passJSON = try parseJSON(verifyPass)
        #expect(passJSON["valid"] as? Bool == true)
        #expect(passJSON["closed"] as? Bool == true)
        #expect(passJSON["manifold"] as? Bool == true)
        #expect(passJSON["positiveVolume"] as? Bool == true)

        let checks = try #require(passJSON["checks"] as? [String: Any])
        let volCheck = try #require(checks["volume"] as? [String: Any])
        let areaCheck = try #require(checks["area"] as? [String: Any])
        let boundsCheck = try #require(checks["bounds"] as? [String: Any])
        #expect(volCheck["passed"] as? Bool == true)
        #expect(areaCheck["passed"] as? Bool == true)
        #expect(boundsCheck["passed"] as? Bool == true)

        // Verify all solids in the scene (box-1, cylinder-1, and the part)
        let verifyAll = await registry.callTool(name: "cad_verify", arguments: [:])
        #expect(verifyAll.isError == false)
        let allJSON = try parseJSON(verifyAll)
        #expect(allJSON["valid"] as? Bool == true)
        let solidsArr = try #require(allJSON["solids"] as? [[String: Any]])
        #expect(solidsArr.count == 3)

        // Now update the part so its geometry (10 x 30 x 10, volume 3000, area 1400) disagrees with expected (volume 6000, surfaceArea 2200, bounds max [20, 30, 10])
        try """
        import { Box } from 'made';
        export default Box({ width: 10, depth: 30, height: 10, center: false });
        export const expected = {
          volume: 6000,
          surfaceArea: 2200,
          bounds: { min: [0, 0, 0], max: [20, 30, 10] },
          tolerance: 0.01
        };
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let reloadMismatch = await registry.callTool(name: "cad_reload", arguments: ["id": .string(partIdStr)])
        #expect(reloadMismatch.isError == false)

        let verifyFail = await registry.callTool(name: "cad_verify", arguments: ["id": .string(partIdStr)])
        #expect(verifyFail.isError == true)
        let failJSON = try parseJSON(verifyFail)
        #expect(failJSON["valid"] as? Bool == false)
        #expect(failJSON["closed"] as? Bool == true)
        #expect(failJSON["manifold"] as? Bool == true)
        #expect(failJSON["positiveVolume"] as? Bool == true)

        let failChecks = try #require(failJSON["checks"] as? [String: Any])
        let failVol = try #require(failChecks["volume"] as? [String: Any])
        #expect(failVol["passed"] as? Bool == false)
        #expect(abs((failVol["measured"] as? Double ?? 0) - 3000.0) < 1.0)
        #expect(failVol["expected"] as? Double == 6000.0)

        let failArea = try #require(failChecks["area"] as? [String: Any])
        #expect(failArea["passed"] as? Bool == false)
        #expect(abs((failArea["measured"] as? Double ?? 0) - 1400.0) < 1.0)
        #expect(failArea["expected"] as? Double == 2200.0)

        let failBounds = try #require(failChecks["bounds"] as? [String: Any])
        #expect(failBounds["passed"] as? Bool == false)
        let measuredBounds = try #require(failBounds["measured"] as? [String: Any])
        let expectedBounds = try #require(failBounds["expected"] as? [String: Any])
        #expect(measuredBounds["max"] as? [Double] == [10.0, 30.0, 10.0])
        #expect(expectedBounds["max"] as? [Double] == [20.0, 30.0, 10.0])

        let failureMessages = try #require(failJSON["failures"] as? [String])
        #expect(failureMessages.count == 3)
        #expect(failureMessages.contains { $0.contains("volume mismatch") })
        #expect(failureMessages.contains { $0.contains("area mismatch") })
        #expect(failureMessages.contains { $0.contains("bounds mismatch") })
    }

    @Test func testVerifyDetectsOpenNonManifoldInvertedAndBrokenPartMeshes() async throws {
        // 1. Valid closed tetrahedron with outward CCW normals:
        // v0=(0,0,0), v1=(10,0,0), v2=(0,10,0), v3=(0,0,10)
        let v0 = SIMD3<Float>(0, 0, 0)
        let v1 = SIMD3<Float>(10, 0, 0)
        let v2 = SIMD3<Float>(0, 10, 0)
        let v3 = SIMD3<Float>(0, 0, 10)

        func makePayload(triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)]) -> MeshPayload {
            var pos: [Float] = []
            var norm: [Float] = []
            var idx: [UInt32] = []
            var cursor: UInt32 = 0
            for (a, b, c) in triangles {
                let n = simd_normalize(simd_cross(b - a, c - a))
                for p in [a, b, c] {
                    pos.append(contentsOf: [p.x, p.y, p.z])
                    norm.append(contentsOf: [n.x, n.y, n.z])
                    idx.append(cursor)
                    cursor += 1
                }
            }
            return MeshPayload(positions: pos, normals: norm, indices: idx)
        }

        let closedTet = makePayload(triangles: [
            (v0, v2, v1), // bottom z=0 (normal -Z)
            (v0, v1, v3), // front y=0 (normal -Y)
            (v0, v3, v2), // left x=0 (normal -X)
            (v1, v2, v3)  // sloped face (normal +X+Y+Z)
        ])
        let closedAnalysis = SolidVerifier.analyzeMesh(closedTet)
        #expect(closedAnalysis.closed == true)
        #expect(closedAnalysis.manifold == true)
        #expect(closedAnalysis.positiveVolume == true)
        #expect(closedAnalysis.isValidSolid == true)

        // 2. Open mesh (missing one face of the tetrahedron -> 3 triangles, or a box missing 1 triangle -> 11 triangles)
        let fullBoxPayload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 10, depth: 10, height: 10))
        let droppedOneTriangleIndices = Array(fullBoxPayload.indices.dropLast(3))
        let openBoxPayload = MeshPayload(
            positions: Array(fullBoxPayload.positions.dropLast(9)),
            normals: Array(fullBoxPayload.normals.dropLast(9)),
            indices: droppedOneTriangleIndices
        )
        let openAnalysis = SolidVerifier.analyzeMesh(openBoxPayload)
        #expect(openAnalysis.closed == false)
        #expect(openAnalysis.openEdgeCount > 0)
        #expect(openAnalysis.isValidSolid == false)

        // 3. Non-manifold mesh: closed tetrahedron plus an extra fin triangle sharing edge (v0, v1)
        let v4 = SIMD3<Float>(5, 5, 20)
        let nonManifoldTet = makePayload(triangles: [
            (v0, v2, v1),
            (v0, v1, v3),
            (v0, v3, v2),
            (v1, v2, v3),
            (v0, v1, v4),
            (v0, v4, v1)
        ])
        let nonManifoldAnalysis = SolidVerifier.analyzeMesh(nonManifoldTet)
        #expect(nonManifoldAnalysis.manifold == false)
        #expect(nonManifoldAnalysis.nonManifoldEdgeCount > 0)
        #expect(nonManifoldAnalysis.isValidSolid == false)

        // 4. Inverted winding (negative signed volume)
        let invertedTet = makePayload(triangles: [
            (v0, v1, v2),
            (v0, v3, v1),
            (v0, v2, v3),
            (v1, v3, v2)
        ])
        let invertedAnalysis = SolidVerifier.analyzeMesh(invertedTet)
        #expect(invertedAnalysis.closed == true)
        #expect(invertedAnalysis.manifold == true)
        #expect(invertedAnalysis.positiveVolume == false)
        #expect(invertedAnalysis.isValidSolid == false)

        // 5. Broken part reload makes cad_verify fail with diagnostic even when previous mesh was valid
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let partURL = tempDir.appendingPathComponent("breakable.part.ts")
        try """
        import { Box } from 'made';
        export default Box({ width: 10, depth: 10, height: 10 });
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        defer { registry.partReloadController.stopAll() }

        let r1 = await registry.callTool(name: "cad_reload", arguments: ["file": .string(partURL.path)])
        let partIdStr = try #require(try parseJSON(r1)["id"] as? String)

        try """
        import { Box } from 'made';
        export default Box({ width: -5, depth: 10, height: 10 });
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let r2 = await registry.callTool(name: "cad_reload", arguments: ["id": .string(partIdStr)])
        #expect(r2.isError == true)

        let verifyBroken = await registry.callTool(name: "cad_verify", arguments: ["id": .string(partIdStr)])
        #expect(verifyBroken.isError == true)
        let brokenJSON = try parseJSON(verifyBroken)
        #expect(brokenJSON["valid"] as? Bool == false)
        #expect(brokenJSON["diagnostic"] != nil)
    }

    @Test func testCaptureSnapshotNamedViewsValidationAndForwarding() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let provider = RecordingViewSnapshotProvider()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: provider)

        let views: [(String, ViewportPerspective)] = [
            ("front", .front),
            ("top", .top),
            ("right", .right),
            ("isometric", .isometric),
            ("perspective", .perspective)
        ]

        for (name, expectedPerspective) in views {
            let result = await registry.callTool(
                name: "cad_capture_snapshot",
                arguments: ["view": .string(name)]
            )
            #expect(result.isError == false)
            #expect(provider.recordedViews.last == expectedPerspective)
        }

        // Omitting 'view' passes nil (current viewport camera)
        let defaultViewResult = await registry.callTool(name: "cad_capture_snapshot", arguments: [:])
        #expect(defaultViewResult.isError == false)
        #expect(provider.recordedViews.last == .some(nil))

        // Invalid view name returns isError: true
        let invalidView = await registry.callTool(
            name: "cad_capture_snapshot",
            arguments: ["view": .string("bottom")]
        )
        #expect(invalidView.isError == true)
        #expect(invalidView.content.first?.text?.contains("Supported views: 'front', 'top', 'right', 'isometric', 'perspective'") == true)

        // Non-string view argument returns isError: true
        let nonStringView = await registry.callTool(
            name: "cad_capture_snapshot",
            arguments: ["view": .int(1)]
        )
        #expect(nonStringView.isError == true)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available))
    func testMetalRendererNamedViewSnapshotsProduceDistinctFramesWithoutMutatingCamera() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let provider = HeadlessSnapshotProvider(document: doc, kernelClient: kernel, target: renderer)
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: provider)

        let originalCamera = renderer.camera

        let frontRes = await registry.callTool(name: "cad_capture_snapshot", arguments: ["view": .string("front")])
        let topRes = await registry.callTool(name: "cad_capture_snapshot", arguments: ["view": .string("top")])
        let rightRes = await registry.callTool(name: "cad_capture_snapshot", arguments: ["view": .string("right")])
        let isoRes = await registry.callTool(name: "cad_capture_snapshot", arguments: ["view": .string("isometric")])

        #expect(frontRes.isError == false)
        #expect(topRes.isError == false)
        #expect(rightRes.isError == false)
        #expect(isoRes.isError == false)

        guard let frontB64 = frontRes.content.first?.data,
              let topB64 = topRes.content.first?.data,
              let rightB64 = rightRes.content.first?.data,
              let isoB64 = isoRes.content.first?.data else {
            Issue.record("Expected PNG image content for all named views")
            return
        }

        #expect(frontB64 != topB64)
        #expect(frontB64 != rightB64)
        #expect(topB64 != isoB64)
        #expect(renderer.camera == originalCamera)
    }

    @Test func testAgentEditReloadVerifyAndRepairLoopOverMCPServer() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let partURL = tempDir.appendingPathComponent("bracket.part.ts")
        let doc = DocumentModel()
        // Remove default solids so the scene contains only the agent's part
        for obj in doc.objects {
            doc.removeObject(id: obj.id)
        }
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let snapshotProvider = RecordingViewSnapshotProvider()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: snapshotProvider)
        defer { registry.partReloadController.stopAll() }
        let server = MCPServer(toolRegistry: registry)

        func callOverJSONRPC(id: Int, tool: String, args: [String: Any]) async throws -> (isError: Bool, text: String?, imageBase64: String?) {
            let reqObj: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "method": "tools/call",
                "params": [
                    "name": tool,
                    "arguments": args
                ]
            ]
            let reqData = try JSONSerialization.data(withJSONObject: reqObj)
            let reqStr = try #require(String(data: reqData, encoding: .utf8))
            let respStr = try #require(await server.processMessage(reqStr))
            let respData = try #require(respStr.data(using: .utf8))
            let respJSON = try #require(try JSONSerialization.jsonObject(with: respData) as? [String: Any])
            // Tool failures must return a result with isError: true, never a JSON-RPC error payload.
            #expect(respJSON["error"] == nil)
            let resultObj = try #require(respJSON["result"] as? [String: Any])
            let isError = resultObj["isError"] as? Bool ?? false
            let contentArr = try #require(resultObj["content"] as? [[String: Any]])
            let firstContent = contentArr.first
            return (isError, firstContent?["text"] as? String, firstContent?["data"] as? String)
        }

        // Step 1: Agent writes initial part script with a mistake (undefined identifier on line 3)
        try """
        import { Box, Cylinder, subtract } from 'made';
        const base = Box({ width: 40, depth: 20, height: 10, center: false });
        export default subtract(base, missingCutter);
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let step1Reload = try await callOverJSONRPC(id: 1, tool: "cad_reload", args: ["file": partURL.path])
        #expect(step1Reload.isError == true)
        let step1Data = try #require(step1Reload.text?.data(using: .utf8))
        let step1JSON = try #require(try JSONSerialization.jsonObject(with: step1Data) as? [String: Any])
        let step1PartId = try #require(step1JSON["id"] as? String)
        let step1Errors = try #require(step1JSON["errors"] as? [[String: Any]])
        #expect(step1Errors.count == 1)
        #expect(step1Errors[0]["line"] as? Int == 3)

        // Agent inspects diagnostics via cad_get_diagnostics
        let step1Diag = try await callOverJSONRPC(id: 2, tool: "cad_get_diagnostics", args: ["id": step1PartId])
        #expect(step1Diag.isError == false)
        let diagData = try #require(step1Diag.text?.data(using: .utf8))
        let diagJSON = try #require(try JSONSerialization.jsonObject(with: diagData) as? [String: Any])
        let diagErrors = try #require(diagJSON["errors"] as? [[String: Any]])
        #expect(diagErrors.count == 1)
        #expect(diagErrors[0]["line"] as? Int == 3)

        // Step 2: Agent fixes the runtime error, but writes width: 30 instead of expected width: 40
        try """
        import { Box } from 'made';
        export default Box({ width: 30, depth: 20, height: 10, center: false });
        export const expected = {
          volume: 8000,
          area: 2800,
          bounds: { min: [0, 0, 0], max: [40, 20, 10] },
          tolerance: 0.01
        };
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let step2Reload = try await callOverJSONRPC(id: 3, tool: "cad_reload", args: ["id": step1PartId])
        #expect(step2Reload.isError == false)

        // Step 3: Agent runs cad_verify and sees expected mismatch (measured volume 6000 vs expected 8000)
        let step3Verify = try await callOverJSONRPC(id: 4, tool: "cad_verify", args: ["id": step1PartId])
        #expect(step3Verify.isError == true)
        let verifyFailData = try #require(step3Verify.text?.data(using: .utf8))
        let verifyFailJSON = try #require(try JSONSerialization.jsonObject(with: verifyFailData) as? [String: Any])
        #expect(verifyFailJSON["valid"] as? Bool == false)
        let checksFail = try #require(verifyFailJSON["checks"] as? [String: Any])
        let volCheckFail = try #require(checksFail["volume"] as? [String: Any])
        #expect(volCheckFail["passed"] as? Bool == false)
        #expect(abs((volCheckFail["measured"] as? Double ?? 0) - 6000.0) < 1.0)
        #expect(volCheckFail["expected"] as? Double == 8000.0)

        // Step 4: Agent repairs width to 40, reloads, verifies, and captures multi-angle snapshots
        try """
        import { Box } from 'made';
        export default Box({ width: 40, depth: 20, height: 10, center: false });
        export const expected = {
          volume: 8000,
          area: 2800,
          bounds: { min: [0, 0, 0], max: [40, 20, 10] },
          tolerance: 0.01
        };
        """.write(to: partURL, atomically: true, encoding: .utf8)

        let step4Reload = try await callOverJSONRPC(id: 5, tool: "cad_reload", args: ["id": step1PartId])
        #expect(step4Reload.isError == false)

        let step4Diag = try await callOverJSONRPC(id: 6, tool: "cad_get_diagnostics", args: ["id": step1PartId])
        #expect(step4Diag.isError == false)
        let cleanDiagData = try #require(step4Diag.text?.data(using: .utf8))
        let cleanDiagJSON = try #require(try JSONSerialization.jsonObject(with: cleanDiagData) as? [String: Any])
        #expect((cleanDiagJSON["errors"] as? [[String: Any]])?.isEmpty == true)

        let step4Verify = try await callOverJSONRPC(id: 7, tool: "cad_verify", args: ["id": step1PartId])
        #expect(step4Verify.isError == false)
        let verifyPassData = try #require(step4Verify.text?.data(using: .utf8))
        let verifyPassJSON = try #require(try JSONSerialization.jsonObject(with: verifyPassData) as? [String: Any])
        #expect(verifyPassJSON["valid"] as? Bool == true)
        #expect(verifyPassJSON["closed"] as? Bool == true)
        #expect(verifyPassJSON["manifold"] as? Bool == true)
        #expect(verifyPassJSON["positiveVolume"] as? Bool == true)

        let snapFront = try await callOverJSONRPC(id: 8, tool: "cad_capture_snapshot", args: ["view": "front"])
        let snapTop = try await callOverJSONRPC(id: 9, tool: "cad_capture_snapshot", args: ["view": "top"])
        let snapIso = try await callOverJSONRPC(id: 10, tool: "cad_capture_snapshot", args: ["view": "isometric"])
        #expect(snapFront.isError == false && snapFront.imageBase64 != nil)
        #expect(snapTop.isError == false && snapTop.imageBase64 != nil)
        #expect(snapIso.isError == false && snapIso.imageBase64 != nil)
        #expect(snapshotProvider.recordedViews == [.front, .top, .isometric])
    }
}
