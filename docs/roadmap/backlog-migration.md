# GitHub Issue Backlog Migration Audit

This document records the migration of the issue backlog from the web prototype (`wade`) to the native Apple platform architecture (`made`).

---

## 1. Web/PWA Issues (Closed as Obsolete)

The following 10 issues were created for the web-based PWA architecture (service workers, WASM streaming, browser workers, and IndexedDB). They do not apply to the native macOS/Apple platform and are formally retired:

| Issue # | Original Title | Retirement Rationale |
| ------- | -------------- | -------------------- |
| **#28** | Phase 3.1: PWA manifest via @vite-pwa/sveltekit | Obsolete. `made` is a native Swift/Metal application with an `Info.plist`, not a browser PWA. |
| **#29** | Phase 3.2: Workbox caching for app shell | Obsolete. Native application binaries are installed locally via macOS/iOS app bundles. |
| **#30** | Phase 3.3: Lazy-load kernel worker | Obsolete. Geometry kernel is a native Swift Actor (`KernelClient`) compiled directly into the binary. |
| **#31** | Phase 3.4: WASM streaming instantiation | Obsolete. Replaced by native compiled ARM64 machine code. |
| **#32** | Phase 3.5: Investigate a slim WASM build | Obsolete. No WASM payloads; Euclid CSG is pure Swift and OCCT is a native xcframework. |
| **#33** | Phase 3.6: Install prompt via beforeinstallprompt | Obsolete. Native desktop app distribution. |
| **#46** | Deferred: Threaded OCCT (SharedArrayBuffer) | Obsolete. Replaced by Swift 6 concurrency and Grand Central Dispatch; no browser COOP/COEP restrictions. |
| **#49** | Phase 3.7: Code-split renderer from app shell | Obsolete. Replaced by modular Swift packages (`MadeCore` and `MadeApp`). |
| **#50** | Deferred: Render-in-worker (OffscreenCanvas) | Obsolete. Replaced by native Metal 3 on-demand rendering on the main thread and offscreen snapshot command buffers. |
| **#76** | Phase 3.8: IndexedDB persistence | Obsolete. Replaced by native `.made` file documents (`FileDocument`) on the local filesystem. |

---

## 2. Phase 4 CAD Depth Issues (Modernized for Native)

The following issues represent core CAD features that remain active and have been reframed for Swift 6, Metal 3, and SwiftUI:

| Issue # | Modernized Title | Native Implementation Target |
| ------- | ---------------- | ---------------------------- |
| **#34** | Feature tree UI in SwiftUI | SwiftUI `OutlineGroup` or hierarchical list bound to `DocumentModel`. |
| **#35** | Boolean operations and fillets | CSG booleans in `EuclidEngine` + topological fillets in `OCCTSwift`. |
| **#36** | 2D sketching layer | Interactive 2D sketch plane in Metal 3 using Euclid path extrusion. |
| **#37** | 2D constraint solver | On-the-fly geometric constraint inference engine in pure Swift. |
| **#38** | STEP import/export bridge | ISO 10303 STEP exchange via `SecondMouseAU/OCCTSwift`. |
| **#39** | Undo/redo on DocumentModel | Integration with system `UndoManager` wrapping command mutations. |
| **#40** | Selection outline shader | Metal 3 stencil buffer and post-processing outline pipeline. |
| **#41** | Predictive command palette | Context-aware SwiftUI action surface reacting to selected sub-elements. |
| **#42** | Contextual radial menu | Radial touch gesture menu for iPadOS pencil/touch interaction. |
| **#43** | Widget-less constrained transforms | Gesture-driven axis constraints backed by `Snapping.swift`. |
| **#44** | Dimension by selection | Dynamic numeric overlays on selected vertices, edges, and faces. |
| **#45** | View snapping | Double-tap / gesture face alignment to square the Metal camera. |
| **#66** | Multi-object scene generalization | Delivered in `DocumentModel` and `MetalRenderer`. |
| **#67** | Parametric panel adaptation | Delivered in SwiftUI `ContentView` Inspector. |
| **#69** | Selection model state | Delivered via `selectedId: ObjectId` in `ContentView`. |
| **#70** | Selection-driven inspector | Delivered in `ContentView` Inspector tab. |
| **#71** | Gizmo write-back (move/rotate) | Metal 3 transform handles writing to `DocumentModel.setTransform`. |
| **#72** | Gizmo resize with GPU preview | Scale matrix preview during drag, single debounced kernel tessellation on release. |
| **#73** | Add / remove objects | Delivered via `document.addObject` and `document.removeObject`. |

---

## 3. New Native Epics

The following new engineering epics have been created on GitHub:

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
   - Swift syntax highlighting and auto-completion in the Copilot sidebar.


---

## 4. Active Milestone Structure on GitHub

The active backlog is organized into 4 coherent sequential milestones:

```
┌──────────────────────────────────────────────────────────────────┐
│ Phase 4A: Native Scene & Interaction Foundation (Milestone 5)    │
│ Direct-manipulation scene and inspector experience.              │
│ Issues: #66, #67, #69, #70, #71, #72, #73, #40, #45              │
└─────────────────────────────────┬────────────────────────────────┘
                                  │
┌─────────────────────────────────▼────────────────────────────────┐
│ Phase 4B: B-Rep Engine, STEP Exchange & Document (Milestone 6)   │
│ OpenCASCADE integration, STEP I/O, fillets, feature tree, .made. │
│ Issues: #82, #38, #35, #34, #39, #83                             │
└─────────────────────────────────┬────────────────────────────────┘
                                  │
┌─────────────────────────────────▼────────────────────────────────┐
│ Phase 4C: 2D Sketching & Constraint Solver (Milestone 7)         │
│ 2D sketch planes, constraint inference, profile extrusions.      │
│ Issues: #36, #37, #44                                            │
└─────────────────────────────────┬────────────────────────────────┘
                                  │
┌─────────────────────────────────▼────────────────────────────────┐
│ Phase 4D: Pencil Precision, Contextual UI & Agent REPL (Milestone 8)
│ Apple Pencil channel, contextual radial menu, Cadova Swift REPL. │
│ Issues: #84, #85, #41, #42, #43                                  │
└──────────────────────────────────────────────────────────────────┘
```
