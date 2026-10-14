import Foundation
import JavaScriptCore
import simd

/// Evaluates `.part.ts` and `.part.js` part files inside a restricted JavaScriptCore sandbox
/// on a dedicated background thread, validates the resulting `ShapeNode` tree, and dispatches
/// geometry evaluation through `KernelClientProtocol` (ADR-D6, #435).
public final class PartRuntime: @unchecked Sendable {
    public static let defaultMaxLoopTicks: Int = 200_000
    public static let defaultRandomSeed: UInt32 = 0x6D616465
    public static let defaultFixedTimeMs: Double = 1_704_067_200_000 // 2024-01-01T00:00:00.000Z

    private let kernelClient: (any KernelClientProtocol)?
    private let maxLoopTicks: Int
    private let worker: JSCWorkerThread
    private let stateLock = NSLock()
    private var latestJobBySolid: [SolidId: JobId] = [:]
    private var cancelledJobs: Set<JobId> = []

    public init(
        kernelClient: (any KernelClientProtocol)? = nil,
        maxLoopTicks: Int = PartRuntime.defaultMaxLoopTicks
    ) {
        self.kernelClient = kernelClient
        self.maxLoopTicks = max(1, maxLoopTicks)
        self.worker = JSCWorkerThread.shared
    }

    /// URL of the bundled `made.d.ts` TypeScript declarations inside `MadeCore`'s resource bundle or app bundle.
    public static func bundledTypeDefinitionsURL() -> URL? {
        if let url = Bundle.module.resourceURL?
            .appendingPathComponent("ScriptingResources", isDirectory: true)
            .appendingPathComponent("made.d.ts", isDirectory: false),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = Bundle.module.url(forResource: "made.d", withExtension: "ts") {
            return url
        }
        if let url = Bundle.main.url(forResource: "made.d", withExtension: "ts") {
            return url
        }
        return nil
    }

    /// Contents of the bundled `made.d.ts` TypeScript declarations.
    public static func bundledTypeDefinitions() throws -> String {
        guard let url = bundledTypeDefinitionsURL() else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Marks `jobId` as cancelled. Any running loop or pending kernel request for `jobId` will abort.
    public func cancel(jobId: JobId) async {
        markCancelled(jobId: jobId)
        if let kernelClient {
            await kernelClient.cancel(jobId: jobId)
        }
    }

    private func markCancelled(jobId: JobId) {
        stateLock.withLock {
            _ = cancelledJobs.insert(jobId)
        }
    }

    /// Returns true if `jobId` is still the active, non-cancelled evaluation for `solidId`.
    public func isJobCurrent(jobId: JobId, solidId: SolidId) -> Bool {
        stateLock.withLock {
            if cancelledJobs.contains(jobId) {
                return false
            }
            guard let latest = latestJobBySolid[solidId] else {
                return true
            }
            return latest == jobId
        }
    }

    private func registerJob(jobId: JobId, solidId: SolidId) -> JobId? {
        stateLock.withLock {
            let previous = latestJobBySolid[solidId]
            latestJobBySolid[solidId] = jobId
            if let previous, previous != jobId {
                cancelledJobs.insert(previous)
                return previous
            }
            return nil
        }
    }

    /// Evaluates a `.part.ts` or `.part.js` file on disk into a validated `PartScriptEvaluation` (`ShapeNode` tree, `expected` block, and parameter specs).
    public func evaluateScriptFile(
        at fileURL: URL,
        jobId: JobId = JobId(UUID().uuidString),
        solidId: SolidId = SolidId("part"),
        parameterOverrides: [String: Double] = [:]
    ) async -> PartRuntimeResult<PartScriptEvaluation> {
        let canonicalFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let directoryURL = canonicalFile.deletingLastPathComponent()
        let source: String
        do {
            source = try String(contentsOf: canonicalFile, encoding: .utf8)
        } catch {
            let err = PartRuntimeError(
                code: .moduleNotFound,
                diagnostic: PartDiagnostic(
                    file: canonicalFile.path,
                    line: 1,
                    column: 1,
                    message: "Cannot read part file '\(canonicalFile.lastPathComponent)': \(error.localizedDescription)"
                )
            )
            return .failure(jobId: jobId, error: err)
        }
        return await evaluateScript(
            source: source,
            filePath: canonicalFile.path,
            rootDirectoryURL: directoryURL,
            jobId: jobId,
            solidId: solidId,
            parameterOverrides: parameterOverrides
        )
    }

    /// Evaluates inline TypeScript or JavaScript source into a validated `PartScriptEvaluation`.
    public func evaluateScript(
        source: String,
        filePath: String = "inline.part.ts",
        rootDirectoryURL: URL? = nil,
        jobId: JobId = JobId(UUID().uuidString),
        solidId: SolidId = SolidId("part"),
        parameterOverrides: [String: Double] = [:]
    ) async -> PartRuntimeResult<PartScriptEvaluation> {
        let superseded = registerJob(jobId: jobId, solidId: solidId)
        if let superseded, let kernelClient {
            await kernelClient.cancel(jobId: superseded)
        }

        if !isJobCurrent(jobId: jobId, solidId: solidId) {
            return .failure(
                jobId: jobId,
                error: cancelledError(filePath: filePath)
            )
        }

        let maxTicks = self.maxLoopTicks
        let scriptResult: Result<PartScriptEvaluation, PartRuntimeError> = await worker.perform { [self] vm, transformFn in
            guard self.isJobCurrent(jobId: jobId, solidId: solidId) else {
                return .failure(self.cancelledError(filePath: filePath))
            }
            let evaluator = JSCPartEvaluator(
                vm: vm,
                transformFn: transformFn,
                maxLoopTicks: maxTicks,
                isCancelled: {
                    !self.isJobCurrent(jobId: jobId, solidId: solidId)
                }
            )
            return evaluator.evaluate(
                source: source,
                filePath: filePath,
                rootDirectoryURL: rootDirectoryURL,
                jobId: jobId,
                solidId: solidId,
                parameterOverrides: parameterOverrides
            )
        }

        guard isJobCurrent(jobId: jobId, solidId: solidId) else {
            return .failure(jobId: jobId, error: cancelledError(filePath: filePath))
        }

        switch scriptResult {
        case .success(let evaluation):
            return .success(jobId: jobId, value: evaluation)
        case .failure(let error):
            return .failure(jobId: jobId, error: error)
        }
    }

    /// Evaluates a `.part.ts` or `.part.js` file on disk through JavaScriptCore and `KernelClientProtocol` to produce a `MeshPayload`.
    public func evaluatePartFile(
        at fileURL: URL,
        jobId: JobId = JobId(UUID().uuidString),
        solidId: SolidId = SolidId("part"),
        parameterOverrides: [String: Double] = [:],
        kernelClient: (any KernelClientProtocol)? = nil
    ) async -> PartRuntimeResult<PartEvaluationOutput> {
        let canonicalFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let directoryURL = canonicalFile.deletingLastPathComponent()
        let source: String
        do {
            source = try String(contentsOf: canonicalFile, encoding: .utf8)
        } catch {
            let err = PartRuntimeError(
                code: .moduleNotFound,
                diagnostic: PartDiagnostic(
                    file: canonicalFile.path,
                    line: 1,
                    column: 1,
                    message: "Cannot read part file '\(canonicalFile.lastPathComponent)': \(error.localizedDescription)"
                )
            )
            return .failure(jobId: jobId, error: err)
        }
        return await evaluatePart(
            source: source,
            filePath: canonicalFile.path,
            rootDirectoryURL: directoryURL,
            jobId: jobId,
            solidId: solidId,
            parameterOverrides: parameterOverrides,
            kernelClient: kernelClient
        )
    }

    /// Evaluates TypeScript or JavaScript source through JavaScriptCore and `KernelClientProtocol` to produce a `MeshPayload`.
    public func evaluatePart(
        source: String,
        filePath: String = "inline.part.ts",
        rootDirectoryURL: URL? = nil,
        jobId: JobId = JobId(UUID().uuidString),
        solidId: SolidId = SolidId("part"),
        parameterOverrides: [String: Double] = [:],
        kernelClient overrideClient: (any KernelClientProtocol)? = nil
    ) async -> PartRuntimeResult<PartEvaluationOutput> {
        let scriptRes = await evaluateScript(
            source: source,
            filePath: filePath,
            rootDirectoryURL: rootDirectoryURL,
            jobId: jobId,
            solidId: solidId,
            parameterOverrides: parameterOverrides
        )

        let scriptEval: PartScriptEvaluation
        switch scriptRes {
        case .success(_, let val):
            scriptEval = val
        case .failure(_, let err):
            return .failure(jobId: jobId, error: err)
        }

        guard isJobCurrent(jobId: jobId, solidId: solidId) else {
            return .failure(jobId: jobId, error: cancelledError(filePath: filePath))
        }

        guard let client = overrideClient ?? self.kernelClient else {
            let err = PartRuntimeError(
                code: .kernelFailed,
                diagnostic: PartDiagnostic(
                    file: filePath,
                    line: 1,
                    column: 1,
                    message: "No KernelClientProtocol configured on PartRuntime"
                )
            )
            return .failure(jobId: jobId, error: err)
        }

        let kernelRes = await client.request(
            .evaluateShape(jobId: jobId, solidId: solidId, shape: scriptEval.shape)
        )

        guard isJobCurrent(jobId: jobId, solidId: solidId) else {
            return .failure(jobId: jobId, error: cancelledError(filePath: filePath))
        }

        switch kernelRes {
        case .success(_, let payload):
            let output = PartEvaluationOutput(
                jobId: jobId,
                solidId: solidId,
                shape: scriptEval.shape,
                payload: payload,
                expected: scriptEval.expected,
                parameters: scriptEval.parameters,
                warnings: scriptEval.warnings,
                evaluatedOnMainThread: scriptEval.evaluatedOnMainThread,
                loadedFiles: scriptEval.loadedFiles
            )
            return .success(jobId: jobId, value: output)
        case .failure(_, let kErr):
            let code: PartRuntimeErrorCode = (kErr.code == .cancelled) ? .cancelled : .kernelFailed
            let err = PartRuntimeError(
                code: code,
                diagnostic: PartDiagnostic(
                    file: filePath,
                    line: 1,
                    column: 1,
                    message: kErr.message
                ),
                kernelError: kErr,
                loadedFiles: scriptEval.loadedFiles
            )
            return .failure(jobId: jobId, error: err)
        }
    }

    private func cancelledError(filePath: String) -> PartRuntimeError {
        PartRuntimeError(
            code: .cancelled,
            diagnostic: PartDiagnostic(
                file: filePath,
                line: 1,
                column: 1,
                message: "Evaluation superseded or cancelled"
            )
        )
    }
}

// MARK: - Dedicated Background JSC Worker Thread

/// Runs all `JSVirtualMachine` and `JSContext` operations on a single non-main OS thread (`pthread_main_np() == 0`).
private final class JSCWorkerThread: @unchecked Sendable {
    static let shared = JSCWorkerThread()
    private static let stripperSource: String? = loadBundledScript(named: "ts-stripper.js")

