# GitHub Issue Backlog Migration Audit

This document records the migration of the issue backlog from the web prototype (`wade`) to the native Apple platform architecture (`made`).

---

## 1. Web/PWA Issues (Retired)

The following 10 issues were created for the web-based PWA architecture (service workers, WASM streaming, browser workers, and IndexedDB). They do not apply to the native macOS app and are retired. All 10 are closed on GitHub with state reason `NOT_PLANNED` and carry the `web-prototype` label. Each has a comment pointing to this document. The titles below are the GitHub titles; the rationale column is this document's own:

| Issue # | Original Title | Retirement Rationale |
| ------- | -------------- | -------------------- |
| **#28** | Phase 3.1: PWA manifest via @vite-pwa/sveltekit | Retired. `made` is a native Swift/Metal application with an `Info.plist`, not a browser PWA. |
| **#29** | Phase 3.2: Workbox caching strategy | Retired. Native application binaries are installed locally as a macOS app bundle. |
| **#30** | Phase 3.3: Lazy-load kernel worker after first paint | Retired. Geometry kernel is a native Swift Actor (`KernelClient`) compiled directly into the binary. |
| **#31** | Phase 3.4: WASM streaming instantiation + Brotli | Retired. Replaced by native compiled ARM64 machine code. |
| **#32** | Phase 3.5: Investigate a slim OCCT build | Retired. No WASM payloads; Euclid CSG is pure Swift. A native OCCT xcframework is planned (#82). |
| **#33** | Phase 3.6: Install prompt via beforeinstallprompt | Retired. Native desktop app distribution. |
| **#46** | Deferred: Threaded OCCT (SharedArrayBuffer + cross-origin isolation) | Retired. Replaced by Swift 6 concurrency and Grand Central Dispatch; no browser COOP/COEP restrictions. |
| **#49** | Phase 3.7: Code-split renderer and kernel out of initial bundle | Retired. Replaced by modular Swift packages (`MadeCore` and `MadeApp`). |
| **#50** | Deferred: Render-in-worker (OffscreenCanvas) | Retired. Replaced by native Metal 4 on-demand rendering and an offscreen snapshot pass. |
| **#76** | Phase 3.8: IndexedDB persistence | Retired. Replaced by the planned native `.made` file format (#83). No persistence exists today. |

---

## 2. Phase 4 CAD Depth Issues (Modernized for Native)

The following issues represent core CAD features that remain open and have been reframed for Swift 6, Metal 4, and SwiftUI. All are open on GitHub. None is delivered. The last column states what the code does today:

| Issue # | Modernized Title | Native Implementation Target |
| ------- | ---------------- | ---------------------------- |
| **#34** | Feature tree UI in SwiftUI | SwiftUI `OutlineGroup` or hierarchical list bound to `DocumentModel`. |
| **#35** | Boolean operations and fillets | CSG booleans in `EuclidEngine` + topological fillets in `OCCTSwift`. |
| **#36** | 2D sketching layer | Interactive 2D sketch plane in Metal 4 using Euclid path extrusion. |
| **#37** | 2D constraint solver | On-the-fly geometric constraint inference engine in pure Swift. |
| **#38** | STEP import/export bridge | ISO 10303 STEP exchange via `SecondMouseAU/OCCTSwift`. |
| **#39** | Undo/redo on DocumentModel | Integration with system `UndoManager` wrapping command mutations. |
| **#40** | Selection outline shader | Metal 4 stencil buffer and post-processing outline pipeline. |
| **#41** | Predictive command palette | Context-aware SwiftUI action surface reacting to selected sub-elements. |
| **#42** | Contextual radial menu | Radial touch gesture menu for iPadOS pencil/touch interaction. |
| **#43** | Widget-less constrained transforms | Gesture-driven axis constraints backed by `Snapping.swift`. |
| **#44** | Dimension by selection | Dynamic numeric overlays on selected vertices, edges, and faces. |
| **#45** | View snapping | Double-tap / gesture face alignment to square the Metal camera. |
| **#66** | Multi-object scene generalization | Open. `DocumentModel` holds an array of objects and `MetalRenderer` draws several meshes. Generalizing the scene (positions, per-object rotation and scale) is not done. |
| **#67** | Parametric panel adaptation | Open. The Inspector (`InspectorPanelView.swift`) has sliders for dimensions and numeric fields for position and scale. Numeric dimension fields are not built. |
| **#69** | Selection model state | Open. `WorkspaceModel.selectedId` holds the selection, set by the Navigator list. The document has no selection state and the viewport has no picking. |
| **#70** | Selection-driven inspector | Open. The Inspector follows the Navigator selection. Typed dimension fields are not built. |
| **#71** | Gizmo write-back (move/rotate) | Metal 4 transform handles writing to `DocumentModel.setTransform`. |
| **#72** | Gizmo resize with GPU preview | Scale matrix preview during drag, single debounced kernel tessellation on release. |
| **#73** | Add / remove objects | Open. `addObject` and `removeObject` run through agent tools and through the Navigator Add menu and Delete action (`NavigatorSidebarView.swift`). |

