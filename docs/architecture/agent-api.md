# Agent integration

How an agent produces geometry for wade. The model is deliberately **out-of-band**: the agent authors and verifies parts with brepjs's own Node tooling, and wade imports the validated result. There is no live command bus into the running browser kernel.

> **Status: designed, not built.** The STEP import path lands in Phase 4 (issue #38); the authoring workflow is documentation (#74). See [`../roadmap/phase-4-cad-depth.md`](../roadmap/phase-4-cad-depth.md).

## Why posture 1 (out-of-band), not a live command bus

brepjs ships an agent toolchain — `brepjs-cad`, exposing a `brep` CLI and a `brep-mcp` stdio MCP server — built around a **verify loop**: the agent writes CAD code, a kernel runs it, and the measured result is checked before hand-off. That toolchain is **Node-only** (`.brep.ts` type-stripping, `fs` export, an MCP server as a local child process).

Wade runs the same occt-wasm kernel in a _browser worker_. Two integration models were possible:

1. **Adopt brepjs's verify loop out-of-band** — the agent authors and verifies parts in Node; wade imports the STEP. This is what brepjs documents, and it is what we do.
2. **Invent a live command bus** — an agent drives wade's running browser kernel to create/modify/delete solids on screen. This is not covered by brepjs, would be entirely wade's own protocol, and would need a live-editing command surface layered on the document model.

Posture 1 is chosen because it delivers agentic part generation with the least invention, stays on brepjs's supported path, and keeps wade a pure client-side static PWA — no backend, invariant 7 (single-threaded, no cross-origin isolation) untouched. The agent's brepjs runs in Node, so invariant 1 (no brepjs on wade's main thread) is not even in play for the authoring step.

The runtime that runs the verify loop is a local developer tool. This planning round does not tie wade to any particular host for it.

## The authoring workflow (developer tooling, not app code)

The agent (e.g. Claude Code) runs `brep-mcp` locally, out of process, and works the loop:

1. **Author** `parts/<name>.brep.ts` — a default export that is a zero-argument function returning a shape or a `Result<shape>`, with an optional `expected` block declaring intent:

   ```ts
   export default () => box(40, 20, 10, { centered: true });
   export const expected = { volume: 8000, tolerancePct: 1 };
   ```

2. **Verify** out-of-band against occt-wasm in Node — the kernel runs the part, checks the `validSolid` brand, measures `volume` / `area` / bounds, compares them to `expected`, and emits a JSON report (`ok`, `checks`, `measurements`, `assertions`, `hints`, `errorInfos`). The agent repairs and re-runs until `ok`.

3. **Export** the validated **STEP** file — the only artifact handed to wade.

No wade app code is involved, and no command bus exists. The units line up: brepjs is millimetres and right-handed Z-up, which is exactly wade's world convention (see [`orientation.md`](./orientation.md)), so an imported part needs no reorientation.

## The wade-side STEP import path

Importing a part reuses the existing kernel seam — Phase 4 already lists STEP import/export.

- **`kernel/types.ts`** (the zero-import wire contract): add `ImportStepRequest { type: 'importStep'; jobId; solidId; step: ArrayBuffer }` to `KernelRequest` / `KernelRequestInput`, and `importStep` to `KernelWorkerApi`. Because those unions are closed, adding a member forces every switch (`toKernelRequest`, `dispatch`) to be reconsidered — by design.
- **`kernel.worker.ts`**: `importStep(req)` calls brepjs `importSTEP(new Blob([req.step]))`, unwraps the `Result`, stores the solid in the existing `solids: Map<SolidId, ValidSolid>` (so later `tessellate` and resize-commit re-mesh it identically to a box or cylinder), and returns via the existing `toMeshPayload`. brepjs is named only here — invariant 1 preserved.
- **`KernelClient`**: add the `importStep` case to `dispatch` / `toKernelRequest`; it inherits per-`SolidId` debounce and stale-drop unchanged.
- **Render**: no new path. An imported object is a `SceneObject` with `def.kind: 'imported'`; its `SolidNode` sends one `importStep` request and renders through the existing `toBufferGeometry` + `buildBoundsTree`. Invariant 4 holds — the UI still talks only to `KernelClient`.
- **UI**: a plain-DOM "Import STEP" file input → `File.arrayBuffer()` → `document.addObject({ kind: 'imported', name })` plus the bytes. The STEP bytes are persisted in the document so an offline reload can rebuild the solid (see [`document-model.md`](./document-model.md) and Phase 3 persistence).

## Two bridge levels

**Near-term (recommended): STEP import, mesh-only, one-way (agent → wade).** wade sees an opaque imported solid — transformable (move/rotate, or scale kept as transform) and pickable, but its intrinsic features are not UI-editable. Low complexity, reuses every existing path, and because `def` is a discriminated union the future kind slots in without a refactor.

**Longer-term (defer, gate on demand): wade executes `.brep.ts` in its own worker.** Transpile `.brep.ts` in-worker with the esbuild already present under Vite, evaluate the default export inside `kernel.worker.ts` (brepjs already lives there — invariant 1 holds), and mesh the result. Then the agent and the UI share **one parametric source**: a `def.kind: 'brep-script'` holding the source, exposed as an `evalBrep` `KernelClient` request kind (invariant 4 — the UI never evaluates code directly).

This is the one genuinely delicate item: evaluating transpiled TypeScript in the worker. It is acceptable under posture 1 because the source is locally authored and trusted, but it is called out and gated rather than assumed. **Ship STEP import now; reserve `brep-script` in the `ObjectDef` union; build the executor only when a parametric round-trip is actually needed** (issue #75, deferred).

## Related

- [`document-model.md`](./document-model.md) — where imported (and reserved brep-script) objects live
- [`kernel.md`](./kernel.md) — the wire contract `importStep` extends
- [`orientation.md`](./orientation.md) — why an imported part needs no reorientation
- [`invariants.md`](./invariants.md) — 1, 4, 7
