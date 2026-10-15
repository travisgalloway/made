# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`made` (macOS-native Aided Design and Engineering) is a native CAD application. It is a Swift 6 package in `macos/`, with SwiftUI for the interface, Metal 4 for rendering, and `nicklockwood/Euclid` for pure-Swift CSG (constructive solid geometry). An embedded MCP (Model Context Protocol) server lets external agents drive a CAD session over stdio. The GitHub repository is still named `wade`.

`docs/` holds the architecture reference. Start at `docs/README.md`. The most relevant files:

- `docs/architecture/invariants.md` holds the nine rules. Read it before any substantial change.
- `docs/architecture/` covers the kernel, rendering, orientation, input, document model, agent API, and threading model.
- `docs/roadmap/phases.md` records what is built and what is next.
- `docs/feature-matrix.md` and `docs/test-plan.md` track every capability by ID, with its status, issue, and tests.
- `docs/reviews/` holds dated audit reports. `docs/parked-findings.md` holds findings with no ticket.
- `docs/guides/` covers testing and conventions.
- `docs/architecture/adr/` holds accepted architecture decision records (ADRs).

## The removed web prototype

The original SvelteKit prototype was removed from the tree. Its code is in the git history at commit `fa75631`, and its documentation lives in `docs/archive/web-prototype/`. Do not restore it, and do not cite its files in new issues or docs.

CI (`.github/workflows/ci.yml`) runs `swift build --build-tests` and `swift test` on `macos-26` for non-draft pull requests touching `macos/**`, workflow, or build files. Push runs on `main` and docs-only changes skip CI to save runner minutes. Manual runs can be triggered with `gh workflow run ci.yml`.

## Commands

