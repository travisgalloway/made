import Testing
import Foundation
import Synchronization
import simd
@testable import MadeCore

/// Tests for `PartRuntime` JavaScriptCore sandbox, TypeScript type stripping, ES module loader,
/// `made` CAD API, deterministic evaluation, error line/column mapping, and `JobId` cancellation (#435).
@Suite struct PartRuntimeTests {
    private func makeKernel(_ engine: any KernelEngine = LocalKernelEngine()) -> KernelClient {
        KernelClient(engine: engine, debounceDuration: .milliseconds(5))
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("made-part-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Full TypeScript Part Evaluation (`made` API)

    @Test func testTypeScriptPartWithPrimitivesSketchExtrudeRevolveBooleansTransformsAndParams() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let partFile = dir.appendingPathComponent("bracket.part.ts")
        let source = """
        import {
          Box,
          Cylinder,
          Sphere,
          Cone,
          Plane,
          Sketch,
          extrude,
          revolve,
          union,
          subtract,
          intersect,
          translate,
          rotate,
          scale,
          param,
          defineParams,
          type Shape,
          type ExpectedSpec,
          type Vec3
        } from 'made';

        interface BracketConfig {
          readonly width: number;
          readonly height: number;
          readonly holeRadius: number;
        }

        type HoleOffset = Vec3;

        const width: number = param('width', 40, { min: 10, max: 100, step: 1, unit: 'mm', label: 'Base Width' });
        const dims = defineParams({
          depth: { default: 30, min: 10, max: 80, unit: 'mm' },
          thickness: 8,
          holeRadius: { default: 4, min: 1, max: 10 }
        });

        function buildBracket(cfg: BracketConfig): Shape {
          // 2D sketch on offset XY plane extruded into base plate
          const basePlane = Plane.XY.offset(-cfg.height / 2);
          const baseSketch = Sketch(basePlane).roundedRectangle(cfg.width, dims.depth, 3, { detail: 4 });
          const basePlate: Shape = extrude(baseSketch, cfg.height);

          // 2D sketch on XZ plane revolved into a boss collar
          const collarProfile = Sketch(Plane.XZ).polygon([
            [cfg.holeRadius, 0],
            [cfg.holeRadius + 3, 0],
            [cfg.holeRadius + 3, 6],
            [cfg.holeRadius, 6]
          ]);
          const collar: Shape = revolve(collarProfile, 360, { slices: 24 }).translate([0, 0, cfg.height / 2]);

          // Primitives + transforms + booleans
          const rib: Shape = Box({ width: 6, depth: dims.depth, height: cfg.height })
            .rotateZ(45)
            .scale([1, 1, 1]);
          const dome: Shape = Sphere(cfg.holeRadius + 2, { slices: 16 }).translate(0, 0, cfg.height / 2 + 4);
          const frustum: Shape = Cone({ bottomRadius: cfg.holeRadius + 2, topRadius: cfg.holeRadius + 1, height: 4, slices: 16 });
          const boundBox: Shape = scale(Box(100, 100, 100), 1);

          const holeOffset: HoleOffset = [0, 0, 0];
          const drill: Shape = translate(Cylinder(cfg.holeRadius, 40, { slices: 24 }), holeOffset);

          const combined = union(basePlate, collar, rib, frustum, dome.intersect(boundBox));
          return subtract(combined, drill) as Shape;
        }

        export const expected: ExpectedSpec = {
          volume: 9500,
          area: 3800,
          bounds: {
            min: [-20, -15, -4],
            max: [20, 15, 10]
          },
          tolerance: 0.05
        };

        export default buildBracket({
          width,
          height: dims.thickness,
          holeRadius: dims.holeRadius
        });
        """
        try source.write(to: partFile, atomically: true, encoding: .utf8)

        let kernel = makeKernel()
        let runtime = PartRuntime(kernelClient: kernel)

        let res = await runtime.evaluatePartFile(
            at: partFile,
            jobId: JobId("ts-bracket-1"),
            solidId: SolidId("bracket")
        )
        let output = try #require(res.value, "Expected evaluation to succeed, got error: \(String(describing: res.error))")

        #expect(output.payload.triangleCount > 0)
        #expect(output.evaluatedOnMainThread == false)
        #expect(output.parameters.count == 4)
        #expect(output.parameters.map(\.name) == ["width", "depth", "thickness", "holeRadius"])
        #expect(output.parameters.first?.defaultValue == 40)
        #expect(output.parameters.first?.value == 40)
        #expect(output.parameters.first?.unit == "mm")
        #expect(output.parameters.first?.label == "Base Width")

        let expected = try #require(output.expected)
        #expect(expected.volume == 9500)
        #expect(expected.area == 3800)
        #expect(expected.tolerance == 0.05)
        #expect(expected.bounds?.min == SIMD3<Float>(-20, -15, -4))
        #expect(expected.bounds?.max == SIMD3<Float>(20, 15, 10))

        // Re-evaluate with parameter override and verify geometry changes
        let resOverride = await runtime.evaluatePartFile(
            at: partFile,
            jobId: JobId("ts-bracket-2"),
            solidId: SolidId("bracket"),
            parameterOverrides: ["width": 80, "holeRadius": 8]
        )
        let overridden = try #require(resOverride.value)
        #expect(overridden.payload.triangleCount > 0)
        #expect(overridden.parameters.first(where: { $0.name == "width" })?.value == 80)
        #expect(overridden.parameters.first(where: { $0.name == "holeRadius" })?.value == 8)
        #expect(overridden.shape != output.shape)
    }

    // MARK: - Plain `.part.js` Files Load Without Build Step

    @Test func testPlainJavaScriptPartLoadsAndEvaluates() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let jsFile = dir.appendingPathComponent("spacer.part.js")
        let source = """
        import { Sketch, Plane, extrude, Cylinder, subtract } from 'made';

        const outer = Sketch(Plane.XY)
          .moveTo(-10, -10)
          .lineTo(10, -10)
          .lineTo(10, 10)
          .arcTo(-10, 10, 15)
          .close()
          .extrude(6, { centered: true });

        const bore = Cylinder({ diameter: 8, height: 20, slices: 24 });
        export default subtract(outer, bore);
        """
        try source.write(to: jsFile, atomically: true, encoding: .utf8)

        let runtime = PartRuntime(kernelClient: makeKernel())
        let res = await runtime.evaluatePartFile(at: jsFile)
        let output = try #require(res.value, "Plain .part.js failed: \(String(describing: res.error))")
        #expect(output.payload.triangleCount > 0)
    }