    private let cond = NSCondition()
    private var queue: [() -> Void] = []
    private var vm: JSVirtualMachine!
    private var transformContext: JSContext!
    private var transformFn: JSValue!

    init() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let machine = JSVirtualMachine()!
                let ctx = JSContext(virtualMachine: machine)!
                ctx.name = "made.ts-stripper"
                if let stripperSource = Self.stripperSource {
                    ctx.evaluateScript(stripperSource, withSourceURL: URL(string: "made://internal/ts-stripper.js"))
                }
                let fn = ctx.objectForKeyedSubscript("__made_transformSource")!
                self.vm = machine
                self.transformContext = ctx
                self.transformFn = fn
            }
            self.runLoop()
        }
        thread.name = "made.part-runtime.jsc"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func perform<T: Sendable>(_ work: @escaping @Sendable (JSVirtualMachine, JSValue) -> T) async -> T {
        await withCheckedContinuation { continuation in
            cond.lock()
            queue.append { [unowned self] in
                autoreleasepool {
                    let result = work(self.vm, self.transformFn)
                    continuation.resume(returning: result)
                }
            }
            cond.signal()
            cond.unlock()
        }
    }

    private func runLoop() {
        while true {
            cond.lock()
            while queue.isEmpty {
                cond.wait()
            }
            let item = queue.removeFirst()
            cond.unlock()
            item()
        }
    }

    static func loadBundledScript(named filename: String) -> String? {
        if let dir = Bundle.module.resourceURL?.appendingPathComponent("ScriptingResources", isDirectory: true) {
            let url = dir.appendingPathComponent(filename, isDirectory: false)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        if let url = Bundle.module.url(forResource: base, withExtension: ext),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return nil
    }
}

// MARK: - Per-Evaluation JSC Execution & Source Mapping

private struct SourceEditRecord {
    let line: Int
    let origCol: Int
    let delta: Int
}

private struct TransformedModuleRecord {
    let filePath: String
    let originalLines: [String]
    let transformedCode: String
    let editsByLine: [Int: [SourceEditRecord]]
}

private final class JSCPartEvaluator {
    private static let runtimeBootstrapSource: String = {
        JSCWorkerThread.loadBundledScript(named: "made-runtime.js") ?? ""
    }()

