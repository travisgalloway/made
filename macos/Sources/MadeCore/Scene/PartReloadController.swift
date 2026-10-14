import Foundation

/// Watches `.part.ts` and `.part.js` source files in the open `DocumentModel`, coalesces rapid disk saves
/// with a 60-ms debounce window (invariant 7), evaluates updated scripts and shapes off the main thread
/// through `PartRuntime` and `KernelClientProtocol` (invariants 1 and 4), installs meshes on success
/// to trigger a single viewport redraw (invariant 2), and keeps the last good model on screen while
/// reporting `file:line:column` diagnostics on failure (#427).
@MainActor
public final class PartReloadController {
    public static let defaultDebounceDuration: Duration = .milliseconds(60)

    private struct WatchedPartState {
        var url: URL
        var watcher: PartFileWatcher
        var knownLoadedFiles: Set<String> = []
        var lastSubmittedSnapshot: PartDependencySnapshot?
        var pendingDebounceSnapshot: PartDependencySnapshot?
        var activeJobId: JobId?
        var inFlightTask: Task<PartRuntimeResult<PartEvaluationOutput>, Never>?
        var isDebouncing: Bool = false
    }

    public let document: DocumentModel
    public let partRuntime: PartRuntime
    public let kernelClient: any KernelClientProtocol
    public let debounceDuration: Duration

    private weak var meshSink: (any SolidMeshSink)?
    private let onViewportInvalidated: (@MainActor () -> Void)?
    private let onReloadResult: (@MainActor (PartRuntimeResult<PartEvaluationOutput>, SolidId) -> Void)?

    private var watchedParts: [SolidId: WatchedPartState] = [:]
    private var reloadWaiters: [SolidId: [UUID: CheckedContinuation<PartRuntimeResult<PartEvaluationOutput>, Never>]] = [:]

    /// Most recent successful evaluation output per solid.
    public private(set) var lastOutputs: [SolidId: PartEvaluationOutput] = [:]
    /// Most recent non-cancelled evaluation error per solid, cleared on the next success.
    public private(set) var lastErrors: [SolidId: PartRuntimeError] = [:]
    /// Per-solid failure tracker shared with Inspector and console reporting.
    public private(set) var failures = RecomputeFailures()
    /// Number of rapid file saves that were coalesced inside the debounce window before evaluation started.
    public private(set) var conflatedSavesCount: Int = 0
    /// Number of non-cancelled reload evaluations that finished (succeeded or failed).
    public private(set) var completedReloadsCount: Int = 0

    public var watchedSolidIds: Set<SolidId> {
        Set(watchedParts.keys)
    }

    public init(
        document: DocumentModel,
        partRuntime: PartRuntime = PartRuntime(),
        kernelClient: any KernelClientProtocol,
        meshSink: (any SolidMeshSink)? = nil,
        debounceDuration: Duration = PartReloadController.defaultDebounceDuration,
        onViewportInvalidated: (@MainActor () -> Void)? = nil,
        onReloadResult: (@MainActor (PartRuntimeResult<PartEvaluationOutput>, SolidId) -> Void)? = nil
    ) {
        self.document = document
        self.partRuntime = partRuntime
        self.kernelClient = kernelClient
        self.meshSink = meshSink
        self.debounceDuration = debounceDuration
        self.onViewportInvalidated = onViewportInvalidated
        self.onReloadResult = onReloadResult
    }

    public func setMeshSink(_ sink: (any SolidMeshSink)?) {
        self.meshSink = sink
    }

    /// Adds a `.part.ts` or `.part.js` file to `document` (or reuses the existing object for the same file URL),
    /// starts watching the file and its directory on disk, and starts its initial evaluation.
    @discardableResult
    public func openPartFile(
        at url: URL,
        name: String? = nil,
        transform: Transform = .identity
    ) -> SolidId {
        let canonical = url.standardizedFileURL
        if let existing = document.objects.first(where: {
            if case .part(let existingURL, _) = $0.def {
                return existingURL.standardizedFileURL == canonical
            }
            return false
        }) {
            watchPart(id: existing.id, url: canonical, evaluateImmediately: true)
            return existing.id
        }

        let id = document.addPart(url: canonical, name: name, transform: transform)
        watchPart(id: id, url: canonical, evaluateImmediately: true)
        return id
    }