    // MARK: - Relative ES Module Imports Inside the Part Directory

    @Test func testRelativeModuleImportsInsidePartDirectory() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dimsFile = dir.appendingPathComponent("dimensions.ts")
        try """
        export interface MountSpec {
          width: number;
          height: number;
        }
        export const DEFAULT_SPEC: MountSpec = { width: 24, height: 12 };
        export default function scaleFactor(mult: number = 1): number {
          return mult * 2;
        }
        """.write(to: dimsFile, atomically: true, encoding: .utf8)

        let subDir = dir.appendingPathComponent("features", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let bossFile = subDir.appendingPathComponent("boss.part.js")
        try """
        import { Cylinder } from 'made';
        import scaleFactor, { DEFAULT_SPEC } from '../dimensions';

        export function makeBoss() {
          return Cylinder(DEFAULT_SPEC.width / (4 * scaleFactor(1)), DEFAULT_SPEC.height * 2);
        }
        """.write(to: bossFile, atomically: true, encoding: .utf8)

        let mainFile = dir.appendingPathComponent("assembly.part.ts")
        try """
        import { Box, subtract, type Shape } from 'made';
        import { DEFAULT_SPEC, type MountSpec } from './dimensions';
        import { makeBoss } from './features/boss';

        const spec: MountSpec = DEFAULT_SPEC;
        const body: Shape = Box(spec.width, spec.width, spec.height);
        export default subtract(body, makeBoss());
        """.write(to: mainFile, atomically: true, encoding: .utf8)

        let runtime = PartRuntime(kernelClient: makeKernel())
        let res = await runtime.evaluatePartFile(at: mainFile)
        let output = try #require(res.value, "Module import failed: \(String(describing: res.error))")
        #expect(output.payload.triangleCount > 0)
    }

