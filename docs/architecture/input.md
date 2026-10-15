# Input Routing, Gestures & Precision Snapping

The input subsystem in `made` enforces Invariant 8 (navigation and editing never share a gesture) and Invariant 9 (precision comes from snapping and typed values). The modules model mouse, touch, and pen input. **Status:** Mouse drag navigation (orbit, pan, and zoom) in the macOS viewport is implemented (#87). Viewport snapping to vertices, edges, and the Z = 0 ground grid during drag operations is implemented (#88). The iPadOS and Apple Pencil paths are planned (#84).

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
- **Pen**: Always returns `.manipulate`, locked. It never reaches the arbiter.
- **Touch**: Forwarded to the `GestureArbiter` rules above.
- **Mouse**: Movement past `mouseClickThresholdPx` (6.0 px) from the press point classifies the gesture as `.navigate`. Otherwise it is `.manipulate`.

The iPadOS runtime for these paths, including Apple Pencil hover, is planned (#84).

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

## 3D Manipulation Gizmo (Move / Rotate)

Implemented in [`Gizmo.swift`](../../macos/Sources/MadeCore/Input/Gizmo.swift) and [`MetalRenderer+Gizmo.swift`](../../macos/Sources/MadeCore/Viewport/MetalRenderer+Gizmo.swift) (#71, Phase 4.19):

When an object is selected in the viewport under the Select tool, 3D translation arrows and rotation rings render at the solid's origin adhering to right-handed Z-up coordinates (+X red, +Y green, +Z blue).

### Interaction and Hit-Testing
- **Handles**: `GizmoHandle` provides 6 degrees of freedom: 3 translation axes (`.translateX`, `.translateY`, `.translateZ`) and 3 rotation rings (`.rotateX`, `.rotateY`, `.rotateZ`).
- **Screen-Space Hit-Testing**: Evaluates pointer proximity against 3D arrow shafts and rotation ring planes/perimeters within `defaultGizmoTolerancePx` (16 pt).
- **Touch Input Offset**: For touch input (`isTouch: true`), the hit test lifts the contact point upwards by `touchPickOffsetPt` (28 pt) so the handle remains visible above the user's finger during touch contact.
- **Gesture Arbitration Lock**: On mouse/pointer down on a gizmo handle, the coordinator locks `GestureArbiter` into `.manipulate`, completely preventing camera orbit/pan until pointer release.

### Drag Projections & Math
- **Translation (Skew-Ray Parameter)**: Computes the closest point parameter $s$ between the camera ray and the selected 3D translation axis $L(s) = \mathbf{C} + s\mathbf{u}$. Movement is projected along the axis as $\Delta s \cdot \mathbf{u}$.
- **Rotation (Ray-Plane Angle)**: Intersects the camera ray with the rotation ring plane to extract radial vectors from the gizmo center. Computes the signed angle $\theta = \text{atan2}((\mathbf{v}_0 \times \mathbf{v}_1) \cdot \mathbf{u}, \mathbf{v}_0 \cdot \mathbf{v}_1)$ and applies delta quaternion $\Delta q = \text{simd\_quatf(angle: } \theta, \text{axis: } \mathbf{u})$.
- **Snapping During Drag**: While translating, vertex, edge, and grid snap candidates are evaluated at the pointer screen location. When snapped, the delta is constrained to the active axis.
- **Two-Physics Rule & On-Demand Rendering**: During drag, live preview transforms are updated locally via `MetalRenderer.updateTransform` and tagged with `InvalidateReason.interaction` without dispatching geometry kernel jobs. The geometry kernel dispatch count remains strictly unchanged across the entire gesture.
- **Single Commit on Release**: The final transform is committed to `DocumentModel.setTransform(id:transform:)` exactly once on gesture release if moved. A drag without movement or a cancelled gesture restores the original transform with zero commits.

---

## Related Documentation

- [`invariants.md`](./invariants.md): Invariants 8 and 9
- [`document-model.md`](./document-model.md): How manipulation commands mutate scene state
- [`ui-controls.md`](./ui-controls.md): Inspector numeric inputs

