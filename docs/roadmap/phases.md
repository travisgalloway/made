# Project Roadmap & Phase Status

## Rules of Engagement

- **Complete phases in dependency order.** Foundations must be solid and verified before downstream features are built.
- **The [architectural invariants](../architecture/invariants.md) are non-negotiable.** A violation is treated as a build break.
- **Verify every phase with automated tests.** Run `make test` and confirm all suites pass with zero failures before declaring a phase complete. A phase is not Done while its features are unwired.

Per-capability status lives in [`../feature-matrix.md`](../feature-matrix.md). The 2026-10-10 audit found gaps in Phases 2 and 3, so those phases are marked In progress below. The Phase 1 milestone is closed. Each open gap is filed under the GitHub milestone named in the table. The web prototype milestones are closed and carry a "(web prototype)" suffix.

---

## Status at a Glance

| Phase | Description | Status | Milestone | Open gaps |
| ----- | ----------- | ------ | --------- | --------- |
| **0** | Native Foundation | Complete | None | None. |
| **1** | Metal 4 Viewport & Input | Complete | Phase 1: Metal 3 Viewport & Input (closed; milestone title predates Metal 4) | None. |
| **2** | Native CSG Kernel | In progress | Phase 2: Native CSG Kernel | Kernel cache not freed on removal (#93); recompute overwrites a transform (#92); parameter clamping (#104); recompute failure message (#109). |
| **3** | Agentic Subsystem | In progress | Phase 3: Agentic Subsystem & MCP | Actor isolation (#91); protocol and argument validation (#95 to #101); the file-edit agent workflow (#427 to #429). |
| **4.0** | Architecture Decisions | In progress | Phase 4.0: Architecture Decisions | Open decisions listed in the architecture documents. |
| **4A** | Native Scene & Interaction Foundation | In progress | Phase 4A | Issues #66, #67, #69 to #73. |
| **4B** | B-Rep Engine, STEP Exchange & Document Persistence | Not started | Phase 4B | Held in the milestone. |
| **4C** | 2D Sketching & Constraint Solver | Not started | Phase 4C | Held in the milestone. |
| **4D** | Pencil Precision, Contextual UI & Agent REPL | Not started | Phase 4D | Held in the milestone. |
| **4E** | Part Features & MVP Exchange | Not started | Phase 4E | Held in the milestone. |
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
- Direct Metal 4 pipeline with Metal Shading Language shaders compiled at build time (originally Metal 3).
- On-demand invalidation loop (`MTKView.isPaused = true`, `enableSetNeedsDisplay = true`).
- Telemetry HUD showing render count and draw calls (#94).
- `GestureArbiter` and `PointerRouter` modules, unit tested (Invariant 8).
- `Snapping` module with Vertex > Edge > Grid precedence (Invariant 9), unit tested.
- Orbit, pan, and zoom with mouse and trackpad (#87).
- Snapping wired to viewport drag pointer (#88).
- Ground grid on Z = 0 (#102) and labelled XYZ axes indicator (#103).
- Xcode-style unified multi-pane desktop workspace (#118 to #123): unified window toolbar, hierarchical navigator sidebar, viewport header, single-form inspector panel, and collapsible console drawer.

Per-object rotation and scale in the renderer (#71) is tracked under Phase 4A.

---

## Phase 2: Native CSG Kernel (In progress)
Built:
- `EuclidEngine` generating parametric boxes and cylinders.
- Subtract, union, and intersect through Euclid.
- Off-thread actor execution in `KernelClient` with a 60 ms debounce.

Open:
- Free the kernel cache when an object is removed (#93).
- Apply a recompute result without overwriting a concurrent transform edit (#92).
- Redraw when a solid's mesh changes (#94).

---

## Phase 3: Agentic Subsystem & MCP (In progress)
Built:
- Pure-Swift JSON-RPC 2.0 and Model Context Protocol (2024-11-05 spec) implementation.
- `--mcp-stdio` flag for external agents (Claude Desktop, Cursor). The SwiftUI window scene still launches in this mode. An offscreen renderer serves `cad_capture_snapshot` (#89).
- In-app MCP TCP server on port 9820, started from the MCP popover (UI-34 to UI-37). The loopback-only bind is a known gap (DSN-f5402406, #129).
- 8 registered CAD tools covering scene inspection, parameter updates, booleans, and snapshots.
- Cadova-inspired declarative Swift CAD DSL ([`CADDSL.swift`](../../macos/Sources/MadeCore/Scripting/CADDSL.swift)) with operator overloads (`-`, `+`, `&`).

Open:
- Protocol and validation errors (#95 to #101).
- Actor isolation of agent-driven document mutations (#91).

See [`phase-3-native-agent.md`](./phase-3-native-agent.md).

---

## Phase 4.0: Architecture Decisions (In progress)
Phase 4.0 records the decisions that gate the CAD depth work. The architecture documents list the remaining open decisions under "Open decisions": topological naming (#144) and the fate of Euclid (#247). The canonical geometry kernel is decided as OpenCASCADE Technology (OCCT) via OCCTSwift, with a clean-room Swift B-rep fallback ([ADR-D1](../architecture/adr/ADR-D1-canonical-geometry-kernel.md), #142). The scripting runtime is decided as TypeScript on JavaScriptCore ([ADR-D6](../architecture/adr/ADR-D6-scripting-runtime.md), #148), the `.made` encoding is decided as a directory package of JSON metadata, plain-text part sources, assets, and regenerable binary caches ([ADR-D7](../architecture/adr/ADR-D7-made-encoding.md), #149), and the project license is decided as `MPL-2.0` ([ADR-D8](../architecture/adr/ADR-D8-project-license.md), #145). Each decision becomes an architecture decision record (ADR) before dependent implementation starts.

## Phase 4A: Native Scene & Interaction Foundation (In progress)
Generalizes the scene and the interaction model so that selection, gizmos, and the inspector have a base. Scope covers the multi-object scene, selection, the inspector, gizmos, and add and remove objects.

## Phase 4B: B-Rep Engine, STEP Exchange & Document Persistence (Not started)
Adds an exact boundary representation engine, STEP exchange, and the native `.made` document. Scope covers the kernel bridge, STEP import and export, and document save and load.

## Phase 4C: 2D Sketching & Constraint Solver (Not started)
Adds sketches on planes and faces with a geometric constraint solver. Scope covers the sketch plane, drawing tools, constraints, and profile extrusion.

## Phase 4D: Pencil Precision, Contextual UI & Agent REPL (Not started)
Adds the Apple Pencil precision channel, context-aware commands, and an interactive scripting console. Scope covers Pencil routing, predictive commands, radial menus, and the agent REPL.

## Phase 4E: Part Features & MVP Exchange (Not started)
Delivers the first complete set of part-modeling features and a minimum viable set of exchange formats, so a user can build, save, and share a part. Scope covers part features such as extrude, revolve, fillet, chamfer, and patterns, plus exchange.

## Phase 5: Assemblies, Drawings & Materials (Not started)
Extends single parts to multi-part products. Users assemble parts with mates, document them in drawings, and assign materials. Scope covers assemblies, 2D drawings, and a material library.

## Phase 6: Simulation (CAE) Foundations (Not started)
Adds the base of computer-aided engineering (CAE) so a model can be analyzed. Scope covers meshing, finite element analysis (FEA), thermal analysis, and results visualization.

## Phase 7: Breadth (Not started)
Widens the product to more design domains and platforms. Scope covers sheet metal, surfacing, motion, iPad, and versioning.

## Phase 8: Advanced (Not started)
Adds advanced analysis and team workflows. Scope covers nonlinear analysis, computational fluid dynamics (CFD), optimization, and collaboration. Phase 8 also holds the App Store path (#419). Swift reimplementations in `libs/` replace the GPL solver and mesher (#415 to #417). App Store builds keep OCCT, with a Swift B-rep engine as the fallback (#418, #420 to #424). [ADR-D8](../architecture/adr/ADR-D8-project-license.md) records the plan.

## V2: macOS 27 and In-App Apple Models (Not started)
The second major version targets the macOS 27 and iPadOS 27 frameworks (#430). It adds an in-app agent on Apple's Foundation Models, similar to the agentic features in Xcode (#432). The agent uses the same CAD tools as MCP (#431). Quick edits run on the on-device model, and longer requests run on Apple's Private Cloud Compute model. An evaluation set measures accuracy (#433), and users may bring a partner model such as Claude (#434). The free-form Copilot item (#155) moved here.

---

## Existing Phase 4 Issues
No Phase 4 issue is closed. Each item below cites its GitHub issue. GitHub issue titles use a different "Phase 4.N" numbering, so the issue number is the key. The milestones hold the authoritative issue lists. [`phase-4-cad-depth.md`](./phase-4-cad-depth.md) groups the same issues by theme.

- Feature tree UI (#34).
- Boolean operations and fillets through the kernel (#35).
- 2D sketching layer (#36) and constraint solver (#37).
- STEP import and export (#38), with the OCCTSwift B-Rep bridge (#82, ADR-D1).
- Undo and redo on the document model (#39).
- Selection outline (#40), predictive commands (#41), radial menu (#42), constrained transforms (#43), dimension by selection (#44), view snapping (#45).
- Scene generalization and inspector (#66, #67, #69, #70), gizmos (#71, #72), add and remove objects (#73).
- `.made` file format (#83), Apple Pencil channel (#84), Cadova scripting REPL (#85).

See [`phase-4-cad-depth.md`](./phase-4-cad-depth.md).
