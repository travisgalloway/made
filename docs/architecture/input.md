# Input Routing, Gestures & Precision Snapping

The input subsystem in `made` enforces Invariant 8 (navigation and editing never share a gesture) and Invariant 9 (precision comes from snapping and typed values). It supports universal Apple input paradigms: trackpad gestures and mouse clicks on macOS, and multi-touch gestures with Apple Pencil precision editing on iPadOS.

---

## Universal Input Pipeline

```
┌────────────────────────────────────────────────────────┐
│              Raw Hardware Pointer Events               │
│   (macOS Trackpad/Mouse  •  iPadOS Multi-Touch/Pencil) │
└──────────────────────────┬─────────────────────────────┘
                           │ PointerEvent (type, position)
┌──────────────────────────▼─────────────────────────────┐
│                     PointerRouter                      │
│   Classifies event into PointerType:                   │
│   • .mouse (macOS click / drag)                        │
│   • .touch (Multi-finger navigation)                   │
│   • .pen   (Apple Pencil precision channel)            │
└──────────────────────────┬─────────────────────────────┘
                           │ Route to Arbiter
┌──────────────────────────▼─────────────────────────────┐
│                    GestureArbiter                      │
│   • Tracks active pointers & movement threshold (3 pt) │
│   • Locks mode on first move:                          │
│     - 1 pointer  → .manipulate (geometry edit)         │
│     - 2+ pointers → .navigate   (camera orbit/pan)     │
│     - Apple Pencil → Locked to .manipulate             │
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

Implemented in [`GestureArbiter.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Input/GestureArbiter.swift):

### The Mode Lock Rules
1. **Movement Threshold**: Pointer motion below 3.0 display points is considered a potential tap. Mode is undecided (`.undecided`).
2. **First Move Decision**: Once motion exceeds 3.0 points:
   - If exactly 1 pointer is active: Mode locks to `.manipulate`. The user is translating, rotating, or resizing geometry.
   - If 2 or more pointers are active: Mode locks to `.navigate`. The user is orbiting, panning, or zooming the camera.
3. **Lock Retention**: Once locked, the mode **never switches** during that gesture, even if additional fingers touch the screen or some fingers lift.
4. **Release Resolution**: Mode resets to `.idle` only after the last pointer lifts. If the gesture finished without exceeding the movement threshold, a tap is emitted with the peak pointer count (e.g., single tap selects, two-finger tap triggers context actions).

### Apple Pencil Precision Channel
On iPadOS, Apple Pencil events (`PointerType.pen`) bypass the multi-touch navigation arbiter entirely:
- **Pencil Touches**: Always lock to `.manipulate` / geometry editing.
- **Finger Touches**: Always lock to `.navigate` / camera movement.
This enables fluid pair-handed modeling: the user's non-dominant hand orbits and positions the model with two fingers while the dominant hand sketches and manipulates features with the Apple Pencil.

---

## Snapping Precedence (Invariant 9)

Manual dragging on a touch surface or mouse is incapable of reliable sub-millimeter alignment. Invariant 9 mandates:

> **Precision comes from snapping and typed values, not steady fingers.**

Implemented in [`Snapping.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Input/Snapping.swift):

### Precedence Hierarchy
When a pointer moves near geometry, candidates are gathered and evaluated in strict priority order:

1. **Vertex Snapping (Priority: Vertex)**:
   Snaps to vertices of existing solid features. Highest priority. Even if a grid line or edge is closer in Euclidean distance, a vertex within the snap radius ($r = 10\text{ mm}$) wins.
2. **Edge Snapping (Priority: Edge)**:
   Projects onto boundary edges and centerlines of features. Second priority. Wins over grid lines.
3. **Grid Snapping (Priority: Grid)**:
   Rounds $(X, Y)$ coordinates to the nearest active grid pitch (default $1.0\text{ mm}$ or $5.0\text{ mm}$). Lowest priority fallback when no geometry features are nearby. Preserves the precise $Z$ height.

Candidates beyond the tolerance radius are discarded immediately.

---

## Related Documentation

- [`invariants.md`](./invariants.md) — Invariants 8 and 9
- [`document-model.md`](./document-model.md) — How manipulation commands mutate scene state
- [`ui-controls.md`](./ui-controls.md) — Inspector numeric inputs
