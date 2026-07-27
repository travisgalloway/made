# wade — documentation

A CAD PWA: SvelteKit run as a client-side SPA, brepjs/OpenCascade for the geometry kernel, three.js WebGPU for rendering.

## Start here

**Read [`architecture/invariants.md`](./architecture/invariants.md) first.** Nine rules govern this codebase, most are enforced by CI rather than by convention, and the source cites them by number. Nothing else here will make sense without them.

Then, depending on what you are doing:

| If you are…                              | Read                                                                                                                               |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| New to the project                       | [invariants](./architecture/invariants.md) → [threading model](./architecture/threading-model.md) → [roadmap](./roadmap/phases.md) |
| Touching geometry or the worker          | [kernel](./architecture/kernel.md)                                                                                                 |
| Touching the viewport or anything visual | [rendering](./architecture/rendering.md) + [orientation](./architecture/orientation.md)                                            |
| Touching pointer, gesture, or snapping   | [input](./architecture/input.md)                                                                                                   |
| Building object manipulation or controls | [ui-controls](./architecture/ui-controls.md) + [document-model](./architecture/document-model.md)                                  |
| Connecting an agent to the kernel        | [agent-api](./architecture/agent-api.md)                                                                                           |
| Adding UI or a store                     | [state and errors](./architecture/state-and-errors.md)                                                                             |
| Writing tests                            | [testing](./guides/testing.md)                                                                                                     |
| About to open a PR                       | [conventions](./guides/conventions.md)                                                                                             |
| Picking up the next phase                | [roadmap](./roadmap/phases.md) → [Phase 3](./roadmap/phase-3-pwa.md)                                                               |

## The doc set

### Architecture — how it works today

- **[invariants.md](./architecture/invariants.md)** — the nine rules, and how each is enforced. Canonical; also GitHub issue #1.
- **[threading-model.md](./architecture/threading-model.md)** — main thread / kernel worker / render context, and the one-way data flow between them. The spine.
- **[kernel.md](./architecture/kernel.md)** — `KernelClient`, the wire contract, debounce and conflation, and the honest cancellation guarantee.
- **[rendering.md](./architecture/rendering.md)** — on-demand rendering, WebGPU with a WebGL2 fallback, TSL-only shading, and the `window.__wade` observability contract.
- **[orientation.md](./architecture/orientation.md)** — right-handed Z-up. World space _is_ kernel space.
- **[input.md](./architecture/input.md)** — router → arbiter → picking → snapping, and the precision model behind it.
- **[state-and-errors.md](./architecture/state-and-errors.md)** — document model / GPU / view models, and how kernel failures surface.
- **[document-model.md](./architecture/document-model.md)** — the N-object model with a command-shaped mutation API. _Designed, not built_ — the keystone for manipulation and agent work.
- **[ui-controls.md](./architecture/ui-controls.md)** — the inspector and the gizmo made real; the two-physics rule for move/rotate vs resize; the component strategy. _Designed, not built._
- **[agent-api.md](./architecture/agent-api.md)** — connecting an agent out-of-band via brepjs's Node tooling; STEP import as the bridge. _Designed, not built._

### Roadmap — what is built and what is next

- **[phases.md](./roadmap/phases.md)** — status. Phases 0–2 done, **Phase 3 next**.
- **[phase-3-pwa.md](./roadmap/phase-3-pwa.md)** — installable, offline, lazy kernel.
- **[phase-4-cad-depth.md](./roadmap/phase-4-cad-depth.md)** — sketches, constraints, booleans, STEP, feature tree.

### Guides

- **[testing.md](./guides/testing.md)** — the Node-only Vitest project, the five Playwright projects, `window.__wade`.
- **[conventions.md](./guides/conventions.md)** — commits, dependencies, and the config you must not "simplify".

### [risks.md](./risks.md)

Deferred decisions (threaded OCCT, OffscreenCanvas) and open risks (brepjs maturity, WebGPU maturity, the touch precision ceiling, the WASM payload).

## Stack

| Concern        | Pick                                                                                   |
| -------------- | -------------------------------------------------------------------------------------- |
| Framework      | SvelteKit, SPA mode (`ssr = false`), Svelte 5 runes, TypeScript                        |
| Delivery       | `@sveltejs/adapter-static` — static, client-only SPA                                   |
| Renderer       | three.js `three/webgpu` (`WebGPURenderer`), WebGL2 fallback                            |
| 3D integration | Threlte (`@threlte/core`, `@threlte/extras`)                                           |
| Kernel         | brepjs + OCCT-WASM, single-threaded, in a worker                                       |
| Worker RPC     | Comlink                                                                                |
| Picking        | three-mesh-bvh                                                                         |
| Input          | Pointer Events, hand-rolled gesture arbiter                                            |
| PWA            | `@vite-pwa/sveltekit` + Workbox — _[Phase 3](./roadmap/phase-3-pwa.md), not yet added_ |
| Tests          | Vitest (unit), Playwright (e2e)                                                        |

## Source layout

```
src/
  lib/
    kernel/          # brepjs + OCCT. The ONLY place brepjs may be named.
      kernel.worker.ts     # Comlink-exposed; the sole brepjs importer
      KernelClient.ts      # main-thread interface — pure, DI'd, imports only ./types
      createKernelClient.ts# the only `new Worker` + `Comlink.wrap`
      types.ts             # the wire contract — zero imports, by design
      geometry.ts          # MeshPayload -> BufferGeometry (the three.js seam)
    viewport/        # imperative three.js. Never reactive.
      Viewport.svelte      # owns the Threlte Canvas + renderer
      Scene.svelte         # the integration point: camera, lights, geometry, input
      renderLoop.ts        # invalidateFor() + the window.__wade contract
      orientation.ts       # the Z-up convention — single source of truth
      picking.ts           # three-mesh-bvh raycasting
      gizmo.ts, instancing.ts, framing.ts, axes.ts, sampleMesh.ts
    input/           # pure, DOM-free, node-testable
      pointerRouter.ts     # branch on pointerType
      gestureArbiter.ts    # lock navigate-vs-manipulate on first move
      snapping.ts          # vertex > edge > grid
    scene/           # view models only — never geometry
      document.svelte.ts, SceneModel.svelte.ts, SnapModel.svelte.ts
    settings/        # forceWebGL, kernel on/off
    ui/              # reactive panels. Never imports three.
      controls/           # in-house control kit (issue #68): NumberField, Slider, Section, Toggle
                           # + tokens.css, scrub.ts, numberEntry.ts
  routes/
    +layout.ts       # ssr = false, prerender = true
    +page.svelte     # app shell; owns the shared document model
e2e/                 # Playwright — five projects
static/models/       # sample-part.stl (regenerate: scripts/make-sample-part.ts)
parts/               # agent-authoring scratch (#74) — out-of-band, not built by the app
```

`src/lib/pwa/` does not exist yet — it arrives with [Phase 3](./roadmap/phase-3-pwa.md). `parts/` does not
exist yet either — see [`agent-api.md`](./architecture/agent-api.md). Nothing in `.prettierignore` or
`eslint.config.js` excludes it, so once it exists it is Prettier- and ESLint-checked like the rest of the
repo, not a scratch directory that skips CI.