    /// Synchronizes watched part files with `document.objects`, starting watchers for newly added `.part`
    /// objects and stopping watchers for removed objects.
    public func syncWithDocument() {
        var currentPartURLs: [SolidId: URL] = [:]
        for obj in document.objects {
            if case .part(let url, _) = obj.def {
                currentPartURLs[obj.id] = url.standardizedFileURL
            }
        }

        for existingId in Array(watchedParts.keys) where currentPartURLs[existingId] == nil {
            stopWatching(id: existingId)
        }

        for (id, url) in currentPartURLs {
            if let existing = watchedParts[id], existing.url == url {
                continue
            }
            watchPart(id: id, url: url, evaluateImmediately: true)
        }
    }

    /// Starts watching `url` for `id`. When `evaluateImmediately` is true, kicks off an immediate evaluation.
    @discardableResult
    public func watchPart(
        id: SolidId,
        url: URL,
        evaluateImmediately: Bool = true
    ) -> Task<PartRuntimeResult<PartEvaluationOutput>, Never>? {
        let canonical = url.standardizedFileURL

        if let existing = watchedParts[id] {
            if existing.url == canonical {
                return evaluateImmediately ? reloadNow(id: id) : existing.inFlightTask
            }
            stopWatching(id: id)
        }

        let initialSnapshot = PartDependencySnapshot.capture(rootFileURL: canonical)
        let watcher = PartFileWatcher(
            fileURL: canonical,
            additionalFileURLs: initialSnapshot.watchedFileURLs,
            additionalDirectoryURLs: initialSnapshot.watchedDirectoryURLs
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFileSystemEvent(for: id)
            }
        }

        let state = WatchedPartState(
            url: canonical,
            watcher: watcher,
            knownLoadedFiles: Set(initialSnapshot.watchedFileURLs.map(\.path)),
            lastSubmittedSnapshot: evaluateImmediately ? nil : initialSnapshot,
            pendingDebounceSnapshot: nil,
            activeJobId: nil,
            inFlightTask: nil,
            isDebouncing: false
        )
        watchedParts[id] = state

