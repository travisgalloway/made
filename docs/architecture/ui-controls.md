# UI Controls & Desktop Layout

The user interface in `made` is built with **SwiftUI**, for macOS. iPadOS is planned (#84). Invariant 3 dictates that UI state remains cleanly separated from imperative Metal viewport buffers.

---

## Desktop Layout Architecture

The application layout is a `NavigationSplitView` in [`ContentView.swift`](../../macos/Sources/MadeApp/ContentView.swift), with an inspector column and a console drawer:

```
┌─────────────────────────────── toolbar (tool picker, MCP, panel toggles) ───┐
├──────────────┬──────────────────────────────────────┬───────────────────────┤
│ Navigator    │ Viewport header (Scene)              │ Inspector             │
│  Box-1       ├──────────────────────────────────────┤  Identity: name       │
│  Cylinder-1  │                                      │  Transform: X Y Z     │
│              │          3D Metal Viewport           │  Dimensions: sliders  │
│              │   (orbit, pan, zoom, snap marker)    │                       │
│              │  ┌────────────────────────────────┐  │                       │
│              │  │ Metal 4 | Renders | Invalidate │  │                       │
│              │  └────────────────────────────────┘  │                       │
│              ├──────────────────────────────────────┤                       │
│              │ Console drawer                       │                       │
└──────────────┴──────────────────────────────────────┴───────────────────────┘
```

---

## Component Breakdown

### 1. 3D Metal Viewport
- **Container**: [`CADMetalViewRepresentable`](../../macos/Sources/MadeApp/CADMetalViewRepresentable.swift) hosting an `MTKView`.
- **Event Handling**: The coordinator feeds mouse and trackpad events to a `PointerRouter`. Orbit, pan, and zoom move the camera, tool shortcuts are handled in `handleKeyDown`, and a snapping marker follows the pointer. Object picking is not built.
- **Telemetry HUD**: An ultra-thin material overlay in the lower corner displaying live Metal 4 status, total frame submissions, draw call counts, and the last invalidation cause.

### 2. Navigator
- [`NavigatorSidebarView`](../../macos/Sources/MadeApp/NavigatorSidebarView.swift) lists the scene objects. The list selection is `WorkspaceModel.selectedId`.
- An Add menu creates a box or cylinder, and a context-menu Delete removes the selected object.

### 3. Parametric Inspector
- [`InspectorPanelView`](../../macos/Sources/MadeApp/InspectorPanelView.swift) is a single form with Identity, Transform, and Dimensions sections.
- Position and scale have numeric text fields. Each dimension has a SwiftUI `Slider` with a millimeter readout and no numeric field (#70).
- A slider change calls `DocumentModel.setParam(id:key:value:)`, which clamps to the `DocumentLimits` ranges, then requests tessellation from `KernelClient`, which debounces it.
- Sliders have no accessibility names or unit values (#106).

### 4. Console Drawer
- [`ConsoleDrawerView`](../../macos/Sources/MadeApp/ConsoleDrawerView.swift) appears below the viewport when `WorkspaceModel.isConsoleVisible` is set.

### 5. Toolbar
- The toolbar holds the viewport tool picker (select, orbit, pan, zoom), zoom in, zoom out, zoom to fit, and reset view buttons, the MCP window control, and the Navigator, Inspector, and Console toggles.

### 6. MCP Window
- [`MCPServerPopoutView`](../../macos/Sources/MadeApp/MCPServerPopoutView.swift) starts and stops the in-app TCP listener on port 9820. See [`agent-api.md`](./agent-api.md).

### 7. Menus and Keybindings
`MadeApp.swift` declares only the standard `SidebarCommands` and `InspectorCommands`, which add View menu items. The earlier File and Geometry menu items were removed. Document creation is planned with the `.made` format (#83), and STEP import is planned (#38). Add Box and Add Cylinder live in the Navigator Add menu.

---

## Related Documentation

- [`document-model.md`](./document-model.md): Scene state bound to UI controls
- [`rendering.md`](./rendering.md): Viewport invalidation loop
- [`input.md`](./input.md): Input gesture handling
