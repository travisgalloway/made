# ADR-D9: Fate of Euclid Mesh Path

- **Status:** Accepted, 2026-10-14
- **Issue:** #247 (BL-KRN-13)
- **Decides:** Disposition of `nicklockwood/Euclid` pure-Swift mesh CSG engine following canonical B-Rep kernel selection ([ADR-D1](./ADR-D1-canonical-geometry-kernel.md))
- **Related decisions:** [ADR-D1: Canonical Geometry Kernel](./ADR-D1-canonical-geometry-kernel.md), [ADR-D2: Modeling Paradigm and Document Model](./ADR-D2-modeling-paradigm-and-document-model.md), [ADR-D6: Scripting Runtime](./ADR-D6-scripting-runtime.md), [ADR-D8: Project License](./ADR-D8-project-license.md)

## Context

In Phase 2, `made` implemented pure-Swift Constructive Solid Geometry (CSG) using `nicklockwood/Euclid` (0.9.6) (`EuclidEngine`, `LocalKernelEngine`, `ShapeEvaluator`) to provide instant 3D geometry rendering and boolean operations without C++ dependencies.

In Phase 4.0, [ADR-D1](./ADR-D1-canonical-geometry-kernel.md) (#142) established OpenCASCADE Technology (OCCT) via `OCCTSwift` (#82) as the canonical B-Rep CAD kernel for `made`, with clean-room pure-Swift B-Rep (#420–#424) as the App Store fallback. ADR-D1 demoted Euclid from the canonical kernel to an optional secondary fast preview engine and unit test backend, deferring to issue #247 (BL-KRN-13) the definitive decision on whether Euclid should be retained permanently or retired once OCCT integration is complete.

As `made` expands to support exact B-Rep modeling, topological naming ([ADR-D3](./ADR-D3-topological-naming.md)), 2D constraint solving ([ADR-D4](./ADR-D4-2d-constraint-solver.md)), declarative CAD DSL scripting (`CADDSL`, #85), and headless agent evaluation (#428, #429), the project requires a definitive decision on the architectural fate of the Euclid mesh engine.

## Options Considered

1. **Complete removal of Euclid once OCCT integration lands (#82).**
   - *Pros:* Single geometry backend; eliminates dual-engine codebase maintenance; ensures all geometry operations share identical topological semantics.
   - *Cons:* Requires the heavy OCCT C++ toolchain and pre-compiled `OCCT.xcframework` for every developer and CI job; significantly inflates clean build and test turnaround times; breaks existing lightweight, in-process unit tests; prevents instant zero-IPC headless shape evaluation for lightweight tooling and scripting.
   - *Verdict:* Rejected.

2. **Demotion exclusively to unit test mock fixtures.**
   - *Pros:* Keeps test suite execution fast without requiring OCCT for unit testing of high-level models.
   - *Cons:* Forfeits Euclid's sub-millisecond execution speeds for interactive parameter scrubbing in the UI and fast procedural shape tree previews; creates dead or test-only code paths divergent from runtime capabilities.
   - *Verdict:* Rejected.

3. **Permanent retention as Tier 1 pure-Swift fast CSG preview engine and lightweight test backend.**
   - *Pros:*
     - **Sub-millisecond interactive parameter scrubbing:** Provides instant 60–120 Hz interactive feedback during slider drags and procedural shape preview before committing high-cost B-Rep calculations.
     - **Zero C++ compilation requirement for core development:** Contributors working on UI, viewport, shaders, MCP tooling, or scripting DSL can build and run tests instantly with pure Swift tools.
     - **Lightweight test execution:** Enables hundreds of kernel, document, and scripting tests (e.g., `EuclidEngineTests`, `ShapeEvaluationTests`, `CADDSLTests`) to execute in seconds without XPC overhead or external C++ runtimes.
     - **Clean engine neutrality:** Exercises and reinforces Invariant 4 (`KernelRequest`/`MeshPayload` wire contract), proving that subsystems remain decoupled from any single concrete kernel.
     - **Permissive MIT licensing:** Euclid is MIT-licensed ([ADR-D8](./ADR-D8-project-license.md)), adding zero copyleft or distribution friction to App Store or open-source builds.
   - *Cons:* Requires maintaining the `EuclidEngine` conversion and CSG evaluation code alongside OCCT B-Rep pipelines.
   - *Verdict:* Accepted.

## Decision

1. **Euclid is permanently retained as the Tier 1 pure-Swift fast CSG preview engine and unit test backend.**
   `nicklockwood/Euclid` (0.9.6) remains an integral part of `made`'s multi-tier geometry architecture. It serves as:
   - The primary fast mesh preview engine for procedural primitives, procedural shape trees (`ShapeEvaluator`), and rapid parameter adjustment.
   - The default in-process engine (`LocalKernelEngine`) for unit testing, test fixture generation, and headless verification without C++ or XPC prerequisites.
   - The draft preview backend for procedural scripting expressions prior to exact B-Rep feature baking.

2. **Reaffirm the multi-tier geometry architecture:**
   - **Tier 1 (Fast CSG Engine):** Pure-Swift `EuclidEngine` / `LocalKernelEngine`. Provides immediate polygonal CSG booleans (`subtract`, `union`, `intersect`), parametric primitives (box, cylinder, sphere, cone), profile extrusion/revolution, and indexed triangle payload generation (`MeshPayload`).
   - **Tier 2 (Canonical Exact B-Rep Engine):** OpenCASCADE Technology via `OCCTSwift` (#82) / clean-room Swift B-Rep (#420–#424). Provides exact analytic curves, NURBS, topological B-Rep entities, fillets, chamfers, drafts, shells, and STEP/IGES exchange.
   - **Tier 3 (Declarative CAD DSL):** Declarative scripting layer (`CADDSL.swift`, `ShapeNode.swift`). Compiles shape operation trees evaluated against the active kernel engine.

3. **Strict adherence to the engine-neutral interface (Invariant 4).**
   All higher-level subsystems—including SwiftUI views, Inspector, Metal viewport, document model, scripting, and agent tooling—must interact with geometry exclusively via `KernelClientProtocol`, `KernelRequest`, and `MeshPayload` defined in [`macos/Sources/MadeCore/Kernel/Types.swift`](../../../macos/Sources/MadeCore/Kernel/Types.swift).
   - No Euclid types (`Euclid.Mesh`, `Euclid.Polygon`, `Euclid.Vector`) may leak past the `Kernel/` boundary into `Scene/`, `Viewport/`, `Agent/`, or `Scripting/`.
   - `LayeringTests.scriptingReferencesNoEuclid` strictly enforces this boundary at build and test time.

4. **Preserve actor and process isolation (Invariants 1 & 7).**
   All Euclid operations execute off the main thread within `KernelClient` or engine actors (`LocalKernelEngine`), ensuring responsive UI interactions, debounce conflation, and thread safety under Swift 6 strict concurrency.

## Consequences

- **Developer experience:** Contributors can build, test, and run `made` with standard Swift toolchains without installing C++ CAD libraries or configuring complex binary frameworks.
- **Interactive performance:** Real-time parameter scrubbing and procedural shape tree evaluations maintain sub-millisecond execution times.
- **Architectural decoupling:** Retaining two distinct engines (Tier 1 Euclid and Tier 2 OCCT) actively exercises and validates Invariant 4, preventing accidental coupling between client code and B-Rep kernel details.
- **Test suite velocity:** The existing 417+ test suite runs in under 3 seconds in pure Swift without requiring XPC service setup or heavy framework boots.
- **Clear limitations:** Euclid cannot perform exact CAD operations (fillets, chamfers, draft angles, STEP exchange, persistent topological naming). When such operations are requested, the request routes to Tier 2 (OCCT), returning explicit error diagnostics (`geometryFailed`) if the Tier 2 engine is unavailable.
- **Licensing:** Euclid's MIT license is cataloged in `LicenseCatalog.swift` and `Resources/licenses.json`, completely compliant with `made`'s MPL-2.0 project license ([ADR-D8](./ADR-D8-project-license.md)).

## Notes

- 2026-10-17: `LayeringTests.scriptingReferencesNoEuclid` was renamed. `LayeringTests.scriptingReferencesNoKernelInternals` (`macos/Tests/MadeCoreTests/LayeringTests.swift:27`) now enforces the boundary in Decision item 3.
