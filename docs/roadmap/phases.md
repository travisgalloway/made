# Phases and status

## Rules of engagement

- **Complete phases in order — meaning _dependency_ order, not calendar order.** Finish a phase before declaring it done, and do not skip ahead casually. But the rule exists to stop work building on foundations that do not exist yet, not to serialize independent work: an item whose dependencies are all met may start even if its phase's other items are outstanding. The roadmap has one deliberate cross-phase edge — Phase 3's persistence (#76) depends on Phase 4's document model (#65) — and reading the rule as strict calendar order would make that edge unsatisfiable.
- **Keep commits small within a phase**, and commit at the end of each phase with a clear message.
- **The [architectural invariants](../architecture/invariants.md) are non-negotiable.** If a task seems to require breaking one, stop and flag it rather than working around it.
- **After each phase, run the build and the dev server** and confirm the verification items yourself before reporting the phase done.

See [`../guides/conventions.md`](../guides/conventions.md) for commit format and dependency policy.

---

## Status at a glance

| Phase                      | Status        | Closed by                         |
| -------------------------- | ------------- | --------------------------------- |
| **0** — Project foundation | ✅ Done       | `00d49d0` (#51), `438f00b` (#52)  |
| **1** — Viewport MVP       | ✅ Done       | `47626c2` (#53) → `ee77141` (#57) |
| **2** — Kernel worker      | ✅ Done       | `9a876cb` (#58) → `cad936f` (#60) |
| **3** — PWA hardening      | 🔜 **Next**   | not started                       |
| **4** — CAD depth          | ⬜ Open-ended | not started                       |

---

## Phase 0 — Project foundation ✅

SvelteKit + TypeScript + Svelte 5, `adapter-static` with `ssr = false` and `prerender = true`, ESLint, Prettier, Vitest, Playwright, CI.

**Verification — all passing.** `pnpm build` produces a static SPA with no SSR; `pnpm dev` serves the shell; lint, format, and tests run clean.

---

## Phase 1 — Viewport MVP ✅

A WebGPU viewport that renders a mesh, orbits, picks, and transforms — drawing only on demand. No kernel; a static STL is loaded instead.

**Delivered:** `Viewport.svelte` with an async-initialized `WebGPURenderer` and a `forceWebGL` escape hatch; `renderLoop.ts` with on-demand invalidation; OrbitControls; BVH picking with occlusion offset; the pointer router and gesture arbiter; a transform gizmo; instanced bolts.

**Verification — all passing.** A GPU frame is issued only on interaction (asserted via `window.__wade.renderCount`). Selection and gizmo work. Touch, pen, and mouse all work, and multi-finger navigation never blends with single-pointer selection. A gesture that starts as an orbit stays an orbit until release. WebGPU is active by default and the WebGL2 fallback renders when forced — asserted in CI, not just by hand.

---

## Phase 2 — Kernel worker ✅

brepjs runs in a worker behind `KernelClient`, and the viewport renders a live parametric primitive.

**Delivered:** `kernel.worker.ts` (single-threaded OCCT, Comlink-exposed); the zero-import `types.ts` wire contract with transferable `MeshPayload`; `KernelClient` with 60 ms per-solid debounce, conflation, and stale-job cancellation; partial re-tessellation keyed on `SolidId`; UI-driven box and cylinder; and `snapping.ts` — vertex, edge, and grid snapping, which is the foundation the Phase 4 interactions build on.

**Verification — all passing.** Dragging a parameter slider updates the solid with no main-thread jank. No brepjs symbol is reachable from the main thread except through `KernelClient` — enforced by ESLint, so this is checked on every CI run rather than reviewed. Meshes are transferred, verified by asserting the source buffer is detached after send.

**Follow-up:** `0aa820c` (#62) fixed an up-axis disagreement between the viewport and the kernel that Phase 2 exposed. It established the [Z-up convention](../architecture/orientation.md).

---

## Phase 3 — PWA hardening 🔜

**This is next, and it has not been started** — there is no `@vite-pwa/sveltekit` dependency, no manifest, and no service worker.

Tracked by epic #5 (#28–#33, #49, #76). See [`phase-3-pwa.md`](./phase-3-pwa.md).

Note the one cross-phase edge: persistence (#76) depends on the document model (#65), a Phase 4 item. Everything else in Phase 3 is independent and can start immediately.

---

## Phase 4 — CAD depth ⬜

Larger and open-ended. Tracked by epic #6.

**Start with the document model (#65).** It replaces the hard-wired two-solid scene with an N-object model behind a command API, and nearly everything else — inspector, gizmo write-back, undo, STEP import, the feature tree, and Phase 3's persistence — depends on it. `KernelClient` is already N-solid-capable; the ceiling is entirely in the scene wiring above it.

See [`phase-4-cad-depth.md`](./phase-4-cad-depth.md).
