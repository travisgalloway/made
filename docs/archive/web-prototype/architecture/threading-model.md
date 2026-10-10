# Threading model

This is the spine. Everything else hangs off getting it right.

## Three separable execution contexts

| Context           | Owns                                                | Never does                             |
| ----------------- | --------------------------------------------------- | -------------------------------------- |
| **Main thread**   | SvelteKit UI, panels, input, render orchestration   | Heavy geometry math, continuous redraw |
| **Kernel worker** | brepjs + OCCT-WASM, booleans, fillets, tessellation | Touch the DOM                          |
| **Render**        | three.js WebGPU scene, GPU uploads, drawing         | Block on kernel work                   |

Rendering currently runs on the main thread. Moving it to a render worker via `OffscreenCanvas` is a known lever, not a current design — see [`risks.md`](../risks.md).

## Data flow is one direction

```
UI intent  ──▶  KernelClient  ──▶  worker  ──▶  OCCT computes exact B-rep
                                                 tessellates only what changed
                                                          │
   GPU  ◀── one invalidate() ◀── BufferGeometry ◀─────────┘
                                   (transferred, zero-copy)
```

A UI intent goes to the kernel worker. The worker computes the exact B-rep, tessellates **only what changed**, and transfers mesh buffers — positions, normals, indices as typed arrays — back using `Transferable` objects for a zero-copy handoff (invariant 6). The render side uploads those buffers to the GPU and requests **exactly one frame** (invariant 2).

Nothing flows the other way. The renderer never calls the kernel; the kernel never reads scene state.

## Why the boundary is enforced, not just intended

Invariant 1 says no brepjs or OCCT call ever executes on the main thread. This is not a performance guideline — OCCT-WASM is a large, synchronous, single-threaded blob, and a single tessellation on the main thread would freeze the UI outright.

So the boundary is a **lint rule**, not a convention. `eslint.config.js` permits the string `brepjs` in exactly one file (`kernel.worker.ts`) and forbids that file from importing `three`, `@threlte/*`, or any `$lib` module in return. See [`invariants.md`](./invariants.md#the-invariant-1-lint-rule-is-worth-understanding).

## Comlink, not hand-written postMessage

The worker is wrapped with [Comlink](https://github.com/GoogleChromeLabs/comlink) so the main thread calls it like a normal async API. The wire contract lives in `src/lib/kernel/types.ts`, which is deliberately **zero-import** — that is what lets both it and `KernelClient` run in the Node-only Vitest project, and it is the type-level half of invariant 1.

One rule that is easy to get wrong: **never throw across the boundary.** Comlink would structured-clone the `Error` and lose its type, turning a recoverable UI condition into an unhandled rejection. Every fallible kernel method returns a result union instead. See [`kernel.md`](./kernel.md).

## Single-threaded OCCT, deliberately

The multithreaded OCCT build is faster, but it needs `SharedArrayBuffer`, which requires cross-origin isolation (`COOP: same-origin`, `COEP: require-corp`). That is a real constraint on a static host and a deliberate, separate decision — so invariant 7 starts single-threaded.

This has a visible consequence, and the codebase is honest about it rather than papering over it: because OCCT is single-threaded and `mesh()` is synchronous, **a cancel message cannot be delivered while a job is running.** The cancellation guarantee is correspondingly modest — see [`kernel.md`](./kernel.md#cancellation-the-honest-guarantee).

If meshing ever shows up as a measured bottleneck, the escape route is a service-worker shim that injects the COEP header. Not before.

## Related

- [`kernel.md`](./kernel.md) — the wire contract and `KernelClient` in detail
- [`rendering.md`](./rendering.md) — what happens after the mesh lands
- [`invariants.md`](./invariants.md) — 1, 6, 7
