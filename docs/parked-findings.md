# Parked findings

Date: 2026-10-11
Scope: macos/
Audit run: 20261011-195134

The list holds 55 parked findings, in source order and unranked. Format: ID, file:line, finding, source pass.

- INPUT-7 | macos/Sources/MadeCore/Input/Snapping.swift:57 | `screenPixelDistance` has a single reference in Sources and no caller. | closure A
- KERN-7 | macos/Sources/MadeCore/Kernel/Geometry.swift:7 | `NativeGeometryGenerator.generateBox` has no reference outside its declaration. | closure A
- KERN-8 | macos/Sources/MadeCore/Kernel/Geometry.swift:89 | `NativeGeometryGenerator.generateCylinder` has no caller. | closure A
- UI-23 | macos/Sources/MadeCore/Platform/PlatformShim.swift:18 | `UniversalPlatform.isIPad` and `isMac` have no reference anywhere in Sources. | closure A
- (no id) | macos/Sources/MadeCore/Kernel/Types.swift:60 | `KernelErrorCode.kernelInitFailed`, `workerCrashed`, and `KernelResult.isSuccess` each have a single reference. | closure A
- (no id) | macos/Sources/MadeCore/Agent/MCPProtocol.swift:77 | `JSONRPCErrorPayload.invalidRequest` and `AnyCodableValue.boolValue` and `arrayValue` each have a single reference. | closure A
- DSL-1 | macos/Sources/MadeCore/Scripting/CADDSL.swift:7 | The public `CADShape` DSL has no consumer in MadeApp or in other MadeCore files. (covered by #85 as DSL-12 on 2026-10-11) | closure A
- (no id) | macos/Sources/MadeCore/Viewport/Orientation.swift:9 | `groundNormal` has a single reference. | closure A
- VIEW-16 | macos/Sources/MadeCore/Viewport/RenderLoop.swift:5 | No call site passes the `InvalidateReason` case `resize`. (narrowed on 2026-10-11: `CADMetalViewRepresentable.swift:287` passes `camera` and `:357` passes `interaction`) | closure A
- (no id) | docs/architecture/invariants.md:28 | The matrix cites KernelClientTests for the 60 ms window, and the audit did not read the 4 tests in full to confirm the assertion. | closure D
- (no id) | docs/roadmap/phase-4-cad-depth.md:8 | The 4.1 and 4.2 numbering differs from the open issues #39 and #83, and the criteria cite behavior not yet built. | closure D
- (no id) | docs/roadmap/backlog-migration.md:75 | Section 4 says epics #82 to #85 were created on GitHub, and the audit did not verify the milestone field of each. | closure D
- (no id) | CLAUDE.md:9 | The doc index lines resolve, and no docs/contracts/ directory exists for any document to declare. | closure D
- (no id) | README.md:23 | The claim of 33 tests matches the count of `func test` over the 8 test files. (stale on 2026-10-11: README.md:23 now documents `make test` and states no test count; the suites hold 128 tests in 18 files) | closure D
- (no id) | docs/archive/web-prototype | README.md and docs/README.md link to the archive, and the target file exists. | closure D
- DSN-4a0f328f | docs/architecture/invariants.md:13 | The DSL operators call `EuclidEngine` synchronously on the caller thread, and no mechanical guard enforces the kernel-only CSG rule. (resolved by #331 on 2026-10-12) | design D1
- DSN-06c119fb | macos/Sources/MadeCore/Agent/MCPServer.swift:85 | `try?` on the stdin read treats an error as end of input and exits with success, and the write failure at :102 is dropped. (superseded by decision DSN-2a85e7de on 2026-10-11) | design D2
- DSN-cbc7f8bb | macos/Sources/MadeCore/Agent/MCPServer.swift:76 | `encodeResponse` returns nil on an encoding error, so the client receives no reply and the cause is discarded. (superseded by decision DSN-2a85e7de on 2026-10-11) | design D2
- DSN-9e901d18 | macos/Sources/MadeApp/WorkspaceModel.swift:152 | The `Task` in `recomputeSolid` drops its handle and ignores the failure branch. | design D2
- DSN-dbd85a54 | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:64 | `MetalRenderer.meshes` is mutated on the main actor and iterated off it, grouped under the decision DSN-1eb23904. (ticketed as #131 on 2026-10-11) | design D2
- API-24a1c7aa | macos/Sources/MadeCore/Agent/CADTools.swift:143 | An unknown tool name returns an `isError` result where MCP specifies a -32602 protocol error. | api P1
- API-0e69ca70 | macos/Sources/MadeCore/Agent/CADTools.swift:149 | `cad_get_scene` returns every object in one response with no limit or cursor. (resolved by #156) | api P1
- API-9d5c8a37 | macos/Sources/MadeCore/Agent/CADTools.swift:149 | The object type key is `kind` in one tool and `type` in two others. | api P1
- REQ-95ea66a6 | macos/Tests/MadeCoreTests/OrientationTests.swift:1 | No test references `Orientation`, so issue #61 has no Z-up regression test. (contradicted on 2026-10-11: `OrientationTests` holds 4 tests) | requirements R1
- REQ-ae1cd1ec | macos/Tests/MadeCoreTests/GestureArbiterTests.swift:1 | No test adds a second pointer after the lock to assert that the mode holds until release. | requirements R1
- REQ-e73808df | macos/Tests/MadeCoreTests/CameraTests.swift:171 | No test references `PointerRouter` or `RouterEvent`, so pointer type routing is untested. (contradicted on 2026-10-11: `testPointerRouterClickVsDragThreshold` covers it) | requirements R1
- REQ-2011a068 | macos/Tests/MadeCoreTests/KernelClientTests.swift:1 | No test requests two solids to assert that only the changed solid re-tessellates. | requirements R1
- UX-9d5cdfe3 | macos/Sources/MadeApp/ContentView.swift:155 | The Copilot transcript pane is blank when no messages exist. (target removed in #124) | ux U1
- UX-d91b82aa | macos/Sources/MadeApp/InspectorPanelView.swift:17 | The inspector renders blank when the document is empty or the selection is stale. (resolved by #400 on 2026-10-15: Inspector panel distinguishes empty document with creation actions from unselected object with selection guidance) | ux U1
- UX-3814a375 | macos/Sources/MadeApp/ContentView.swift:198 | The Copilot text field has no focus state on tab switch or after submit. (target removed in #124) | ux U1
- UX-619d2b55 | macos/Sources/MadeApp/NavigatorSidebarView.swift:1 | The UI uses inconsistent nouns for scene entities and inconsistent product names. (see also UX-c45e9d6c) | ux U1
- KERN-14 | macos/Sources/MadeCore/Kernel/KernelClient.swift:38 | `getStats` and `pendingJobId(for:)` have no caller outside tests, so the job counters have no reader. | closure A
- KERN-11 | macos/Sources/MadeCore/Kernel/KernelClient.swift:42 | `cancel(jobId:)` has no caller outside tests. | closure A
- KERN-15 | macos/Sources/MadeCore/Kernel/Types.swift:114 | `KernelRequest.tessellate` has no construction site in Sources. | closure A
- INPUT-1 | macos/Sources/MadeCore/Input/PointerRouter.swift:32 | The touch path of `PointerRouter` and `GestureArbiter` receives no events, because the macOS view feeds only mouse and pen pointers. | closure A
- VIEW-2 | macos/Sources/MadeApp/CADMetalViewRepresentable.swift:479 | The `UIViewRepresentable` branch under `#if os(iOS)` is never compiled, because `Package.swift` lists only macOS. | closure A
- VIEW-18 | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:240 | `updateGrid` and `updateAxes` have no caller, and `setupGrid` runs only from `init`. | closure A
- VIEW-18 | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:170 | `shaderFunctionNames` has a single reference and may be a test seam. | closure A
- VIEW-18 | macos/Sources/MadeCore/Viewport/GridGenerator.swift:23 | `lineCount` has a single reference. | closure A
- INPUT-8 | macos/Sources/MadeCore/Viewport/Camera.swift:162 | `Camera.orbited` and `panned` have a single reference each, because the app calls the static `orbit` and `pan`. | closure A
- VIEW-23 | macos/Sources/MadeCore/Viewport/ViewportState.swift:27 | `statusText` and `unavailableReason` have a single reference, because the app builds its own status strings. | closure A
- VIEW-24 | macos/Sources/MadeCore/Viewport/ViewportState.swift:112 | `CustomMetalDeviceProvider` and `ViewportStateResolver.resolve` have a single reference and may be test seams. | closure A
- AGENT-9 | macos/Sources/MadeCore/Agent/CADTools.swift:23 | `setSnapshotProvider` has a single reference, because the GUI passes the provider through `init`. | closure A
- DSL-11 | macos/Sources/MadeCore/Scripting/CADDSL.swift:124 | `CADShapeBuilder.buildBlock` supports a single shape, and the compiler invokes it, so the probe cannot see its use. | closure A
- KERN-16 | macos/Sources/MadeCore/Kernel/KernelClient.swift:171 | The `importStep` case returns a hard-coded `geometryFailed`, and no caller constructs the request. #82 and #38 track the bridge. | closure B
- (no id) | macos/Tests/MadeCoreTests:1 | Four suites use `.enabled(if:)` guards for Metal availability. The guards are environment checks, not disabled tests. | closure B
- DSN-0b8fce3d | macos/Sources/MadeApp/WorkspaceModel.swift:10 | `WorkspaceModel` and `MadeApp` type `kernelClient` as the concrete actor, while invariant 4 names `KernelClientProtocol`. | design D1
- DSN-acdc5e77 | macos/Sources/MadeCore/Viewport/Camera.swift:98 | Inline axis vectors duplicate `Orientation.groundNormal`, and `Kernel/Geometry.swift:42` and `:74` write inline normals. | design D1
- DSN-aa44aa3e | macos/Sources/MadeApp/MadeApp.swift:16 | The stdio `Task` drops its handle and calls `exit(0)` whatever ended `runStdio`. | design D2
- API-a89664a0 | macos/Sources/MadeCore/Viewport/ViewportState.swift:85 | Three flags and two environment variables name one behavior, and no document mentions them. | api P1
- REQ-2574b26a | macos/Sources/MadeApp/WorkspaceModel.swift:1 | No test target imports MadeApp, so the visibility, selection, and numeric edit criteria of #120 and #122 have no automated check. | requirements R1
- UX-a630e5c4 | macos/Sources/MadeApp/NavigatorSidebarView.swift:20 | An empty document shows a search-no-results view, because the overlay does not check for an empty filter. (resolved by #400 on 2026-10-15: Navigator sidebar prioritizes empty scene guidance with quick actions over search filter) | ux U1
- UX-2413dcfc | macos/Sources/MadeApp/ConsoleDrawerView.swift:18 | Clear Console Logs runs at once with no confirmation. The impact is low, since logs are diagnostic. | ux U1
- UX-c45e9d6c | macos/Sources/MadeApp/NavigatorSidebarView.swift:1 | The UI names the scene entity object, solid, and Scene Outline in different places, and the console three ways. | ux U1
- UX-6c264994 | macos/Sources/MadeApp/ContentView.swift:78 | The MCP toolbar button shows the running state by color only, and the label does not change. | ux U1
- [2026-10-12] `macos/Sources/MadeCore/Agent/CADTools.swift:331`, `handleBooleanOperation` caches its result under a `csg-xxxxxx` ID but registers the document object under a different ID, so removing that object never disposes the cache entry. Found while working on #93. Severity, low.
- [2026-10-12] `macos/Sources/MadeCore/Kernel/KernelClient.swift:43`, `cancel(jobId:)` inserts into `cancelledJobs` even for a job that never reaches `executePending`, so the entry is never removed. Found while working on #93. Severity, low.
- [2026-10-12] `macos/Sources/MadeCore/Agent/CADTools.swift:234`, `cad_set_param` echoes the raw input value and reports success for unknown keys. Found while working on #104. Severity, low.
- [2026-10-12] `macos/Sources/MadeCore/Kernel/KernelClient.swift:135`, the kernel rejects values at or below zero but accepts NaN. Found while working on #104. Severity, low.
- [2026-10-12] `docs/guides/testing.md:19`, the suite table omits `SolidMeshApplierTests`, so it lists fewer suites than the count above it. Found while working on #109. Severity, low, docs.
- [2026-10-12] `macos/Sources/MadeCore/Kernel/XPC/XPCKernelEngine.swift`, `kernelInitFailed` and `workerCrashed` now have producers, which resolves the "defined but never produced" observation logged earlier in this file. Found while working on #245. Severity, none, record only.
- [2026-10-12] `macos/Sources/MadeCore/Agent/CADTools.swift:324-336`, `cad_boolean_operation` registers the kernel output as `csg-…` but adds a document object with a different `ObjectId` and an `.imported` def, so the boolean result is never shown and cannot be regenerated after a kernel restart. Found while planning #245. Severity, functional, non-blocking.
- [2026-10-12] `macos/Sources/MadeCore/Agent/MCPServer.swift:166`, `runStdio` calls `read(upToCount: 65536)`, which blocks until 64 KiB or EOF arrive, so stdio requests are answered only in 64-KiB batches or at EOF. Found while running the #245 manual check. Severity, functional, blocks interactive stdio use.
- [2026-10-12] `macos/Sources/MadeApp/MadeApp.swift:10`, the `--mcp-stdio` document never submits its initial box and cylinder to the kernel, so `cad_boolean_operation` on them returns `unknown-solid` until a kernel restart regenerates them. Found while running the #245 manual check. Severity, functional, non-blocking.
- [2026-10-12] `macos/Tests/MadeCoreTests/ViewportStateTests.swift:44`, `testForceNoGPUSeam` toggles the process-global `MetalDeviceProvider.forceNoDeviceSeam` while sibling tests run in parallel, so it fails intermittently (one in three local runs) and can reject an unrelated commit at the pre-commit hook. Found while committing #331. Severity, flaky test, non-blocking.
- [2026-10-13] `macos/Sources/MadeCore/Kernel/XPC/XPCKernelEngine.swift:185`, when the breaker is open the third restart is never emitted, so a parameter edit rejected with `kernel-init-failed` leaves the document and the viewport out of step until the next edit after the 30-s window. Found while running the #444 manual check for #245. Severity, functional, low.
- [2026-10-13] `macos/Sources/MadeCore/Kernel/XPC/XPCKernelEngine.swift:120`, the relaunch after a second crash inside 10 s waited about 9 s in both observed runs (consistent with the launchd respawn throttle), and the Inspector gives no sign that regeneration is pending. Found while running the #444 manual check for #245. Severity, UX, low.
- [2026-10-13] `docs/architecture/agent-api.md:103`, the -32700 row still says structurally invalid requests "should return -32600 (#95)", which #95 already fixed. Found while working on #96. Severity, docs, low.

- [2026-10-13] `macos/Sources/MadeCore/Agent/InAppAgentController.swift:137-150`, a prompt containing "cylinder" and "width" or "depth" sends a box-only name to `cylinder-1`, which `cad_set_param` now rejects with an error.
  Found while working on #97 set-param validation. Severity, low (the controller has no caller in `MadeApp`).

- [2026-10-13] `macos/Sources/MadeApp/InspectorPanelView.swift:64-74`, the inspector position fields accept values outside `DocumentLimits.position`.
  Found while working on #98 transform validation. Severity, low.

- [2026-10-13] `CLAUDE.md:42`, the text says tests live in 24 files under `macos/Tests/MadeCoreTests`, and the directory now holds 32.
  Found while working on #101 MCP input framing. Severity, low (documentation).

- [2026-10-13] `docs/roadmap/phase-3-native-agent.md:68-77`, the Open Issues table still lists #95 to #101 after their fixes merged.
  Found while working on #101 MCP input framing. Severity, low (documentation).

- [2026-10-14] `macos/Tests/MadeCoreTests/CADToolsTests.swift:709`, `testWindowBoundSetParamAndSetTransformRedrawSolid` binds unused variable `kernel` triggering compiler warning `#NoUsage`.
  Found while working on #129. Severity, low (compiler warning).

- [2026-10-15] `macos/Tests/MadeCoreTests/CADToolsTests.swift:894`, `testWindowBoundSetTransformUpdatesMeshRotation` binds unused variable `doc` triggering compiler warning `#NoUsage`.
  Found while working on #315. Severity, low (compiler warning).

- [2026-10-15] `macos/Tests/MadeAppTests/SettingsViewTests.swift:21,25`, `#expect(view != nil)` compares non-optional `some View` to nil triggering compiler warnings.
  Found while working on #400. Severity, low (compiler warning).

- [2026-10-16] `macos/Tests/MadeCoreTests/MCPServerTests.swift:436`, `testStopClosesConnectedClientAndSubsequentToolsCallReceivesNoResponse` intermittently fails with empty `initResp` under full-suite parallel execution due to a 2-second connection timeout under CPU load.
  Found while working on #397. Severity, low (flaky test).

- [2026-10-17] `macos/Sources/MadeCore/Scene/ConstraintSolver.swift:526-529`, `SketchConstraint.Kind.coincident` only evaluates `entityA.startPoint ?? centerPoint` against `entityB.startPoint ?? centerPoint`, with no support for `endPoint` pairing or midpoint selection.
  Found while working on #200. Severity, low (functional constraint expressiveness limitation).


## Audit run 20261017-112015

Date: 2026-10-17. The run parked 84 findings, in source order and unranked. Format: ID, file:line, finding, source pass.

- AGENT-10 | macos/Sources/MadeCore/Agent/InAppAgentController.swift:21 | A person can ask the in-app Copilot to add, measure or edit solids. public final class InAppAgentController: @unchecked Sendable  Consumer search: 'InAppAgentController' occurs once in Sources (the declaration); the Copilot tab was removed in #124. | closure A
- DOC-20 | macos/Sources/MadeCore/Scene/DocumentModel.swift:1601 | A person can export or reference geometry in a user coordinate system. public func exportTransform(coordinateSystemId: UUID) -> Transform?  Consumer search: 0 callers outside tests for both. | closure A
- DOC-28 | macos/Sources/MadeCore/Scene/DocumentModel.swift:1207 | A person can step the rollback marker one feature at a time. public func rollBackOne() -> Result<Void, DocumentMutationError>  0 callers outside tests (no test file references them either). | closure A
- (no id) | macos/Sources/MadeApp/CADMetalViewRepresentable.swift:1223 | Coordinator.handleCancel(button:). func handleCancel(button: MouseButton) { _ = pointerRouter.handle(.cancel(...)); . | closure A
- DSL-12 | macos/Sources/MadeCore/Scripting/PartRuntime.swift:94 | PartRuntime.evaluateScriptFile (:94), bundledTypeDefinitions (:47). public func evaluateScriptFile(at fileURL: URL, ...) async -> PartRuntimeResult<PartScriptEvaluation>  1 occurrence in Sources and 0 in Tests; matrix DSL-12 cites :94 as the entry point but PartReloadController uses evaluatePartFile. | closure A
- WORKSPACE-3 | macos/Sources/MadeApp/WorkspaceModel.swift:263 | isolateSelectionFilter (:263), resetDisplaySettings (:526), toggleFeatureVisibility (:2214), setDocumentSettings (:2288), setLastRegenerationDuration (:218). func isolateSelectionFilter(_ filter: SelectionFilter) { . | closure A
- DSL-13 | macos/Sources/MadeCore/Scene/PartReloadController.swift:182 | stopAll (:182), nextReload (:234), settleAll (:255), watchedSolidIds (:46), conflatedSavesCount (:42, written :314, never read). public func stopAll()  stopAll has 3 test files but 0 Sources callers, so file watchers are not stopped on document close or termination by this API. | closure A
- UI-15 | macos/Sources/MadeApp/Document/MadeDocument.swift:5 | MadeDocument: FileDocument. public struct MadeDocument: FileDocument  'MadeDocument' occurs once in Sources; no DocumentGroup or fileExporter uses it (grep DocumentGroup/fileExporter/fileImporter in MadeApp returns 0). | closure A
- KERN-23 | macos/Sources/MadeCore/Scene/ReferenceResolver.swift:209 | ReferenceResolver.resolveAll (:209), TopologicalResolver.resolveSubshape (:325), Feature.inputReferences (Feature.swift:542), SketchEntity.withEndpoints (:305) / updatingConstruction (:309), DocumentModel.insertObject (:2731), KernelResponse.triangleRanges(forFace:) (Types.swift:246), DatumEntities. | closure A
- AGENT-17 | macos/Sources/MadeCore/Agent/MCPServer.swift:62 | MCPServer.lastError (:62), AnyCodableValue.arrayValue (MCPProtocol.swift:193), DocumentMigrator.register (DocumentMigration.swift:42), SketchDOFStatus.isUnderConstrained / isFullyConstrained / isOverConstrained (SketchDOFStatus.swift:72-84), Platform UniversalPlatform (PlatformShim.swift:18), Licens. | closure A
- AGENT-11 | macos/Sources/MadeCore/Scene/ConstraintSolverActor.swift:4 | ConstraintSolverActor. public actor ConstraintSolverActor  Type name occurs once in Sources; ConstraintSolver.solve is called synchronously from WorkspaceModel.swift:1044, :1069, :1100 and CommandSession.swift:1591. | closure A
- (no id) | macos/Sources/MadeCore/Kernel/KernelClient.swift:41 | A person can export STEP. default extension returns .failure geometryFailed 'STEP export not supported by this client'; real engines override (LocalKernelEngine.swift:232 calls OCCTEngine.exportStep; KernelClient.swift:72 forwards to engine; caller WorkspaceModel.swift:2044). | closure B
- (no id) | macos/Sources/MadeCore/Kernel/KernelEngine.swift:50 | A person can export STEP. default extension returns .failure geometryFailed 'STEP export not supported by this engine'; LocalKernelEngine overrides. | closure B
- (no id) | macos/Tests/MadeCoreTests/StdioProcessTests.swift:15 | MCP stdio server process tests. @Test(.enabled(if: binary != nil, "MadeApp executable not built")) at lines 15, 51, 67; skipped when MadeApp is unbuilt, an environment guard; stdio server (--mcp-stdio) loses process-level coverage in that case. | closure B
- (no id) | macos/Tests/MadeCoreTests | GPU-dependent render tests. Metal 4 gate summary row: MetalTestSupport.isMetal4Available used in 15 files; plus direct gates ShaderLibraryTests.swift:12 and ViewportStateTests.swift:63 'Metal unavailable'; documented environment guard; pre-push hook blocks on skips. | closure B
- (no id) | macos/Sources/MadeCore/Agent/InAppAgentController.swift:21 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Agent/MCPServer.swift:21 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Input/GestureArbiter.swift:41 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Input/PointerRouter.swift:20 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Scene/PartFileWatcher.swift:145 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Scripting/PartRuntime.swift:8 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Scripting/PartRuntime.swift:318 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Viewport/RenderLoop.swift:11 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Viewport/RenderLoop.swift:45 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Viewport/RenderTypes.swift:243 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Viewport/ViewportState.swift:104 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Viewport/ViewportState.swift:158 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:11 | Invariant 7 thread-safe execution. @unchecked Sendable with no stated reason comment on the preceding lines (invariant 7 known gap, DSN-1eb23904). | closure B
- (no id) | macos/Sources/MadeApp/CADMetalViewRepresentable.swift:386 | Invariant 7 thread-safe execution. public class Coordinator: NSObject, @unchecked Sendable with no stated reason comment (@MainActor on prior line); invariant 7 known gap, DSN-1eb23904. | closure B
- (no id) | macos/Sources/MadeApp/CADMetalViewRepresentable.swift:1452 | Invariant 7 thread-safe execution. public class Coordinator: NSObject, @unchecked Sendable with no stated reason comment (@MainActor on prior line); invariant 7 known gap, DSN-1eb23904. | closure B
- (no id) | macos/Tests/MadeCoreTests | Test support types. 8 test doubles marked @unchecked Sendable without reason (RecordingKernelClient, MockKernelClient, TestResponseCollector, TestMCPModel, ResponseOnlyEncoder, RecordingViewSnapshotProvider, PluginSkillSnapshotProvider, StubInvalidationTarget); test-only, not a user path. | closure B
- INPUT-13 | macos/Sources/MadeApp/CADMetalViewRepresentable.swift:64 | A user sees the viewport cursor follow the active tool (arrow, crosshair, open hand, resize) and a closed hand during a pan drag. No test references cursor(for:) or the closed-hand pan cursor. | closure C
- UI-36 | macos/Sources/MadeApp/MCPServerPopoverView.swift:17 | A user can copy a Claude Desktop config snippet from the MCP popover; the snippet launches `swift run ... --mcp-stdio`, which drives a separate document, not th. No test file names MCPServerPopover or configSnippet. | closure C
- UI-37 | macos/Sources/MadeApp/MCPServerPopoverView.swift:27 | A user can read the registered CAD tool names and the TCP address in the MCP popover. No test file names MCPServerPopover. | closure C
- DSL-15 | macos/Sources/MadeApp/WorkspaceModel.swift:828 | (new) A person can open a part file at launch by passing a .part.ts, .part.js or .made path as a command-line argument or by setting MADE_PART_FILE. No test references MADE_PART_FILE or the launch-argument path. | closure C
- UI-33 | macos/Sources/MadeApp/ConsoleDrawerView.swift:52 | A user can clear the console log. EmptyStatesTests.testViewInstantiationUnderEmptyAndPopulatedStates calls clearLogs() as setup and asserts nothing about the result. | closure C
- AGENT-10 | macos/Sources/MadeCore/Agent/InAppAgentController.swift:57 | A user can ask the Copilot to measure `box-1` or `cylinder-1` (keywords "measure", "volume", "dimensions of"); the controller has no caller since #124. No test file references InAppAgentController, and the controller has no caller since #124. | closure C
- AGENT-11 | macos/Sources/MadeCore/Agent/InAppAgentController.swift:86 | A user can ask the Copilot to add a box, with up to three numbers for width, depth and height, at a random XY position. No test file references InAppAgentController, and the controller has no caller since #124. | closure C
- AGENT-12 | macos/Sources/MadeCore/Agent/InAppAgentController.swift:65 | A user can ask the Copilot to subtract `cylinder-1` from `box-1` (keywords "subtract", "cut", "drill"); ids are fixed and the result is not drawn. No test file references InAppAgentController, and the controller has no caller since #124. | closure C
- AGENT-13 | macos/Sources/MadeCore/Agent/InAppAgentController.swift:75 | A user can ask the Copilot to union `box-1` and `cylinder-1` (keywords "union", "combine", "fuse"); ids are fixed and the result is not drawn. No test file references InAppAgentController, and the controller has no caller since #124. | closure C
- AGENT-14 | macos/Sources/MadeCore/Agent/InAppAgentController.swift:112 | A user can ask the Copilot to add a cylinder, with radius and height numbers, at a random XY position. No test file references InAppAgentController, and the controller has no caller since #124. | closure C
- AGENT-15 | macos/Sources/MadeCore/Agent/InAppAgentController.swift:134 | A user can ask the Copilot to set width, depth, height or radius on `box-1` or `cylinder-1` (keywords "width", "wide", "depth", "height", "tall", "radius"). No test file references InAppAgentController, and the controller has no caller since #124. | closure C
- AGENT-16 | macos/Sources/MadeCore/Agent/InAppAgentController.swift:178 | A user can ask the Copilot to show the scene (keywords "scene", "list", "show", "what"). No test file references InAppAgentController, and the controller has no caller since #124. | closure C
- VIEW-3 | macos/Sources/MadeApp/CADMetalViewRepresentable.swift:279 | A user gets on-demand rendering only (`isPaused = true`, `enableSetNeedsDisplay = true`), so the GPU stays idle until a redraw is requested. isPaused and enableSetNeedsDisplay (invariant 2) are never asserted. | closure C
- VIEW-7 | macos/Sources/MadeCore/Viewport/MetalRenderer+MeshInstall.swift:7 | A user sees kernel meshes uploaded to `.storageModeShared` Metal buffers. .storageModeShared (invariant 6) is never asserted on the uploaded buffers. | closure C
- VIEW-20 | macos/Sources/MadeApp/ContentView.swift:136 | A user can zoom in, zoom out, zoom to fit the visible solids, and reset the view from the toolbar or with =, -, F and H. Only the shortcut constants and the framing math are tested. | closure C
- KERN-19 | macos/Sources/MadeCore/Kernel/OCCTEngine.swift:294 | A user can export or import STEP and IGES files, apply B-Rep fillets, chamfers and draft angles, reference sub-elements via persistent topological naming, verif. Chamfer, draft angle and IGES import or export have no test. | closure C
- KERN-20 | macos/Sources/MadeCore/Kernel/KernelClient+Default.swift:19 | A user keeps the window and document when the geometry kernel crashes; the kernel runs in an XPC service, meshes return as shared memory, and the app relaunches. KernelXPCTests covers the restart and breaker. | closure C
- KERN-23 | macos/Sources/MadeCore/Kernel/TopologicalResolver.swift:18 | (new) A person gets stable sub-element (face, edge, vertex) references that survive regeneration, resolved against generation history with geometric-signature f. No test is named for the geometric-signature tie-breaker required by ADR-D3. | closure C
- AGENT-7 | macos/Sources/MadeCore/Agent/CADTools.swift:621 | An agent can measure a box, cylinder, sphere, cone, torus, or wedge for bounds, volume and surface area from its parameters (imported solids return the name onl. The name-only result for an imported solid has no test. | closure C
- AGENT-21 | macos/Sources/MadeCore/Agent/MCPServer.swift:452 | An agent can invoke any registered tool by name with arguments (missing name gives `-32602`; unknown tool gives an `isError` result). No test calls an unknown tool name and checks for an isError result. | closure C
- AGENT-25 | macos/Sources/MadeApp/WorkspaceModel.swift:286 | An agent can drive the CAD session in the running GUI window from an external MCP client: the GUI registry shares the window's document, kernel and renderer, so. MCPServerTests.testWindowBoundTCPClientAddsEditsMovesAndCombinesSolids uses a window-bound stub. | closure C
- DOC-12 | macos/Sources/MadeApp/MadeCommands.swift:43 | A user can export or load imported B-Rep solids from STEP or IGES into the scene via File / Solid menu commands and retain data across kernel restarts. IGES has no test. | closure C
- UI-35 | macos/Sources/MadeApp/MCPServerPopoverView.swift:32 | A user can start or stop the in-app MCP server from the MCP popover switch and read its address (127.0.0.1:9820). MCPServerTests covers the server. | closure C
- DSN-99ed47b4 | macos/Sources/MadeCore/Scene/DocumentModel.swift:923 | DocumentModel.init comment (dangling reference). The comment reads "Initialize with default box and cylinder matching document.svelte.ts". (resolved by #576 on 2026-10-19: removed reference to document.svelte.ts) | closure D
- DSN-9b4d1b20 | docs/architecture/adr/ADR-D1-canonical-geometry-kernel.md:16 | Decision 3: no OCCT or Euclid types past the kernel boundary. ADR-D1 decision 3 says no OCCT or Euclid types leak past the kernel boundary into MadeCore. | design D1
- DSN-2bd10d0f | macos/Sources/MadeCore | directory import cycle. 11 nodes (9 MadeCore directories, MadeApp, MadeKernelService) and 25 type-reference edges. | design D2
- DSN-5da57abd | macos/Sources/MadeCore/Kernel/KernelClient.swift:77 | KernelClient.cancel / cancelledJobs. cancel(jobId:) runs 'if executingJobs.contains(jobId) { . | design D2
- API-6e7a62c9 | macos/Sources/MadeCore/Agent/CADTools.swift:375 | CADToolRegistry.handleRollback. Solid-reference argument key: 'id' in 7 of 9 tools that reference a solid (set_param, set_transform, remove_solid, measure, reload, get_diagnostics, verify); boolean uses solidA/solidB (two operands, accepted); cad_rollback uses 'solidId' and also reads an undocumente. | api P1
- API-aff57cf5 | macos/Sources/MadeCore/Scene/Body.swift:46 | Body (synthesized Decodable). Body declares seven stored properties with no init(from:) (Body.swift:46-55), so every key is required on decode. | api P2
- API-af53dc8e | macos/Sources/MadeCore/Serialization/MadePackage.swift:96 | schemaVersion in manifest.json and document.json. schemaVersion is stored in both files. | api P2
- API-61ffae39 | macos/Sources/MadeCore/Serialization/DocumentMigration.swift:92 | MigrationV1ToV2.migrate. The only migration step (1 of 1) decodes document objects with the live types: JSONDecoder().decode([SceneObject].self ...) and Feature(from: $0) (DocumentMigration.swift:98-100). | api P2
- API-58377827 | docs/architecture/document-model.md:284 | manifest.json description. document-model.md:284 states `schemaVersion: 1` for manifest.json; MadeManifest.currentSchemaVersion is 2 (MadeManifest.swift:5) and MigrationV1ToV2 exists. | api P2
- REQ-4fde014f | macos/Sources/MadeApp/CADMetalViewRepresentable.swift:1170 | onHoverSketchRegion. Code: 'parent.onHoverSketchRegion?(hitRegion?.id)' (:1170) feeds WorkspaceModel.setHoveredSketchRegion, which installs a highlight mesh via updateRegionHighlightMesh (:180). | requirements R1
- UX-b48164df | macos/Sources/MadeApp/NavigatorSidebarView.swift | object-solid-remove-console naming. Same action named three ways: Edit menu Button("Delete") (MadeCommands.swift:78), Solid menu Button("Delete Solid") (MadeCommands.swift:274), navigator context menu Button("Delete") with dialog "Delete <name>?", and Inspector "Delete Constraint". | ux U1
- UX-69efca76 | macos/Sources/MadeApp/ContentView.swift:84 | MCP toolbar Button state. Label("MCP Server", systemImage: "sparkles").foregroundStyle(workspace.isMCPServerRunning ? Color.green : Color.primary); only .help() carries "running"/"off", and no .accessibilityValue is set, so VoiceOver does not announce the state. | ux U1
- UX-d1700419 | macos/Sources/MadeApp/ViewCubeOverlayView.swift:42 | ViewCubeOverlayView.onTapGesture. .onTapGesture { location in ViewCube.hitTest(...) } over a Canvas; no accessibility element for the cube regions. | ux U1
- UX-62dce945 | macos/Sources/MadeApp/ViewCubeOverlayView.swift:125 | homeButton. Button { workspace.resetView() } label: { Image(systemName: "house"). | ux U1
- UX-388c9bb9 | macos/Sources/MadeApp/WorkspaceModel.swift:2361 | recomputeSolid/loading. Task { . | ux U1
- UX-8a502261 | macos/Sources/MadeApp/CommandPanelView.swift:4 | CommandPanelView/focus. The panel (HUD overlay or inspector embed) declares no @FocusState and no .defaultFocus; the first text/number input is not focused on open and focus is not returned to the viewport on OK or Cancel (.keyboardShortcut handles the buttons only). | ux U1
- UX-ef4404a2 | macos/Sources/MadeApp | summary. About 248 interactive control declarations (Button, Toggle, Picker, TextField, Slider, Stepper, ColorPicker, CommitNumberField, DisclosureGroup) across 20 MadeApp files; 5 .accessibilityIdentifier calls exist (SnapOverlayView 1, ViewportStatusBar 4). | ux U1
- QA-UITEST-02 | .claude/audit/20261017-112015/xcuitest-proposal.md | Edit a box width in the Inspector number field and see the Navigator summary update. Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-UITEST-03 | .claude/audit/20261017-112015/xcuitest-proposal.md | Undo and redo an added box through the Edit menu. Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-UITEST-04 | .claude/audit/20261017-112015/xcuitest-proposal.md | Save to a temporary package, start a new document, reopen it, and see the same rows. Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-UITEST-05 | .claude/audit/20261017-112015/xcuitest-proposal.md | Recover unsaved changes from a seeded recovery record through the alert. Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-UITEST-06 | .claude/audit/20261017-112015/xcuitest-proposal.md | Start the MCP listener from the toolbar popover and see the running state. Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-UITEST-07 | .claude/audit/20261017-112015/xcuitest-proposal.md | Source check that every queried accessibility identifier exists in Sources/MadeApp. Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-VPT-02 | .claude/audit/20261017-112015/xcuitest-proposal.md | Orbit drag across a solid changes the camera and keeps the selection, with mode locked to navigate (invariant 8). Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-VPT-03 | .claude/audit/20261017-112015/xcuitest-proposal.md | Scroll to zoom at the cursor moves the camera target toward the pointer. Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-VPT-04 | .claude/audit/20261017-112015/xcuitest-proposal.md | Viewport element screenshot at a fixed window size matches a coarse golden (Metal 4). Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-VPT-05 | .claude/audit/20261017-112015/xcuitest-proposal.md | Snap indicator appears at a box vertex during a drag (invariant 9). Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-VPT-06 | .claude/audit/20261017-112015/xcuitest-proposal.md | Add a box from the menu and see one model render with reason=model, then a flat count at idle. Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-VPT-07 | .claude/audit/20261017-112015/xcuitest-proposal.md | Gizmo drag on a selected box moves it, and the Inspector position updates. Follow-on slice of ADR-D10. | audit 20261017-112015
- QA-VPT-08 | .claude/audit/20261017-112015/xcuitest-proposal.md | Self-hosted Apple-silicon CI job for layers 2 to 4, restricted to non-fork events. Follow-on slice of ADR-D10. | audit 20261017-112015
- (no id) | macos/Sources/MadeApp/InspectorPanelView.swift:1200 | Sketch region area is formatted as hardcoded mm² without checking document unit preferences. | execution #556
- (no id) | macos/Sources/MadeCore/Serialization/MadePackage.swift:173 | URL(fileURLWithPath: "assets/\($0)") constructs a file URL relative to current working directory instead of package root. | execution #559
- (no id) | macos/Tests/MadeAppTests/SettingsViewTests.swift:21 | Comparing non-optional value of type 'some View' to nil always returns true. | execution #563
- (no id) | macos/Tests/MadeAppTests/SketchConstructionAppTests.swift:71 | Under parallel test suite execution, explicit regenerateIncremental races with undo recompute causing sporadic conflation failure. | execution #571
- (no id) | macos/Tests/MadeAppTests/SketchOperationsAppTests.swift:207 | Under parallel test execution, testTrimRegeneratesDownstreamExtrude sleep window can race with background recompute. | execution #154
