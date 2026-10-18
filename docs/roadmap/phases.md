# Project Roadmap & Phase Status

## Rules of Engagement

- **Complete phases in dependency order.** Foundations must be solid and verified before downstream features are built.
- **The [architectural invariants](../architecture/invariants.md) are non-negotiable.** A violation is treated as a build break.
- **Verify every phase with automated tests.** Run `make test` and confirm all suites pass with zero failures before declaring a phase complete. A phase is not Done while its features are unwired.

Per-capability status lives in [`../feature-matrix.md`](../feature-matrix.md). As of 2026-10-17, the GitHub milestones for Phases 0 to 4A hold no open issues. Phases 4B and 4C hold open gaps from audit run 20261017-112015. That audit verified 174 of 1,208 criteria in closed issues, so a Complete phase can still hold an unfound gap. Each open gap is filed under the GitHub milestone named in the table. The web prototype milestones are closed and carry a "(web prototype)" suffix.

---

## Status at a Glance

| Phase | Description | Status | Milestone | Open gaps |
| ----- | ----------- | ------ | --------- | --------- |
| **0** | Native Foundation | Complete | None | None. |
| **1** | Metal 4 Viewport & Input | Complete | Phase 1: Metal 3 Viewport & Input | None. |
| **2** | Native CSG Kernel | Complete | Phase 2: Native CSG Kernel | None. |
| **3** | Agentic Subsystem | Complete | Phase 3: Agentic Subsystem & MCP | None. |
| **4.0** | Architecture Decisions | Complete | Phase 4.0: Architecture Decisions | None in the milestone. ADR-D10 is proposed (#549) and has no milestone. |
| **4A** | Native Scene & Interaction Foundation | Complete | Phase 4A | None. |
| **4B** | B-Rep Engine, STEP Exchange & Document Persistence | In progress | Phase 4B | 6 open issues: #552 to #557. IGES has no entry point (#404). |
| **4C** | 2D Sketching & Constraint Solver | In progress | Phase 4C | 1 open issue: #558. |
| **4D** | Pencil Precision, Contextual UI & Agent REPL | In progress | Phase 4D | 10 open issues, 1 closed. |
| **4E** | Part Features & MVP Exchange | In progress | Phase 4E | 20 open issues, 1 closed. |
| **5** | Assemblies, Drawings & Materials | Not started | Phase 5 | Held in the milestone. |
| **6** | Simulation (CAE) Foundations | Not started | Phase 6 | Held in the milestone. |
| **7** | Breadth | Not started | Phase 7 | Held in the milestone. |
| **8** | Advanced | Not started | Phase 8 | Held in the milestone. |
| **V2** | macOS 27 and In-App Apple Models | Not started | V2: macOS 27 and In-App Apple Models | Held in the milestone. |

---

## Phase 0: Native Foundation (Complete)
Established the Swift 6 package hierarchy for `MadeNative`:
- `MadeCore`: Library target containing geometry, viewport, input, and agent modules.
- `MadeApp`: Executable SwiftUI application target.
- Target platform: `.macOS(.v26)` only (`Package.swift`). An iPadOS target is planned (#84).

---

## Phase 1: Metal 4 Viewport & Input (Complete)
Built:
- Direct Metal 4 pipeline with Metal Shading Language shaders compiled at build time.
- On-demand invalidation loop (`MTKView.isPaused = true`, `enableSetNeedsDisplay = true`).
- Telemetry HUD showing render count and draw calls (#94).
- `GestureArbiter` and `PointerRouter` modules, unit tested (Invariant 8).
- `Snapping` module with Vertex > Edge > Grid precedence (Invariant 9), unit tested.
- Orbit, pan, and zoom with mouse and trackpad (#87).
- Snapping wired to viewport drag pointer (#88).
- Ground grid on Z = 0 (#102) and labelled XYZ axes indicator (#103).
- Xcode-style unified multi-pane desktop workspace (#118 to #123): unified window toolbar, hierarchical navigator sidebar, viewport header, single-form inspector panel, and collapsible console drawer.

Per-object rotation and scale in the renderer (#71) shipped under Phase 4A.

---

## Phase 2: Native CSG Kernel (Complete)
Built:
- `EuclidEngine` generating parametric boxes and cylinders.
- Subtract, union, and intersect through Euclid.
- Off-thread actor execution in `KernelClient` with a 60 ms debounce.

Closed gaps from the 2026-10-10 audit:
- Free the kernel cache when an object is removed (#93).
- Apply a recompute result without overwriting a concurrent transform edit (#92).
- Redraw when a solid's mesh changes (#94).

---

## Phase 3: Agentic Subsystem & MCP (Complete)
Built:
- Pure-Swift JSON-RPC 2.0 and Model Context Protocol (2024-11-05 spec) implementation.
- `--mcp-stdio` flag for external agents (Claude Desktop, Cursor). The SwiftUI window scene still launches in this mode. An offscreen renderer serves `cad_capture_snapshot` (#89).
- In-app MCP TCP server on port 9820, started from the MCP popover (UI-34 to UI-37). The listener binds loopback only (DSN-f5402406, #129).
- 12 registered CAD tools covering scene inspection, parameter updates, booleans, part reload, diagnostics, verification, snapshots, and history rollback.
- Cadova-inspired declarative Swift CAD DSL ([`CADDSL.swift`](../../macos/Sources/MadeCore/Scripting/CADDSL.swift)) with operator overloads (`-`, `+`, `&`).

Closed gaps from the 2026-10-10 audit:
- Protocol and validation errors (#95 to #101).
- Actor isolation of agent-driven document mutations (#91).
- The file-edit agent workflow (#427 to #429).

See [`phase-3-native-agent.md`](./phase-3-native-agent.md).

---

## Phase 4.0: Architecture Decisions (Complete)
Phase 4.0 records the decisions that gate the CAD depth work. All Phase 4.0 architecture decisions are decided. The canonical geometry kernel is decided as OpenCASCADE Technology (OCCT) via OCCTSwift, with a clean-room Swift B-rep fallback ([ADR-D1](../architecture/adr/ADR-D1-canonical-geometry-kernel.md), #142), and Euclid is permanently retained as the Tier 1 pure-Swift fast CSG preview engine and unit test backend ([ADR-D9](../architecture/adr/ADR-D9-fate-of-euclid-mesh-path.md), #247). The modeling paradigm and document model is decided as a hybrid history-based feature list recording direct edits as features with multi-body parts by default ([ADR-D2](../architecture/adr/ADR-D2-modeling-paradigm-and-document-model.md), #143, #150). The topological naming is decided as query-based references built from generation history (`BRepTools_History`) with fallback geometric signatures and raw index prohibition ([ADR-D3](../architecture/adr/ADR-D3-topological-naming.md), #144, #152). The 2D constraint solver is decided as FreeCAD `planegcs` (LGPL-2.1) as the canonical primary solver, with a clean-room pure-Swift solver in `libs/` (#415) as the Mac App Store and iPadOS fallback, while rejecting SolveSpace (`libslvs`, GPLv3) ([ADR-D4](../architecture/adr/ADR-D4-2d-constraint-solver.md), #146, #37). The CAE solver and mesher integration is decided as out-of-process file deck execution for CalculiX `ccx` (structural/thermal) and Gmsh (volume meshing from OCCT B-rep) bundled in `Contents/Helpers/` (#413) as GPL mere aggregation, with clean-room pure-Swift fallback in `libs/` (#415-#417) for App Store/iPadOS and rejection of in-process GPL linking ([ADR-D5](../architecture/adr/ADR-D5-cae-solver-and-mesher-integration.md), #147). The scripting runtime is decided as TypeScript on JavaScriptCore ([ADR-D6](../architecture/adr/ADR-D6-scripting-runtime.md), #148), the `.made` encoding is decided as a directory package of JSON metadata, plain-text part sources, assets, and regenerable binary caches ([ADR-D7](../architecture/adr/ADR-D7-made-encoding.md), #149), and the project license is decided as `MPL-2.0` ([ADR-D8](../architecture/adr/ADR-D8-project-license.md), #145). Each decision becomes an architecture decision record (ADR) before dependent implementation starts.

## Phase 4A: Native Scene & Interaction Foundation (Complete)
Generalizes the scene and the interaction model so that selection, gizmos, and the inspector have a base. Scope covers the multi-object scene, selection, the inspector, gizmos, and add and remove objects.

## Phase 4B: B-Rep Engine, STEP Exchange & Document Persistence (In progress)
Adds an exact boundary representation engine, STEP exchange, and the native `.made` document. Scope covers the kernel bridge, STEP import and export, and document save and load. Six closed issues have unmet criteria or no person-facing entry point. They are re-filed as #552 (multi-selection), #553 (body edits), #554 (feature delete and lock), #555 (tolerance re-tessellation), #556 (inch conversion), and #557 (Sketch Entities filter).

## Phase 4C: 2D Sketching & Constraint Solver (In progress)
Adds sketches on planes and faces with a geometric constraint solver governed by [ADR-D4](../architecture/adr/ADR-D4-2d-constraint-solver.md) (#146, #37). Scope covers the sketch plane, drawing tools, constraints, degrees-of-freedom tracking, drag solving, and profile extrusion. Sketch entities do not draw in the viewport, which #356 promised. #558 tracks that gap.

## Phase 4D: Pencil Precision, Contextual UI & Agent REPL (In progress)
Adds the Apple Pencil precision channel, context-aware commands, and an interactive scripting console. Scope covers Pencil routing, predictive commands, radial menus, and the agent REPL.

## Phase 4E: Part Features & MVP Exchange (In progress)
Delivers the first complete set of part-modeling features and a minimum viable set of exchange formats, so a user can build, save, and share a part. Scope covers part features such as extrude, revolve, fillet, chamfer, and patterns, plus exchange.

## Phase 5: Assemblies, Drawings & Materials (Not started)
Extends single parts to multi-part products. Users assemble parts with mates, document them in drawings, and assign materials. Scope covers assemblies, 2D drawings, and a material library.

## Phase 6: Simulation (CAE) Foundations (Not started)
Adds the base of computer-aided engineering (CAE) so a model can be analyzed, governed by [ADR-D5](../architecture/adr/ADR-D5-cae-solver-and-mesher-integration.md) (#147). Scope covers volume meshing (Gmsh, #188), background solver execution (CalculiX `ccx`, #187), linear static finite element analysis (#219), steady-state thermal conduction (#190), and results visualization.

## Phase 7: Breadth (Not started)
Widens the product to more design domains and platforms. Scope covers sheet metal, surfacing, motion, iPad, and versioning.

## Phase 8: Advanced (Not started)
Adds advanced analysis and team workflows. Scope covers nonlinear analysis, computational fluid dynamics (CFD, OpenFOAM, #186), remote/cloud solve runners (#352), optimization, and collaboration. Phase 8 also holds the App Store path (#419). Swift reimplementations in `libs/` replace the GPL solver and mesher under the dual-engine strategy ([ADR-D5](../architecture/adr/ADR-D5-cae-solver-and-mesher-integration.md), #415 to #417). App Store builds keep OCCT, with a Swift B-rep engine as the fallback (#418, #420 to #424). [ADR-D8](../architecture/adr/ADR-D8-project-license.md) records the plan.

## V2: macOS 27 and In-App Apple Models (Not started)
The second major version targets the macOS 27 and iPadOS 27 frameworks (#430). It adds an in-app agent on Apple's Foundation Models, similar to the agentic features in Xcode (#432). The agent uses the same CAD tools as MCP (#431). Quick edits run on the on-device model, and longer requests run on Apple's Private Cloud Compute model. An evaluation set measures accuracy (#433), and users may bring a partner model such as Claude (#434). The free-form Copilot item (#155) moved here.

---

## Existing Phase 4 Issues
The issues for 4.0 and 4A are closed. Phases 4B and 4C hold the open gaps #552 to #558. Of the items below, #41 to #43 and #84 are still open. Each item cites its GitHub issue. GitHub issue titles use a different "Phase 4.N" numbering, so the issue number is the key. The milestones hold the authoritative issue lists. [`phase-4-cad-depth.md`](./phase-4-cad-depth.md) groups the same issues by theme.

- Feature tree UI (#34, ADR-D2).
- Boolean operations and fillets through the kernel (#35, ADR-D2).
- 2D sketching layer (#36) and constraint solver (#37).
- STEP import and export (#38), with the OCCTSwift B-Rep bridge (#82, ADR-D1).
- Undo and redo on the document model (#39, ADR-D2).
- Selection outline (#40), predictive commands (#41), radial menu (#42), constrained transforms (#43), dimension by selection (#44), view snapping (#45).
- Scene generalization and inspector (#66, #67, #69, #70), gizmos (#71, #72), add and remove objects (#73).
- `.made` file format (#83, ADR-D2, ADR-D7), Apple Pencil channel (#84), Cadova scripting REPL (#85).

See [`phase-4-cad-depth.md`](./phase-4-cad-depth.md).
