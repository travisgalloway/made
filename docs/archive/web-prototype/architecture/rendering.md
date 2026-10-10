# Rendering

`src/lib/viewport/` — three.js WebGPU via Threlte, drawing only when something changed.

## On-demand rendering is not optional

A CAD scene is static until the user acts. **There is no `requestAnimationFrame` loop anywhere in this codebase**, and `renderLoop.ts` opens by saying so: no `setAnimationLoop`, no `renderMode="always"`.

Threlte's `renderMode="manual"` plus `invalidate()` is the mechanism. The only sanctioned way to trigger a draw is:

```ts
invalidateFor(invalidate, reason);
export type InvalidateReason = 'camera' | 'resize' | 'model' | 'interaction';
```

Those four are the complete set of legal reasons to draw, and naming one at every call site is what keeps the set honest. A change that reintroduces a continuous render loop **fails review** — and, in practice, fails CI: `e2e/viewport.e2e.ts` and `e2e/snapping.e2e.ts` assert `window.__wade.renderCount` stays flat once the scene settles.

### The idle-quiescence trap

Hover and snap resolve on _every_ `pointermove`. If their view models invalidated unconditionally, moving the mouse across the canvas would produce a continuous stream of frames — a render loop by another name, and invariant 2 would be dead without a single `rAF` in sight.

So `SceneModel` and `SnapModel` **no-op when the value has not actually changed**. `SnapModel` compares structurally (`kind` equal _and_ `point.equals(point)`). That equality guard is load-bearing, not an optimization.

## One renderer, two backends

`Viewport.svelte` is the only file that constructs a renderer, and it always constructs a `WebGPURenderer` from `three/webgpu`.

**The WebGL2 path is not a second renderer class.** `WebGPURenderer` silently falls back to a WebGL2 backend when `navigator.gpu` is absent, or when `forceWebGL` is set. So "which backend am I on" is a runtime property of one object, not a branch in our code.

- **Initialization is async** (invariant 5). `renderMode` starts as `'manual'` so no frame is issued before `renderer.init()` resolves, then flips to `'on-demand'`.
- The backend is not knowable until init resolves. `publishBackend(renderer)` then sniffs `renderer.backend.isWebGPUBackend` and publishes `window.__wade.backend` as `'webgpu' | 'webgl2'`.
- `settings.forceWebGL` comes from `?forceWebGL=1` (query param wins) or `localStorage`. The `<Canvas>` is wrapped in `{#key settings.forceWebGL}` so toggling it rebuilds the renderer.

### Shaders are TSL. This is a hard constraint.

`WebGPURenderer` does **not** support `ShaderMaterial`, `RawShaderMaterial`, `onBeforeCompile`, or the legacy `EffectComposer`. Any custom shading must be authored in TSL node materials (`MeshStandardNodeMaterial`, `MeshBasicNodeMaterial`, `SpriteNodeMaterial`), which compile to the WebGL2 fallback as well.

If you need selection outlines or SSAO later, use the WebGPU-native RenderPipeline node stack, and keep it minimal.

## Keeping draw calls down

- **Instance repeated hardware.** `instancing.ts` renders the bolts as a single `InstancedMesh` — one draw call regardless of count.
- **Index everything.** All viewport geometry is indexed `BufferGeometry`; `allGeometriesIndexed()` guards it and kernel geometry is indexed by construction.
- **Re-tessellate only changed solids**, never the whole assembly. This is a kernel-side property — see [`kernel.md`](./kernel.md).
- **Cap pixel ratio** at `Math.min(devicePixelRatio, 2)`.

## `window.__wade` — the observability contract

Declared in `renderLoop.ts`. It is the app's _entire_ end-to-end test surface: `renderCount`, `backend`, `drawCalls`, `allIndexed`, `selected`, `hovered`, `gizmoVisible`, `boltCount`, `kernelReady`, `kernelMeshCount`, `kernelError`, `snapKind`, `snapPoint`, `boxExtents`, `axesPresent`, `projectToNdc`.

**A new viewport feature publishes a hook here. E2E never scrapes the DOM.** Each field is documented with the issue that introduced it.

Two entries exist for a reason worth remembering: `boxExtents` and `projectToNdc` were added after the Z-up bug (#61/#62), because that regression lived in the _camera's_ idea of up — the geometry was always correct, so no world-space measurement could see it. Only a projection into screen space could. See [`orientation.md`](./orientation.md).

`instrumentRenderer()` monkey-patches `renderer.render` to count draws, and sets `renderer.info.autoReset = false` with a manual reset — because three's own per-frame reset only runs inside its animation-loop scheduler, which this app never uses.

## Graceful degradation is real, not theoretical

Two query params switch the app into a degraded mode, and both are **real fallback paths that also happen to be useful in tests** — not test-only hooks:

- **`?kernel=off`** — skips the worker entirely and renders the Phase 1 STL scene. This is the same branch a fatal `kernel-init-failed` takes, so a kernel that fails to boot degrades to a working viewport instead of a blank canvas.
- **`?forceWebGL=1`** — forces the WebGL2 backend.

Query params beat `localStorage`, specifically so Playwright need not seed storage.

**One consequence to know before adding anything to the scene:** `e2e/viewport.e2e.ts` asserts an _exact_ draw-call count against the `?kernel=off` scene. The grid, the axes triad, and the snap marker are therefore mounted **only in the kernel scene**. Adding a mesh to the fallback scene breaks that test. See [`../guides/testing.md`](../guides/testing.md).

## Related

- [`orientation.md`](./orientation.md) — the Z-up world the renderer draws into
- [`input.md`](./input.md) — picking and snapping feed the `'interaction'` invalidate reason
- [`invariants.md`](./invariants.md) — 2 and 5
