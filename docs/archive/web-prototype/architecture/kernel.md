# The kernel layer

`src/lib/kernel/` — brepjs on OpenCascade (OCCT-WASM), quarantined in a worker behind an interface of our own (invariants 1 and 4).

## Module map

| File                    | Role                                                                         |
| ----------------------- | ---------------------------------------------------------------------------- |
| `types.ts`              | The wire contract. **Zero imports**, by design.                              |
| `KernelClient.ts`       | Main-thread interface. Pure, dependency-injected — imports only `./types`.   |
| `createKernelClient.ts` | The _only_ place `new Worker` and `Comlink.wrap` are allowed to appear.      |
| `kernel.worker.ts`      | The _only_ file permitted to name `brepjs` or `occt-wasm`.                   |
| `geometry.ts`           | `toBufferGeometry(payload)` — the three.js seam, kept out of `KernelClient`. |

The split between `KernelClient.ts` and `createKernelClient.ts` is what makes the client testable: `KernelClient` takes a `connect()` function and a `Scheduler`, so unit tests drive it with a hand-written `ManualClock` and `RecordingKernel` and never boot a worker. `createKernelClient()` is the thin production wiring.

The split between `KernelClient.ts` and `geometry.ts` is the same idea applied once more — it keeps `KernelClient` free of `three`, so it runs in the Node-only Vitest project.

## The wire contract

Three request kinds, discriminated on `type`, all carrying a `jobId` and a `solidId`:

```ts
export type KernelRequest = MakeBoxRequest | MakeCylinderRequest | TessellateRequest;
```

STEP import (Phase 4) adds a fourth, `ImportStepRequest`, carrying the STEP bytes as an `ArrayBuffer`; the worker calls brepjs `importSTEP` and stores the result in the same `Map<SolidId, ValidSolid>` so it re-meshes like any other solid. Because the union is closed, adding the member forces every `switch` to be reconsidered — by design. See [`agent-api.md`](./agent-api.md#the-wade-side-step-import-path).

### Never throw across the boundary

Comlink structured-clones a thrown `Error` and loses its type — a recoverable UI condition becomes an unhandled rejection. So every fallible method returns a result union:

```ts
export type KernelResult<T> =
	{ ok: true; jobId: JobId; value: T } | { ok: false; jobId: JobId; error: KernelError };
```

`KernelErrorCode` is a **closed** union — `'kernel-init-failed' | 'invalid-params' | 'geometry-failed' | 'unknown-solid' | 'cancelled' | 'worker-crashed'` — not `string`. Adding a failure mode therefore forces every call site to reconsider, which is the whole point.

Only `'kernel-init-failed'` is fatal: it flips the scene to the STL fallback (see [`rendering.md`](./rendering.md#graceful-degradation-is-real-not-theoretical)). `'cancelled'` is never surfaced to the user — a cancelled job is a normal outcome, not a failure.

### `SolidId` vs `JobId`

Two identifiers, two different jobs, and confusing them breaks things:

- **`SolidId`** is stable across a solid's entire lifetime (`'box-1'`, `'cylinder-1'`). It is what makes **partial re-tessellation** expressible — the worker keeps a `Map<SolidId, ValidSolid>`, so `tessellate` can re-mesh one solid without rebuilding the others. Debounce and conflation are keyed on it, which is why dragging the box slider never re-tessellates the cylinder.
- **`JobId`** is never reused — one per dispatch. It is what makes **stale-drop** possible: a result whose `jobId` no longer matches the in-flight job for its solid is discarded on arrival.

### Meshes are transferred, not cloned

```ts
export interface MeshPayload {
	positions: Float32Array<ArrayBuffer>;
	normals: Float32Array<ArrayBuffer>;
	indices: Uint32Array<ArrayBuffer>;
	triangleCount: number;
}
```

Pinning the type parameter to `ArrayBuffer` rather than the default `ArrayBufferLike` is what makes `.buffer` _statically_ `Transferable`. That is the type-level statement of invariant 6 — and, indirectly, of invariant 7, since `SharedArrayBuffer` could never satisfy it. `types.spec.ts` asserts the source buffers actually detach after send.

`meshTransferables()` de-dupes via a `Set`: if a future brepjs ever returned several views over one buffer, listing that buffer twice would make `postMessage` throw `DataCloneError`.

## Debounce and conflation

Requests are debounced **60 ms** and conflated **per solid** — there is exactly one pending slot per `SolidId`, so a fast slider drag collapses to the latest value rather than queueing every intermediate one. Superseded inputs are counted (`stats.dropped`) rather than silently discarded.

`KernelClient` never calls `invalidate()` itself. Triggering a frame is the caller's decision, made once per settled update in `Scene.svelte` — so "one invalidate per completed update" is enforced at the seam rather than buried in the client.

## Cancellation: the honest guarantee

This is the subtlest thing in the layer, and both sides of the boundary document it identically rather than pretending otherwise.

**OCCT-WASM is single-threaded and `mesh()` is synchronous.** A `cancel()` message therefore _physically cannot_ be delivered while a job is inside it — the worker's event loop is blocked. No amount of API design changes that.

So the guarantee is not "cancel stops the work." It is:

> **At most one stale computation can ever run to completion per solid.**

Two mechanisms together produce it:

- **Worker side** — every operation awaits a macrotask yield and re-checks a `cancelledJobs` set _before_ touching OCCT. A cancel that arrives while the worker is idle preempts the job entirely.
- **Client side** — a job flagged as cancelled never becomes a mesh, even if it returns `ok: true`. Results are dropped by `jobId`.

A cancel arriving mid-`mesh()` is a no-op; that one job runs to completion and its result is thrown away. That is the cost of invariant 7, and it is bounded.

## Kernel init

`ensureReady()` memoizes initialization manually rather than calling brepjs's own `init()`. It loads the WASM through Vite's content-hashed `?url` import and registers the adapter itself.

Calling brepjs's `init()` would re-derive the WASM URL and **race** this one. The `?url` import is also what makes the asset cacheable by the future service worker ([Phase 3](../roadmap/phase-3-pwa.md)).

Because `connect()` is lazy, **constructing a `KernelClient` does not boot the ~22 MB WASM** — only the first `request()` or `warmup()` does.

## Gotchas

- `new Worker` must not run at module scope. SvelteKit's prerender pass executes the module graph in Node, where `Worker` does not exist. `createKernelClient()` is called inside an `$effect`.
- `kernel.worker.ts` never names `self`. `Comlink.expose()` defaults its endpoint to `globalThis`, and the tsconfig has no `webworker` lib (adding it produces duplicate-identifier errors and breaks `pnpm check`).
- Geometry from the kernel is **indexed by construction** — `toBufferGeometry` always calls `setIndex`, which is what lets the viewport assert `allGeometriesIndexed()`.

## Related

- [`threading-model.md`](./threading-model.md) — why the boundary exists
- [`state-and-errors.md`](./state-and-errors.md) — how kernel errors surface in the UI
- [`invariants.md`](./invariants.md) — 1, 4, 6, 7
