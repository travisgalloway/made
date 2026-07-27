# Phase 4 — CAD depth

**Status: not started. Open-ended.**

Larger than the phases before it — break it into sub-tasks as you go. The [invariants](../architecture/invariants.md) hold unchanged.

Much of this phase is where the [interaction model](../architecture/input.md) finally pays off. The snapping foundation shipped in Phase 2 specifically so these interactions would have something to stand on.

## The foundation — build this first

The scene is hard-wired to exactly two solids today, with no model of user-created objects. The [document model](../architecture/document-model.md) removes that limit, and nearly everything else in this phase depends on it. `KernelClient` is already N-solid-capable — all its state is keyed by `SolidId` — so the ceiling is entirely above it, in the scene wiring.

- **#65 — Document model core. Done.** `src/lib/scene/document.svelte.ts` — N objects, each `{ id, def, transform }`, with a command-shaped mutation API (`addObject` / `removeObject` / `setParam` / `setTransform`). Replaced `params.svelte.ts`. Getters return fresh plain objects (never the proxy); no `three` imports and no runtime kernel dependency — type-only sharing of wire-contract types from `$lib/kernel/types` is fine (invariants 3, 4). _Depends on: nothing. Blocks: nearly everything below._
- **#66 — `SolidNode` + Scene generalization.** `src/lib/viewport/SolidNode.svelte`, one per object; `Scene.svelte` becomes a keyed `{#each}`; generic pick / snap / `onMesh` routing replaces the hard-coded two-solid branches. Preserves one `invalidateFor(…, 'model')` per settled mesh (invariant 2) and retains the `boxExtents` probe. _Depends on: #65._
- **#67 — Panel adapts to the document.** `ParamsPanel` drives the two default objects through the document model (not yet selection-driven). App stays visually unchanged. _Depends on: #65, #66._

[Phase 3](./phase-3-pwa.md)'s persistence issue (#76) also depends on #65 — the roadmap's one cross-phase dependency, explained there.

## Manipulating objects

The two control surfaces — a DOM inspector for exact values, the gizmo for direct manipulation — are designed in [`../architecture/ui-controls.md`](../architecture/ui-controls.md). Both write through the document model's command API.

- **#68 — In-house control kit.** `src/lib/ui/controls/` (native `NumberField` with drag-scrub, `Slider`, `Section`, `Toggle`) + `tokens.css`. A headless Svelte-5 lib (Bits UI / Melt UI) is pulled in only for the hard widgets — drag-scrub focus behaviour, popovers/menus, and the feature tree — not the common case. _Depends on: nothing._
- **#69 — `SceneModel.selectedId`.** A `three`-free selected-object id (read from `mesh.userData.objectId`) so the inspector never imports `three` (invariant 3). _Depends on: #66._
- **#70 — Selection-driven inspector.** `InspectorPanel.svelte` generalizes `ParamsPanel`: edits the selected object's params plus typed transform fields, dispatched on `def.kind`. _Depends on: #68, #69._
- **#71 — Gizmo write-back (move / rotate).** On release, `setTransform` once; a rigid transform never calls the kernel. _Depends on: #65, #66._
- **#72 — Gizmo resize (GPU preview).** Scale previews on the GPU during the drag (no kernel call, no geometry allocation per tick); on release the scale delta becomes clamped params → one debounced re-tessellate. Acceptance: `kernelMeshCount` does not advance during the drag and advances exactly once on release. _Depends on: #71._
- **#73 — Add / remove objects.** Command-backed add/remove, wiring the worker's currently-unused `dispose(solidId)`. _Depends on: #65, #66._

## Kernel and document

- **#34 — Feature tree UI** backed by the document model, virtualized list. (First real use of the headless-lib tree primitive — see [`../architecture/ui-controls.md`](../architecture/ui-controls.md#component-strategy-in-house-kit--a-headless-lib-for-the-hard-parts).) _Depends on: #65._
- **#35 — Boolean operations and fillets** through the kernel.
- **#36 / #37 — 2D sketching layer**, then a constraint solver — with common constraints (tangency, perpendicularity, concentricity, parallelism, symmetry) **inferred on the fly as the user sketches**, not merely applied afterward.
- **#38 — STEP import and export** through the kernel. Import adds an `importStep` kind to the closed wire contract and a `def.kind: 'imported'` object; it is also the bridge for agent-authored parts. See [`../architecture/agent-api.md`](../architecture/agent-api.md).
- **#39 — Undo and redo on the document model, not on geometry.** A `createHistory(doc)` wrapper over the document's command API (`addObject` / `removeObject` / `setParam` / `setTransform`) — additive because every mutation is already one serializable command. This is the reason the document model exists as a separate thing — see [`../architecture/document-model.md`](../architecture/document-model.md#the-mutation-api-is-command-shaped-from-day-one). _Depends on: #65._

## Interaction

These are the touch-first ideas the input model was designed around:

- **#41 — Predictive command surface.** Selecting an edge offers a fillet; selecting a face offers push-pull or offset. The tool follows the selection instead of living in a toolbar.
- **#42 — Contextual radial menu** at the point of interaction, in place of fixed toolbars where it suits touch.
- **#43 — Widget-less constrained transforms.** Encode the axis or plane _and_ the operation into the gesture, backed by snapping and axis borrowing — so move and resize never depend on grabbing a small handle (invariant 9). This is the evolution of the first-cut gizmo in [`../architecture/ui-controls.md`](../architecture/ui-controls.md#the-gizmo-made-real).
- **#44 — Dimension by selection.** Tapping a line pops a length field; tapping between elements pops a distance field. No formal dimensioning mode.
- **#45 — View snapping.** Double-tap a face to square the camera to it, replacing precise manual orbit.

## Agent integration

Out-of-band, via brepjs's own Node tooling — the agent authors and verifies parts, wade imports the validated result. No live command bus into the browser kernel. Full design in [`../architecture/agent-api.md`](../architecture/agent-api.md).

- **#74 — Agent authoring workflow (docs).** Document the local `brep-mcp` loop and the `.brep.ts` contract. No app code — the STEP import path (#38) is the wade-side half.
- **#75 (deferred) — `brep-script` in-worker executor.** Transpile + evaluate `.brep.ts` in wade's own worker so the agent and the UI share one parametric source. The one delicate item (evaluating TS in the worker); reserve `def.kind: 'brep-script'` now, build the executor only when a parametric round-trip is actually needed. Must stay in the worker (invariant 1), behind `KernelClient` (invariant 4).

## Rendering

- **Selection outline** via the WebGPU-native RenderPipeline node post-processing. Keep it minimal — and remember the legacy `EffectComposer` is not an option on `WebGPURenderer`. See [`../architecture/rendering.md`](../architecture/rendering.md#shaders-are-tsl-this-is-a-hard-constraint).

## Verification

- Each operation recomputes **only affected geometry**.
- A resize drag issues **no kernel job mid-drag and exactly one on release** (`kernelMeshCount`); a move/rotate drag issues **none at all**.
- A gizmo edit then an offline reload restores the object's position, rotation, and dimensions.
- Undo restores the prior param/transform, recomputing only the affected object.
- Round-trip a STEP file in and back out; an agent-authored `.brep.ts` verified with `brep-mcp` imports and renders.
- The feature tree stays responsive at a few hundred features.
