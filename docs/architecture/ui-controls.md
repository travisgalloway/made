# UI Controls & Desktop Layout

The user interface in `made` is built with **SwiftUI**, for macOS. iPadOS is planned (#84). Invariant 3 dictates that UI state remains cleanly separated from imperative Metal viewport buffers.

---

## Desktop Layout Architecture

The application layout is structured as a split view in [`ContentView.swift`](../../macos/Sources/MadeApp/ContentView.swift):

```
┌───────────────────────────────────────────────┬────────────────────────┐
│                                               │ [ Inspector | Copilot ]│
│                                               ├────────────────────────┤
│                                               │ Selection: Box-1       │
│               3D Metal Viewport               │ Active Solid: [menu]   │
│        (display only; no camera input)       │ Dimensions (sliders):  │
│                                               │   Width:  40.0 mm ──── │
│                                               │   Depth:  30.0 mm ──── │
│                                               │   Height: 20.0 mm ──── │
│                                               │                        │
│                                               │ (no position fields)   │
│ ┌───────────────────────────────────────────┐ │                        │
│ │ ⚡ Metal 4 | Renders: 42 | Invalidate: mod│ │                        │
│ └───────────────────────────────────────────┘ │                        │
└───────────────────────────────────────────────┴────────────────────────┘
```

---

## Component Breakdown

### 1. 3D Metal Viewport
- **Container**: [`CADMetalViewRepresentable`](../../macos/Sources/MadeApp/CADMetalViewRepresentable.swift) hosting an `MTKView`.
- **Event Handling (planned, #87)**: `CADMetalViewRepresentable` holds a `PointerRouter` in its coordinator, but nothing feeds it pointer events. The viewport has no orbit, pan, zoom, or selection.
- **Telemetry HUD**: An ultra-thin material overlay in the lower corner displaying live Metal 4 status, total frame submissions, draw call counts, and the last invalidation cause.

### 2. Dual-Mode Sidebar
The right sidebar features a segmented picker switching between two primary workflows:

#### A. Parametric Inspector
- A menu picker ("Active Solid") chooses the solid. Selection lives in `ContentView` state (#69).
- Each dimension has a SwiftUI `Slider` with a millimeter readout. There are no numeric text fields (#70) and no position fields.
- A slider change calls `DocumentModel.setParam(id:key:value:)`, which clamps to the `DocumentLimits` ranges, then requests tessellation from `KernelClient`, which debounces it.
- Sliders have no accessibility names or unit values (#106).

#### B. In-App AI Copilot
- Powered by [`InAppAgentController.swift`](../../macos/Sources/MadeCore/Agent/InAppAgentController.swift).
- Accepts natural language instructions (e.g., *"Make a 50x50 plate and subtract a 10mm hole in the center"*).
- Maps keywords in the prompt (measure, add box, add cylinder, subtract, union) to tool calls on the live document and recomputes all solids on completion.
- The send button has no accessible name (#105). The tab shows no progress and allows a second send while processing (#107).

### 3. Native Menus & Keybindings
`MadeApp.swift` declares these menu items. Every action body is empty, so none of them does anything yet:
- **File > New CAD Document** (`Cmd+N`): planned with the `.made` format (#83).
- **Geometry > Add Box** and **Add Cylinder**: planned (#73).
- **Geometry > Import STEP File...** (`Cmd+Shift+I`): planned (#38).

---

## Related Documentation

- [`document-model.md`](./document-model.md): Scene state bound to UI controls
- [`rendering.md`](./rendering.md): Viewport invalidation loop
- [`input.md`](./input.md): Input gesture handling
