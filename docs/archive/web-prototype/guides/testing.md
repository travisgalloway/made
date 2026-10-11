# Testing

Two layers, with a sharp line between them: **anything pure is unit-tested in Node; anything touching the DOM or the GPU is tested end-to-end in a real browser.** There is no middle tier, and that is deliberate.

## Unit tests — Vitest

Colocated `*.spec.ts` next to the source.

**There is exactly one Vitest project, and it runs in `environment: 'node'`. There is no jsdom.**

That constraint drives a lot of the codebase's shape. It is _why_ `gestureArbiter`, `pointerRouter`, `snapping`, `picking`, `framing`, `instancing`, `geometry`, and `KernelClient` are written as pure functions and classes over plain data — they have to be testable with no DOM shim. All the DOM and Threlte glue is quarantined in `Scene.svelte` and `Viewport.svelte`, which Playwright covers instead.

Two knock-on effects worth knowing:

- `kernel/types.ts` has **zero imports**, and `KernelClient.ts` imports only `./types` — no `comlink`, no `three`. That is what lets them run here at all.
- `KernelClient` takes an injectable `Scheduler`, so its tests drive a hand-written `ManualClock` and `RecordingKernel`. **No `vi.mock`, no `vi.useFakeTimers()`** — the house style is hand-written stubs.

### `expect.requireAssertions` is on globally

An `it()` block containing no `expect()` **fails**. A test that asserts nothing is a bug, not a passing test.

### Running them

```sh
pnpm test:unit --run                                  # all (omit --run for watch mode)
pnpm test:unit --run src/lib/input/snapping.spec.ts   # one file
pnpm test:unit --run -t 'locks to manipulate'          # by name substring
```

## End-to-end — Playwright

`e2e/*.e2e.ts`. The `webServer` config runs `npm run build && npm run preview` on port 4173, so **e2e always runs against a real production build** — and against a secure context, which WebGPU requires.

### Five projects, and why they are separate

| Project       | Spec                 | Why it exists                                                                                                                                                              |
| ------------- | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `chromium`    | `viewport.e2e.ts`    | **No WebGPU flag** — so `navigator.gpu` is absent and the renderer takes its WebGL2 fallback. This is what keeps the fallback genuinely exercised rather than theoretical. |
| `webgpu`      | `webgpu.e2e.ts`      | `--enable-unsafe-webgpu --enable-gpu`. Chrome ships a SwiftShader WebGPU backend, so a headless CI runner with no GPU still gets a real adapter — no GPU runner needed.    |
| `kernel`      | `kernel.e2e.ts`      | Kernel-driven. `timeout: 150_000` — it waits on the ~22 MB occt-wasm module compiling on first load.                                                                       |
| `snapping`    | `snapping.e2e.ts`    | Kernel-driven, same long timeout.                                                                                                                                          |
| `orientation` | `orientation.e2e.ts` | Kernel-driven. The Z-up regression suite.                                                                                                                                  |

The split is not cosmetic. The first two run against **`?kernel=off`** so they never wait on the WASM compile; separating them is what lets the fast suites keep a tight timeout while the kernel suites get a generous one. Neither inherits the other's.

Splitting `snapping` and `orientation` out rather than folding them into `kernel` means a `testMatch` change to one cannot accidentally pick up the other's spec file.

### Running them

```sh
pnpm test:e2e                                                    # all five
pnpm exec playwright test --project=kernel                       # one project
pnpm exec playwright test e2e/snapping.e2e.ts                    # one file
pnpm exec playwright test --project=webgpu -g 'WebGPU is the active backend' # by title
```

Omitting `--project` runs all five, including the slow kernel-driven ones.

## The `window.__wade` contract

**E2E asserts against `window.__wade`. It does not scrape the DOM.**

The object is declared in `src/lib/viewport/renderLoop.ts` and every field is documented with the issue that introduced it: `renderCount`, `backend`, `drawCalls`, `allIndexed`, `selected`, `hovered`, `gizmoVisible`, `boltCount`, `kernelReady`, `kernelMeshCount`, `kernelError`, `snapKind`, `snapPoint`, `boxExtents`, `axesPresent`, `projectToNdc`.

**Adding a new e2e assertion means adding a `__wade` field**, not reaching into the canvas or the DOM.

## Two patterns you will need

**Boot settle.** Every suite has a `waitForRenderCountToSettle()` helper — poll until `renderCount` is unchanged across three consecutive 150 ms polls — before asserting idle flatness. Kernel suites additionally gate on `window.__wade.kernelReady`.

**Idle flatness.** This is how invariant 2 is actually enforced. Once the scene settles, a repeated no-op interaction must **not** advance `renderCount`. If you add anything that invalidates on every `pointermove`, these tests will catch it.

## The exact draw-call assertion

`viewport.e2e.ts` asserts an **exact** `EXPECTED_DRAW_CALLS` against the `?kernel=off` scene — not a loose bound.

**Consequence: adding any mesh to the fallback scene breaks that test.** This is precisely why the grid, the axes triad, and the snap marker are mounted **only in the kernel scene**, and why `window.__wade.axesPresent` exists to pin that asymmetry down.

If you need to add something to the fallback scene, you are changing the expected count deliberately — update the constant and say why in the commit.

## Regenerating the sample part

Not part of the build. `node scripts/make-sample-part.ts` regenerates `static/models/sample-part.stl` — an asymmetric L-bracket, asymmetric on purpose so that "centered and framed" and picking are meaningful from any orbit. **Commit the regenerated STL** when you change it.

STL rather than glTF is deliberate: brepjs's `importSTL()` can ingest the same file later.
