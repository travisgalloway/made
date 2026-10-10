# UI Controls & Desktop Layout

The user interface in `made` is built with **SwiftUI**, delivering an authentic native macOS and iPadOS experience. Invariant 3 dictates that UI state remains cleanly separated from imperative Metal viewport buffers.

---

## Desktop Layout Architecture

The application layout is structured as a split view in [`ContentView.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeApp/ContentView.swift):

```
┌───────────────────────────────────────────────┬────────────────────────┐
│                                               │ [ Inspector | Copilot ]│
│                                               ├────────────────────────┤
│                                               │ Selection: Box-1       │
│               3D Metal Viewport               │                        │
│          (Interactive Orbit / Edit)           │ Dimensions:            │
│                                               │   Width:  [ 40.0 ] ─── │
│                                               │   Depth:  [ 30.0 ] ─── │
│                                               │   Height: [ 20.0 ] ─── │
│                                               │                        │
│                                               │ Position:              │
│ ┌───────────────────────────────────────────┐ │   X: [ 0.0 ]           │
│ │ ⚡ Metal 3 | Renders: 42 | Invalidate: mod│ │   Y: [ 0.0 ]           │
│ └───────────────────────────────────────────┘ │   Z: [ 0.0 ]           │
└───────────────────────────────────────────────┴────────────────────────┘
```

---

## Component Breakdown

### 1. 3D Metal Viewport
- **Container**: [`CADMetalViewRepresentable`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeApp/CADMetalViewRepresentable.swift) hosting an `MTKView`.
- **Event Handling**: Direct mouse, trackpad, and touch input piped through `PointerRouter` and `GestureArbiter`.
- **Telemetry HUD**: An ultra-thin material overlay in the lower corner displaying live Metal 3 status, total frame submissions, draw call counts, and the last invalidation cause.

### 2. Dual-Mode Sidebar
The right sidebar features a segmented picker switching between two primary workflows:

#### A. Parametric Inspector
- Displays dimensions and transforms of the currently selected solid.
- Uses custom SwiftUI numeric inputs with real-time slider scrubbing.
- Changes dispatch to `DocumentModel.setParam(...)`, clamping to safe limits and debouncing kernel tessellation.

#### B. In-App AI Copilot
- Powered by [`InAppAgentController.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Agent/InAppAgentController.swift).
- Accepts natural language instructions (e.g., *"Make a 50x50 plate and subtract a 10mm hole in the center"*).
- Maps user intent to structured tool calls on the live document and triggers on-demand re-rendering upon completion.

### 3. Native Menus & Keybindings
Native menus integrate with macOS system menu bars:
- **CommandGroup(replacing: .newItem)**: `Cmd+N` creates a clean document.
- **Geometry Menu**: Shortcuts to instantiate primitive solids or import STEP files (`Cmd+Shift+I`).

---

## Related Documentation

- [`document-model.md`](./document-model.md) — Scene state bound to UI controls
- [`rendering.md`](./rendering.md) — Viewport invalidation loop
- [`input.md`](./input.md) — Input gesture handling
