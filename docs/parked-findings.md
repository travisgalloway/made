# Parked findings

Date: 2026-10-10
Scope: macos/
Audit run: 20261010-114045

The list holds 33 parked findings, in source order and unranked. Format: ID, file:line, finding, source pass.

- INPUT-7 | macos/Sources/MadeCore/Input/Snapping.swift:57 | `screenPixelDistance` has a single reference in Sources and no caller. | closure A
- KERN-7 | macos/Sources/MadeCore/Kernel/Geometry.swift:7 | `NativeGeometryGenerator.generateBox` has no reference outside its declaration. | closure A
- KERN-8 | macos/Sources/MadeCore/Kernel/Geometry.swift:89 | `NativeGeometryGenerator.generateCylinder` has no caller. | closure A
- UI-23 | macos/Sources/MadeCore/Platform/PlatformShim.swift:18 | `UniversalPlatform.isIPad` and `isMac` have no reference anywhere in Sources. | closure A
- (no id) | macos/Sources/MadeCore/Kernel/Types.swift:60 | `KernelErrorCode.kernelInitFailed`, `workerCrashed`, and `KernelResult.isSuccess` each have a single reference. | closure A
- (no id) | macos/Sources/MadeCore/Agent/MCPProtocol.swift:77 | `JSONRPCErrorPayload.invalidRequest` and `AnyCodableValue.boolValue` and `arrayValue` each have a single reference. | closure A
- DSL-1 | macos/Sources/MadeCore/Scripting/CADDSL.swift:7 | The public `CADShape` DSL has no consumer in MadeApp or in other MadeCore files. | closure A
- (no id) | macos/Sources/MadeCore/Viewport/Orientation.swift:9 | `groundNormal` has a single reference. | closure A
- (no id) | macos/Sources/MadeCore/Viewport/RenderLoop.swift:5 | No call site passes the `InvalidateReason` cases `resize`, `camera`, or `interaction`. | closure A
- (no id) | docs/architecture/invariants.md:28 | The matrix cites KernelClientTests for the 60 ms window, and the audit did not read the 4 tests in full to confirm the assertion. | closure D
- (no id) | docs/roadmap/phase-4-cad-depth.md:8 | The 4.1 and 4.2 numbering differs from the open issues #39 and #83, and the criteria cite behavior not yet built. | closure D
- (no id) | docs/roadmap/backlog-migration.md:75 | Section 4 says epics #82 to #85 were created on GitHub, and the audit did not verify the milestone field of each. | closure D
- (no id) | CLAUDE.md:13 | The doc index lines resolve, and no docs/contracts/ directory exists for any document to declare. | closure D
- (no id) | README.md:23 | The claim of 33 tests matches the count of `func test` over the 8 test files. | closure D
- (no id) | docs/archive/web-prototype | README.md and docs/README.md link to the archive, and the target file exists. | closure D
- DSN-4a0f328f | docs/architecture/invariants.md:13 | The DSL operators call `EuclidEngine` synchronously on the caller thread, and no mechanical guard enforces the kernel-only CSG rule. | design D1
- DSN-06c119fb | macos/Sources/MadeCore/Agent/MCPServer.swift:85 | `try?` on the stdin read treats an error as end of input and exits with success, and the write failure at :102 is dropped. | design D2
- DSN-cbc7f8bb | macos/Sources/MadeCore/Agent/MCPServer.swift:76 | `encodeResponse` returns nil on an encoding error, so the client receives no reply and the cause is discarded. | design D2
- DSN-9e901d18 | macos/Sources/MadeApp/ContentView.swift:272 | The `Task` in `recomputeSolid` drops its handle and ignores the failure branch. | design D2
- DSN-a46151d3 | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:56 | Viewport references the Agent directory through `SnapshotProvider`, which sits above it in the assumed layer order. | design D2
- DSN-d809c2cf | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:36 | Viewport references the Scene directory through `Transform`, which sits above it in the assumed layer order. | design D2
- DSN-dbd85a54 | macos/Sources/MadeCore/Viewport/MetalRenderer.swift:64 | `MetalRenderer.meshes` is mutated on the main actor and iterated off it, grouped under the decision DSN-1eb23904. | design D2
- API-24a1c7aa | macos/Sources/MadeCore/Agent/CADTools.swift:143 | An unknown tool name returns an `isError` result where MCP specifies a -32602 protocol error. | api P1
- API-0e69ca70 | macos/Sources/MadeCore/Agent/CADTools.swift:149 | `cad_get_scene` returns every object in one response with no limit or cursor. | api P1
- API-9d5c8a37 | macos/Sources/MadeCore/Agent/CADTools.swift:149 | The object type key is `kind` in one tool and `type` in two others. | api P1
- REQ-95ea66a6 | macos/Tests/MadeCoreTests:1 | No test references `Orientation`, so issue #61 has no Z-up regression test. | requirements R1
- REQ-ae1cd1ec | macos/Tests/MadeCoreTests/GestureArbiterTests.swift:1 | No test adds a second pointer after the lock to assert that the mode holds until release. | requirements R1
- REQ-e73808df | macos/Tests/MadeCoreTests:1 | No test references `PointerRouter` or `RouterEvent`, so pointer type routing is untested. | requirements R1
- REQ-2011a068 | macos/Tests/MadeCoreTests/KernelClientTests.swift:1 | No test requests two solids to assert that only the changed solid re-tessellates. | requirements R1
- UX-9d5cdfe3 | macos/Sources/MadeApp/ContentView.swift:155 | The Copilot transcript pane is blank when no messages exist. | ux U1
- UX-d91b82aa | macos/Sources/MadeApp/ContentView.swift:97 | The inspector renders blank when the document is empty or the selection is stale. | ux U1
- UX-3814a375 | macos/Sources/MadeApp/ContentView.swift:198 | The Copilot text field has no focus state on tab switch or after submit. | ux U1
- UX-619d2b55 | macos/Sources/MadeApp/ContentView.swift:88 | The UI uses inconsistent nouns for scene entities and inconsistent product names. | ux U1