    private let vm: JSVirtualMachine
    private let transformFn: JSValue
    private let maxLoopTicks: Int
    private let isCancelled: () -> Bool

    private var modulesByPath: [String: TransformedModuleRecord] = [:]
    private var moduleExportsByPath: [String: JSValue] = [:]
    private var loadingStack: [String] = []
    private var activeError: PartRuntimeError?
    private var warnings: [PartDiagnostic] = []
    private var tickCount: Int = 0

    init(
        vm: JSVirtualMachine,
        transformFn: JSValue,
        maxLoopTicks: Int,
        isCancelled: @escaping () -> Bool
    ) {
        self.vm = vm
        self.transformFn = transformFn
        self.maxLoopTicks = maxLoopTicks
        self.isCancelled = isCancelled
    }

    func evaluate(
        source: String,
        filePath: String,
        rootDirectoryURL: URL?,
        jobId: JobId,
        solidId: SolidId,
        parameterOverrides: [String: Double]
    ) -> Result<PartScriptEvaluation, PartRuntimeError> {
        let onMainThread = (pthread_main_np() != 0)
        let canonicalRootDir: String? = rootDirectoryURL.map {
            let path = $0.standardizedFileURL.resolvingSymlinksInPath().path
            return path.hasSuffix("/") ? path : path + "/"
        }

        guard let context = JSContext(virtualMachine: vm) else {
            return .failure(
                PartRuntimeError(
                    code: .scriptError,
                    diagnostic: PartDiagnostic(file: filePath, line: 1, column: 1, message: "Failed to create JSContext")
                )
            )
        }
        context.name = "made.part-eval.\(jobId.rawValue)"

        // Load sandbox & 'made' module runtime
        context.evaluateScript(Self.runtimeBootstrapSource, withSourceURL: URL(string: "made://internal/made-runtime.js"))
        if let bootExc = context.exception {
            let msg = bootExc.toString() ?? "Runtime bootstrap failed"
            return .failure(
                PartRuntimeError(
                    code: .scriptError,
                    diagnostic: PartDiagnostic(file: filePath, line: 1, column: 1, message: msg)
                )
            )
        }

        // Configure per-evaluation parameter overrides and deterministic seed/Date
        if let beginFn = context.objectForKeyedSubscript("__made_beginEvaluation") {
            _ = beginFn.call(withArguments: [
                parameterOverrides,
                PartRuntime.defaultRandomSeed,
                PartRuntime.defaultFixedTimeMs
            ])
        }

        // Install loop tick guard (__made_tick)
        let tickBlock: @convention(block) () -> Void = { [weak self, weak context] in
            guard let self, let context else { return }
            if self.isCancelled() {
                let currentFile = self.loadingStack.last ?? filePath
                self.recordFirstError(
                    PartRuntimeError(
                        code: .cancelled,
                        diagnostic: PartDiagnostic(
                            file: currentFile,
                            line: 1,
                            column: 1,
                            message: "Evaluation superseded or cancelled"
                        )
                    )
                )
                context.exception = JSValue(newErrorFromMessage: "Evaluation cancelled", in: context)
                return
            }
            self.tickCount += 1
            if self.tickCount > self.maxLoopTicks {
                let currentFile = self.loadingStack.last ?? filePath
                self.recordFirstError(
                    PartRuntimeError(
                        code: .executionLimitExceeded,
                        diagnostic: PartDiagnostic(
                            file: currentFile,
                            line: 1,
                            column: 1,
                            message: "Execution limit exceeded (\(self.maxLoopTicks) loop iterations)"
                        )
                    )
                )
                context.exception = JSValue(
                    newErrorFromMessage: "Execution limit exceeded (\(self.maxLoopTicks) loop iterations)",
                    in: context
                )
            }
        }
        context.setObject(tickBlock, forKeyedSubscript: "__made_tick" as NSString)

        // Install console.warn / console.error collector (__made_warn)
        let warnBlock: @convention(block) (String, String) -> Void = { [weak self] message, stack in
            guard let self else { return }
            let fallbackFile = self.loadingStack.last ?? filePath
            if let frame = self.parseTopUserFrame(from: stack) {
                let record = self.modulesByPath[frame.filePath]
                let totalLines = max(1, record?.originalLines.count ?? 1)
                let origLine = min(totalLines, max(1, frame.jscLine - 1))
                let origCol = self.mapColumnToOriginal(
                    jscColumn: frame.jscColumn,
                    origLine: origLine,
                    moduleRecord: record
                )
                self.warnings.append(
                    PartDiagnostic(
                        file: frame.filePath,
                        line: origLine,
                        column: origCol,
                        message: message
                    )
                )
            } else {
                self.warnings.append(
                    PartDiagnostic(
                        file: fallbackFile,
                        line: 1,
                        column: 1,
                        message: message
                    )
                )
            }
        }
        context.setObject(warnBlock, forKeyedSubscript: "__made_warn" as NSString)

        // Execute root module
        let rootExportsResult = executeModule(
            source: source,
            filePath: filePath,
            currentDirectoryURL: rootDirectoryURL,
            canonicalRootDirWithSlash: canonicalRootDir,
            in: context
        )

        let rootExports: JSValue
        switch rootExportsResult {
        case .success(let exportsVal):
            rootExports = exportsVal
        case .failure(let err):
            return .failure(err.withLoadedFiles(currentLoadedFiles(defaultFilePath: filePath)))
        }

        if isCancelled() {
            return .failure(
                PartRuntimeError(
                    code: .cancelled,
                    diagnostic: PartDiagnostic(file: filePath, line: 1, column: 1, message: "Evaluation superseded or cancelled"),
                    loadedFiles: currentLoadedFiles(defaultFilePath: filePath)
                )
            )
        }

        // Extract exported Shape (supports export default shape, export default (params) => shape, export function main/build/part, or export const shape/part/model)
        let shapeValueResult = resolveExportedShape(from: rootExports, filePath: filePath, in: context)
        let shapeJSValue: JSValue
        switch shapeValueResult {
        case .success(let v):
            shapeJSValue = v
        case .failure(let err):
            return .failure(err.withLoadedFiles(currentLoadedFiles(defaultFilePath: filePath)))
        }

        // Decode ShapeNode from shapeJSValue.node
        guard let nodeJSValue = shapeJSValue.forProperty("node"), !nodeJSValue.isUndefined, !nodeJSValue.isNull else {
            return .failure(
                PartRuntimeError(
                    code: .invalidExport,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: 1,
                        column: 1,
                        message: "Part script must export a Shape created with the 'made' module"
                    ),
                    loadedFiles: currentLoadedFiles(defaultFilePath: filePath)
                )
            )
        }