---

## 3. New Native Epics

The following new engineering epics were created on GitHub. All are open:

1. **#82: Epic: OCCTSwift C++ Framework Integration for STEP/IGES & Exact B-Rep**
   - Integrate pre-compiled `OCCT.xcframework` via Swift Package Manager.
   - Implement `OCCTSwiftIO` wrapper for STEP AP203/AP214 import and export.
   - Expose exact B-Rep fillet and chamfer operations in `KernelClient`.

2. **#83: Epic: Native Document File Format (.made) via FileDocument**
   - Implement `ReferenceFileDocument` conforming to `UTType(exportedAs: "com.made.cad.document")`.
   - Support macOS document windows, autosave, and iCloud Drive synchronization.

3. **#84: Epic: Apple Pencil Precision Channel & iPadOS Gesture Arbitration**
   - Implement Apple Pencil hover detection (`UIHoverGestureRecognizer`).
   - Route `PointerType.pen` directly to geometry creation and vertex editing.
   - Support Scribble for inline numeric dimension entry in the viewport.

4. **#85: Epic: Interactive Cadova-Style Swift CAD Scripting REPL**
   - Live script reload: watching `.swift` CAD scripts and re-rendering on save.
   - Swift syntax highlighting and auto-completion in the console or MCP pane (placement open).


---

## 4. Audit Issues (#87 to #109)

The 2026-10-10 audit opened issues #87 to #109 for gaps between the documents and the code. Examples: #87 camera navigation, #88 snapping, #89 headless snapshot, #90 conflation, #91 actor isolation, #102 ground grid, #103 axes indicator. The full list with titles is in `.claude/audit/20261010-114045/created.tsv`, and [`../feature-matrix.md`](../feature-matrix.md) maps each capability to its issue.

---

## 5. Active Milestone Structure on GitHub

The active backlog is organized into seven sequential milestones. The first three close the audit gaps in the built phases. Phase 4A to 4D add CAD depth.

| Milestone | Scope | Issues |
| --------- | ----- | ------ |
| Phase 1: Metal 4 Viewport & Input (9) | Camera navigation, snapping, grid, axes, redraw reasons. | #87, #88, #94, #102, #103, #108 |
| Phase 2: Native CSG Kernel (10) | Cache lifetime, recompute races, parameter clamping. | #92, #93, #104, #109 |
| Phase 3: Agentic Subsystem & MCP (11) | Protocol validation, tool argument errors, headless snapshot, actor isolation. | #89, #91, #95 to #101, #105, #107 |
| Phase 4A: Native Scene & Interaction Foundation (5) | Scene generalization, selection, inspector, gizmos. | #40, #45, #66, #67, #69 to #73, #106 |
| Phase 4B: B-Rep Engine, STEP Exchange & Document Persistence (6) | OpenCASCADE, STEP I/O, fillets, feature tree, `.made` files. | #34, #35, #38, #39, #82, #83 |
| Phase 4C: 2D Sketching & Constraint Solver (7) | Sketch planes, constraint inference, profile extrusions. | #36, #37, #44 |
| Phase 4D: Pencil Precision, Contextual UI & Agent REPL (8) | Apple Pencil channel, radial menu, Cadova Swift REPL. | #41, #42, #43, #84, #85 |

The milestone number is in parentheses. Milestones 1 to 4 belonged to the web prototype. They are closed and renamed with a "(web prototype)" suffix, and their issues carry the `web-prototype` label.

## 6. Labels

Area labels match the commit scopes in `CLAUDE.md`: `kernel`, `viewport`, `input`, `scene`, `agent`, `ui`, `infra`, and `docs`. The `cad` label marks Phase 4 features. The `pwa` label was renamed to `web-prototype`.
