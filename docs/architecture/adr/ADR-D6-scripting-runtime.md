# ADR-D6: Scripting Runtime

- **Status:** Accepted, 2026-10-12
- **Issue:** #148
- **Implemented by:** #435 (part runtime), #427 (reload), #428 (MCP inspection tools), #429 (plugin skill), #85 (REPL)

## Context

In the Mac MVP, external agents edit part source files directly, and the running app rebuilds the model when a file is saved. Agents then inspect the app over MCP. The brepjs agent workflow (https://brepjs.dev/agent/overview) is the model for this loop. The part file language must therefore run inside the released app, with no developer tools installed, and later on iPad.

`made` already has a Swift result-builder DSL in `Scripting/CADDSL.swift`. Running a Swift part file needs the Swift compiler, which the released app and iPads do not have.

## Options Considered

1. The Swift DSL, compiled at runtime. Rejected, because the released app has no Swift toolchain.
2. JavaScriptCore running TypeScript or JavaScript part files. Accepted.
3. Embedded Python, which reaches the CadQuery and build123d ecosystem. Rejected, because it adds bundle size and sandbox friction, and it cannot ship easily on iPad.

## Decision

Part files are TypeScript, with a brepjs-style API, evaluated by JavaScriptCore.

- **File format.** Part files use the `.part.ts` extension. Plain `.part.js` files also load.
- **Runtime.** JavaScriptCore ships with macOS and iOS, so the app bundles no interpreter and adds no license obligation. A bundled JavaScript type stripper, such as Sucrase (MIT), removes TypeScript types at load time.
- **Type checking.** The app publishes `made.d.ts`. Agents and editors run `tsc --noEmit` against it before saving. The app itself reports runtime errors only.
- **API.** The `made` module follows brepjs naming where it fits. brepjs is Apache-2.0, so its API shape and documentation may be adapted with its notice kept. Agents that know brepjs then need little new guidance.
- **Intent checks.** A part file may export an `expected` block with volume, area, bounds, and tolerance. `cad_verify` compares the built part with it (#428).

## Consequences

- **Scripts describe geometry and never compute it.** A script returns a shape description (an operation tree). Swift validates the tree and evaluates it through `KernelClient`. Scripts never call Euclid or OCCT, which keeps invariant 4.
- **Evaluation runs off the main thread.** The runtime owns a `JSVirtualMachine` on a dedicated thread (invariant 1). Results carry a job ID, and superseded results are discarded (invariant 7).
- **Scripts run in a restricted context.** They have no network, file system, timer, or process access. Imports resolve only to the `made` module and to files in the part's directory. `Math.random` and `Date` are seeded or fixed, so the same file always builds the same part.
- **Runaway scripts are an open implementation question.** JavaScriptCore has no public API to interrupt a running script. #435 must choose a limit, for example by running evaluation in a separate process.
- **Errors map to source.** Diagnostics report the original `.part.ts` file, line, and column.
- **The Swift DSL stays for tests and library use.** `CADDSL.swift` is not the user or agent part format. The interactive REPL (#85) uses the JavaScript runtime.
- **Scripting issues retarget the TypeScript API.** #331, #332, #333, and #334 now describe the JavaScript runtime. #330, the multi-statement result builder, applies to the Swift test DSL only.
- **iPad support follows.** JavaScriptCore runs on iPadOS, so the same part files work there (#84).
