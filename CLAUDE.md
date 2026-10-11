# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`made` (macOS-native Aided Design and Engineering) is a native CAD application. It is a Swift 6 package in `macos/`, with SwiftUI for the interface, Metal 3 for rendering, and `nicklockwood/Euclid` for pure-Swift CSG (constructive solid geometry). An embedded MCP (Model Context Protocol) server lets external agents drive a CAD session over stdio. The GitHub repository is still named `wade`.

`docs/` holds the architecture reference. Start at `docs/README.md`. The most relevant files:

- `docs/architecture/invariants.md` holds the nine rules. Read it before any substantial change.
- `docs/architecture/` covers the kernel, rendering, orientation, input, document model, agent API, and threading model.
- `docs/roadmap/phases.md` records what is built and what is next.
- `docs/feature-matrix.md` and `docs/test-plan.md` track every capability by ID, with its status, issue, and tests.
- `docs/reviews/` holds dated audit reports. `docs/parked-findings.md` holds findings with no ticket.
- `docs/guides/` covers testing and conventions.

## The removed web prototype

The original SvelteKit prototype was removed from the tree. Its code is in the git history at commit `fa75631`, and its documentation lives in `docs/archive/web-prototype/`. Do not restore it, and do not cite its files in new issues or docs.

CI (`.github/workflows/ci.yml`) runs `swift build --build-tests` and `swift test` on `macos-15` for non-draft pull requests touching `macos/**`, workflow, or build files. Push runs on `main` and docs-only changes skip CI to save runner minutes. Manual runs can be triggered with `gh workflow run ci.yml`.

## Commands

Run commands from the repository root using `make`, or directly from `macos/` with `swift`. The package needs Swift 6 tools (`swift-tools-version: 6.0`) and targets macOS 14.

| Task | Root Make Command | Direct Swift Command (in `macos/`) |
| --- | --- | --- |
| Build | `make build` | `swift build` |
| Build tests | `make build-tests` | `swift build --build-tests` |
| Run the app | `make run` | `swift run MadeApp` |
| Run with MCP on stdio | `make run-mcp` | `swift run MadeApp --mcp-stdio` |
| All tests | `make test` | `swift test` |
| One test class | `make test FILTER=KernelClientTests` | `swift test --filter KernelClientTests` |
| One test | `make test FILTER=KernelClientTests/testRapidRequestsConflateToLatestValue` | `swift test --filter KernelClientTests/testRapidRequestsConflateToLatestValue` |
| Clean artifacts | `make clean` | `swift package clean && rm -rf .build` |
| Full local CI | `make ci-local` | `swift build --build-tests && swift test --skip-build` |
| Install the git hooks | `make hooks` | `git config core.hooksPath .githooks` (run from the repository root) |

Tests use XCTest in `macos/Tests/MadeCoreTests`. There are 14 test files, and no UI or integration test target.

The pre-commit and pre-push hooks (`.githooks/`) run every suite that calls `MTLCreateSystemDefaultDevice` when the change touches `macos/`. A failure or a skipped test blocks the commit or push, because CI runners may have no GPU. The pre-push hook also blocks when the pushed ref is not the clean checkout, because the tests run against the working tree. Bypass deliberately with `git commit --no-verify` or `git push --no-verify`.

**Stage every change before you commit** (`git add -A`). The pre-commit hook builds and tests the files on disk, not the staged snapshot. A partial commit can therefore pass on an unstaged fix that the commit does not contain. If a partial commit is unavoidable, run `git stash --keep-index` first, and `git stash pop` after.

## Layout

```
macos/
  Package.swift            MadeCore (library), MadeApp (executable), MadeCoreTests
  Sources/MadeCore/
    Kernel/                Types.swift (wire contract), KernelClient actor, EuclidEngine, Geometry
    Viewport/              MetalRenderer, MetalShaders, Orientation, RenderLoop (instrumentation)
    Input/                 PointerRouter, GestureArbiter, Snapping
    Scene/                 DocumentModel (@Observable)
    Agent/                 MCPProtocol, MCPServer, CADTools (tool registry), InAppAgentController
    Scripting/             CADDSL (result-builder CAD DSL)
    Platform/              AppKit and UIKit shims
  Sources/MadeApp/         MadeApp (@main, menus, --mcp-stdio), ContentView, CADMetalViewRepresentable
  Tests/MadeCoreTests/     XCTest suites
```

## Architectural invariants

`docs/architecture/invariants.md` is the canonical list. Source comments cite invariants by number, so **the numbers can never be reassigned**. If a task seems to require breaking one, stop and flag it.

