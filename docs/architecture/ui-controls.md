# UI Controls & Desktop Layout

The user interface in `made` is built with **SwiftUI**, for macOS. iPadOS is planned (#84). Invariant 3 dictates that UI state remains cleanly separated from imperative Metal viewport buffers.

---

## Desktop Layout Architecture

The application layout is a `NavigationSplitView` in [`ContentView.swift`](../../macos/Sources/MadeApp/ContentView.swift), with an inspector column and a console split pane:

```
┌ ● ● ● [≡] │ Untitled Project   (tools) (View Angle ▾) (zoom, fit, reset) (✦) │ [⊟] ┐
├──────────────┬──────────────────────────────────────┬───────────────────────┤
│ Scene        │ Viewport header (Scene > name)       │ Identity              │
│  box-1       ├──────────────────────────────────────┤  Name  [box-1]        │
│  cylinder-1  │                                      │ Transform             │
│              │          3D Metal Viewport           │  Position [x][y][z]   │
│              │   (orbit, pan, zoom, snap marker)    │ Dimensions            │
│              ├──────────────────────────────────────┤  Width [40.0] mm [±]  │
│              │ Metal 4 | Render | Draw Calls … [▁]  │                       │
│              ├──────────── (drag to resize) ────────┤                       │
│ [+] [Filter] │ Console log            [Filter] [🗑] │                       │
└──────────────┴──────────────────────────────────────┴───────────────────────┘
```

---

## Control Conventions

The window uses system primitives for its chrome, and one button style per context:

- **Toolbar.** `.navigationTitle` draws the title. The system sidebar toggle sits beside the window controls. Related buttons form one `ToolbarItemGroup`, which the system draws as one glass capsule, and `ToolbarSpacer(.fixed)` separates the groups. The toolbar is declared on the detail column, because spacers declared on the split view itself are ignored. The viewport tool picker is the only segmented control.
- **Bars inside content.** The viewport header, status bar, console footer, and Navigator footer use `barControl()` from [`BarControls.swift`](../../macos/Sources/MadeApp/BarControls.swift). It applies small, borderless, icon-only buttons. Every bar is `BarMetrics.height` (36 pt) tall, matching Xcode 26's jump bar and editor status bar, and the header and status bar use `.callout` text. `BarFilterField` is the shared filter field.
- **Forms.** The Inspector uses `.formStyle(.columns)` with small controls. The MCP popover uses `.formStyle(.grouped)`. Neither uses glass button styles.
- **Pane tabs.** Each side pane opens with an icon tab bar from [`PaneTabs.swift`](../../macos/Sources/MadeApp/PaneTabs.swift). It wraps `NSSegmentedControl`, because SwiftUI's segmented `Picker` cannot stretch its segments. Navigator tabs are left-aligned, and Inspector tabs fill the pane width, as in Xcode. `NavigatorTab` and `InspectorTab` each have one case today (Scene and Properties). A new pane view is a new case.
- Every icon-only button keeps a text title and a `.help` string, for VoiceOver and tooltips.

---

## Component Breakdown

### 1. 3D Metal Viewport
- **Container**: [`CADMetalViewRepresentable`](../../macos/Sources/MadeApp/CADMetalViewRepresentable.swift) hosting an `MTKView`.
- **Event Handling**: The coordinator feeds mouse and trackpad events to a `PointerRouter`. Orbit, pan, and zoom move the camera, tool shortcuts are handled in `handleKeyDown`, and a snapping marker follows the pointer. Object picking is not built.
- **Status bar**: [`ViewportStatusBar`](../../macos/Sources/MadeApp/ViewportStatusBar.swift) sits under the viewport. It shows Metal 4 status, render count, draw calls, the last invalidation cause, the active tool, and the snap kind. Its trailing button shows or hides the console.

### 2. Navigator
- [`NavigatorSidebarView`](../../macos/Sources/MadeApp/NavigatorSidebarView.swift) opens with its tab bar (Scene only). The Scene tab lists the scene objects, one line per row. The list selection is `WorkspaceModel.selectedId`.
- Visibility and lock buttons appear on hover. They stay visible while an object is hidden or locked.
- The footer holds the Add menu (box or cylinder) and the filter field. A context-menu Delete removes the selected object.

### 3. Parametric Inspector
- [`InspectorPanelView`](../../macos/Sources/MadeApp/InspectorPanelView.swift) opens with its tab bar (Properties only). The Properties tab is a columns-style form with Identity, Transform, and Dimensions sections.
- Position and scale have three numeric fields each, with X, Y, and Z captions.
- Every numeric field is a `CommitNumberField`. It edits a text draft and writes to the model only on Return or focus loss, then shows the model's value, which may be clamped. A field bound directly to the model reformatted its text after each keystroke.
- Each dimension has a numeric millimeter field and a 1-mm stepper, with accessibility names and values in millimeters. Both call `DocumentModel.setParam(id:key:value:)`, which clamps to the `DocumentLimits` ranges, then requests tessellation from `KernelClient`, which debounces it.
- When no object is selected (`selectedObject == nil`), the Inspector displays an empty state (`ContentUnavailableView`) with the message "No Object Selected". Imported meshes (`.imported`) display identity and transform fields without editable dimension fields.

### 4. Console
- [`ConsoleDrawerView`](../../macos/Sources/MadeApp/ConsoleDrawerView.swift) sits in a `VSplitView` below the viewport, so its height can be dragged. It appears when `WorkspaceModel.isConsoleVisible` is set. Its footer holds the filter field and the clear button.

### 5. Toolbar
- The toolbar holds the viewport tool picker (select, orbit, pan, zoom), the View Angle menu (Perspective, Top, Front, Right, Isometric), one group of zoom in, zoom out, zoom to fit, and reset view buttons, and the MCP button. The Inspector toggle is declared in the inspector's own toolbar, so it sits over the inspector column. The system moves it to the window toolbar while the inspector is hidden.

### 6. MCP Popover
- The sparkles toolbar button opens [`MCPServerPopover`](../../macos/Sources/MadeApp/MCPServerPopoverView.swift). Its switch starts and stops the in-app TCP listener on port 9820, and the icon turns green while the server runs. The popover also shows the address, copies the Claude Desktop config, and lists the registered tools. See [`agent-api.md`](./agent-api.md).

### 7. Menus and Keybindings
`MadeApp.swift` declares the standard `SidebarCommands` and `InspectorCommands`, plus a View menu item that shows or hides the console with ⇧⌘Y. Document creation is planned with the `.made` format (#83), and STEP import is planned (#38). Add Box and Add Cylinder live in the Navigator Add menu.

---

## Related Documentation

- [`document-model.md`](./document-model.md): Scene state bound to UI controls
- [`rendering.md`](./rendering.md): Viewport invalidation loop
- [`input.md`](./input.md): Input gesture handling
