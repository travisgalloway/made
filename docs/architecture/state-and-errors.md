# State and error handling

Invariant 3, plus the cross-cutting rules for how failures surface.

## Three kinds of state that never merge

| Holds                              | Lives in               |
| ---------------------------------- | ---------------------- |
| Parametric definitions and history | the **document model** |
| Meshes                             | the **GPU**            |
| View models                        | **Svelte** (`$state`)  |

These three never merge. Geometry does not enter `$state`; view models do not enter the render path; the document model does not hold `BufferGeometry`.

The **document model** row is made concrete by [`document-model.md`](./document-model.md) — the N-object model with a command-shaped mutation API that replaced the old hard-wired `params.svelte.ts` (issue #65). It is the keystone the manipulation and agent work depend on.

**The canvas is imperative, not reactive** (invariant 3). One component owns the renderer and the scene directly. Svelte state drives the UI panels and the feature tree, never the per-frame render path. Binding reactive state that re-runs Svelte work every frame is the failure mode this invariant exists to prevent.

Svelte 5 runes give fine-grained updates, which makes the split cheap to hold: keep geometry in the worker and on the GPU, and hold only lightweight view models in `$state`.

## The store pattern

Every store is a `.svelte.ts` file — that suffix is what enables runes outside a component. The per-scene stores follow one shape: **factory function, closure-local runes, an object of getters.** The one exception is `settings.svelte.ts`, which is a module-level singleton because there is exactly one settings object per document and nothing needs to instantiate a second — see below.

- **`scene/document.svelte.ts`** — the N-object document model (issue #65), replacing the old `params.svelte.ts`'s five hand-rolled scalar `$state` fields. One `let objects = $state<SceneObject[]>([...])` holds all of them: Svelte 5 deep-proxies the array's entries, so reading `obj.def.params.width` inside an `$effect` subscribes at field granularity — the same fine-grained dependency the old per-field primitives established, without hand-rolling one primitive per field.

  `paramsFor(id)` returns a **fresh plain object**, never a Svelte proxy — because that object is exactly what ends up inside a `KernelRequest`, and a proxy would not survive structured clone.

  `setParam(id, key, value)` clamps through pure, unit-tested functions against `BOX_LIMITS` / `CYLINDER_LIMITS`, so a slider can never send an out-of-range value to the kernel regardless of what the DOM element's own `min`/`max` say. It is the only param write path — `addObject` / `removeObject` / `setTransform` round out the command-shaped mutation API. See [`document-model.md`](./document-model.md).

- **`scene/SceneModel.svelte.ts`** and **`scene/SnapModel.svelte.ts`** — use `$state.raw`, not `$state`. They hold _references_ to imperative three.js objects, never geometry and never per-frame data. Both **no-op when the value is unchanged**, which is what keeps hover and snap from reintroducing a render loop. See [`rendering.md`](./rendering.md#the-idle-quiescence-trap).

- **`settings/settings.svelte.ts`** — a module-level singleton, persisted to `localStorage['wade:settings']` (write failures swallowed, for privacy mode). Read once at renderer construction, **never per frame**.

## Panels are plain DOM

`ui/ParamsPanel.svelte` never imports `three`. It is pinned to a corner rather than being a full-screen overlay, so it needs no `pointer-events` trick.

Long panels — the feature tree, the assembly tree — should be **virtualized**, with CSS containment to isolate layout. _(Phase 4.)_

## Where the shared model is created

`+page.svelte` creates the [document model](./document-model.md), not `Scene.svelte`. `ParamsPanel` (plain DOM) and `Scene` (inside the Threlte `<Canvas>`) are **sibling trees**, and Svelte context flows down only one tree. So the shared instance is created above both and passed as a prop.

## Error handling

**Kernel operations return typed results. Nothing is ever thrown across the worker boundary.** See [`kernel.md`](./kernel.md#never-throw-across-the-boundary) for the mechanism and the closed `KernelErrorCode` union.

The surfacing rule:

- **`'cancelled'` is never a user-facing failure.** It is swallowed. A cancelled job is a normal outcome of debouncing, not an error.
- **`'kernel-init-failed'` is the only fatal code.** It flips the scene to the STL fallback, so a kernel that cannot boot degrades to a working viewport rather than a blank canvas.
- **Everything else is a per-request failure** — `'invalid-params'`, `'geometry-failed'`, `'unknown-solid'` — surfaced as a recoverable UI error. They are _not_ grounds for abandoning the kernel scene.

## Performance budget

Track **first-interaction time** and **idle GPU frames**. A regression that reintroduces a continuous render loop fails review — and CI, which asserts `window.__wade.renderCount` stays flat at idle.

## Related

- [`kernel.md`](./kernel.md) — the result union and error codes
- [`rendering.md`](./rendering.md) — why view-model setters must guard on equality
- [`invariants.md`](./invariants.md) — 3
