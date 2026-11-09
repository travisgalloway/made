# Input Routing, Gestures & Precision Snapping

The input subsystem in `made` enforces Invariant 8 (navigation and editing never share a gesture) and Invariant 9 (precision comes from snapping and typed values). The modules model mouse, touch, and pen input. **Status:** Mouse drag navigation (orbit, pan, and zoom) in the macOS viewport is implemented (#87). Viewport snapping to vertices, edges, and the Z = 0 ground grid during drag operations is implemented (#88). The iPadOS multi-touch navigation and Apple Pencil precision channel are implemented (#84).

---

## Input Pipeline

```
┌────────────────────────────────────────────────────────┐
│              Raw Hardware Pointer Events               │
│   (macOS Trackpad/Mouse  •  iPadOS Multi-Touch/Pencil) │
└──────────────────────────┬─────────────────────────────┘
                           │ PointerEvent (type, position)
┌──────────────────────────▼─────────────────────────────┐
│                     PointerRouter                      │
│   Classifies event into PointerType:                   │
│   • .mouse (6 px click-vs-drag, decided here)          │
│   • .touch (Multi-finger navigation)                   │
│   • .pen   (always manipulate, decided here)           │
└──────────────────────────┬─────────────────────────────┘
                           │ Touch events only
┌──────────────────────────▼─────────────────────────────┐
│                    GestureArbiter                      │
│   • Tracks active pointers (touch path only)           │
│   • Locks mode on the first move event:                │
│     - 1 pointer  → .manipulate (geometry edit)         │
│     - 2+ pointers → .navigate   (camera orbit/pan)     │
│   • Holds mode until ALL pointers release              │
└──────────────────────────┬─────────────────────────────┘
                           │ Manipulate Mode Active
┌──────────────────────────▼─────────────────────────────┐
│                    Snapping Engine                     │
│   Evaluates candidates in strict priority order:       │
│   1. Vertex Snap (Highest priority)                    │
│   2. Edge Snap   (Medium priority)                     │
│   3. Grid Snap   (Lowest priority fallback)            │
└────────────────────────────────────────────────────────┘
```

---

## Gesture Arbitration (Invariant 8)

A common point of frustration in 3D applications is accidental camera rotation while attempting to select or drag a geometry feature. Invariant 8 establishes a strict separation:

> **Navigation and editing never share a gesture.** The gesture arbiter locks the mode on the first movement and holds it until release.

Implemented in [`GestureArbiter.swift`](../../macos/Sources/MadeCore/Input/GestureArbiter.swift):

### The Mode Lock Rules
1. **No Distance Threshold in the Arbiter**: `GestureArbiter` applies no movement threshold. Before the first move event, the decision is undecided (`GestureDecision.undecided`, with `mode == nil`). `GestureMode` has only `.navigate` and `.manipulate`.
2. **First Move Decision**: The first `.move` event locks the mode using the peak concurrent pointer count:
   - A peak of 1 pointer locks `.manipulate`.
   - A peak of 2 or more pointers locks `.navigate`.
3. **Lock Retention**: Once locked, the mode does not change during that gesture, even if pointers join or lift.
4. **Release Resolution**: When the last pointer lifts, the arbiter locks (if it has not yet), returns the decision, and resets to undecided. A pure tap therefore resolves at release using the peak pointer count. Tap emission and context actions are not implemented (#42).

### Pointer Router Channels
[`PointerRouter.swift`](../../macos/Sources/MadeCore/Input/PointerRouter.swift) chooses the channel by `PointerType`:
- **Pen**: Always returns `.manipulate`, locked. It never reaches the arbiter. While pen is active (`isPenActive`), single-touch events are suppressed as palm contact, while two-finger touches route to `GestureArbiter` for camera navigation.
- **Touch**: Forwarded to the `GestureArbiter` rules above.
- **Mouse**: Movement past `mouseClickThresholdPx` (6.0 px) from the press point classifies the gesture as `.navigate`. Otherwise it is `.manipulate`.

### iPadOS and Apple Pencil Architecture (#84)
The iPadOS runtime in [`CADMetalViewRepresentable.swift`](../../macos/Sources/MadeApp/CADMetalViewRepresentable.swift) connects hardware touch and stylus events:
1. **Multi-Touch Navigation**: Touch events (`touchesBegan`, `touchesMoved`, `touchesEnded`, `touchesCancelled`) route through `PointerRouter` and `GestureArbiter`. Moving two or more fingers locks the arbiter into `.navigate`, computing average centroid deltas to drive `Camera.orbit` around the resolved pivot.
2. **Dedicated Pen Channel & Palm Rejection**: Apple Pencil (`touch.type == .pencil`) routes to `PointerType.pen`, locking `.manipulate`. Single-finger touches while the pencil is active are suppressed as palm contact, returning `.undecided` without latching manipulate or altering transforms.
3. **Direct Manipulation**: Pencil drags over selected solids or gizmo handles update preview transforms locally on `MetalRenderer` with `InvalidateReason.interaction` without kernel dispatches, committing once to `DocumentModel` on lift.
4. **Hover Preselection**: `UIHoverGestureRecognizer` updates `renderer.preselectedSubElement` during Apple Pencil hover and clears preselection when hover ends.
5. **Scribble Numeric Entry**: `CommitNumberField` configures `.autocorrectionDisabled()` and `.keyboardType(.numbersAndPunctuation)` on iOS, sanitizing handwritten unit suffixes (`mm`, `in`, `deg`, `°`).

---

## Snapping Precedence (Invariant 9)

Manual dragging on a touch surface or mouse cannot give reliable sub-millimeter alignment. Invariant 9 mandates:

> **Precision comes from snapping and typed values, not steady fingers.**

Implemented in [`Snapping.swift`](../../macos/Sources/MadeCore/Input/Snapping.swift):

### Precedence Hierarchy
`resolveSnap(candidates:tolerancePx:)` evaluates candidates in strict priority order. `SnapCandidateGenerator` extracts vertex and edge candidates from tessellated scene meshes and ground grid candidates on $Z = 0$ (#88):

1. **Vertex Snapping (Priority: Vertex)**:
   Snaps to vertices of existing solid features. Highest priority. Even if a grid candidate or edge is closer on screen, a vertex inside the tolerance wins.
2. **Edge Snapping (Priority: Edge)**:
   Projects onto boundary edges and centerlines of features. Second priority. Wins over grid lines.
3. **Grid Snapping (Priority: Grid)**:
   `snapToGrid` rounds $(X, Y)$ to the nearest multiple of `defaultGridSpacing` ($10.0\text{ mm}$). It leaves $Z$ unchanged. A ground grid is drawn on Z = 0 in the viewport (#102).

Each candidate carries a screen distance in pixels. Candidates beyond `defaultSnapTolerancePx` ($20.0\text{ px}$, screen space) are discarded. Within one kind, the smallest screen distance wins.

---

## Advanced Selection & Inspection Modalities

Precision mechanical modeling requires rapid, disambiguated selection of topological sub-elements (faces, edges, vertices) within dense assemblies:

### 1. Directional Marquee Selection (`Window` vs `Crossing`)
Dragging a selection box in the viewport implements directional marquee semantics:
- **Left-to-Right (`Window` Selection):** Rendered with a solid outline and blue translucent fill. Selects only entities (solids, faces, edges, or sketch primitives) whose screen projections lie **strictly enclosed** within the selection rectangle.
- **Right-to-Left (`Crossing` Selection):** Rendered with a dashed outline and green translucent fill. Selects any entity that is **either enclosed by or intersects** the bounding rectangle.

### 2. "Select Other" Depth-Peeling Hover Popup
When selecting internal faces, counterbores, or rear edges obscured by front geometry, clicking or hovering near dense features activates the **"Select Other"** popup:
- The camera ray performs screen-space depth peeling across all intersecting geometry layers.
- A compact HUD menu appears adjacent to the cursor, listing all pierced sub-elements ordered from nearest to furthest with their topological type (e.g., `Planar Face (Top)`, `Cylindrical Face (Hole #2)`, `Back Face`).
- Hovering over a list item renders that sub-element in cyan x-ray highlight through front geometry. Clicking commits the selection without requiring camera reorientation.

### 3. Double-Click Tangent Chain & Loop Propagation
- **Tangent Chain Propagation:** Double-clicking an edge evaluates the tangent continuity ($G^1$) across adjacent edges. If connected edges deviate by less than the angular tangent threshold (default $5^\circ$), the selection automatically chains along the continuous fillet or blend run.
- **Closed Loop Propagation:** Shift-double-clicking an edge traverses the face boundary perimeter, selecting the entire closed topological wire (e.g., all bounding edges of an extruded pocket or boss).

### 4. `Look Normal To` (`N` Shortcut)
Pressing the `N` key smoothly animates the camera orientation to align its line of sight perpendicular to the selected planar face, reference datum plane, or active 2D sketch plane. If the viewport is in perspective mode, it temporarily aligns the view matrix and aligns the plane's local coordinate axes with screen +Y up.

### 5. Paint / Brush Selection with Crease Stop
Holding `Shift + Option` while dragging the pointer activates Paint / Brush Selection:
- A circular brush cursor paints across adjacent geometry, adding brushed faces directly to the active selection set.
- **Crease Angle Stop:** The paint flood automatically terminates at sharp feature edges where the dihedral angle between adjacent face normals exceeds a configurable crease angle threshold (default $30^\circ$). This allows instant single-stroke selection of complex curved fillets or pocket floors without spilling onto adjacent sidewalls.

### 6. Single-Click Mate Connector LCS Pucks
For 3D assembly mate constraints (#164) and datum attachment:
- Hovering over solid geometry dynamically displays Local Coordinate System (LCS) "pucks" (circular disc glyphs displaying local $X$ red, $Y$ green, and $Z$ blue axes).
- Candidate pucks snap automatically to topological landmarks: face centroids, hole centers, cylinder axis endpoints/midpoints, sphere centers, and edge midpoints.
- Single-clicking an LCS puck instantiates a persistent mate coordinate frame, fully constraining 3D origin, surface normal (+Z), and tangent orientation (+X) in a single gesture.

---

## 3D Manipulation Gizmo (Move / Rotate / Scale)

Implemented in [`Gizmo.swift`](../../macos/Sources/MadeCore/Input/Gizmo.swift) and [`MetalRenderer+Gizmo.swift`](../../macos/Sources/MadeCore/Viewport/MetalRenderer+Gizmo.swift) (#71 Phase 4.19, #72 Phase 4.20):

When an object is selected in the viewport under the Select tool, 3D translation arrows, rotation rings, and scale handles render at the solid's origin adhering to right-handed Z-up coordinates (+X red, +Y green, +Z blue).

### Interaction and Hit-Testing
- **Handles**: `GizmoHandle` provides 9 degrees of freedom: 3 translation axes (`.translateX`, `.translateY`, `.translateZ`, length 30 mm), 3 rotation rings (`.rotateX`, `.rotateY`, `.rotateZ`, radius 24 mm), and 3 scale handles (`.scaleX`, `.scaleY`, `.scaleZ`, length 42 mm with 3 mm wireframe cubes at tips).
- **Screen-Space Hit-Testing**: Evaluates pointer proximity against 3D arrow shafts, rotation ring planes/perimeters, and scale shaft extensions/cube edges within `defaultGizmoTolerancePx` (16 pt).
- **Touch Input Offset**: For touch input (`isTouch: true`), the hit test lifts the contact point upwards by `touchPickOffsetPt` (28 pt) so the handle remains visible above the user's finger during touch contact.
- **Gesture Arbitration Lock**: On mouse/pointer down on a gizmo handle, the coordinator locks `GestureArbiter` into `.manipulate`, completely preventing camera orbit/pan until pointer release.
- **Pivot Re-Anchoring (`Option` / `Alt` Drag):** Holding `Option` allows the user to drag the gizmo center independently of the object geometry. Snapping (vertex, edge, midpoint, cylinder axis) applies to the pivot, allowing users to re-anchor the center of rotation to an arbitrary point in 3D space prior to rotating or scaling.
- **Protractor Detents & Angular Snapping (`ImGuizmo` / `Ketchup3D` Patterns):**
  - While dragging a rotation ring, an on-screen circular protractor HUD overlay visualizes the swept angle and angular subdivisions.
  - By default, rotation snaps to discrete **$15^\circ$ detents** when dragging along the inner radius of the ring.
  - Dragging outward toward the perimeter or holding `Shift` switches to fine **$1^\circ$ vernier increments**, delivering precision tactile feedback without requiring manual numeric typing.

### Drag Projections & Math
- **Translation (Skew-Ray Parameter)**: Computes the closest point parameter $s$ between the camera ray and the selected 3D translation axis $L(s) = \mathbf{C} + s\mathbf{u}$. Movement is projected along the axis as $\Delta s \cdot \mathbf{u}$.
- **Rotation (Ray-Plane Angle)**: Intersects the camera ray with the rotation ring plane to extract radial vectors from the gizmo center. Computes the signed angle $\theta = \text{atan2}((\mathbf{v}_0 \times \mathbf{v}_1) \cdot \mathbf{u}, \mathbf{v}_0 \cdot \mathbf{v}_1)$ and applies delta quaternion $\Delta q = \text{simd\_quatf(angle: } \theta, \text{axis: } \mathbf{u})$.
- **Scale (Ray-Axis Ratio)**: Computes parameter $s$ along the active axis and scale factor $\text{ratio} = \max\left(0.01, \frac{\text{baseParam} + (s - s_0)}{\text{baseParam}}\right)$ with $\text{baseParam} = 42.0$ mm. Updates `previewTransform.scale` along the active axis in-place on the renderer.
- **Snapping During Drag**: While translating or scaling, vertex, edge, and grid snap candidates are evaluated at the pointer screen location. When snapped, the delta is constrained to the active axis.
- **Two-Physics Rule & On-Demand Rendering**: During drag, live preview transforms are updated locally via `MetalRenderer.updateTransform` and tagged with `InvalidateReason.interaction` without dispatching geometry kernel jobs. The geometry kernel dispatch count remains strictly unchanged across the entire gesture.
- **Single Commit & Parameter Conversion on Release**:
  - For translation and rotation: The final transform is committed to `DocumentModel.setTransform(id:transform:)` exactly once on gesture release if moved.
  - For scale: The preview scale factor converts into geometric parameters (`width`, `depth`, `height` for boxes; `radius`, `height` for cylinders) clamped by `DocumentLimits`. Renderer preview scale resets to $(1, 1, 1)$, and parameters flow through `WorkspaceModel.setParam`, which conflates rapid updates into exactly 1 kernel dispatch. For imported objects, scale is retained in `Transform` with zero kernel jobs.
  - A drag without movement or a cancelled gesture restores the original transform with zero commits.

---

## Related Documentation

- [`invariants.md`](./invariants.md): Invariants 8 and 9
- [`document-model.md`](./document-model.md): How manipulation commands mutate scene state
- [`ui-controls.md`](./ui-controls.md): Inspector numeric inputs

