# UI controls and object manipulation

How the user edits objects: a DOM inspector for exact values, an in-viewport gizmo for direct manipulation. Invariant 9 — "set intent by selection, exact value by entry."

> **Status: the component kit is built (issue #68); the inspector and the gizmo are still designed, not built.** The kit is additive — nothing mounts it yet, so `ParamsPanel.svelte` and the existing e2e contract are untouched. Depends on [`document-model.md`](./document-model.md). Lands across Phase 4 (issues #68, #70, #71, #72). See [`../roadmap/phase-4-cad-depth.md`](../roadmap/phase-4-cad-depth.md).

## Two surfaces, one source of truth

Both surfaces write through the document model's command API (`setParam` / `setTransform`); neither holds its own copy of object state.

- **Inspector panel** — plain DOM, for exact numeric entry.
- **Gizmo** — three's `TransformControls` in the viewport, for coarse direct manipulation.

The gizmo is unavoidably a `three` object (it _is_ 3D), but its numeric companion — mode toggle, value fields — is plain DOM in the inspector. So invariants 2 and 3 hold: nothing per-frame lives in `$state`, and no DOM control imports `three`.

## Component strategy: in-house kit + a headless lib for the hard parts

The DOM controls are built as a **small in-house Svelte kit**, reaching for a **headless primitive lib only where accessibility is genuinely hard**.

```
src/lib/ui/
  controls/               # built, issue #68
    NumberField.svelte   # native <input>, typed exact entry + drag-to-scrub
    Slider.svelte         # native <input type="range">, testid pass-through
    Section.svelte        # collapsible; <button type="button"> header + Snippet body
    Toggle.svelte          # native <input type="checkbox">
    scrub.ts               # pure: pointer delta -> value (modifier-aware fine/coarse step)
    numberEntry.ts          # pure: parse, step/precision rounding, arrow-key increment, Esc-revert
    tokens.css             # shared design tokens — the repo's first
  InspectorPanel.svelte  # binds to the document model — not yet built, see #70
```

The pure logic (`scrub.ts`, `numberEntry.ts`) is split out from the four `.svelte` files for the same reason `gestureArbiter.ts`/`pointerRouter.ts`/`snapping.ts`/`framing.ts` are: the single Node-only Vitest project has no DOM, so anything worth unit-testing has to be DOM-free (see [`../guides/testing.md`](../guides/testing.md)). The components themselves are exercised by e2e once something mounts them (#70+), not by a jsdom/browser Vitest tier — this repo deliberately has no middle tier.

**The zero-new-dependency decision for #68, recorded so it isn't relitigated:** `NumberField`, `Slider`, `Section`, and `Toggle` are exactly the "common case" below — ships dependency-free, no Bits UI, no Melt UI. Reach for a headless, Svelte-5-native lib (Bits UI / Melt UI) **only** for the widgets where rolling your own accessibility is a real cost: popovers and context menus (#42) and the eventual virtualized feature tree (#34). Those arrive later in Phase 4.

**Why not a parameter-panel lib (tweakpane / lil-gui):** they manage their own DOM imperatively, which fights Svelte 5 runes and the reactive document model — you would reconcile two state systems — and they read as debug panels, not a product UI. (tweakpane is fine as a _dev-only_ debug overlay if one is ever wanted; it is not the product inspector.)

**Why not a styled kit (Skeleton / Flowbite):** they impose a design system and carry bundle weight the app can't spare while it already ships ~22 MB of occt-wasm, and a CAD inspector wants a dense, bespoke look a generic kit works against.

## The inspector

`src/lib/ui/InspectorPanel.svelte` generalizes today's `ParamsPanel.svelte`:

- Plain DOM, **never imports `three`** (invariant 3), corner-pinned like today so it needs no `pointer-events` trick.
- Reads the selected object id (below) and renders an editor dispatched on `def.kind` — box → width/depth/height, cylinder → radius/height (reusing the existing slider markup and `data-testid`s so current e2e survives) — **plus typed numeric fields for the transform** (position, rotation). Those transform fields are invariant 9 made literal, and they are where the gizmo's formerly-discarded transform becomes editable.
- Writes through `document.setParam` / `document.setTransform`.

### Selection → id, without touching `three`

The inspector is `three`-free, but selection lives as an `Object3D`. Bridge it in `SceneModel.svelte.ts`: add `selectedId: ObjectId | null`, set alongside the existing `selected` reference by reading `mesh.userData.objectId` (which `SolidNode` stamps). The inspector reads `sceneModel.selectedId` and never sees an `Object3D`. This preserves the no-op-on-unchanged discipline `SceneModel` already has (invariant 2).

## The gizmo, made real

Today `TransformControls` is visual-only: its `onobjectChange` calls `invalidateFor(invalidate, 'interaction')` and nothing persists. The fix distinguishes **two different physics**, because they have completely different costs:

### Move / rotate — pure matrix update, no kernel call

A rigid transform does not change geometry, so **it never calls the kernel**. During the drag, `onobjectChange` keeps invalidating with reason `'interaction'` (already correct). On release — `dragging-changed` → false, already tracked via `gizmoDragging` — read `object.position` / `object.quaternion` / `object.scale` and call `document.setTransform(selectedId, …)` **once**. The document is now the source of truth; the `SolidNode`'s bound transform re-asserts it. One command, zero re-tessellation. This is also where undo/redo gets its `setTransform` command for free.

### Resize — GPU preview during drag, one re-tessellate on commit

This is the performance-sensitive path, and the answer to "the most performant way to manipulate." A scale gizmo changes intrinsic dimensions, which _does_ require re-tessellation — but not on every tick.

- **During drag**, `TransformControls` mutates `object.scale`. That scales the _existing_ `BufferGeometry` on the GPU with **zero kernel calls and no geometry allocation per tick** — this is the key property; never rebuild geometry mid-drag. `onobjectChange` issues one `invalidateFor(…, 'interaction')`.
- **On release**, convert the scale delta into new intrinsic params and reset `object.scale` to `[1, 1, 1]`:
  - box: `width *= sx`, `depth *= sy`, `height *= sz` → `document.setParam` (clamped)
  - cylinder: `radius *= max(sx, sy)`, `height *= sz`
  - imported / no editable params: keep the scale as part of the `transform`, no re-tessellate
- The param change flows through the `SolidNode` request `$effect` → the **existing 60 ms-debounced `KernelClient`** → exactly one real re-tessellate.

So a whole resize drag is _N cheap invalidates + one kernel job on release_. Its acceptance test asserts `kernelMeshCount` does not advance during the drag and advances exactly once on release.

**Why preview-then-commit over live re-tessellation:** live re-tessellation per tick (what the sliders do today) is simplest and reuses everything, but a coarse solid can visibly lag the handle under load — the geometry trails the gesture. GPU scale-preview keeps the handle and the shape locked together and pays the real kernel cost once, where the user won't feel it.

## What is reused, not rebuilt

- `gizmoDragging` for gesture arbitration (invariant 8) — no new arbitration logic; `TransformControls.autoPauseControls` already suspends OrbitControls during a drag.
- `invalidateFor` reasons — `'interaction'` during a drag, `'model'` on the settled mesh.
- `KernelClient`'s debounce / conflation / stale-drop for the single commit job.
- `SceneModel` selection, extended with `selectedId`.
- `clampBoxParam` / `clampCylinderParam` for the inspector fields and the resize commit.

A radial / contextual mode menu at the point of action is the Phase 4 upgrade described in [`input.md`](./input.md); it is not required for the first cut.

## Related

- [`document-model.md`](./document-model.md) — the command API both surfaces write to
- [`input.md`](./input.md) — the gesture pipeline the gizmo plugs into
- [`rendering.md`](./rendering.md) — `invalidateFor` and the on-demand render contract
- [`invariants.md`](./invariants.md) — 2, 3, 8, 9
