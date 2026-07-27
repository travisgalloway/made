# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`wade` is a CAD PWA: SvelteKit (Svelte 5 runes) + brepjs/OpenCascade for the geometry kernel + three.js WebGPU for rendering. It builds to a static, client-only SPA.

`docs/` holds the full architecture reference — start at `docs/README.md`. The sections below are the short version; the docs are the long one. Most relevant:

- `docs/architecture/invariants.md` — the nine rules, canonical. Read this before any substantial change.
- `docs/architecture/` — kernel, rendering, orientation, input, state, threading model.
- `docs/roadmap/phases.md` — what is built and what is next.
- `docs/guides/` — testing and conventions.

## Commands

pnpm only (`pnpm@10.14.0`). Node >= 24 is a hard requirement — `brepjs@18` declares it and `.npmrc` sets `engine-strict=true`, so a wrong Node version fails `pnpm install` outright.

| Task            | Command                                         |
| --------------- | ----------------------------------------------- |
| Dev server      | `pnpm dev`                                      |
| Build / preview | `pnpm build` / `pnpm preview`                   |
| Typecheck       | `pnpm check` (svelte-check)                     |
| Lint            | `pnpm lint` (`prettier --check .` + `eslint .`) |
| Format          | `pnpm format`                                   |
| Unit tests      | `pnpm test:unit --run` (omit `--run` for watch) |
| E2E tests       | `pnpm test:e2e`                                 |
| Everything      | `pnpm test`                                     |

Run a single unit test by file or by name:

```sh
pnpm test:unit --run src/lib/input/snapping.spec.ts
pnpm test:unit --run -t 'locks to manipulate on the first move'
```

Run a single e2e project or test. Omitting `--project` runs all five, including the slow kernel-driven suites:

```sh
pnpm exec playwright test --project=kernel
pnpm exec playwright test e2e/snapping.e2e.ts
pnpm exec playwright test --project=webgpu -g 'WebGPU is the active backend'
```

CI (`.github/workflows/ci.yml`, Node 24, every PR) runs `check → lint → test:unit → build` in one job and Playwright in another.

## Architectural invariants

