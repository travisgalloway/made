# Requirements review, 2026-11-09

## Scope

Date: 2026-11-09
Repository: made (/Users/travisgalloway/github/made; GitHub repository travisgalloway/made)
Scope tokens: macos/ (Swift 6 package, branch feat/cad-cae-research-upgrades), lens requirements
Audit run: 20261109-140405

Coverage.

- R1 (closed issues and Shipped matrix rows): 2,330 acceptance criteria across 257 closed issues with checklists (8 closed issues had `no-criteria`, 37 closed issues were superseded/not-planned) and 244 `Shipped` rows in `docs/feature-matrix.md`. 33 rows.

## Findings

### REQ-f1f045b8 (#332)

- Location: macos/Sources/MadeCore/Scene/DSLFeatureDecomposer.swift:196
- Kind: 
- Severity: high
- Verdict: CONFIRMED
- Evidence: DSLFeatureDecomposer.swift:196 throws DSLDecompositionError.unsupportedNode("revolve is not yet supported in linear feature history (BL-PRT-02)") when decomposing .revolve or .revolveSolid nodes into features, contradicting closed issue #332 DoD ("DSL produces features (sketch, extrude, fillet with selectors) rather than raw meshes, so DSL output is editable in the GUI") and BL-PRT-02 (#290, closed as completed).
- Disposition: ticketed as #715; commented on closed #332

### REQ-eef49e9d (DSL-16)