Run commands from the repository root using `make`, or directly from `macos/` with `swift`. Direct commands need `--build-system swiftbuild`, because only Swift Build compiles `Shaders.metal`. The package needs Swift 6 tools (`swift-tools-version: 6.2`) and targets macOS 26 on Apple silicon. Building needs the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`), because shaders compile at build time.

| Task | Root Make Command | Direct Swift Command (in `macos/`) |
| --- | --- | --- |
| Build | `make build` | `swift build --build-system swiftbuild` |
| Build tests | `make build-tests` | `swift build --build-system swiftbuild --build-tests` |
| Assemble `Made.app` with the kernel XPC service | `make bundle` | `scripts/bundle-app.sh` (after a build) |
| Run the bundled app | `make run` | `swift run --build-system swiftbuild MadeApp` (no kernel service; geometry runs in process) |
| Run the bundled app with MCP on stdio | `make run-mcp` | `swift run --build-system swiftbuild MadeApp --mcp-stdio` (no kernel service) |
| All tests | `make test` | `swift test --build-system swiftbuild` |
| One test class | `make test FILTER=KernelClientTests` | `swift test --build-system swiftbuild --filter KernelClientTests` |
| One test | `make test FILTER=KernelClientTests/testRapidRequestsConflateToLatestValue` | `swift test --build-system swiftbuild --filter KernelClientTests/testRapidRequestsConflateToLatestValue` |
| Clean artifacts | `make clean` | `swift package clean && rm -rf .build` |
| Full local CI | `make ci-local` | `swift build --build-system swiftbuild --build-tests && swift test --build-system swiftbuild --skip-build` |
| First-time setup (Metal Toolchain and hooks) | `make setup` | `xcodebuild -downloadComponent MetalToolchain` |
| Install the git hooks | `make hooks` | `git config core.hooksPath .githooks` (run from the repository root) |

Tests use Swift Testing (`@Test`) in 24 files under `macos/Tests/MadeCoreTests`. There is no UI or integration test target.

The pre-commit and pre-push hooks (`.githooks/`) run every suite that calls `MTLCreateSystemDefaultDevice` when the change touches `macos/`. A failure or a skipped test blocks the commit or push, because CI runners may have no GPU. The pre-push hook also blocks when the pushed ref is not the clean checkout, because the tests run against the working tree. Bypass deliberately with `git commit --no-verify` or `git push --no-verify`.

**Stage every change before you commit** (`git add -A`). The pre-commit hook tests the staged snapshot. It saves unstaged edits as a patch, runs the tests, and reapplies the patch. If reapplying fails, the hook prints the patch path and the `git apply` command to restore it. Untracked files under `macos/` block the commit, because SwiftPM would compile them into the build.

## Layout

```
macos/
  Package.swift            MadeCore (library), MadeApp and MadeKernelService (executables), MadeCoreTests, MadeAppTests
  Support/                 Info.plist files for Made.app and the kernel XPC service
  scripts/bundle-app.sh    Assembles .build/Made.app with Contents/XPCServices/MadeKernelService.xpc (make bundle)
                           and compiles the app icon (img/made.icon, an Icon Composer file) with actool
  Sources/MadeCore/
    Kernel/                Types.swift (wire contract), KernelClient actor, KernelEngine, LocalKernelEngine, MeshStorage, EuclidEngine, Geometry
    Kernel/XPC/            KernelWire, KernelServiceHandler (service side), XPCKernelEngine (app side)
    Viewport/              MetalRenderer, MetalRenderer+Gizmo, RenderTypes, Shaders.metal, Orientation, Camera, CameraFraming, GridGenerator, AxesGenerator, ViewportState, RenderLoop (instrumentation)
    Input/                 PointerRouter, GestureArbiter, Snapping, ViewportTool, Picking, Gizmo
    Scene/                 DocumentModel (@Observable), SolidMeshApplier, KernelRegeneration
    Agent/                 MCPProtocol, MCPServer, MCPLineFramer (input framing), CADTools (tool registry), HeadlessSnapshotProvider (stdio snapshots), InAppAgentController (no caller in `MadeApp` since the Copilot tab was removed in #124)
    Scripting/             CADDSL (Swift result-builder DSL, for tests and library use). Part files will be TypeScript on JavaScriptCore (ADR-D6, #435)
    Platform/              AppKit and UIKit shims
  Sources/MadeKernelService/ main.swift: the kernel XPC service's XPCListener
  Sources/MadeApp/         MadeApp (@main, sidebar, console, and inspector commands, --mcp-stdio), ContentView, WorkspaceModel, WorkspaceTypes,
                           NavigatorSidebarView, InspectorPanelView, ViewportCanvasView, ConsoleDrawerView,
                           MCPServerPopoverView, ViewportStatusBar, BarControls, PaneTabs, CommitNumberField,
                           CADMetalViewRepresentable
  Tests/MadeCoreTests/     Swift Testing suites
  Tests/MadeAppTests/      WorkspaceModelTests and application unit tests
```

## Architectural invariants

`docs/architecture/invariants.md` is the canonical list. Source comments cite invariants by number, so **the numbers can never be reassigned**. If a task seems to require breaking one, stop and flag it.

1. **The kernel runs off the main thread.** Geometry and CSG run inside the `KernelClient` actor.
2. **Rendering is on-demand.** `MTKView.isPaused = true` and `enableSetNeedsDisplay = true`. Draw only on a camera move, a solid change, or an active interaction.
3. **The viewport is imperative, not reactive.** SwiftUI state drives panels only. Meshes and per-frame state never live in `@State`.
4. **The kernel sits behind our own interface.** UI and viewport code use `KernelRequest` and `KernelResult` from `Kernel/Types.swift`, never Euclid directly.
5. **Direct Metal 4 pipeline.** Rendering uses `MTL4CommandQueue`, argument tables, and residency sets through MetalKit, with MSL compiled at build time. Apple silicon only.
6. **Meshes cross boundaries as shared buffers** in unified memory (`.storageModeShared`).
7. **Thread-safe geometry execution.** Swift 6 strict concurrency, 60-ms debounce, and cancellation of superseded jobs.
8. **Navigation and editing never share a gesture.** The arbiter locks the mode on first movement and holds it until release.
9. **Precision comes from snapping and typed values, not steady fingers.**

Enforcement is weaker than the doc's matrix once claimed. Check `docs/architecture/invariants.md` for the current state before you rely on a test to catch a violation. Known gaps: 13 types are `@unchecked Sendable` (invariant 7, DSN-1eb23904).

## The kernel boundary (`Kernel/`)

- `Types.swift` is the wire contract: `KernelRequest`, `KernelResult<T>`, `MeshPayload`, `KernelError`.
- **Never throw across the boundary.** Every fallible call returns `KernelResult`. `KernelErrorCode` is a closed set: `kernelInitFailed`, `invalidParams`, `geometryFailed`, `unknownSolid`, `cancelled`, `workerCrashed`.
- **`SolidId` vs `JobId`.** A `SolidId` is stable across a solid's lifetime. A `JobId` is never reused, and stale results are dropped by `JobId`.
- In the bundled app, `KernelClient` runs geometry in the `MadeKernelService` XPC service through `XPCKernelEngine` (`KernelClient.makeDefault()`). `swift run` and tests use `LocalKernelEngine` in process. A service crash fails at most the job in flight with `worker-crashed`. The engine relaunches the service, emits `restarts()`, and `WorkspaceModel` and the stdio server regenerate every solid from the document. Three restarts in 30 s open a breaker that returns `kernel-init-failed`. Meshes cross as `xpc_shmem` regions (`MeshStorage`).
- `KernelClient` debounces requests 60 ms (`debounceDuration`) and conflates them per solid, with one pending slot each. `executePending` checks the job ID before it takes the slot, so a stale debounce task never strands a newer request.
- STEP import returns `geometryFailed` until the OpenCASCADE bridge lands. OCCT via OCCTSwift is the canonical B-rep kernel ([ADR-D1](docs/architecture/adr/ADR-D1-canonical-geometry-kernel.md), #142), with an App Store Swift fallback (#418). Euclid is permanently retained as the Tier 1 pure-Swift fast CSG preview engine and unit test backend ([ADR-D9](docs/architecture/adr/ADR-D9-fate-of-euclid-mesh-path.md), #247). OCCTSwift is planned (#82), not yet a dependency in `Package.swift` (which depends only on Euclid).

## Rendering (`Viewport/`)

- `MetalRenderer` owns the pipeline and the per-solid `meshes` dictionary. `CADMetalViewRepresentable` hosts the `MTKView`.
- `RenderInstrumentation.shared` records `renderCount`, `drawCalls`, and the last `InvalidateReason`. Tests and the viewport status bar read it. Publish new viewport telemetry there.
- The ground grid (#102), axes indicator (#103), selection outline (#40), orbit, pan, and zoom navigation (#87), viewport object picking (#69), and orthographic projection switching (#128) are built.

## Coordinate convention: right-handed Z-up

`Viewport/Orientation.swift` is the single source of truth: X is width, Y is depth, and Z is height. Read `Orientation.worldUp`, `groundNormal`, and `defaultViewDirection` instead of writing vectors inline. Euclid geometry mounts with zero rotation, so world space is kernel space.

## Input (`Input/`)

- `PointerRouter` chooses the channel. A pen always manipulates. A mouse decides click or drag at `mouseClickThresholdPx` (6 px).
- `GestureArbiter` locks navigate or manipulate on the first move.
- `Snapping` resolves vertex, then edge, then grid, by strict priority.
- `Picking` tests rays against candidate mesh bounds for nearest-hit solid selection.

All four are pure and unit-tested. `CADMetalViewRepresentable` calls them for mouse and pen input and object picking. The touch path remains unwired.

## Document model and agent API

- `Scene/DocumentModel.swift` is the `@Observable` scene: objects, parameters with clamp ranges, transforms, and `addObject`/`removeObject`/`setParam`/`setTransform`. ADR-D2 ([ADR-D2](docs/architecture/adr/ADR-D2-modeling-paradigm-and-document-model.md), #143, #150) establishes the target hybrid modeling paradigm: an ordered linear feature list recording direct edits as features, with multi-body parts by default.
- `Agent/CADTools.swift` registers eight MCP tools: `cad_get_scene`, `cad_add_solid`, `cad_set_param`, `cad_set_transform`, `cad_remove_solid`, `cad_measure`, `cad_boolean_operation`, `cad_capture_snapshot`. `MCPServer` speaks JSON-RPC 2.0 with protocol version `2024-11-05`.
- Tool failures return an `isError` tool result, not a JSON-RPC error object.
- The MCP popover (sparkles toolbar button) starts a TCP listener on port 9820 (`MCPServer.start`). It serves the window's own document, kernel, and renderer. The listener must accept connections only from the local machine. It binds every interface today (#129).
- `--mcp-stdio` builds its own `DocumentModel` and still opens the window. The agent edits a document the window does not show. `HeadlessSnapshotProvider` serves snapshots from an offscreen renderer, tessellating the document before each capture.

## Conventions

- **Commits:** `<type>(<scope>): <description> (#issue) (#PR)`. Scopes match the `MadeCore` directories (`kernel`, `viewport`, `input`, `scene`, `agent`), plus `ui`, `infra`, and `docs`. Bodies are explanatory prose. They name the invariant the change upholds, say why alternatives were rejected, and describe how the change was verified.
- **Prefer many small, single-purpose files** over few large ones.
- **Swift 6 concurrency:** UI types and `DocumentModel` belong on `@MainActor`. Use `@unchecked Sendable` only with a stated, reviewed reason.
- **Issue titles from audits and research** start with a stable ID (`DSN-`, `API-`, `REQ-`, `UX-`, a capability ID such as `INPUT-3`, a research ID such as `BL-FND-01`, or `ADR-D1`). Keep the ID when you edit a title, because reruns match on it.
- **Check a dependency's current version and API before adding it.** Versions in the docs are guidance.

## Current phase

Phases 0 and 1 are complete. Phases 2 and 3 are in progress, and `docs/roadmap/phases.md` lists each open gap with its issue. Close those gaps before you declare a phase done. Phase 4 (CAD depth) is split into milestones 4.0 (architecture decisions) and 4A to 4E. Phase 4.0 records ADR-D1 to ADR-D9, which gate the B-rep, document, and solver work. ADR-D1 establishes OCCT via OCCTSwift as the canonical B-rep kernel with a clean-room Swift fallback (#142, #82, #418). ADR-D9 permanently retains Euclid as the Tier 1 fast CSG engine (#247). ADR-D2 establishes a hybrid modeling paradigm with a history-based feature list recording direct edits as features and multi-body parts by default, replacing the flat object array ([ADR-D2](docs/architecture/adr/ADR-D2-modeling-paradigm-and-document-model.md), #143, #150). ADR-D3 establishes query-based topological naming derived from generation history (`BRepTools_History`) with geometric signatures as fallback tie-breakers and prohibits raw face indices ([ADR-D3](docs/architecture/adr/ADR-D3-topological-naming.md), #144, #152). ADR-D4 adopts FreeCAD planegcs (LGPL-2.1) as the canonical 2D constraint solver with a clean-room Swift fallback in libs/ (#415) and rejects SolveSpace (GPLv3) ([ADR-D4](docs/architecture/adr/ADR-D4-2d-constraint-solver.md), #146, #37). ADR-D5 establishes out-of-process file deck execution for CalculiX ccx (structural/thermal) and Gmsh (volume meshing from OCCT B-rep) bundled in `Contents/Helpers/` (#413) as GPL mere aggregation, with clean-room pure-Swift fallback in `libs/` (#415-#417) for App Store/iPadOS and rejection of in-process GPL linking ([ADR-D5](docs/architecture/adr/ADR-D5-cae-solver-and-mesher-integration.md), #147). ADR-D7 defines `.made` as a directory package of canonical JSON, plain-text `.part.ts` part sources, imported assets, and regenerable binary caches (#83, #427, #376). ADR-D8 licenses `made` under `MPL-2.0`. LGPL-2.1 code such as OCCT may link into the app, and GPL code may not (`docs/architecture/adr/`). Phases 5 to 8 hold the v1 and Later research items: assemblies, drawings and materials; simulation; breadth; and advanced work. The Mac MVP agent workflow is file edits by external agents plus MCP inspection (#427 to #429). The V2 milestone targets macOS 27 and adds in-app agents on Apple's Foundation Models.