These are the design contract. `docs/architecture/invariants.md` is the canonical list (it is also GitHub issue #1) and calls them non-negotiable — "treat a violation as a build break". Source comments cite them by number, so **the numbers can never be reassigned**. If a task seems to require breaking one, stop and flag it rather than working around it.

1. **The kernel runs only in a Web Worker.** No brepjs or OCCT call ever executes on the main thread.
2. **Rendering is on-demand.** No continuous animation loop. Draw only when the camera moves, a solid changes, or a transient interaction is active.
3. **The canvas is imperative, not reactive.** Reactive state drives UI panels only; geometry and per-frame state never live in `$state`.
4. **The kernel sits behind our own interface.** UI and render code talk to `KernelClient`, never to brepjs.
5. **WebGPU initializes async, with a WebGL2 escape hatch.** Await renderer init before the first frame.
6. **Meshes cross the worker boundary as transferable typed arrays.** Never structurally cloned.
7. **Start single-threaded on OCCT.** No `SharedArrayBuffer`, no COOP/COEP.
8. **Navigation and editing never share a gesture.** The arbiter locks the mode on first movement and holds it until release.
9. **Precision comes from snapping and typed values, not steady fingers.**

Most are enforced mechanically, not by convention:

| #   | Enforced by                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `eslint.config.js` bans `brepjs`/`occt-wasm` across `src/**` with one exception: `kernel.worker.ts`. It uses the **base** `no-restricted-imports` rule, not the TS one, so `import type` is caught too — the invariant is checkable as "no file but `kernel.worker.ts` _imports_ brepjs/occt-wasm". It checks imports, not file text; the name appears in comments elsewhere. The converse rule bans `three`/`@threlte`/`$app`/`$lib` inside the worker. |
| 2   | `viewport/renderLoop.ts` — no `requestAnimationFrame` anywhere; e2e asserts the render count is flat at idle.                                                                                                                                                                                                                                                                                                                                            |
| 3   | `eslint.config.js` bans `three`/`three/*`/`@threlte/*` across `src/lib/ui/**` — same base `no-restricted-imports` rule as invariant 1, so `import type` is caught too.                                                                                                                                                                                                                                                                                   |
| 4   | `KernelClient.ts` imports only `./types` — no comlink, no three, no brepjs.                                                                                                                                                                                                                                                                                                                                                                              |
| 5   | Playwright's `chromium` project runs **without** the WebGPU flag, so the WebGL2 fallback stays exercised rather than theoretical.                                                                                                                                                                                                                                                                                                                        |
| 6   | `types.ts` pins `Float32Array<ArrayBuffer>` (not `ArrayBufferLike`) so `.buffer` is statically `Transferable`; `types.spec.ts` asserts source buffers detach.                                                                                                                                                                                                                                                                                            |

## The kernel boundary (`src/lib/kernel/`)

Main thread ↔ worker over **Comlink** on a module Worker. The wire contract is `types.ts`, which is deliberately **zero-import** — that is what lets it and `KernelClient` run in the Node-only Vitest project, and it is the type-level half of invariant 1.

- **Never throw across the boundary.** Every fallible method returns `KernelResult<T>` / `KernelOutcome`. Comlink would structured-clone a thrown `Error` and lose the code, turning a recoverable UI condition into an unhandled rejection. The `KernelErrorCode` set is closed, so adding a failure mode forces every call site to reconsider.
- **`SolidId` vs `JobId`.** `SolidId` is stable across a solid's lifetime and is what makes partial re-tessellation expressible. `JobId` is never reused, one per dispatch, and is what makes stale-drop possible.
- **`KernelClient` is pure and DI'd** — it takes a `connect()` and a `Scheduler`. `new Worker` and `Comlink.wrap` live _only_ in `createKernelClient.ts`. `connect()` is lazy, so constructing a client does not boot the ~22 MB wasm.
- **Requests are debounced 60 ms and conflated per solid** — one pending slot each, so dragging the box slider never re-tessellates the cylinder.
- **The cancellation guarantee is deliberately modest.** OCCT-WASM is single-threaded and `mesh()` is synchronous, so a `cancel()` physically cannot be delivered mid-job. Neither side pretends otherwise. What _is_ guaranteed: at most one stale computation runs to completion per solid. The worker yields to the macrotask queue and re-checks cancellation before touching OCCT; the client drops results by `jobId`.

`geometry.ts` (`toBufferGeometry`) is a separate module from `KernelClient` precisely so the client stays three-free and Node-testable.

## Rendering (`src/lib/viewport/`)

**There is no rAF loop.** `renderLoop.ts` is not a loop — no `requestAnimationFrame`, no `setAnimationLoop`, no `renderMode="always"`. `invalidateFor(invalidate, reason)` is the only sanctioned way to trigger a draw, and `InvalidateReason` (`'camera' | 'resize' | 'model' | 'interaction'`) names the four legal triggers at every call site. View-model setters no-op when the value is unchanged — hover and snap fire on every `pointermove`, and an unconditional invalidate would resurrect a continuous loop.

`Viewport.svelte` is the only file that constructs a renderer. It always builds a `WebGPURenderer` from `three/webgpu`; the WebGL2 path is not a separate class — that renderer _silently falls back_ when `navigator.gpu` is absent or `forceWebGL` is set. Consequently **`WebGPURenderer` supports no `ShaderMaterial`, `RawShaderMaterial`, or `onBeforeCompile`.** Custom shading must be TSL node materials.

`window.__wade` (declared in `renderLoop.ts`) is the app's entire e2e observability surface — `renderCount`, `backend`, `drawCalls`, `kernelReady`, `snapKind`, `boxExtents`, and so on. **A new viewport feature publishes a hook there; e2e never scrapes the DOM.**

## Coordinate convention: right-handed Z-up

`viewport/orientation.ts` is the single source of truth. X = width (right), Y = depth (away), Z = height (up).

This is not three.js's Y-up default, and that is the point: OCCT/brepjs is Z-up, so **world space _is_ kernel space**. A kernel mesh mounts with zero rotation and a snap point can be handed to the kernel as-is — no conversion layer at the seam. Read `WORLD_UP` / `GROUND_NORMAL` / `DEFAULT_VIEW_DIRECTION` rather than writing vectors inline.

`installZUpWorld()` must be called at module/script scope, **not** in an `$effect`: `Object3D.DEFAULT_UP` is copied into each object's own `up` at construction, so running it after the camera exists leaves a Y-up camera in a Z-up world.

Several three.js primitives are authored Y-up and fight this. Each is corrected once, at the boundary, and the fixes are audited in `orientation.ts`: `GridHelper` is rotated onto XY, `CylinderGeometry` is rotated on the geometry (so instance transforms stay plain translations), `HemisphereLight` is rotated, and the Y-up sample STL is rotated at load.

## Input pipeline (`src/lib/input/`)

Four stages, strictly separated (invariants 8 and 9):

- **`pointerRouter.ts` — which channel.** Pen always manipulates, never navigates. Mouse decides click-vs-drag at a 6 px threshold. Touch is forwarded to the arbiter.
- **`gestureArbiter.ts` — navigate or manipulate.** More than one concurrent pointer ⇒ navigate; a lone pointer ⇒ manipulate. It deliberately does _not_ decide on first `down` (two fingers landing milliseconds apart must still be navigate); it locks on the first move and never flips until all pointers release.
- **`picking.ts` — what's under the ray.** three-mesh-bvh, CPU-side and renderer-agnostic. Every pickable geometry needs `buildBoundsTree()` first. Touch and pen pick rays are lifted 40 px above the contact point so a fingertip never occludes its own target.
- **`snapping.ts` — where exactly.** Priority is strictly vertex > edge > grid: a numerically closer lower-priority candidate never beats a higher-priority one still inside tolerance, which is what stops the indicator jittering between kinds.

Both pure modules take plain pointer-ish structs, not real `PointerEvent`s, so they unit-test in the Node-only Vitest project. Only `Scene.svelte` touches the DOM or the three.js scene graph.

## Svelte 5 / SvelteKit specifics

- **Runes are forced on** for every non-`node_modules` file (`vite.config.ts`). Scene stores follow one shape: `.svelte.ts` file, factory function, closure-local runes, an object of getters. `settings.svelte.ts` is the exception — a module-level singleton.
- **Static SPA.** `src/routes/+layout.ts` is `ssr = false` + `prerender = true`, with `adapter-static`. There is **no `svelte.config.js`** — the adapter is configured inline in `vite.config.ts`.
- The prerender pass still executes the module graph, so `new Worker`, `document`, and canvas textures must stay inside an `$effect`, never at module scope.

## Gotchas

- **Do not "clean up" the three occt-wasm settings in `vite.config.ts`.** `worker: { format: 'es' }`, `optimizeDeps: { exclude: ['occt-wasm'] }`, and `build: { target: 'esnext' }` are each load-bearing and commented; removing any one breaks the wasm load.
- **Unit tests run in a single Node-env Vitest project — there is no jsdom.** Anything unit-tested must be pure and DOM-free. DOM and Threlte glue is quarantined in `Scene.svelte`/`Viewport.svelte` and covered by Playwright instead. Tests use hand-written stubs (a `ManualClock`, a `RecordingKernel`), not `vi.mock`/fake timers.
- **`expect.requireAssertions` is on globally** — an `it()` with no `expect()` fails.
- **`e2e/viewport.e2e.ts` asserts an _exact_ draw-call count.** Adding any mesh to the `?kernel=off` fallback scene breaks it. That is why the grid, axes triad, and snap marker are mounted only in the kernel scene.
- **`?kernel=off` and `?forceWebGL=1` are real graceful-degradation paths**, not just test hooks — a fatal kernel-init error live-falls-back to the STL scene. Query params beat localStorage, so Playwright needn't seed storage.

## Current phase

Phases 0 (foundation), 1 (viewport MVP), and 2 (kernel worker) are done. **Phase 3 — PWA hardening — is next and not started**: no `@vite-pwa/sveltekit`, no manifest, no service worker.

Complete phases in **dependency** order (see `docs/roadmap/phases.md`): finish a phase before declaring it done, but an item whose dependencies are met may start even if its phase's other items are outstanding. There is one deliberate cross-phase edge — Phase 3's persistence (#76) depends on Phase 4's document model (#65).

If you are picking up Phase 4, **start with #65**: it replaces the hard-wired two-solid scene with an N-object document model behind a command API, and nearly everything else in Phases 3–4 depends on it.

## Conventions

- **Commits:** `<type>(<scope>): <description> (#issue) (#PR)`, e.g. `feat(input): vertex/edge/grid snapping foundation (#27) (#60)`. Scopes in use: `kernel`, `viewport`, `input`, `infra`. Bodies are explanatory prose, not bullet dumps — they name the invariant the change upholds, say why alternatives were rejected, and describe how the change was verified.
- **Prefer many small, single-purpose files** over few large ones.
- **Check a dependency's current version and API before installing it** rather than trusting a version pinned in the docs — those are guidance, not gospel. See `docs/guides/conventions.md`.
