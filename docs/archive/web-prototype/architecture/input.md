# Input and precision

`src/lib/input/` — invariants 8 and 9.

## The problem

Traditional desktop CAD assumes a precise pointer, hover, a scroll wheel, and modifier keys. This app is **desktop-first but must not emulate a mouse on touch**, which is exactly what makes ported CAD feel wrong.

The model separates who does what **by input channel**, and makes precision _forgiving_ rather than _demanded_.

## Principles

- **Separate navigation from editing.** Multi-finger touch drives the camera — orbit, pan, zoom. Single-pointer input selects and manipulates. A pen, when present, is the precise create-and-edit channel. The same gesture never carries two meanings.
- **Lock the mode on first move.** The arbiter reads the opening motion, chooses navigate or manipulate, and holds it until release, so orbit, pan, and select never blend mid-drag.
- **Snapping and inference are a core system, not polish.** Precision comes from snapping to vertices, edges, and guides, so a coarse fingertip still lands exactly.
- **No dependence on tiny handles.** A large, touch-sized gizmo is fine; precise-handle dragging is not.
- **The tool follows the selection.** Selecting an edge offers a fillet; selecting a face offers push-pull. This removes the toolbar hunting that is painful on touch. _(Phase 4.)_
- **Beat occlusion.** Offset the active point above the fingertip, and prefer contextual menus at the point of action over distant toolbars.
- **Exact values by selection, then entry.** Set intent with a tap, set the number with a field — rather than demanding a precise drag.

Desktop-first means mouse and trackpad stay primary. But every viewport interaction is built on Pointer Events, so pen and touch are first-class from day one rather than retrofitted later.

## The pipeline

```
pointer event
     │
     ▼
pointerRouter ──▶ which channel?      (pen / mouse / touch)
     │
     ▼
gestureArbiter ─▶ navigate or manipulate?   (locked at first move)
     │
     ▼
picking ───────▶ what is under the ray?     (BVH raycast)
     │
     ▼
snapping ──────▶ where exactly?             (vertex > edge > grid)
```

### `pointerRouter.ts` — which channel

Branches on `pointerType`. Each type gets its own never-overlapping channel (invariant 8):

- **Pen** → always `{ mode: 'manipulate', locked: true }` from first contact. **Never navigates.**
- **Mouse** → OrbitControls already handles orbit natively, so the router's only job is click-vs-drag: within `MOUSE_CLICK_THRESHOLD_PX` (6 px) it is a selection click, beyond it is navigation.
- **Touch** → forwarded wholesale to the arbiter.

### `gestureArbiter.ts` — navigate or manipulate

A pure state machine. The rule: **more than one concurrent pointer at any point during the gesture ⇒ navigate; a lone pointer ⇒ manipulate.**

Two subtleties that are easy to get wrong and are both deliberate:

- It does **not** decide on the first `down`. Two fingers landing milliseconds apart must still resolve to navigate, so the decision waits for the **opening motion** — the first `move`.
- A pure tap never moves. So for taps, the decision is made at the final `up`/`cancel` using the **peak** concurrent pointer count, not the count still remaining.

Once locked, the mode never flips for the rest of the gesture. It resets only when all pointers release.

### `picking.ts` — what is under the ray

CPU-side raycasting through **three-mesh-bvh**, independent of the renderer — it behaves identically on WebGPU and on the WebGL2 fallback.

- `installBVHAcceleration()` — a one-time, idempotent global prototype patch. Same "call once at script scope" discipline as `installZUpWorld()`.
- `buildBoundsTree(geometry)` — **every pickable or snappable geometry needs a BVH before it is pickable.** `Scene.svelte` calls it on the STL load and on every kernel mesh payload, disposing the outgoing geometry and its BVH so a slider drag does not leak one `BufferGeometry` per tick.
- `OCCLUSION_OFFSET_PX = 40` — touch and pen pick rays are lifted 40 px above the contact point, so a fingertip or stylus never occludes its own target. **Mouse gets no offset.** This is "beat occlusion" made concrete.

### `snapping.ts` — where exactly

Invariant 9, made usable.

- `DEFAULT_SNAP_TOLERANCE_PX = 20` — deliberately touch-sized, not mouse-precision.
- `DEFAULT_GRID_SPACING = 10`.
- **Priority is strictly vertex > edge > grid.** A numerically closer lower-priority candidate never beats a higher-priority one that is still inside tolerance. That strictness is what stops the snap indicator jittering between kinds as the pointer moves.
- `nearestVertex` / `nearestEdgePoint` reuse the **existing BVH** and consider only the three vertices and three edges of the _hit triangle_. This is O(1) per pointer move, and it matches the user's intuition — snap to what is under the cursor, not to some vertex on the far side of the model that happens to fall within pixel tolerance.
- BVHs live in local space, so callers convert with `worldRayToLocal(ray, object)`.

## Why the two core modules are pure

`pointerRouter` and `gestureArbiter` take **plain pointer-shaped structs, not real `PointerEvent`s**. Together with `snapping` and `picking`, that makes them unit-testable in the Node-only Vitest project with no DOM shim.

All DOM and three.js scene-graph knowledge is quarantined in `Scene.svelte`, which is covered by Playwright instead. See [`../guides/testing.md`](../guides/testing.md).

## Wiring notes

- Pointer listeners are registered on Threlte's `dom` element with **`{ capture: true }`**. This is load-bearing: OrbitControls treats pen exactly like mouse, which would let a pen drag orbit the camera. The capture-phase listener calls `stopPropagation()` for `pointerType === 'pen'` so OrbitControls never sees pen events at all.
- `<OrbitControls touches={{ ONE: null, TWO: TOUCH.DOLLY_PAN }} />` disables single-finger orbit — one finger must select or manipulate.
- `touch-action: none` on the canvas, so the app owns every gesture.

## Related

- [`orientation.md`](./orientation.md) — snapping's ground plane comes from `GROUND_NORMAL`
- [`ui-controls.md`](./ui-controls.md) — the gizmo and inspector that sit on top of this pipeline
- [`../roadmap/phase-4-cad-depth.md`](../roadmap/phase-4-cad-depth.md) — radial menus, widget-less transforms, constraint inference
- [`invariants.md`](./invariants.md) — 8 and 9