1. **The kernel runs off the main thread.** Geometry and CSG run inside the `KernelClient` actor.
2. **Rendering is on-demand.** `MTKView.isPaused = true` and `enableSetNeedsDisplay = true`. Draw only on a camera move, a solid change, or an active interaction.
3. **The viewport is imperative, not reactive.** SwiftUI state drives panels only. Meshes and per-frame state never live in `@State`.
4. **The kernel sits behind our own interface.** UI and viewport code use `KernelRequest` and `KernelResult` from `Kernel/Types.swift`, never Euclid directly.
5. **Direct Metal 3 pipeline.** Rendering uses compiled MSL pipelines through MetalKit.
6. **Meshes cross boundaries as shared buffers** in unified memory (`.storageModeShared`).
7. **Thread-safe geometry execution.** Swift 6 strict concurrency, 60-ms debounce, and cancellation of superseded jobs.
8. **Navigation and editing never share a gesture.** The arbiter locks the mode on first movement and holds it until release.
9. **Precision comes from snapping and typed values, not steady fingers.**

Enforcement is weaker than the doc's matrix once claimed. Check `docs/architecture/invariants.md` for the current state before you rely on a test to catch a violation. Known gaps: nine types are `@unchecked Sendable` (invariant 7, #91), and the snapping and pointer-routing code has no caller in the app (invariants 8 and 9, #87, #88).

## The kernel boundary (`Kernel/`)

- `Types.swift` is the wire contract: `KernelRequest`, `KernelResult<T>`, `MeshPayload`, `KernelError`.
- **Never throw across the boundary.** Every fallible call returns `KernelResult`. `KernelErrorCode` is a closed set: `kernelInitFailed`, `invalidParams`, `geometryFailed`, `unknownSolid`, `cancelled`, `workerCrashed`.
- **`SolidId` vs `JobId`.** A `SolidId` is stable across a solid's lifetime. A `JobId` is never reused, and stale results are dropped by `JobId`.
- `KernelClient` debounces requests 60 ms (`debounceDuration`) and conflates them per solid, with one pending slot each. `executePending` checks the job ID before it takes the slot, so a stale debounce task never strands a newer request.
- STEP import returns `geometryFailed` until the OpenCASCADE bridge lands. OCCTSwift is planned (#82), not a dependency. `Package.swift` depends only on Euclid.

## Rendering (`Viewport/`)

- `MetalRenderer` owns the pipeline and the per-solid `meshes` dictionary. `CADMetalViewRepresentable` hosts the `MTKView`.
- `RenderInstrumentation.shared` records `renderCount`, `drawCalls`, and the last `InvalidateReason`. Tests and the HUD (heads-up display) read it. Publish new viewport telemetry there.
- There is no ground grid, axes indicator, or camera navigation yet (#102, #103, #87). The camera is fixed at the default view.

## Coordinate convention: right-handed Z-up

`Viewport/Orientation.swift` is the single source of truth: X is width, Y is depth, and Z is height. Read `Orientation.worldUp`, `groundNormal`, and `defaultViewDirection` instead of writing vectors inline. Euclid geometry mounts with zero rotation, so world space is kernel space.

## Input (`Input/`)

- `PointerRouter` chooses the channel. A pen always manipulates. A mouse decides click or drag at `mouseClickThresholdPx` (6 px).
- `GestureArbiter` locks navigate or manipulate on the first move.
- `Snapping` resolves vertex, then edge, then grid, by strict priority.

All three are pure and unit-tested, but nothing in `MadeApp` calls them yet.

## Document model and agent API

- `Scene/DocumentModel.swift` is the `@Observable` scene: objects, parameters with clamp ranges, transforms, and `addObject`/`removeObject`/`setParam`/`setTransform`.
- `Agent/CADTools.swift` registers eight MCP tools: `cad_get_scene`, `cad_add_solid`, `cad_set_param`, `cad_set_transform`, `cad_remove_solid`, `cad_measure`, `cad_boolean_operation`, `cad_capture_snapshot`. `MCPServer` speaks JSON-RPC 2.0 with protocol version `2024-11-05`.
- Tool failures return an `isError` tool result, not a JSON-RPC error object.
- `--mcp-stdio` builds its own `DocumentModel` and still opens the window. The agent edits a document the window does not show, and snapshots are unavailable in that mode (#89).

## Conventions

- **Commits:** `<type>(<scope>): <description> (#issue) (#PR)`. Scopes match the `MadeCore` directories (`kernel`, `viewport`, `input`, `scene`, `agent`), plus `ui`, `infra`, and `docs`. Bodies are explanatory prose. They name the invariant the change upholds, say why alternatives were rejected, and describe how the change was verified.
- **Prefer many small, single-purpose files** over few large ones.
- **Swift 6 concurrency:** UI types and `DocumentModel` belong on `@MainActor`. Use `@unchecked Sendable` only with a stated, reviewed reason.
- **Issue titles from audits** start with a stable ID (`DSN-`, `API-`, `REQ-`, `UX-`, or a capability ID such as `INPUT-3`). Keep the ID when you edit a title, because reruns match on it.
- **Check a dependency's current version and API before adding it.** Versions in the docs are guidance.

## Current phase

Phase 0 is complete. Phases 1 to 3 are in progress, and `docs/roadmap/phases.md` lists each open gap with its issue. Close those gaps before you declare a phase done. Phase 4 (CAD depth) is split into milestones 4A to 4D. Phase 4A (native scene and interaction foundation: #66, #67, #69 to #73) comes first, because selection, gizmos, and the inspector depend on it.