        if evaluateImmediately {
            return reloadNow(id: id)
        }
        return nil
    }

    /// Stops watching `id`, cancels any pending debounce or running evaluation, and clears stored diagnostics.
    public func stopWatching(id: SolidId) {
        guard let state = watchedParts.removeValue(forKey: id) else { return }
        state.watcher.stop()
        state.inFlightTask?.cancel()
        if let jobId = state.activeJobId {
            let runtime = partRuntime
            Task { await runtime.cancel(jobId: jobId) }
        }
        lastOutputs.removeValue(forKey: id)
        lastErrors.removeValue(forKey: id)
        failures.clear(id)
        resumeWaiters(
            for: id,
            with: .failure(jobId: state.activeJobId ?? JobId("stopped"), error: Self.cancelledError(filePath: state.url.path))
        )
    }

    /// Stops all active file watchers and cancels any in-flight reloads.
    public func stopAll() {
        for id in Array(watchedParts.keys) {
            stopWatching(id: id)
        }
    }

    /// Immediately evaluates the part file for `id` without waiting for a file-system save debounce.
    @discardableResult
    public func reloadNow(id: SolidId) -> Task<PartRuntimeResult<PartEvaluationOutput>, Never>? {
        guard var state = watchedParts[id] else {
            if let obj = document.objects.first(where: { $0.id == id }),
               case .part(let url, _) = obj.def {
                return watchPart(id: id, url: url, evaluateImmediately: true)
            }
            return nil
        }

        let jobId = JobId("part-reload-\(UUID().uuidString)")
        let previousJobId = state.activeJobId
        state.inFlightTask?.cancel()
        state.activeJobId = jobId
        state.isDebouncing = false
        state.pendingDebounceSnapshot = nil

        let url = state.url
        let task = Task { @MainActor [weak self] () -> PartRuntimeResult<PartEvaluationOutput> in
            if let previousJobId {
                await self?.partRuntime.cancel(jobId: previousJobId)
            }
            guard let self else {
                return .failure(jobId: jobId, error: Self.cancelledError(filePath: url.path))
            }
            return await self.performEvaluation(for: id, url: url, jobId: jobId)
        }
        state.inFlightTask = task
        watchedParts[id] = state
        return task
    }

    /// Reloads every watched part in the document now.
    public func reloadAll() {
        syncWithDocument()
        for id in watchedParts.keys {
            _ = reloadNow(id: id)
        }
    }

    /// Suspends until the next non-cancelled reload for `id` completes (used by tests and callers awaiting a file save).
    public func nextReload(for id: SolidId) async -> PartRuntimeResult<PartEvaluationOutput> {
        let waiterId = UUID()
        return await withCheckedContinuation { continuation in
            reloadWaiters[id, default: [:]][waiterId] = continuation
        }
    }

    /// Awaits any pending debounce and in-flight evaluation for `id`, continuing if a newer save replaced an earlier job.
    @discardableResult
    public func settle(for id: SolidId) async -> PartRuntimeResult<PartEvaluationOutput>? {
        var lastResult: PartRuntimeResult<PartEvaluationOutput>? = nil
        while let state = watchedParts[id], let task = state.inFlightTask, let jobId = state.activeJobId {
            lastResult = await task.value
            if watchedParts[id]?.activeJobId == jobId && watchedParts[id]?.inFlightTask == nil {
                break
            }
        }
        return lastResult
    }

    /// Awaits all pending debounces and in-flight evaluations across all watched parts.
    public func settleAll() async {
        for id in Array(watchedParts.keys) {
            _ = await settle(for: id)
        }
    }

    // MARK: - File-System Event Coalescing & Execution

    private func handleFileSystemEvent(for id: SolidId) {
        guard var state = watchedParts[id] else { return }
        guard document.objects.contains(where: { $0.id == id }) else {
            stopWatching(id: id)
            return
        }

        let currentSnapshot = PartDependencySnapshot.capture(
            rootFileURL: state.url,
            additionalFilePaths: state.knownLoadedFiles
        )
        state.watcher.updateWatchedTargets(
            fileURLs: currentSnapshot.watchedFileURLs,
            directoryURLs: currentSnapshot.watchedDirectoryURLs
        )

        if state.isDebouncing {
            // Multiple kqueue notifications for the exact same file state do not reset the debounce window.
            if currentSnapshot == state.pendingDebounceSnapshot {
                watchedParts[id] = state
                return
            }
            conflatedSavesCount += 1
        } else {
            // Ignore directory events from unrelated sibling files or pre-rename temp files when our part's files are unchanged.
            if currentSnapshot == state.lastSubmittedSnapshot {
                watchedParts[id] = state
                return
            }
        }

        let jobId = JobId("part-reload-\(UUID().uuidString)")
        let previousJobId = state.activeJobId
        state.inFlightTask?.cancel()
        state.activeJobId = jobId
        state.isDebouncing = true
        state.pendingDebounceSnapshot = currentSnapshot

        let url = state.url
        let delay = debounceDuration

        let task = Task { @MainActor [weak self] () -> PartRuntimeResult<PartEvaluationOutput> in
            if let previousJobId {
                await self?.partRuntime.cancel(jobId: previousJobId)
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return .failure(jobId: jobId, error: Self.cancelledError(filePath: url.path))
            }
            guard let self, self.watchedParts[id]?.activeJobId == jobId else {
                return .failure(jobId: jobId, error: Self.cancelledError(filePath: url.path))
            }
            self.watchedParts[id]?.isDebouncing = false
            self.watchedParts[id]?.pendingDebounceSnapshot = nil
            return await self.performEvaluation(for: id, url: url, jobId: jobId)
        }

        state.inFlightTask = task
        watchedParts[id] = state
    }

    private func performEvaluation(
        for id: SolidId,
        url: URL,
        jobId: JobId
    ) async -> PartRuntimeResult<PartEvaluationOutput> {
        guard var state = watchedParts[id], state.activeJobId == jobId else {
            return .failure(jobId: jobId, error: Self.cancelledError(filePath: url.path))
        }
        guard document.objects.contains(where: { $0.id == id }) else {
            stopWatching(id: id)
            return .failure(jobId: jobId, error: Self.cancelledError(filePath: url.path))
        }

        // Snapshot the exact file contents on disk at the start of evaluation.
        let preEvalSnapshot = PartDependencySnapshot.capture(
            rootFileURL: url,
            additionalFilePaths: state.knownLoadedFiles
        )
        state.lastSubmittedSnapshot = preEvalSnapshot
        state.watcher.updateWatchedTargets(
            fileURLs: preEvalSnapshot.watchedFileURLs,
            directoryURLs: preEvalSnapshot.watchedDirectoryURLs
        )
        watchedParts[id] = state

        let runtime = partRuntime
        let client = kernelClient
        let result = await runtime.evaluatePartFile(
            at: url,
            jobId: jobId,
            solidId: id,
            kernelClient: client
        )

        // If the part was removed from the document while the evaluation was in flight, dispose any kernel solid it created.
        guard document.objects.contains(where: { $0.id == id }) else {
            if case .success = result {
                await client.dispose(solidId: id)
            }
            stopWatching(id: id)
            return .failure(jobId: jobId, error: Self.cancelledError(filePath: url.path))
        }

        // If a newer save superseded this job while it was running, drop this stale result.
        guard var currentState = watchedParts[id], currentState.activeJobId == jobId else {
            return .failure(jobId: jobId, error: Self.cancelledError(filePath: url.path))
        }

        currentState.inFlightTask = nil

        // Update watched helper module paths from the evaluation output or error.
        let loadedPaths: [String]
        switch result {
        case .success(_, let output):
            loadedPaths = output.loadedFiles
        case .failure(_, let err):
            loadedPaths = err.loadedFiles
        }
        if !loadedPaths.isEmpty {
            currentState.knownLoadedFiles.formUnion(loadedPaths)
        }

        let updatedSnapshot = PartDependencySnapshot.capture(
            rootFileURL: url,
            additionalFilePaths: currentState.knownLoadedFiles
        )
        currentState.watcher.updateWatchedTargets(
            fileURLs: updatedSnapshot.watchedFileURLs,
            directoryURLs: updatedSnapshot.watchedDirectoryURLs
        )
        // If no file write happened during evaluation, update lastSubmittedSnapshot with any newly discovered helper imports.
        if updatedSnapshot.entries.first(where: { $0.path == preEvalSnapshot.rootFileURL.path })
            == preEvalSnapshot.entries.first(where: { $0.path == preEvalSnapshot.rootFileURL.path }) {
            currentState.lastSubmittedSnapshot = updatedSnapshot
        }
        watchedParts[id] = currentState

        switch result {
        case .success(let resJobId, let output):
            completedReloadsCount += 1
            document.setPartShape(id: id, shape: output.shape)
            lastOutputs[id] = output
            lastErrors.removeValue(forKey: id)
            _ = failures.record(result, for: id)
            onReloadResult?(result, id)

            let kernelSuccess = KernelResult<MeshPayload>.success(jobId: resJobId, value: output.payload)
            if let sink = meshSink,
               SolidMeshApplier.apply(kernelSuccess, to: id, document: document, sink: sink) {
                onViewportInvalidated?()
            }
            resumeWaiters(for: id, with: result)

        case .failure(_, let error):
            guard error.code != .cancelled else {
                return result
            }
            completedReloadsCount += 1
            // Keep the last good shape in DocumentModel and the last good mesh in SolidMeshSink untouched.
            lastErrors[id] = error
            _ = failures.record(result, for: id)
            onReloadResult?(result, id)
            resumeWaiters(for: id, with: result)
        }

        // If the file changed on disk while this evaluation was running and no new job was scheduled yet, schedule it now.
        if watchedParts[id]?.activeJobId == jobId {
            let latestDiskSnapshot = PartDependencySnapshot.capture(
                rootFileURL: url,
                additionalFilePaths: watchedParts[id]?.knownLoadedFiles ?? []
            )
            if latestDiskSnapshot != watchedParts[id]?.lastSubmittedSnapshot {
                handleFileSystemEvent(for: id)
            }
        }

        return result
    }

    private func resumeWaiters(for id: SolidId, with result: PartRuntimeResult<PartEvaluationOutput>) {
        guard let waiters = reloadWaiters.removeValue(forKey: id) else { return }
        for continuation in waiters.values {
            continuation.resume(returning: result)
        }
    }

    private static func cancelledError(filePath: String) -> PartRuntimeError {
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