- Location: docs/feature-matrix.md:199
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Row DSL-16 in docs/feature-matrix.md claims targeting DSL output directly to the document feature list as editable features in the GUI is Shipped (#332), but DSLFeatureDecomposer throws unsupportedNode on revolve and revolveSolid shapes.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-9c77ee29 (#309)

- Location: macos/Sources/MadeCore/Scene/DocumentModel.swift:2927
- Kind: 
- Severity: high
- Verdict: CONFIRMED
- Evidence: DocumentModel.exportTransform(coordinateSystemId:) computes a rigid transform matrix for export referencing a user coordinate system (UCS) per #309 DoD, but neither STLExporter, ThreeMFExporter, STEP export, nor CAE simulation routines call it or accept a coordinate system parameter. The only call site across the entire repository is unit test DatumEntitiesTests.swift:413.
- Disposition: ticketed as #716; commented on closed #309

### REQ-d78ed634 (DOC-20)

- Location: docs/feature-matrix.md:214
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Row DOC-20 in docs/feature-matrix.md claims datum coordinate systems (UCS) "serve as modeling references, alignment guides, and export frames" as Shipped (#309), but neither STLExporter, ThreeMFExporter, nor STEP export routines support exporting relative to a UCS.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-b5407c29 (#209)

- Location: macos/Sources/MadeCore/Kernel/KernelClient.swift:31
- Kind: 
- Severity: high
- Verdict: CONFIRMED
- Evidence: DRW-2 and issue #209 DoD require computing 2D drawing hidden line removal asynchronously through the kernel client service, but all 10 production drawing projection call sites in WorkspaceModel call HLREngine.computeHLR directly in-process synchronously, while XPCKernelEngine.computeHLR returns a hardcoded error ("HLR not supported by this engine" at KernelEngine.swift:54).
- Disposition: parked (docs/parked-findings.md; all 10 production drawing projection sites call HLREngine.computeHLR directly in-process)

### REQ-9e023116 (#164)

- Location: macos/Sources/MadeCore/Scene/AssemblyConstraintSolverActor.swift:4
- Kind: 
- Severity: high
- Verdict: CONFIRMED
- Evidence: Issue #164 and ADR-D4 require solving 3D assembly constraint systems asynchronously off the main thread in a background actor (AssemblyConstraintSolverActor), but WorkspaceModel and CommandSession invoke AssemblyConstraintSolver.solve synchronously on the main thread; AssemblyConstraintSolverActor has 0 call sites across all Sources and is only instantiated in AssemblyConstraintSolverTests.swift:425.
- Disposition: ticketed as #717; commented on closed #164

### REQ-4c7456af (#37)

- Location: macos/Sources/MadeCore/Scene/ConstraintSolverActor.swift:4
- Kind: 
- Severity: high
- Verdict: CONFIRMED
- Evidence: Invariant 1 and issue #37 DoD require solving 2D sketch constraint systems asynchronously off the main thread in a background actor, but WorkspaceModel and CommandSession call ConstraintSolver.solve synchronously; ConstraintSolverActor has 0 call sites across all Sources and is only instantiated in unit tests (ConstraintSolverTests.swift:231, SolverRegressionCorpusTests.swift:935).
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-acad2864 (#161)

- Location: macos/Sources/MadeApp/Document/MadeDocument.swift:5
- Kind: 
- Severity: high
- Verdict: CONFIRMED
- Evidence: UI-15 claims opening, editing, and saving CAD packages using standard SwiftUI DocumentGroup architecture, but MadeApp declares WindowGroup with manual AppKit NSOpenPanel and NSSavePanel sheet workflows; no DocumentGroup or SwiftUI fileExporter/fileImporter modifier references MadeDocument in Sources.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-9e341fb2 (#85)

- Location: macos/Sources/MadeCore/Scene/PartReloadController.swift:182
- Kind: 
- Severity: high
- Verdict: PLAUSIBLE
- Evidence: DSL-13 and #85 specify stopping background file system watchers when closing a document, but WorkspaceModel only calls stopWatching(id:) upon single-solid deletion; closing or resetting a document never calls stopAll(), leaving FSEvent file watchers alive until process exit. stopAll has 0 callers in Sources.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-01173edf (#155)

- Location: macos/Sources/MadeCore/Agent/InAppAgentController.swift:21
- Kind: 
- Severity: high
- Verdict: CONFIRMED
- Evidence: AGENT-10 is marked Shipped in docs/feature-matrix.md (#155), but the in-app Copilot GUI tab was removed in #124; InAppAgentController and AgentChatMessage are fully defined in InAppAgentController.swift but have 0 callers across all of MadeApp.
- Disposition: covered by open #155; parked (docs/parked-findings.md)

### REQ-544d7838 (AGENT-10)

- Location: docs/feature-matrix.md:183
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Row AGENT-10 in docs/feature-matrix.md claims an in-app CAD Copilot is Shipped (#155), but the Copilot GUI was removed in #124 in favor of external MCP client integration, leaving InAppAgentController dead code with 0 callers in MadeApp.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-8fb02a55 (DOC-28)

- Location: docs/feature-matrix.md:322
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: docs/feature-matrix.md duplicates capability ID DOC-28 across two distinct rows: line 228 defines DOC-28 as 2D sketch text entities (#311, BL-SKT-13), while line 322 defines DOC-28 as feature timeline rollback (#235).
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-dfa6700a (SIM-7)

- Location: docs/feature-matrix.md:389
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: docs/feature-matrix.md:389 capability description for SIM-7 labels the capability as "(BL-SIM-07)" (#353), colliding with the separate planned capability row BL-SIM-07 (#714) at line 390.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-aab459b0 (INPUT-9)

- Location: docs/feature-matrix.md:94
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Row INPUT-9 in docs/feature-matrix.md claims selection filtering restricts picking/hover preselection to faces, edges, vertices, bodies, sketch entities, or components (#338), but allowsComponents has no picking or hover path in CADMetalViewRepresentable.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-4b3a161c (INPUT-13)

- Location: macos/Sources/MadeApp/CADMetalViewRepresentable.swift:186
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: No unit, integration, or e2e test references cursor(for:) or the closed-hand pan drag cursor. Viewport cursor following the active tool is completely untested.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-08d575c3 (UI-36)

- Location: macos/Sources/MadeApp/MCPServerPopoverView.swift:103
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: No unit, integration, or e2e test references the Claude Desktop config snippet or copy button action.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-57a8965e (UI-37)

- Location: macos/Sources/MadeApp/MCPServerPopoverView.swift:27
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: No unit, integration, or e2e test references the registered CAD tool names list or TCP address display in the MCP popover.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-99c00327 (DSL-15)

- Location: macos/Sources/MadeApp/MadeApp.swift:34
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: No unit, integration, or e2e test references opening part files at launch via command-line arguments or MADE_OPEN_FILE / MADE_PART_FILE.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-d0668296 (VIEW-7)

- Location: macos/Sources/MadeCore/Viewport/MetalRenderer.swift:30
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Unit test coverage is none; capability is exercised only through integration tests (MetalRendererLifecycleTests, MetalRendererGeometryTests). .storageModeShared on uploaded buffers is unasserted.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-a6a6477c (VIEW-12)

- Location: macos/Sources/MadeCore/Viewport/MetalRenderer.swift:200
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Unit test coverage is none; capability is exercised only through integration tests (MetalRendererGeometryTests). The two lights and ambient term are not asserted separately.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-27acd2d2 (KERN-20)

- Location: macos/Sources/MadeCore/Kernel/KernelClient+Default.swift:19
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Unit test coverage is none; capability is exercised only through integration tests (KernelXPCTests). WorkspaceModel regeneration on kernel crash is unasserted.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-cba41929 (AGENT-25)

- Location: macos/Sources/MadeApp/WorkspaceModel.swift:286
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Unit test coverage is none; capability is exercised only through integration tests (MCPServerTests). WorkspaceModel GUI registry wiring is not asserted directly.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-319b8846 (VIEW-2)

- Location: macos/Sources/MadeApp/CADMetalViewRepresentable.swift:1382
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: No unit test references the iPadOS view; the code compiles only under #if os(iOS) and is unexercised in macOS CI suites.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-cf23d12d (VIEW-3)

- Location: macos/Sources/MadeApp/CADMetalViewRepresentable.swift:279
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: isPaused and enableSetNeedsDisplay (Invariant 2) are unasserted in unit tests. Coordinator relies on ViewportSelectionUITests for E2E validation.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-1a95f916 (VIEW-20)

- Location: macos/Sources/MadeApp/ContentView.swift:136
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Only shortcut constants and camera framing math are tested; WorkspaceModel zoom actions (zoomIn, zoomOut, zoomToFit, resetView) are not driven.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-df39b430 (VIEW-24)

- Location: macos/Sources/MadeCore/Viewport/ViewportState.swift:78
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Parsing of --force-no-gpu and --disable-metal-4 command-line arguments and MADE_DISABLE_METAL_4 environment variables is not tested.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-0dc29d63 (KERN-11)

- Location: macos/Sources/MadeCore/Kernel/KernelClient.swift:77
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: No test calls cancel by job ID before execution; cancellation of actively executing jobs is unasserted.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-c947225e (KERN-15)

- Location: macos/Sources/MadeCore/Kernel/Types.swift:352
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: No test explicitly asserts cached mesh re-fetch behavior when an unchanged solid is tessellated repeatedly.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-2e20e35b (KERN-23)

- Location: macos/Sources/MadeCore/Kernel/TopologicalResolver.swift:18
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Geometric-signature tie-breaker required by ADR-D3 for sub-element persistent naming is not explicitly asserted.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-4c272ab2 (AGENT-7)

- Location: macos/Sources/MadeCore/Agent/CADTools.swift:621
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Name-only result for an imported solid in CADTools has no test.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-caf20575 (AGENT-21)

- Location: macos/Sources/MadeCore/Agent/MCPServer.swift:452
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: No test invokes an unknown MCP tool name and verifies an isError JSON-RPC response payload.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-6190ebb0 (DOC-12)

- Location: macos/Sources/MadeApp/MadeCommands.swift:43
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Retention of imported CAD data across a geometry kernel restart is untested.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)

### REQ-a415283d (UI-35)

- Location: macos/Sources/MadeApp/MCPServerPopoverView.swift:32
- Kind: 
- Severity: medium
- Verdict: CONFIRMED
- Evidence: WorkspaceModel MCP server start and stop action path and popover status text display are unasserted.
- Disposition: recorded in docs/test-plan.md and parked (docs/parked-findings.md)
