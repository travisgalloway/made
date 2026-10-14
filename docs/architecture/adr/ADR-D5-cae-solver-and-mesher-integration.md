# ADR-D5: CAE Solver and Mesher Integration Strategy

- **Status:** Accepted, 2026-10-14
- **Issue:** #147
- **Implemented by:** #413 (Helper bundling), #187 (Solver runner), #188 (Volume mesher), #186 (CFD runner), #352 (Remote solve), #416 (Clean-room Swift solver), #417 (Clean-room Swift mesher), #157 (Study model), #219 (Linear static FEA), #190 (Thermal conduction), #192 (Result storage), #328 (Convergence plots), #281 (Parametric sweep), #353 (Solver verification), #415 (Clean-room libs), #419 (App Store distribution)

## Context

Computer-Aided Engineering (CAE) extends `made` from a geometric authoring system into a multiphysics engineering analysis platform (Phase 6, #109, #157). Mechanical design workflows require rigorous numerical simulation to evaluate structural integrity, thermal dissipation, and fluid flow prior to physical fabrication:
1. **Linear Static Structural Analysis (FEA, #219):** Computes displacements, strains, and Cauchy/von Mises stress tensors under external mechanical loads (forces, pressures, body accelerations) and kinematic boundary conditions (fixed clamps, pinned supports, roller constraints).
2. **Steady-State Thermal Conduction (#190):** Solves Fourier heat conduction across solid bodies subject to prescribed boundary temperatures, convective film coefficients, and volumetric heat generation rates.
3. **Incompressible Computational Fluid Dynamics (CFD, #186):** Solves the Navier-Stokes equations for internal and external aerodynamic flow fields, pressure drops, and skin friction coefficients.
4. **Tetrahedral Volume Meshing (#188):** Discretizes 3D solid continuum domains into linear (4-node C3D4) and quadratic (10-node C3D10) tetrahedral finite element meshes. Crucially, the mesher must operate directly upon exact Boundary Representation (B-rep) geometry (`TopoDS_Shape` from OpenCASCADE Technology, [ADR-D1](./ADR-D1-canonical-geometry-kernel.md), #82) or standard STEP exchange files, rather than intermediate faceted polygon meshes (such as Euclid CSG). Generating volume elements from exact analytic surfaces (planes, cylinders, spheres, NURBS) ensures geometric fidelity and prevents artificial boundary layer stress concentrations.

### Licensing and Distribution Boundaries

Maintainer decisions establish that `made` is licensed under MPL-2.0 ([ADR-D8](./ADR-D8-project-license.md), #145). This imposes strict structural constraints on third-party engineering software integration:
- **Direct-Download Releases (#254):** Direct-download macOS releases allow dynamically linking LGPL-2.1 libraries (such as OCCT, [ADR-D1](./ADR-D1-canonical-geometry-kernel.md)), but strictly prohibit in-process linking of GPL-licensed dependencies (such as CalculiX or Gmsh) to prevent viral copyleft obligations from attaching to `made`'s application code. Under the legal doctrine of "mere aggregation," GPL-licensed tools may be bundled as separate executable programs alongside `made` in `MadeApp.app/Contents/Helpers/` (#413), communicating exclusively over operating system process boundaries via disk files.
- **App Store & iPadOS Distribution (#419, #84):** The sandboxed Mac App Store and iPadOS environments prohibit spawning arbitrary unnotarized helper subprocesses and disallow GPL-licensed binaries. To ensure long-term availability across Apple platforms, strategic clean-room pure-Swift reimplementations of the FEM solver (#416) and volume mesher (#417) in `libs/` (#415) provide an unencumbered, zero-dependency fallback architecture.

### Operational Contrast with 2D Constraint Solving (ADR-D4)

The operational requirements of CAE simulation differ fundamentally from 2D sketch constraint solving ([ADR-D4](./ADR-D4-2d-constraint-solver.md), #146):
- 2D sketch constraint solving is an **interactive, real-time** task operating at 60–120 Hz. When dragging a sketch vertex, the solver must converge within sub-16ms latency budgets to avoid UI hitching. Out-of-process execution or disk I/O would introduce unacceptable latency and frame drops; therefore, ADR-D4 mandates in-process background actor execution.
- CAE simulation, by contrast, consists of **discrete, batch compute jobs** spanning seconds, minutes, or hours. Meshing and solving involve heavy matrix factorizations (e.g., Sparse direct solvers or conjugate gradient iterations) and consume hundreds of megabytes or gigabytes of RAM. Running CAE solvers and meshers out-of-process as independent command-line executables driven by file decks introduces negligible overhead relative to the solve time, while offering vital architectural advantages: total crash isolation, decoupled process lifecycles, real-time stdout/stderr diagnostic streaming to the console drawer (#187, #328), and seamless dispatch to remote high-performance computing clusters or cloud runners (#352).

A definitive architecture decision record is required to select the canonical CAE solvers and volume meshers, define the out-of-process file deck execution protocol, establish process lifecycle and cancellation semantics, define binary location resolution order, specify disk cache layout, and map the clean-room Swift fallback path.

---

## Options Considered

### 1. In-Process Library Linking — Strictly Rejected

Link existing C/C++ or Fortran simulation libraries (e.g., CalculiX engine routines, Gmsh C++ API, or Netgen C++ library) directly into the `made` or `MadeKernelService` process.
- **Advantages:** Direct memory sharing of mesh data structures; avoids writing intermediate input decks and result files to disk.
- **Disadvantages & Rejection Rationale:**
  1. **Strict GPL Copyleft Conflict:** CalculiX `ccx` is licensed under GPL-2.0-or-later, and Gmsh is licensed under GPL-2.0-or-later. Linking GPL code in-process into `made` imposes viral copyleft obligations across the entire application codebase under ADR-D8 (#145), violating `made`'s MPL-2.0 license and breaching App Store distribution rules (#419).
  2. **Memory Safety Hazards:** Legacy numerical solvers written in Fortran 77/90 and C contain pointer arithmetic, global static memory pools, and unsafe buffer operations. A memory corruption bug, array bounds violation, or stack overflow inside solver code would cause a fatal segmentation fault (`SIGSEGV`) terminating the entire host CAD application.
  3. **Threading and Runtime Conflicts:** OpenMP threading runtimes bundled in Fortran/C solvers conflict with Grand Central Dispatch (GCD) and Swift 6 cooperative thread pool schedulers, causing thread starvation and kernel scheduling contention on Apple silicon efficiency and performance cores.

### 2. Out-of-Process File Deck Execution — Accepted as Primary Canonical Architecture

Execute established open-source CLI executables (CalculiX `ccx` for structural/thermal, Gmsh for tetrahedral meshing, and OpenFOAM for CFD) as independent subprocesses communicating strictly via standard file decks on disk (`.inp`, `.msh`, `.frd`).
- **Advantages:**
  1. **Licensing Compliance via Mere Aggregation:** Running GPL-licensed executables as separate subprocesses communicating via standard disk files qualifies as "mere aggregation" under GPLv2 and GPLv3. The `made` application remains cleanly licensed under MPL-2.0.
  2. **Total Crash and Fault Isolation (Invariant 1):** If a solver encounters numerical divergence, memory exhaustion, or a fatal segmentation fault, only the child process dies. `MadeApp` remains completely stable, captures exit status and stderr, and displays structured diagnostics in the UI.
  3. **Streaming Diagnostics (Invariant 7):** Standard output and error streams are piped line-by-line to `WorkspaceModel.log(_:_:_:)` for live monitoring in the Console drawer (#187) and convergence plot tracking (#328).
  4. **Universal Standard File Decks:** CalculiX natively consumes industry-standard Abaqus `.inp` decks, while Gmsh natively reads STEP/B-rep files and outputs standard `.msh` formats. This enables interoperability with external commercial CAE packages (Abaqus, ANSYS, Nastran).
  5. **Natural Path to Cloud / Remote Compute (#352):** Because the execution contract is entirely encapsulated in disk file decks, jobs can be dispatched to remote Linux compute servers, headless containers, or cloud clusters without altering solver runner semantics.
- **Trade-offs:** Small file I/O overhead to write the input deck and parse results. For CAE jobs taking multiple seconds or minutes, this microsecond-scale I/O overhead is completely negligible.

### 3. Remote or Cloud Solve via Decoupled File Decks — Accepted as Natural Architectural Extension

Dispatch simulation input decks to remote high-performance compute nodes or cloud clusters (Phase 8, #352 BL-SIM-06).
- **Advantages:** Offloads intensive FEA/CFD computations from mobile hardware (e.g., MacBook Air or iPad); enables massive parallel parameter sweeps (#281).
- **Trade-offs:** Requires network connectivity and remote credential configuration. Fully enabled by the decoupled file deck architecture of Option 2.

### 4. Clean-Room Pure-Swift Solver and Mesher in `libs/` — Accepted as Strategic App Store Fallback

Develop pure-Swift linear static FEA (#416) and 3D Delaunay volume meshing (#417) libraries in `libs/` under the clean-room procedure (#415).
- **Advantages:**
  1. **100% Unencumbered for App Store & iPadOS:** Authored from first-principles engineering textbooks (e.g., Bathe, *Finite Element Procedures*; Zienkiewicz & Taylor, *The Finite Element Method*) without inspecting GPL source code. Fully unencumbered for the Apple App Store (#419) and iPadOS sandboxes (#84).
  2. **Native Swift 6 & Apple Silicon Optimization:** Direct integration with Apple's Accelerate framework (`SparseSolve`, `vDSP`, BLAS/LAPACK) and Metal compute shaders.
  3. **Zero Subprocess Overhead:** Runs directly on background Swift actors without spawning helper processes.
- **Trade-offs:** Developing an industrial-grade FEA solver and robust volume mesher from scratch requires substantial engineering investment. Therefore, like the Swift B-rep engine in ADR-D1 (#420), it acts as the strategic fallback while CalculiX and Gmsh deliver immediate production capabilities for the Mac direct-download MVP.

---

## Decision

1. **Strict Rejection of In-Process GPL Linking.**
   CalculiX, Gmsh, OpenFOAM, and any other GPL-licensed CAE tools shall never be linked in-process into `made`, `MadeKernelService`, or any internal dynamic framework.

2. **Canonical Desktop Architecture: Out-of-Process File Deck Execution.**
   For macOS direct-download releases, CAE volume meshing and numerical solving execute strictly out-of-process via disk file decks. `made` generates standardized input decks, launches CLI helper executables in isolated process groups, captures stdout/stderr in real time, and parses result files back into engine-neutral Swift value types.

3. **Canonical Structural & Thermal Solver Selection: CalculiX `ccx`.**
   CalculiX CrunchiX (`ccx`) is selected as the primary canonical solver for:
   - Linear static structural analysis (#219): Computes displacements, stresses, and reaction forces.
   - Steady-state thermal conduction (#190): Computes temperature distributions and heat flux vectors.
   - Coupled thermo-mechanical analysis (Phase 8).
   `ccx` is driven by standard Abaqus-compatible `.inp` input decks generated by `MadeCore`, and outputs volumetric nodal results in `.frd` (CalculiX Frd result) and `.dat` formats.

4. **Canonical Volume Mesher Selection: Gmsh.**
   Gmsh is selected as the primary canonical volume mesher (#188). Gmsh incorporates native OpenCASCADE B-rep geometry support, enabling direct meshing of CAD boundary surfaces (`.step` / `TopoDS_Shape`) into linear 4-node (C3D4) and quadratic 10-node (C3D10) tetrahedra without polygonal faceting errors. Gmsh generates `.msh` format files (version 2.2 or 4.1 ASCII/binary), which `MadeCore` parses into internal mesh representations.

5. **Canonical CFD Solver Selection: OpenFOAM (Phase 8, #186).**
   OpenFOAM is designated as the solver for incompressible steady fluid flow in Phase 8 (#186), driven via standard OpenFOAM case directories (`0/`, `constant/`, `system/`).

6. **Bundled Helper Distribution and Binary Location Resolution Order (#413).**
   For direct-download releases (#254), pre-compiled, code-signed, and notarized arm64 binaries for `ccx` and `gmsh` are bundled inside `MadeApp.app/Contents/Helpers/`. When executing a simulation or meshing job, `MadeCore` resolves the executable binary path using the following strict priority sequence:
   1. *Environment Variable Override:* `MADE_CALCULIX_PATH`, `MADE_GMSH_PATH`, or `MADE_OPENFOAM_PATH`.
   2. *Application Bundle Helpers:* `Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/<binary>")`.
   3. *Developer Environment & System PATH:* `/opt/homebrew/bin/<binary>`, `/usr/local/bin/<binary>`, or search in standard `$PATH`.
   4. *Graceful Typed Failure:* If no executable is located, return a typed failure `CAEErrorCode.solverBinaryNotFound(solver: String, searchedPaths: [URL])`. The application shall never crash or silently fail.

7. **Dual-Engine Distribution Strategy & Clean-Room Swift Fallback (#415-#417, #419).**
   - Direct-download macOS releases (#254) bundle CalculiX and Gmsh under `Contents/Helpers/` (#413), accompanied by full license texts, attribution notices (#425), and a written offer for corresponding source code fulfilling GPL mere aggregation requirements.
   - App Store builds on macOS (#419) and iPadOS (#84) utilize clean-room pure-Swift reimplementations:
     - `libs/made-fem`: Pure-Swift FEM solver implementing linear elastic and thermal conduction formulations on linear/quadratic tetrahedra (#416).
     - `libs/made-mesh`: Pure-Swift Delaunay tetrahedral volume mesher operating from boundary surface representations (#417).
   - Reimplementations are developed in accordance with the clean-room provenance protocol (#415), citing academic textbooks and papers in `PROVENANCE.md`.

8. **Strict Engine-Neutral Swift Interface in `MadeCore` (Invariant 4).**
   UI components, Viewport renderers, Document models, and MCP agent tools interact solely with engine-neutral Swift protocols and value types defined in `MadeCore/Simulation`:
   - Protocols: `SolverRunnerProtocol`, `VolumeMesherProtocol`.
   - Input Specifications: `CAEStudy`, `MeshSpecification` (target element size, element order: linear C3D4 vs quadratic C3D10, refinement regions), `CAEDeck`.
   - Results: `CAEResult` holding `VolumeMesh`, `NodalField` (scalar fields such as temperature, von Mises stress; vector fields such as displacement, heat flux), and `ElementField`.
   - Errors: Exhaustive typed errors conforming to `Sendable` and `Codable`:
     ```swift
     public enum CAEErrorCode: Sendable, Codable, Equatable {
         case solverBinaryNotFound(solver: String, searchedPaths: [String])
         case meshingFailed(reason: String, exitCode: Int32)
         case solverFailed(reason: String, exitCode: Int32)
         case solverDiverged(iterations: Int, residual: Double)
         case invalidStudyConfiguration(message: String)
         case resultParsingFailed(details: String)
         case executionCancelled
     }
     ```
   Neither CalculiX `.inp` syntax, Gmsh `.geo` scripting, POSIX process handles, nor CLI flags leak beyond the runner implementations.

9. **Concurrency, Process Groups, and Cancellation Semantics (Invariants 1 & 7).**
   - Subprocess execution occurs strictly off the main UI thread via asynchronous background actors (`SolverRunnerActor`, `VolumeMesherActor`).
   - Every child process is spawned inside an independent POSIX process group using `setpgid(0, 0)` via `Process.qualityOfService = .userInitiated`.
   - **Immediate Cancellation Guarantee (Invariant 7):** When a user or agent cancels an active job, or when `MadeApp` terminates:
     1. `SIGTERM` is dispatched immediately to the negative process group ID (`kill(-pgid, SIGTERM)`), allowing the child executable to cleanly terminate any scratch file handles.
     2. A 500 ms grace period is observed; if the process group remains active, `SIGKILL` (`kill(-pgid, SIGKILL)`) is dispatched.
     3. This eliminates orphan background compute processes and prevents CPU/RAM exhaustion.

10. **Live Diagnostic Streaming & Console Drawer Integration (#187, #328).**
    - The child process's `stdout` and `stderr` streams are captured via non-blocking asynchronous pipes.
    - Output is line-buffered and streamed live to `WorkspaceModel.log(_:_:_:)` using the `CAE` subsystem log channel, displaying real-time solver logs in the Console drawer.
    - Iteration lines (such as Newton-Raphson residuals or solver time-steps) are parsed live by regex matchers to drive real-time convergence plots (#328).

11. **Package Cache Lifecycle & Metal 4 Visualization (Invariants 5, 6, and ADR-D7).**
    - Temporary computation files are written to a sandboxed scratch directory in `NSTemporaryDirectory()/made-cae/<job-id>/`.
    - Upon successful solve completion, canonical files are committed to the `.made` document package cache under `.made/cache/results/<study-id>/` ([ADR-D7](./ADR-D7-made-encoding.md), #149):
      - `mesh.msh`: Discretized tetrahedral volume mesh.
      - `deck.inp`: Input solver deck.
      - `results.frd`: Raw solver output dataset.
      - `summary.json`: Lightweight summary of maximum stress, displacement bounds, and solve metadata.
    - Result files in `.made/cache/` are regenerable and Git-ignored.
    - **GPU Shared-Storage Visualization (Invariant 6):**
      The volumetric tetrahedral result is post-processed on background actors to extract external boundary surface triangle meshes. Scalar result fields (e.g., von Mises stress, temperature) are mapped to nodal vertex colors using perceptually uniform colormaps (Turbo, Viridis). Extracted triangle surface meshes and color attributes are uploaded directly into `.storageModeShared` Metal buffers for real-time 60–120 Hz interactive rendering in the Metal 4 viewport. Dynamic clipping plane shaders slice through the volume mesh on the GPU to visualize internal stress gradients without CPU re-tessellation.

---

## Consequences

- **Licensing Integrity and Compliance:** `made` retains its clean MPL-2.0 open-source license. The use of GPL-licensed tools (CalculiX, Gmsh) is strictly isolated across process boundaries under the doctrine of mere aggregation. The clean-room pure-Swift path in `libs/` guarantees an unencumbered long-term route for the Mac App Store and iPadOS.
- **Robust Fault and Memory Isolation:** Legacy Fortran/C memory corruption, infinite loops, and segmentation faults are strictly confined to external worker subprocesses, guaranteeing that `MadeApp` will never crash due to a solver defect.
- **Off-Main-Thread Responsiveness (Invariant 1):** Heavy numerical factorizations and tetrahedral meshing execute on background actors. The SwiftUI UI and Metal 4 viewport remain fully interactive during compute jobs.
- **Scalability to High-Performance & Cloud Computing (#352):** Decoupled file decks (`.inp`, `.msh`) establish an architecture that naturally extends from local subprocesses to remote SSH/HTTPS HPC solve runners and cloud clusters without changing the UI or study data model.
- **Unblocks Downstream Milestones:**
  - #413: Bundling CAE solver and mesher binaries under `Contents/Helpers/`
  - #187 (BL-SIM-02): Background solver runner actor with progress, cancel, and logs
  - #188 (BL-MSH-01): Gmsh volume mesher integration from OCCT B-rep geometry
  - #157 (BL-SIM-01): CAE Study model and Navigator tree integration
  - #219 (BL-FEA-01): Linear static structural FEA implementation
  - #190 (BL-THM-01): Steady-state thermal conduction analysis
  - #192 (BL-RES-01): CAE result field storage in `.made` package cache
  - #328 (BL-RES-08): Live convergence plots in inspector/drawer
  - #281 (BL-SIM-05): Automated parameter sweeps across geometry configurations
  - #352 (BL-SIM-06): Remote and cloud solver runner dispatch
  - #353 (BL-SIM-07): Solver verification suite against textbook benchmarks
  - #415: Clean-room `libs/` directory structure and provenance guidelines
  - #416: Clean-room pure-Swift FEM solver reimplementation
  - #417: Clean-room pure-Swift Delaunay volume mesher reimplementation
  - #419: Sandboxed Mac App Store distribution compliance
