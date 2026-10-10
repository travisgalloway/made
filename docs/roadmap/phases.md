# Project Roadmap & Phase Status

## Rules of Engagement

- **Complete phases in dependency order.** Foundations must be solid and verified before downstream features are built.
- **The [architectural invariants](../architecture/invariants.md) are non-negotiable.** A violation is treated as a build break.
- **Verify every phase with automated tests.** Run `cd macos && swift test` and confirm all suites pass with zero failures before declaring a phase complete. A phase is not Done while its features are unwired.

Per-capability status lives in [`../feature-matrix.md`](../feature-matrix.md). The 2026-10-10 audit found gaps in Phases 1 to 3, so those phases are marked In progress below.

---

## Status at a Glance

| Phase | Description | Status | Open gaps |
| ----- | ----------- | ------ | --------- |
| **0** | Native Foundation | Complete | None. |
| **1** | Metal 3 Viewport | In progress | Orbit, pan, zoom (#87); snapping unwired (#88); ground grid (#102); axes indicator (#103); redraw reasons (#94). |
| **2** | Native CSG Kernel | In progress | Conflation bug and failing test `KernelClientTests.testRapidRequestsConflateToLatestValue` (#90); kernel cache not freed on removal (#93). |
| **3** | Agentic Subsystem | In progress | Headless snapshot (#89); protocol and argument validation (#95 to #101). |
| **4** | CAD Depth | Not started | Issues #34 to #45, #66 to #73, #82 to #85. |

---

## Phase 0: Native Foundation (Complete)
Established the Swift 6 package hierarchy for `MadeNative`:
- `MadeCore`: Library target containing geometry, viewport, input, and agent modules.
- `MadeApp`: Executable SwiftUI application target.
- Target platform: `.macOS(.v14)` only (`Package.swift`). An iPadOS target is planned (#84).

---

## Phase 1: Metal 3 Viewport & Input (In progress)
Built:
- Direct Metal 3 pipeline with compiled Metal Shading Language shaders.
- On-demand invalidation loop (`MTKView.isPaused = true`, `enableSetNeedsDisplay = true`). No test covers it yet.
- Telemetry HUD showing render count and draw calls. Only the `model` redraw reason is recorded (#94).
- `GestureArbiter` and `PointerRouter` modules, unit tested. The arbiter locks navigate or manipulate on the first move (Invariant 8). Nothing sends them events.
- `Snapping` module with Vertex > Edge > Grid precedence (Invariant 9), unit tested. Nothing calls it.

Open:
- Orbit, pan, and zoom with mouse and trackpad (#87).
- Wire snapping into the viewport (#88).
- Ground grid on Z = 0 (#102) and labelled axes indicator (#103).
- Per-object rotation and scale in the renderer (#71).

---

## Phase 2: Native CSG Kernel (In progress)
Built:
- `EuclidEngine` generating parametric boxes and cylinders.
- Subtract, union, and intersect through Euclid.
- Off-thread actor execution in `KernelClient` with a 60 ms debounce.

Open:
- The conflation bug. `testRapidRequestsConflateToLatestValue` fails, so Invariant 7's conflation claim is unverified (#90).
- Free the kernel cache when an object is removed (#93).
- Apply a recompute result without overwriting a concurrent transform edit (#92).
- Redraw when a solid's mesh changes (#94).

---

## Phase 3: Agentic Subsystem & MCP Stdio Server (In progress)
Built:
- Pure-Swift JSON-RPC 2.0 and Model Context Protocol (2024-11-05 spec) implementation.
- `--mcp-stdio` flag for external agents (Claude Desktop, Cursor). The SwiftUI window scene still launches in this mode.
- 8 registered CAD tools covering scene inspection, parameter updates, booleans, and snapshots.
- Cadova-inspired declarative Swift CAD DSL ([`CADDSL.swift`](../../macos/Sources/MadeCore/Scripting/CADDSL.swift)) with operator overloads (`-`, `+`, `&`).

Open:
- `cad_capture_snapshot` fails over `--mcp-stdio` because the registry has no snapshot provider (#89).
- Protocol and validation errors (#95 to #101).
- Actor isolation of agent-driven document mutations (#91).

See [`phase-3-native-agent.md`](./phase-3-native-agent.md).

---

## Phase 4: CAD Depth (Not started)
No Phase 4 issue is closed. Each item below cites its GitHub issue. GitHub issue titles use a different "Phase 4.N" numbering, so the issue number is the key. [`phase-4-cad-depth.md`](./phase-4-cad-depth.md) groups the same issues by theme.

- Feature tree UI (#34).
- Boolean operations and fillets through the kernel (#35).
- 2D sketching layer (#36) and constraint solver (#37).
- STEP import and export (#38), with the OCCTSwift B-Rep bridge (#82).
- Undo and redo on the document model (#39).
- Selection outline (#40), predictive commands (#41), radial menu (#42), constrained transforms (#43), dimension by selection (#44), view snapping (#45).
- Scene generalization and inspector (#66, #67, #69, #70), gizmos (#71, #72), add and remove objects (#73).
- `.made` file format (#83), Apple Pencil channel (#84), Cadova scripting REPL (#85).

See [`phase-4-cad-depth.md`](./phase-4-cad-depth.md).
