# Risks and deferred decisions

Things we know are shaky, and the decisions we deliberately did not make yet.

## Deferred decisions

### Threaded OCCT

The multithreaded OCCT build is faster, but it requires `SharedArrayBuffer`, which requires cross-origin isolation (`COOP: same-origin`, `COEP: require-corp`). Invariant 7 starts single-threaded to avoid that constraint entirely.

**Revisit only if meshing shows up as a _measured_ bottleneck.** It is a deliberate, separate task — never an incidental change, because it touches hosting headers and the whole security context. On a static host, a service-worker shim can inject the COEP header.

The visible cost of staying single-threaded today: cancellation cannot preempt a running job, because `mesh()` is synchronous and blocks the worker's event loop. The codebase is explicit about this rather than pretending otherwise — see [the honest cancellation guarantee](./architecture/kernel.md#cancellation-the-honest-guarantee).

### Rendering in a worker

`OffscreenCanvas` would free the main thread from drawing entirely, and is supported on desktop Chromium. It is a **phase-two lever, not a current design** — verify behavior on non-Chromium fallback targets before committing.

## Open risks

### brepjs is young and single-maintainer

**This is exactly why invariant 4 exists.** All UI and render code talks to `KernelClient`, never to brepjs directly, so replicad or raw OCCT could be swapped in without touching the UI.

Practical guidance: **keep the surface you use small.** Every brepjs API the worker calls is a thing that has to be re-implemented if the kernel is ever swapped.

### WebGPU is still maturing

The renderer is still labelled experimental, and some scenes are genuinely faster on WebGL2. Two mitigations, both already in place:

- The `forceWebGL` escape hatch stays wired to a runtime setting, so backends can be compared on real hardware.
- **The WebGL2 fallback is exercised in CI, not merely available.** Playwright's `chromium` project runs without the WebGPU flag on purpose. A fallback nobody tests is a fallback that does not work.

**Benchmark honestly.** If WebGPU is losing on a real scene, that is worth knowing.

### Touch precision has a ceiling

Fingertips occlude their own target and lack precision. This is a known, permanent limit of touch CAD, not a bug to be fixed.

Mitigate with snapping, inference, offset picking (`OCCLUSION_OFFSET_PX`), and typed values — and **do not promise mouse-level precision from bare touch.** See [`architecture/input.md`](./architecture/input.md).

### The WASM payload

~22 MB of occt-wasm, uncompressed. Nothing about the current build hides this — the app waits on it today.

[Phase 3](./roadmap/phase-3-pwa.md) is the mitigation: lazy-load the kernel behind an interactive shell, cache the binary once, and investigate a slim OCCT build. Until then, first load is slow, and the `kernel` Playwright project needs a 150-second timeout to accommodate it.
