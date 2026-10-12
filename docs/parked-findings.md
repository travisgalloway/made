# Parked findings

Date: 2026-10-11
Scope: macos/
Audit run: 20261011-195134

The list holds 57 parked findings, in source order and unranked. Format: ID, file:line, finding, source pass.

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
- DSN-4a0f328f | docs/architecture/invariants.md:13 | The DSL operators call `EuclidEngine` synchronously on the caller thread, and no mechanical guard enforces the kernel-only CSG rule. | design D1
- DSN-06c119fb | macos/Sources/MadeCore/Agent/MCPServer.swift:85 | `try?` on the stdin read treats an error as end of input and exits with success, and the write failure at :102 is dropped. (superseded by decision DSN-2a85e7de on 2026-10-11) | design D2
- DSN-cbc7f8bb | macos/Sources/MadeCore/Agent/MCPServer.swift:76 | `encodeResponse` returns nil on an encoding error, so the client receives no reply and the cause is discarded. (superseded by decision DSN-2a85e7de on 2026-10-11) | design D2
- DSN-9e901d18 | macos/Sources/MadeApp/WorkspaceModel.swift:152 | The `Task` in `recomputeSolid` drops its handle and ignores the failure branch. | design D2
- DSN-a46151d3 | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:56 | Viewport references the Agent directory through `SnapshotProvider`, which sits above it in the assumed layer order. | design D2
- DSN-d809c2cf | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:36 | Viewport references the Scene directory through `Transform`, which sits above it in the assumed layer order. | design D2
- DSN-dbd85a54 | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:64 | `MetalRenderer.meshes` is mutated on the main actor and iterated off it, grouped under the decision DSN-1eb23904. (ticketed as #131 on 2026-10-11) | design D2
- API-24a1c7aa | macos/Sources/MadeCore/Agent/CADTools.swift:143 | An unknown tool name returns an `isError` result where MCP specifies a -32602 protocol error. | api P1
- API-0e69ca70 | macos/Sources/MadeCore/Agent/CADTools.swift:149 | `cad_get_scene` returns every object in one response with no limit or cursor. | api P1
- API-9d5c8a37 | macos/Sources/MadeCore/Agent/CADTools.swift:149 | The object type key is `kind` in one tool and `type` in two others. | api P1
- REQ-95ea66a6 | macos/Tests/MadeCoreTests/OrientationTests.swift:1 | No test references `Orientation`, so issue #61 has no Z-up regression test. (contradicted on 2026-10-11: `OrientationTests` holds 4 tests) | requirements R1
- REQ-ae1cd1ec | macos/Tests/MadeCoreTests/GestureArbiterTests.swift:1 | No test adds a second pointer after the lock to assert that the mode holds until release. | requirements R1
- REQ-e73808df | macos/Tests/MadeCoreTests/CameraTests.swift:171 | No test references `PointerRouter` or `RouterEvent`, so pointer type routing is untested. (contradicted on 2026-10-11: `testPointerRouterClickVsDragThreshold` covers it) | requirements R1
- REQ-2011a068 | macos/Tests/MadeCoreTests/KernelClientTests.swift:1 | No test requests two solids to assert that only the changed solid re-tessellates. | requirements R1
- UX-9d5cdfe3 | macos/Sources/MadeApp/ContentView.swift:155 | The Copilot transcript pane is blank when no messages exist. (target removed in #124) | ux U1
- UX-d91b82aa | macos/Sources/MadeApp/InspectorPanelView.swift:17 | The inspector renders blank when the document is empty or the selection is stale. (target removed in #124; the Inspector now shows an empty state at lines 17-21) | ux U1
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
- UX-a630e5c4 | macos/Sources/MadeApp/NavigatorSidebarView.swift:20 | An empty document shows a search-no-results view, because the overlay does not check for an empty filter. | ux U1
- UX-2413dcfc | macos/Sources/MadeApp/ConsoleDrawerView.swift:18 | Clear Console Logs runs at once with no confirmation. The impact is low, since logs are diagnostic. | ux U1
- UX-c45e9d6c | macos/Sources/MadeApp/NavigatorSidebarView.swift:1 | The UI names the scene entity object, solid, and Scene Outline in different places, and the console three ways. | ux U1
- UX-6c264994 | macos/Sources/MadeApp/ContentView.swift:78 | The MCP toolbar button shows the running state by color only, and the label does not change. | ux U1
- [2026-10-12] `macos/Sources/MadeCore/Agent/CADTools.swift:331`, `handleBooleanOperation` caches its result under a `csg-xxxxxx` ID but registers the document object under a different ID, so removing that object never disposes the cache entry. Found while working on #93. Severity, low.
- [2026-10-12] `macos/Sources/MadeCore/Kernel/KernelClient.swift:43`, `cancel(jobId:)` inserts into `cancelledJobs` even for a job that never reaches `executePending`, so the entry is never removed. Found while working on #93. Severity, low.