    // MARK: - Sandbox: Network, File System, Timers, Process, and Escaping Imports Blocked

    @Test func testForbiddenGlobalsAndAPIsFailClearly() async throws {
        let runtime = PartRuntime(kernelClient: makeKernel())

        let forbiddenSnippets: [(name: String, code: String)] = [
            ("fetch", "import { Box } from 'made'; fetch('https://example.com'); export default Box(10);"),
            ("setTimeout", "import { Box } from 'made'; setTimeout(() => {}, 10); export default Box(10);"),
            ("XMLHttpRequest", "import { Box } from 'made'; new XMLHttpRequest(); export default Box(10);"),
            ("process", "import { Box } from 'made'; process.exit(1); export default Box(10);"),
            ("fs", "import { Box } from 'made'; fs.readFileSync('/etc/passwd'); export default Box(10);")
        ]

        for snippet in forbiddenSnippets {
            let res = await runtime.evaluateScript(source: snippet.code, filePath: "\(snippet.name).part.ts")
            let err = try #require(res.error, "Expected \(snippet.name) to fail in sandbox")
            #expect(err.code == .scriptError)
            #expect(err.diagnostic.message.contains(snippet.name))
        }
    }

    @Test func testImportsOutsidePartDirectoryAndExternalModulesAreRejected() async throws {
        let outerDir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: outerDir) }

        let partDir = outerDir.appendingPathComponent("part", isDirectory: true)
        try FileManager.default.createDirectory(at: partDir, withIntermediateDirectories: true)

        let secretFile = outerDir.appendingPathComponent("secret.ts")
        try "export const x = 10;\n".write(to: secretFile, atomically: true, encoding: .utf8)

        // 1. Parent traversal `../secret`
        let traversalPart = partDir.appendingPathComponent("traversal.part.ts")
        try """
        import { Box } from 'made';
        import { x } from '../secret';
        export default Box(x);
        """.write(to: traversalPart, atomically: true, encoding: .utf8)

        let runtime = PartRuntime(kernelClient: makeKernel())
        let traversalRes = await runtime.evaluatePartFile(at: traversalPart)
        let traversalErr = try #require(traversalRes.error)
        #expect(traversalErr.code == .accessDenied)
        #expect(traversalErr.diagnostic.file == traversalPart.standardizedFileURL.resolvingSymlinksInPath().path)
        #expect(traversalErr.diagnostic.line == 2)
        #expect(traversalErr.diagnostic.message.contains("outside"))

        // 2. Symlink inside partDir pointing to ../secret.ts
        let symlinkURL = partDir.appendingPathComponent("linked.ts")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: secretFile)
        let symlinkPart = partDir.appendingPathComponent("symlink.part.ts")
        try """
        import { Box } from 'made';
        import { x } from './linked';
        export default Box(x);
        """.write(to: symlinkPart, atomically: true, encoding: .utf8)

        let symlinkRes = await runtime.evaluatePartFile(at: symlinkPart)
        let symlinkErr = try #require(symlinkRes.error)
        #expect(symlinkErr.code == .accessDenied)
        #expect(symlinkErr.diagnostic.line == 2)

        // 3. Bare / built-in module import `'fs'`
        let barePart = partDir.appendingPathComponent("bare.part.ts")
        try """
        import * as fs from 'fs';
        import { Box } from 'made';
        export default Box(10);
        """.write(to: barePart, atomically: true, encoding: .utf8)

        let bareRes = await runtime.evaluatePartFile(at: barePart)
        let bareErr = try #require(bareRes.error)
        #expect(bareErr.code == .accessDenied)
        #expect(bareErr.diagnostic.line == 1)
        #expect(bareErr.diagnostic.message.contains("'fs'"))
    }

    // MARK: - Deterministic `Math.random` and `Date`

    @Test func testMathRandomAndDateAreDeterministicAcrossEvaluations() async throws {
        let source = """
        import { Box, translate, type Shape } from 'made';

        const r1: number = Math.random();
        const r2: number = Math.random();
        const nowMs: number = Date.now();
        const isoYear: number = new Date().getUTCFullYear();

        const width = 10 + r1 * 20;
        const depth = 10 + r2 * 20;
        const height = (nowMs === 1704067200000 && isoYear === 2024) ? 15 : 1;

        const shape: Shape = translate(Box(width, depth, height), [r1 * 5, r2 * 5, 0]);
        export default shape;
        """

        let runtime = PartRuntime(kernelClient: makeKernel())
        let eval1 = try #require(await runtime.evaluatePart(source: source, filePath: "det.part.ts").value)
        let eval2 = try #require(await runtime.evaluatePart(source: source, filePath: "det.part.ts").value)

        #expect(eval1.shape == eval2.shape)
        #expect(Array(eval1.payload.positions) == Array(eval2.payload.positions))
        #expect(Array(eval1.payload.indices) == Array(eval2.payload.indices))

        // Verify height was 15 (confirming Date.now() === 1704067200000 and UTC year === 2024)
        if case .translate(.box(let boxParams), _) = eval1.shape {
            #expect(boxParams.height == 15)
            #expect(boxParams.width > 10 && boxParams.width < 30)
        } else {
            Issue.record("Expected translated box shape, got \(eval1.shape)")
        }
    }

    // MARK: - Error Reporting (Syntax Error, Runtime Error, Imported File Error, Runaway Loop)

    @Test func testSyntaxErrorMapsToSourceFileLineAndColumn() async throws {
        let source = """
        import { Box, type Shape } from 'made';

        const valid: number = 10;
        const broken: Shape = Box(valid, ));
        export default broken;
        """
        let runtime = PartRuntime(kernelClient: makeKernel())
        let res = await runtime.evaluateScript(source: source, filePath: "/parts/syntax_err.part.ts")
        let err = try #require(res.error)

        #expect(err.code == .syntaxError)
        #expect(err.diagnostic.file == "/parts/syntax_err.part.ts")
        #expect(err.diagnostic.line == 4)
        #expect(err.diagnostic.column == 34)
    }

    @Test func testRuntimeErrorMapsToExactTypeScriptLineAndColumn() async throws {
        let source = """
        import { Box, type Shape } from 'made';

        function makePart(size: number): Shape {
          if (size <= 0) {
            throw new RangeError('size must be positive');
          }
          return Box(size);
        }

        export default makePart(-5);
        """
        let runtime = PartRuntime(kernelClient: makeKernel())
        let res = await runtime.evaluateScript(source: source, filePath: "/parts/runtime_err.part.ts")
        let err = try #require(res.error)

        #expect(err.code == .scriptError)
        #expect(err.diagnostic.file == "/parts/runtime_err.part.ts")
        #expect(err.diagnostic.line == 5)
        #expect(err.diagnostic.column >= 5)
        #expect(err.diagnostic.message.contains("size must be positive"))
    }

    @Test func testErrorInsideImportedHelperMapsToHelperFileLineAndColumn() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let helperURL = dir.appendingPathComponent("helper.ts")
        try """
        import { Box, type Shape } from 'made';

        export function brokenHelper(w: number): Shape {
          const bad: any = undefined;
          return Box(bad.nonExistentProperty, w, w);
        }
        """.write(to: helperURL, atomically: true, encoding: .utf8)

        let rootURL = dir.appendingPathComponent("main.part.ts")
        try """
        import { brokenHelper } from './helper';
        export default brokenHelper(10);
        """.write(to: rootURL, atomically: true, encoding: .utf8)

        let runtime = PartRuntime(kernelClient: makeKernel())
        let res = await runtime.evaluatePartFile(at: rootURL)
        let err = try #require(res.error)

        let canonicalHelperPath = helperURL.standardizedFileURL.resolvingSymlinksInPath().path
        #expect(err.code == .scriptError)
        #expect(err.diagnostic.file == canonicalHelperPath)
        #expect(err.diagnostic.line == 5)
        #expect(err.diagnostic.column > 1)
    }

    @Test func testRunawayLoopFailsWithoutHanging() async throws {
        let source = """
        import { Box } from 'made';

        let count: number = 0;
        while (true) {
          count += 1;
        }

        export default Box(10);
        """
        let runtime = PartRuntime(kernelClient: makeKernel(), maxLoopTicks: 5_000)
        let res = await runtime.evaluateScript(source: source, filePath: "infinite.part.ts")
        let err = try #require(res.error)

        #expect(err.code == .executionLimitExceeded)
        #expect(err.diagnostic.file == "infinite.part.ts")
        #expect(err.diagnostic.message.contains("Execution limit exceeded"))
    }

    // MARK: - Main-Thread Isolation & Single-Request Kernel Evaluation (Invariants 1 & 4)

    @MainActor @Test func testPartRuntimeNeverRunsJSCOrKernelOnMainThread() async throws {
        #expect(pthread_main_np() != 0)
        let kernelRequests = Mutex<[KernelRequest]>([])
        let kernelOnMain = Mutex<Bool?>(nil)

        let kernel = makeKernel(HookedEngine { req in
            kernelRequests.withLock { $0.append(req) }
            kernelOnMain.withLock { $0 = (pthread_main_np() != 0) }
            return true
        })

        let runtime = PartRuntime(kernelClient: kernel)
        let source = """
        import { Box, Cylinder, subtract } from 'made';
        export default subtract(Box(20, 20, 10), Cylinder(4, 20));
        """

        let res = await runtime.evaluatePart(
            source: source,
            filePath: "main_actor_check.part.ts",
            jobId: JobId("m1"),
            solidId: SolidId("s1")
        )
        let output = try #require(res.value)

        // JSC evaluation happened off the main thread
        #expect(output.evaluatedOnMainThread == false)
        // Kernel evaluation happened off the main thread in a single .evaluateShape request
        #expect(kernelOnMain.withLock { $0 } == false)
        let seen = kernelRequests.withLock { $0 }
        #expect(seen.count == 1)
        if case .evaluateShape(let jId, let sId, _)? = seen.first {
            #expect(jId == JobId("m1"))
            #expect(sId == SolidId("s1"))
        } else {
            Issue.record("Expected single evaluateShape request, got \(seen)")
        }
    }

    // MARK: - Superseded Evaluations Discarded by `JobId` (Invariant 7)

    @Test func testSupersededEvaluationsAreDiscardedByJobId() async throws {
        let gate = AsyncGate()
        let kernel = KernelClient(
            engine: HookedEngine { req in
                if req.jobId == JobId("job-1") {
                    await gate.wait()
                }
                return true
            },
            debounceDuration: .milliseconds(1)
        )

        let runtime = PartRuntime(kernelClient: kernel)
        let solidId = SolidId("part-solid")

        let script1 = "import { Box } from 'made'; export default Box(10, 10, 10);"
        let script2 = "import { Box } from 'made'; export default Box(30, 30, 30);"

        let task1 = Task {
            await runtime.evaluatePart(
                source: script1,
                filePath: "part.part.ts",
                jobId: JobId("job-1"),
                solidId: solidId
            )
        }

        // Wait until job-1 has registered and entered the gate, then launch job-2 for the same solidId
        try await Task.sleep(for: .milliseconds(30))

        let task2 = Task {
            await runtime.evaluatePart(
                source: script2,
                filePath: "part.part.ts",
                jobId: JobId("job-2"),
                solidId: solidId
            )
        }

        try await Task.sleep(for: .milliseconds(30))
        await gate.open()

        let (res1, res2) = await (task1.value, task2.value)

        #expect(res1.jobId == JobId("job-1"))
        #expect(res1.error?.code == .cancelled)
        #expect(runtime.isJobCurrent(jobId: JobId("job-1"), solidId: solidId) == false)

        #expect(res2.jobId == JobId("job-2"))
        #expect(res2.isSuccess)
        #expect(runtime.isJobCurrent(jobId: JobId("job-2"), solidId: solidId) == true)
        #expect(res2.value?.shape == .box(BoxParams(width: 30, depth: 30, height: 30)))
    }

    // MARK: - Bundled `made.d.ts` Type Definitions

    @Test func testBundledTypeDefinitionsExistAndValidateWithTypeScriptCompiler() async throws {
        let dtsURL = try #require(PartRuntime.bundledTypeDefinitionsURL())
        let dtsContents = try PartRuntime.bundledTypeDefinitions()

        #expect(dtsContents.contains("declare module 'made'"))
        #expect(dtsContents.contains("export function Box"))
        #expect(dtsContents.contains("export function Sketch"))
        #expect(dtsContents.contains("export function extrude"))
        #expect(dtsContents.contains("export function revolve"))
        #expect(dtsContents.contains("export function param"))
        #expect(dtsContents.contains("export interface ExpectedSpec"))

        // If a local `tsc` binary is available, verify `tsc --noEmit` passes on a sample `.part.ts` file against `made.d.ts`.
        let candidateTscPaths = [
            "/Users/travisgalloway/.npm/_npx/a5fa6ff2e59295e5/node_modules/.bin/tsc",
            "/usr/local/bin/tsc",
            "/opt/homebrew/bin/tsc"
        ]
        guard let tscPath = candidateTscPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return
        }

        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let copiedDts = dir.appendingPathComponent("made.d.ts")
        try FileManager.default.copyItem(at: dtsURL, to: copiedDts)

        let samplePart = dir.appendingPathComponent("sample.part.ts")
        try """
        /// <reference path="./made.d.ts" />
        import {
          Box, Cylinder, Sphere, Cone,
          Plane, Sketch, extrude, revolve,
          union, subtract, intersect,
          translate, rotate, scale,
          param, defineParams,
          type Shape, type ExpectedSpec
        } from 'made';

        const w = param('w', 20, { min: 5, max: 50, unit: 'mm' });
        const p = defineParams({ h: 10, r: { default: 3, min: 1, max: 8 } });
        const sk = Sketch(Plane.XY.offset(2)).roundedRectangle(w, w, 2);
        const base: Shape = extrude(sk, p.h);
        const ring: Shape = revolve(Sketch(Plane.XZ).rectangle(2, 4, { center: [6, 2] }), 360);
        const combined: Shape = union(base, ring, Sphere(p.r), Cone(p.r, p.h)).subtract(Cylinder(p.r, p.h * 2));
        export const expected: ExpectedSpec = {
          volume: 1000,
          area: 600,
          bounds: { min: [-10, -10, 0], max: [10, 10, 12] },
          tolerance: 0.01
        };
        export default scale(rotate(translate(combined, [1, 2, 3]), 45, [0, 0, 1]), 1);
        """.write(to: samplePart, atomically: true, encoding: .utf8)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tscPath)
        proc.arguments = [
            "--noEmit",
            "--strict",
            "--target", "ES2022",
            "--module", "ES2022",
            copiedDts.path,
            samplePart.path
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()

        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        #expect(proc.terminationStatus == 0, "tsc --noEmit failed:\n\(output)")
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func open() {
        isOpen = true
        let current = waiters
        waiters.removeAll()
        for w in current {
            w.resume()
        }
    }
}
