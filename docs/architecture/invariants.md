# Architectural invariants

**This is the canonical list. It is also GitHub issue #1**, which is why source comments cite it both ways — "invariant 8" and "architecture issue #1" refer to the same thing.

These must hold at every phase. **Treat a violation as a build break.** If a task seems to require breaking one, stop and flag it rather than working around it.

> **The numbers are load-bearing.** Every one of the nine is cited by number somewhere in the source — in comments, in config files, and in two test names. Six phrasings are in use (`invariant N`, `Invariant N`, `architecture invariant N`, `Architecture invariant N`, `invariant-N`, `invariants N and M`). **Never renumber.** Add new invariants at the end.

---

## The nine

1. **The kernel runs only in a Web Worker.** No brepjs or OCCT call ever executes on the main thread.

2. **Rendering is on-demand.** No continuous animation loop. The renderer draws only when the camera moves, a solid changes, or a transient interaction is active. In Threlte this is `renderMode="manual"` plus `invalidate()`.

3. **The canvas is imperative, not reactive.** Svelte reactive state drives UI panels only. Geometry and per-frame state never live in `$state` that would re-run on each frame.

4. **The kernel sits behind our own interface.** All UI and render code talks to a `KernelClient` abstraction, never to brepjs directly, so the kernel can be swapped later.

5. **WebGPU initializes async, with a WebGL2 escape hatch.** Await renderer init before the first frame. Expose a `forceWebGL` setting wired to a runtime toggle for benchmarking and fallback.

6. **Meshes cross the worker boundary as transferable typed arrays.** Positions, normals, indices are transferred, never structurally cloned.

7. **Start single-threaded on OCCT.** Do not pull in SharedArrayBuffer or cross-origin isolation. That decision is deferred to a later, separate task.

8. **Navigation and editing never share a gesture.** Multi-finger input drives the camera, single-pointer input selects and manipulates, and a pen is the precise create-and-edit channel. The gesture arbiter locks the mode on the first movement and holds it until release.

9. **Precision comes from snapping and typed values, not steady fingers.** Move and resize are driven by gestures plus snapping and inference, never by demanding a precise drag on a small handle.

---

## How each one is enforced

The distinction that matters: some invariants are **checked** — CI fails if you break them — and some are only **asserted**, meaning they hold by construction and by review. Know which is which before you rely on one.

| #   | Status      | Enforced by                                                                                                                                                                                                                                                    |
| --- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Checked** | `eslint.config.js` — see below. `pnpm lint` fails on violation.                                                                                                                                                                                                |
| 2   | **Checked** | `e2e/viewport.e2e.ts` and `e2e/snapping.e2e.ts` assert `window.__wade.renderCount` stays flat at idle. `renderLoop.ts` contains no `requestAnimationFrame` or `setAnimationLoop`.                                                                              |
| 3   | Asserted    | View models hold only lightweight references (`$state.raw`). `ParamsPanel.svelte` never imports `three`. Reviewed, not automated.                                                                                                                              |
| 4   | **Checked** | `KernelClient.ts` imports only `./types` — no comlink, no three, no brepjs. The invariant-1 ESLint rule catches any regression here too.                                                                                                                       |
| 5   | **Checked** | Playwright's `chromium` project runs _without_ the WebGPU flag, so `navigator.gpu` is absent and the WebGL2 fallback is genuinely exercised. `e2e/webgpu.e2e.ts` asserts `window.__wade.backend === 'webgpu'` by default and `'webgl2'` under `?forceWebGL=1`. |
| 6   | **Checked** | `types.ts` pins `Float32Array<ArrayBuffer>` (not `ArrayBufferLike`) so `.buffer` is _statically_ `Transferable`. `types.spec.ts` asserts the source buffers detach after send.                                                                                 |
| 7   | Asserted    | No COOP/COEP headers anywhere; the single-threaded occt-wasm build is the one installed.                                                                                                                                                                       |
| 8   | **Checked** | `gestureArbiter.spec.ts` and `pointerRouter.spec.ts` — both modules are pure and unit-tested.                                                                                                                                                                  |
| 9   | **Checked** | `snapping.spec.ts` covers the vertex > edge > grid precedence; `e2e/snapping.e2e.ts` drives it end to end.                                                                                                                                                     |

### The invariant-1 lint rule is worth understanding

`eslint.config.js` bans `brepjs`, `brepjs/*`, `occt-wasm`, and `occt-wasm/*` across all of `src/**`, with exactly one exception: `src/lib/kernel/kernel.worker.ts`.

It uses the **base** `no-restricted-imports` rule rather than the `@typescript-eslint` one. That is deliberate — the base rule also flags `import type`, so the invariant stays true even for type-only imports. The payoff is that invariant 1 reduces to a claim CI can actually check:

> no file other than `kernel.worker.ts` **imports** `brepjs` or `occt-wasm` — type-only imports included.

Note the word _imports_. The rule inspects import statements, not file text, so it is not the same as "the string `brepjs` appears once": the name also shows up in explanatory comments in `types.ts`, `KernelClient.ts`, `geometry.ts`, `geometry.spec.ts`, and `viewport/orientation.ts`. A `grep -rl brepjs src/` returning more than one file is expected and is **not** a violation.

The converse rule also exists: `kernel.worker.ts` may not import `three`, `@threlte/*`, `$app/*`, or `$lib/*`. The worker has no DOM, no renderer, and no SvelteKit runtime — it talks to the main thread only through the typed wire contract in `kernel/types.ts`.

---

## A tenth convention, unnumbered

The **right-handed Z-up world** ([`orientation.md`](./orientation.md)) postdates the original nine and is not part of the numbered list, but it carries the same weight: violating it puts the viewport and the kernel into disagreement about which way is up. It is left unnumbered precisely because the numbers are load-bearing and appending to the list retroactively would be more confusing than a named convention.

---

## Related

- [`threading-model.md`](./threading-model.md) — invariants 1, 6, and 7 in practice
- [`rendering.md`](./rendering.md) — invariants 2 and 5
- [`kernel.md`](./kernel.md) — invariants 1, 4, 6
- [`input.md`](./input.md) — invariants 8 and 9
- [`state-and-errors.md`](./state-and-errors.md) — invariant 3