        let shapeNode: ShapeNode
        do {
            shapeNode = try decodeShapeNode(from: nodeJSValue)
        } catch let err as PartRuntimeError {
            return .failure(err.withLoadedFiles(currentLoadedFiles(defaultFilePath: filePath)))
        } catch {
            return .failure(
                PartRuntimeError(
                    code: .invalidExport,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: 1,
                        column: 1,
                        message: "Invalid shape tree exported by part script: \(error.localizedDescription)"
                    ),
                    loadedFiles: currentLoadedFiles(defaultFilePath: filePath)
                )
            )
        }

        // Validate ShapeNode before sending to KernelClient (invariant 4)
        if let validationErr = shapeNode.validate() {
            return .failure(
                PartRuntimeError(
                    code: .validationFailed,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: 1,
                        column: 1,
                        message: validationErr.message
                    ),
                    kernelError: validationErr,
                    loadedFiles: currentLoadedFiles(defaultFilePath: filePath)
                )
            )
        }

        // Parse optional `export const expected = { volume, area, bounds, tolerance }`
        let expectedBlock: PartExpected?
        do {
            expectedBlock = try decodeExpected(from: rootExports, filePath: filePath)
        } catch let err as PartRuntimeError {
            return .failure(err.withLoadedFiles(currentLoadedFiles(defaultFilePath: filePath)))
        } catch {
            return .failure(
                PartRuntimeError(
                    code: .invalidExport,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: 1,
                        column: 1,
                        message: "Invalid 'expected' export: \(error.localizedDescription)"
                    ),
                    loadedFiles: currentLoadedFiles(defaultFilePath: filePath)
                )
            )
        }

        // Extract recorded parameters
        let parameters = decodeRecordedParameters(in: context)

        let evaluation = PartScriptEvaluation(
            jobId: jobId,
            solidId: solidId,
            shape: shapeNode,
            expected: expectedBlock,
            parameters: parameters,
            warnings: warnings,
            evaluatedOnMainThread: onMainThread,
            loadedFiles: currentLoadedFiles(defaultFilePath: filePath)
        )
        return .success(evaluation)
    }

    private func currentLoadedFiles(defaultFilePath: String) -> [String] {
        var files = Set(modulesByPath.keys)
        files.insert(defaultFilePath)
        return files.sorted()
    }

    // MARK: Module Loading & Execution

    private func executeModule(
        source: String,
        filePath: String,
        currentDirectoryURL: URL?,
        canonicalRootDirWithSlash: String?,
        in context: JSContext
    ) -> Result<JSValue, PartRuntimeError> {
        if let cached = moduleExportsByPath[filePath] {
            return .success(cached)
        }
        if loadingStack.contains(filePath) {
            return .failure(
                PartRuntimeError(
                    code: .scriptError,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: 1,
                        column: 1,
                        message: "Circular module import detected involving '\((filePath as NSString).lastPathComponent)'"
                    )
                )
            )
        }

        let transformedResult = transformModuleSource(source: source, filePath: filePath)
        let record: TransformedModuleRecord
        switch transformedResult {
        case .success(let rec):
            record = rec
        case .failure(let err):
            recordFirstError(err)
            return .failure(err)
        }

        modulesByPath[filePath] = record
        loadingStack.append(filePath)
        defer { _ = loadingStack.popLast() }

        let exportsObj = JSValue(newObjectIn: context)!
        let defaultHolderObj = JSValue(newObjectIn: context)!
        moduleExportsByPath[filePath] = exportsObj

        let requireBlock: @convention(block) (String, Int, Int) -> JSValue = { [weak self, weak context] specifier, reqLine, reqCol in
            guard let self, let context else {
                return JSValue(undefinedIn: nil)
            }
            let line = max(1, reqLine)
            let col = max(1, reqCol)

            if specifier == "made" {
                return context.objectForKeyedSubscript("__made_module") ?? JSValue(undefinedIn: context)
            }

            // Block bare, external, protocol, or absolute module imports
            if !specifier.hasPrefix("./") && !specifier.hasPrefix("../") {
                let err = PartRuntimeError(
                    code: .accessDenied,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: line,
                        column: col,
                        message: "External or built-in module '\(specifier)' is not permitted; only 'made' and relative files in the part directory may be imported"
                    )
                )
                self.recordFirstError(err)
                context.exception = JSValue(newErrorFromMessage: err.diagnostic.message, in: context)
                return JSValue(undefinedIn: context)
            }

            guard let currentDirectoryURL, let canonicalRootDirWithSlash else {
                let err = PartRuntimeError(
                    code: .accessDenied,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: line,
                        column: col,
                        message: "Relative module import '\(specifier)' is not available for inline scripts without a part directory"
                    )
                )
                self.recordFirstError(err)
                context.exception = JSValue(newErrorFromMessage: err.diagnostic.message, in: context)
                return JSValue(undefinedIn: context)
            }

            switch self.resolveRelativeImport(
                specifier: specifier,
                fromFile: filePath,
                line: line,
                column: col,
                baseDirectoryURL: currentDirectoryURL,
                canonicalRootDirWithSlash: canonicalRootDirWithSlash
            ) {
            case .failure(let err):
                self.recordFirstError(err)
                context.exception = JSValue(newErrorFromMessage: err.diagnostic.message, in: context)
                return JSValue(undefinedIn: context)
            case .success(let resolvedURL):
                let childSource: String
                do {
                    childSource = try String(contentsOf: resolvedURL, encoding: .utf8)
                } catch {
                    let err = PartRuntimeError(
                        code: .moduleNotFound,
                        diagnostic: PartDiagnostic(
                            file: filePath,
                            line: line,
                            column: col,
                            message: "Cannot read imported module '\(specifier)': \(error.localizedDescription)"
                        )
                    )
                    self.recordFirstError(err)
                    context.exception = JSValue(newErrorFromMessage: err.diagnostic.message, in: context)
                    return JSValue(undefinedIn: context)
                }

                switch self.executeModule(
                    source: childSource,
                    filePath: resolvedURL.path,
                    currentDirectoryURL: resolvedURL.deletingLastPathComponent(),
                    canonicalRootDirWithSlash: canonicalRootDirWithSlash,
                    in: context
                ) {
                case .success(let childExports):
                    return childExports
                case .failure(let childErr):
                    self.recordFirstError(childErr)
                    if context.exception == nil {
                        context.exception = JSValue(newErrorFromMessage: childErr.diagnostic.message, in: context)
                    }
                    return JSValue(undefinedIn: context)
                }
            }
        }

        // Line 1 is the wrapper header; Line 2 is Line 1 of the module code, preserving 1-based columns on every line.
        let wrappedScript = "(function(__made_exports, __made_require, __made_d){\n" + record.transformedCode + "\n})"
        let sourceURL = URL(fileURLWithPath: filePath)
        let fnValue = context.evaluateScript(wrappedScript, withSourceURL: sourceURL)

        if let exc = context.exception {
            context.exception = nil
            if let existing = activeError {
                return .failure(existing)
            }
            let mapped = mapJSCException(exc, defaultFilePath: filePath, defaultCode: .syntaxError)
            recordFirstError(mapped)
            return .failure(mapped)
        }

        guard let fnValue, fnValue.isObject else {
            let err = PartRuntimeError(
                code: .syntaxError,
                diagnostic: PartDiagnostic(file: filePath, line: 1, column: 1, message: "Failed to compile module '\((filePath as NSString).lastPathComponent)'")
            )
            recordFirstError(err)
            return .failure(err)
        }

        let requireJSValue = JSValue(object: requireBlock, in: context)!
        _ = fnValue.call(withArguments: [exportsObj, requireJSValue, defaultHolderObj])

        if let exc = context.exception {
            context.exception = nil
            if let existing = activeError {
                return .failure(existing)
            }
            let mapped = mapJSCException(exc, defaultFilePath: filePath, defaultCode: .scriptError)
            recordFirstError(mapped)
            return .failure(mapped)
        }

        if let existing = activeError {
            return .failure(existing)
        }

        return .success(exportsObj)
    }

    private func resolveRelativeImport(
        specifier: String,
        fromFile: String,
        line: Int,
        column: Int,
        baseDirectoryURL: URL,
        canonicalRootDirWithSlash: String
    ) -> Result<URL, PartRuntimeError> {
        let rawTargetURL = URL(fileURLWithPath: specifier, relativeTo: baseDirectoryURL).standardizedFileURL
        let rootWithoutTrailingSlash = String(canonicalRootDirWithSlash.dropLast())

        // First check lexical standardization before hitting the filesystem
        let rawPath = rawTargetURL.path
        if rawPath != rootWithoutTrailingSlash && !rawPath.hasPrefix(canonicalRootDirWithSlash) {
            return .failure(
                PartRuntimeError(
                    code: .accessDenied,
                    diagnostic: PartDiagnostic(
                        file: fromFile,
                        line: line,
                        column: column,
                        message: "Import '\(specifier)' resolves outside the part's directory"
                    )
                )
            )
        }

        let candidateExtensions = ["", ".part.ts", ".ts", ".part.js", ".js"]
        let fm = FileManager.default

        for suffix in candidateExtensions {
            let candidateURL = suffix.isEmpty
                ? rawTargetURL
                : URL(fileURLWithPath: rawTargetURL.path + suffix)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidateURL.path, isDirectory: &isDir), !isDir.boolValue {
                let resolvedURL = candidateURL.standardizedFileURL.resolvingSymlinksInPath()
                let resolvedPath = resolvedURL.path
                if !resolvedPath.hasPrefix(canonicalRootDirWithSlash) {
                    return .failure(
                        PartRuntimeError(
                            code: .accessDenied,
                            diagnostic: PartDiagnostic(
                                file: fromFile,
                                line: line,
                                column: column,
                                message: "Import '\(specifier)' points outside the part's directory via symlink"
                            )
                        )
                    )
                }
                return .success(resolvedURL)
            }
        }

        return .failure(
            PartRuntimeError(
                code: .moduleNotFound,
                diagnostic: PartDiagnostic(
                    file: fromFile,
                    line: line,
                    column: column,
                    message: "Module not found: '\(specifier)'"
                )
            )
        )
    }

    // MARK: TypeScript Type Stripping & Source Transformation

    private func transformModuleSource(
        source: String,
        filePath: String
    ) -> Result<TransformedModuleRecord, PartRuntimeError> {
        let lower = filePath.lowercased()
        let isTypeScript = lower.hasSuffix(".ts") || (!lower.hasSuffix(".js") && !lower.hasSuffix(".mjs"))
        let originalLines = source.components(separatedBy: "\n")

        let transformCtx = transformFn.context!
        transformCtx.exception = nil
        let resultVal = transformFn.call(withArguments: [source, isTypeScript])

        if let exc = transformCtx.exception {
            transformCtx.exception = nil
            let msg = exc.toString() ?? "SyntaxError"
            let line = (exc.forProperty("line")?.isNumber == true) ? Int(exc.forProperty("line").toInt32()) : 1
            let col = (exc.forProperty("column")?.isNumber == true) ? Int(exc.forProperty("column").toInt32()) : 1
            return .failure(
                PartRuntimeError(
                    code: .syntaxError,
                    diagnostic: PartDiagnostic(file: filePath, line: line, column: col, message: msg)
                )
            )
        }

        guard let resultVal,
              let codeVal = resultVal.forProperty("code"),
              let transformedCode = codeVal.toString() else {
            return .failure(
                PartRuntimeError(
                    code: .syntaxError,
                    diagnostic: PartDiagnostic(file: filePath, line: 1, column: 1, message: "Failed to strip TypeScript types")
                )
            )
        }

        var editsByLine: [Int: [SourceEditRecord]] = [:]
        if let editsVal = resultVal.forProperty("edits"), editsVal.isArray,
           let rawEdits = editsVal.toArray() as? [[String: Any]] {
            for item in rawEdits {
                if let line = item["line"] as? Int,
                   let origCol = item["origCol"] as? Int,
                   let delta = item["delta"] as? Int,
                   delta != 0 {
                    editsByLine[line, default: []].append(
                        SourceEditRecord(line: line, origCol: origCol, delta: delta)
                    )
                }
            }
        }

        return .success(
            TransformedModuleRecord(
                filePath: filePath,
                originalLines: originalLines,
                transformedCode: transformedCode,
                editsByLine: editsByLine
            )
        )
    }

    // MARK: Error Mapping to File, Line, and Column

    private func recordFirstError(_ error: PartRuntimeError) {
        if activeError == nil {
            activeError = error
        }
    }

    private func mapJSCException(
        _ exception: JSValue,
        defaultFilePath: String,
        defaultCode: PartRuntimeErrorCode
    ) -> PartRuntimeError {
        let rawMessage = exception.toString() ?? "Unknown JavaScript error"
        let isSyntax = rawMessage.hasPrefix("SyntaxError") || defaultCode == .syntaxError
        let errorCode: PartRuntimeErrorCode = isSyntax ? .syntaxError : defaultCode

        // Determine which module file threw the exception
        var targetFilePath = defaultFilePath
        if let sourceURLVal = exception.forProperty("sourceURL"),
           sourceURLVal.isString,
           let urlString = sourceURLVal.toString(),
           !urlString.isEmpty,
           !urlString.hasPrefix("made://") {
            if let url = URL(string: urlString), url.isFileURL {
                targetFilePath = url.path
            } else if modulesByPath[urlString] != nil {
                targetFilePath = urlString
            }
        }

        var rawJscLine: Int? = nil
        if let lineVal = exception.forProperty("line"), lineVal.isNumber {
            let l = Int(lineVal.toInt32())
            if l > 0 { rawJscLine = l }
        }

        var rawJscCol: Int? = nil
        if let colVal = exception.forProperty("column"), colVal.isNumber {
            let c = Int(colVal.toInt32())
            if c > 0 { rawJscCol = c }
        }

        // Also check the top user module frame in `exception.stack` when available
        if let stackVal = exception.forProperty("stack"), stackVal.isString, let stackText = stackVal.toString() {
            if let frame = parseTopUserFrame(from: stackText) {
                targetFilePath = frame.filePath
                if rawJscLine == nil { rawJscLine = frame.jscLine }
                if rawJscCol == nil { rawJscCol = frame.jscColumn }
            }
        }

        let moduleRecord = modulesByPath[targetFilePath] ?? modulesByPath[defaultFilePath]
        let totalLines = max(1, moduleRecord?.originalLines.count ?? 1)

        // Subtract 1 for the wrapper header line `(function(__made_exports, __made_require, __made_d){\n`
        let origLine: Int
        if let jscLine = rawJscLine {
            origLine = min(totalLines, max(1, jscLine - 1))
        } else {
            origLine = 1
        }

        let origColumn: Int
        if let jscCol = rawJscCol {
            origColumn = mapColumnToOriginal(
                jscColumn: jscCol,
                origLine: origLine,
                moduleRecord: moduleRecord
            )
        } else {
            origColumn = inferSyntaxErrorColumn(
                message: rawMessage,
                origLine: origLine,
                moduleRecord: moduleRecord
            )
        }

        return PartRuntimeError(
            code: errorCode,
            diagnostic: PartDiagnostic(
                file: targetFilePath,
                line: origLine,
                column: origColumn,
                message: rawMessage
            )
        )
    }

    private func parseTopUserFrame(from stack: String) -> (filePath: String, jscLine: Int, jscColumn: Int)? {
        for rawLine in stack.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("made://internal/") else { continue }
            let locationPart: String
            if let atIndex = trimmed.lastIndex(of: "@") {
                locationPart = String(trimmed[trimmed.index(after: atIndex)...])
            } else {
                locationPart = trimmed
            }
            // Match `<file-or-url>:<line>:<col>` from the right
            let parts = locationPart.components(separatedBy: ":")
            guard parts.count >= 3,
                  let col = Int(parts[parts.count - 1]),
                  let line = Int(parts[parts.count - 2]) else {
                continue
            }
            let fileCandidate = parts.dropLast(2).joined(separator: ":")
            let resolvedPath: String
            if let url = URL(string: fileCandidate), url.isFileURL {
                resolvedPath = url.path
            } else {
                resolvedPath = fileCandidate
            }
            if modulesByPath[resolvedPath] != nil {
                return (resolvedPath, line, col)
            }
        }
        return nil
    }

    private func mapColumnToOriginal(
        jscColumn: Int,
        origLine: Int,
        moduleRecord: TransformedModuleRecord?
    ) -> Int {
        guard let edits = moduleRecord?.editsByLine[origLine], !edits.isEmpty else {
            return max(1, jscColumn)
        }
        var shift = 0
        for edit in edits {
            let transformedEditStart = edit.origCol + shift
            if jscColumn <= transformedEditStart {
                break
            }
            let transformedEditEnd = transformedEditStart + max(0, edit.delta)
            if jscColumn <= transformedEditEnd {
                return max(1, edit.origCol)
            }
            shift += edit.delta
        }
        return max(1, jscColumn - shift)
    }

    private func inferSyntaxErrorColumn(
        message: String,
        origLine: Int,
        moduleRecord: TransformedModuleRecord?
    ) -> Int {
        guard let lines = moduleRecord?.originalLines,
              origLine >= 1,
              origLine <= lines.count else {
            return 1
        }
        let lineText = lines[origLine - 1]
        if lineText.isEmpty {
            return 1
        }

        // Extract first single-quoted offending token from JSC SyntaxError message (e.g. "Unexpected token ')'. Expected ';'")
        if let firstQuote = message.firstIndex(of: "'") {
            let afterFirst = message.index(after: firstQuote)
            if let secondQuote = message[afterFirst...].firstIndex(of: "'"),
               afterFirst < secondQuote {
                let token = String(message[afterFirst..<secondQuote])
                if !token.isEmpty, let range = lineText.range(of: token) {
                    return lineText.distance(from: lineText.startIndex, to: range.lowerBound) + 1
                }
            }
        }

        // Fall back to first non-whitespace column on that line
        if let firstNonSpace = lineText.firstIndex(where: { !$0.isWhitespace }) {
            return lineText.distance(from: lineText.startIndex, to: firstNonSpace) + 1
        }
        return 1
    }

    // MARK: Export Extraction & Decoding

    private func resolveExportedShape(
        from exportsObj: JSValue,
        filePath: String,
        in context: JSContext
    ) -> Result<JSValue, PartRuntimeError> {
        let candidateKeys = ["default", "shape", "part", "model", "main", "build"]
        var candidate: JSValue? = nil

        for key in candidateKeys {
            if let val = exportsObj.forProperty(key), !val.isUndefined, !val.isNull {
                candidate = val
                break
            }
        }

        guard let exportedVal = candidate else {
            return .failure(
                PartRuntimeError(
                    code: .invalidExport,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: 1,
                        column: 1,
                        message: "Part script must export a default Shape, 'export const shape', or 'export function main()'"
                    )
                )
            )
        }

        // If the export is a builder function `(params) => Shape`, invoke it with current parameter values
        let resolvedVal: JSValue
        if isShapeObject(exportedVal) {
            resolvedVal = exportedVal
        } else if exportedVal.isObject && !exportedVal.isArray {
            // Check if it is callable
            let paramsMap = buildCurrentParamsObject(in: context)
            guard let called = exportedVal.call(withArguments: [paramsMap]) else {
                return .failure(
                    PartRuntimeError(
                        code: .invalidExport,
                        diagnostic: PartDiagnostic(
                            file: filePath,
                            line: 1,
                            column: 1,
                            message: "Exported builder function did not return a Shape"
                        )
                    )
                )
            }
            if let exc = context.exception {
                context.exception = nil
                if let existing = activeError {
                    return .failure(existing)
                }
                return .failure(mapJSCException(exc, defaultFilePath: filePath, defaultCode: .scriptError))
            }
            resolvedVal = called
        } else {
            return .failure(
                PartRuntimeError(
                    code: .invalidExport,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: 1,
                        column: 1,
                        message: "Part script default export must be a Shape or a function returning a Shape"
                    )
                )
            )
        }

        guard isShapeObject(resolvedVal) else {
            return .failure(
                PartRuntimeError(
                    code: .invalidExport,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: 1,
                        column: 1,
                        message: "Exported value is not a valid 'made' Shape"
                    )
                )
            )
        }

        return .success(resolvedVal)
    }

    private func isShapeObject(_ value: JSValue) -> Bool {
        guard value.isObject,
              let flag = value.forProperty("__madeShape"),
              flag.isBoolean,
              flag.toBool() else {
            return false
        }
        return true
    }

    private func buildCurrentParamsObject(in context: JSContext) -> JSValue {
        let obj = JSValue(newObjectIn: context)!
        for spec in decodeRecordedParameters(in: context) {
            obj.setObject(spec.value, forKeyedSubscript: spec.name as NSString)
        }
        return obj
    }

    private func decodeShapeNode(from jsValue: JSValue) throws -> ShapeNode {
        guard let dict = jsValue.toObject() as? [String: Any] else {
            throw NSError(domain: "MadeCore.PartRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Shape node is not an object"])
        }
        return try parseShapeNodeDictionary(dict)
    }

    private func parseShapeNodeDictionary(_ dict: [String: Any]) throws -> ShapeNode {
        guard let kind = dict["kind"] as? String else {
            throw NSError(domain: "MadeCore.PartRuntime", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing shape node kind"])
        }

        switch kind {
        case "box":
            let width = try parseFloat(dict["width"], name: "box.width")
            let depth = try parseFloat(dict["depth"], name: "box.depth")
            let height = try parseFloat(dict["height"], name: "box.height")
            return .box(BoxParams(width: width, depth: depth, height: height))

        case "cylinder":
            let radius = try parseFloat(dict["radius"], name: "cylinder.radius")
            let height = try parseFloat(dict["height"], name: "cylinder.height")
            let slices = try parseInt(dict["slices"] ?? 32, name: "cylinder.slices")
            return .cylinder(CylinderParams(radius: radius, height: height), slices: slices)

        case "sphere":
            let radius = try parseFloat(dict["radius"], name: "sphere.radius")
            let slices = try parseInt(dict["slices"] ?? 32, name: "sphere.slices")
            return .sphere(SphereParams(radius: radius), slices: slices)

        case "cone":
            let bottomRadius = try parseFloat(dict["bottomRadius"], name: "cone.bottomRadius")
            let topRadius = try parseFloat(dict["topRadius"] ?? 0.0, name: "cone.topRadius")
            let height = try parseFloat(dict["height"], name: "cone.height")
            let slices = try parseInt(dict["slices"] ?? 32, name: "cone.slices")
            return .cone(ConeParams(bottomRadius: bottomRadius, topRadius: topRadius, height: height), slices: slices)

        case "extrude":
            guard let profileDict = dict["profile"] as? [String: Any] else {
                throw NSError(domain: "MadeCore.PartRuntime", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing extrude profile"])
            }
            let profile = try parseSketchProfile(profileDict)
            let distance = try parseFloat(dict["distance"], name: "extrude.distance")
            let centered = (dict["centered"] as? Bool) ?? false
            return .extrude(profile: profile, distance: distance, centered: centered)

        case "revolve":
            guard let profileDict = dict["profile"] as? [String: Any] else {
                throw NSError(domain: "MadeCore.PartRuntime", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing revolve profile"])
            }
            let profile = try parseSketchProfile(profileDict)
            let angleDegrees = try parseFloat(dict["angleDegrees"] ?? 360.0, name: "revolve.angleDegrees")
            let slices = try parseInt(dict["slices"] ?? 32, name: "revolve.slices")
            return .revolve(profile: profile, angleDegrees: angleDegrees, slices: slices)

        case "translate":
            guard let childDict = dict["child"] as? [String: Any] else {
                throw NSError(domain: "MadeCore.PartRuntime", code: 5, userInfo: [NSLocalizedDescriptionKey: "Missing translate child"])
            }
            let child = try parseShapeNodeDictionary(childDict)
            let offset = try parseSIMD3(dict["offset"], name: "translate.offset")
            return .translate(child, offset: offset)

        case "rotate":
            guard let childDict = dict["child"] as? [String: Any] else {
                throw NSError(domain: "MadeCore.PartRuntime", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing rotate child"])
            }
            let child = try parseShapeNodeDictionary(childDict)
            let axis = try parseSIMD3(dict["axis"], name: "rotate.axis")
            let angleDegrees = try parseFloat(dict["angleDegrees"], name: "rotate.angleDegrees")
            return .rotate(child, axis: axis, angleDegrees: angleDegrees)

        case "scale":
            guard let childDict = dict["child"] as? [String: Any] else {
                throw NSError(domain: "MadeCore.PartRuntime", code: 7, userInfo: [NSLocalizedDescriptionKey: "Missing scale child"])
            }
            let child = try parseShapeNodeDictionary(childDict)
            let factor = try parseSIMD3(dict["factor"], name: "scale.factor")
            return .scale(child, factor: factor)

        case "boolean":
            guard let opRaw = dict["op"] as? String,
                  let op = BooleanOp(rawValue: opRaw),
                  let lhsDict = dict["lhs"] as? [String: Any],
                  let rhsDict = dict["rhs"] as? [String: Any] else {
                throw NSError(domain: "MadeCore.PartRuntime", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid boolean node"])
            }
            let lhs = try parseShapeNodeDictionary(lhsDict)
            let rhs = try parseShapeNodeDictionary(rhsDict)
            return .boolean(op, lhs, rhs)

        default:
            throw NSError(domain: "MadeCore.PartRuntime", code: 9, userInfo: [NSLocalizedDescriptionKey: "Unknown shape node kind '\(kind)'"])
        }
    }

    private func parseSketchProfile(_ dict: [String: Any]) throws -> SketchProfile {
        let plane: SketchPlane
        if let planeDict = dict["plane"] as? [String: Any] {
            let origin = try parseSIMD3(planeDict["origin"] ?? [0.0, 0.0, 0.0], name: "plane.origin")
            let normal = try parseSIMD3(planeDict["normal"] ?? [0.0, 0.0, 1.0], name: "plane.normal")
            let xAxis = try parseSIMD3(planeDict["xAxis"] ?? [1.0, 0.0, 0.0], name: "plane.xAxis")
            plane = SketchPlane(origin: origin, normal: normal, xAxis: xAxis)
        } else {
            plane = .xy
        }

        guard let rawPoints = dict["points"] as? [Any] else {
            throw NSError(domain: "MadeCore.PartRuntime", code: 10, userInfo: [NSLocalizedDescriptionKey: "Missing sketch profile points"])
        }
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(rawPoints.count)
        for item in rawPoints {
            points.append(try parseSIMD2(item, name: "profile.point"))
        }
        return SketchProfile(plane: plane, points: points)
    }

    private func decodeExpected(from exportsObj: JSValue, filePath: String) throws -> PartExpected? {
        guard let expVal = exportsObj.forProperty("expected"),
              !expVal.isUndefined,
              !expVal.isNull else {
            return nil
        }
        guard expVal.isObject, let raw = expVal.toObject() as? [String: Any] else {
            throw PartRuntimeError(
                code: .invalidExport,
                diagnostic: PartDiagnostic(
                    file: filePath,
                    line: 1,
                    column: 1,
                    message: "'export const expected' must be an object"
                )
            )
        }

        let knownKeys: Set<String> = ["volume", "area", "surfaceArea", "bounds", "tolerance"]
        for key in raw.keys.sorted() where !knownKeys.contains(key) {
            warnings.append(
                PartDiagnostic(
                    file: filePath,
                    line: 1,
                    column: 1,
                    message: "Unrecognized key '\(key)' in 'export const expected' (supported: volume, area, bounds, tolerance)"
                )
            )
        }

        let volume = try parseOptionalDouble(raw["volume"], name: "expected.volume")
        let area = try parseOptionalDouble(raw["area"] ?? raw["surfaceArea"], name: "expected.area")
        let tolerance = try parseOptionalDouble(raw["tolerance"], name: "expected.tolerance")

        var bounds: PartExpectedBounds? = nil
        if let rawBounds = raw["bounds"], !(rawBounds is NSNull) {
            if let boundsDict = rawBounds as? [String: Any] {
                let minVec = try parseSIMD3(boundsDict["min"], name: "expected.bounds.min")
                let maxVec = try parseSIMD3(boundsDict["max"], name: "expected.bounds.max")
                bounds = PartExpectedBounds(min: minVec, max: maxVec)
            } else if let boundsArr = rawBounds as? [Any], boundsArr.count == 2 {
                let minVec = try parseSIMD3(boundsArr[0], name: "expected.bounds[0]")
                let maxVec = try parseSIMD3(boundsArr[1], name: "expected.bounds[1]")
                bounds = PartExpectedBounds(min: minVec, max: maxVec)
            } else {
                throw PartRuntimeError(
                    code: .invalidExport,
                    diagnostic: PartDiagnostic(
                        file: filePath,
                        line: 1,
                        column: 1,
                        message: "'expected.bounds' must have { min, max } or [[minX, minY, minZ], [maxX, maxY, maxZ]]"
                    )
                )
            }
        }

        return PartExpected(volume: volume, area: area, bounds: bounds, tolerance: tolerance)
    }

    private func decodeRecordedParameters(in context: JSContext) -> [PartParameterSpec] {
        guard let fn = context.objectForKeyedSubscript("__made_getRecordedParams"),
              let arrVal = fn.call(withArguments: []),
              let rawArray = arrVal.toArray() as? [[String: Any]] else {
            return []
        }

        var specs: [PartParameterSpec] = []
        specs.reserveCapacity(rawArray.count)
        for item in rawArray {
            guard let name = item["name"] as? String,
                  let defaultNum = (item["defaultValue"] as? NSNumber)?.doubleValue,
                  let valNum = (item["value"] as? NSNumber)?.doubleValue else {
                continue
            }
            let minVal = (item["min"] as? NSNumber)?.doubleValue
            let maxVal = (item["max"] as? NSNumber)?.doubleValue
            let stepVal = (item["step"] as? NSNumber)?.doubleValue
            let unitVal = item["unit"] as? String
            let labelVal = item["label"] as? String
            specs.append(
                PartParameterSpec(
                    name: name,
                    defaultValue: defaultNum,
                    value: valNum,
                    min: minVal,
                    max: maxVal,
                    step: stepVal,
                    unit: unitVal,
                    label: labelVal
                )
            )
        }
        return specs
    }

    private func parseFloat(_ raw: Any?, name: String) throws -> Float {
        guard let num = raw as? NSNumber else {
            throw NSError(domain: "MadeCore.PartRuntime", code: 20, userInfo: [NSLocalizedDescriptionKey: "Expected number for \(name)"])
        }
        return num.floatValue
    }

    private func parseOptionalDouble(_ raw: Any?, name: String) throws -> Double? {
        guard let raw, !(raw is NSNull) else { return nil }
        guard let num = raw as? NSNumber else {
            throw NSError(domain: "MadeCore.PartRuntime", code: 21, userInfo: [NSLocalizedDescriptionKey: "Expected number for \(name)"])
        }
        let d = num.doubleValue
        guard d.isFinite else {
            throw NSError(domain: "MadeCore.PartRuntime", code: 22, userInfo: [NSLocalizedDescriptionKey: "\(name) must be finite"])
        }
        return d
    }

    private func parseInt(_ raw: Any?, name: String) throws -> Int {
        guard let num = raw as? NSNumber else {
            throw NSError(domain: "MadeCore.PartRuntime", code: 23, userInfo: [NSLocalizedDescriptionKey: "Expected integer for \(name)"])
        }
        return num.intValue
    }

    private func parseSIMD2(_ raw: Any?, name: String) throws -> SIMD2<Float> {
        if let arr = raw as? [Any], arr.count >= 2 {
            let x = try parseFloat(arr[0], name: "\(name)[0]")
            let y = try parseFloat(arr[1], name: "\(name)[1]")
            return SIMD2(x, y)
        }
        if let dict = raw as? [String: Any] {
            let x = try parseFloat(dict["x"] ?? 0.0, name: "\(name).x")
            let y = try parseFloat(dict["y"] ?? 0.0, name: "\(name).y")
            return SIMD2(x, y)
        }
        throw NSError(domain: "MadeCore.PartRuntime", code: 24, userInfo: [NSLocalizedDescriptionKey: "Expected 2D vector for \(name)"])
    }

    private func parseSIMD3(_ raw: Any?, name: String) throws -> SIMD3<Float> {
        if let arr = raw as? [Any], arr.count >= 3 {
            let x = try parseFloat(arr[0], name: "\(name)[0]")
            let y = try parseFloat(arr[1], name: "\(name)[1]")
            let z = try parseFloat(arr[2], name: "\(name)[2]")
            return SIMD3(x, y, z)
        }
        if let dict = raw as? [String: Any] {
            let x = try parseFloat(dict["x"] ?? 0.0, name: "\(name).x")
            let y = try parseFloat(dict["y"] ?? 0.0, name: "\(name).y")
            let z = try parseFloat(dict["z"] ?? 0.0, name: "\(name).z")
            return SIMD3(x, y, z)
        }
        throw NSError(domain: "MadeCore.PartRuntime", code: 25, userInfo: [NSLocalizedDescriptionKey: "Expected 3D vector for \(name)"])
    }
}
