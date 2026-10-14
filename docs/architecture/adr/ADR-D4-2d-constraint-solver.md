# ADR-D4: 2D Constraint Solver Strategy

- **Status:** Accepted, 2026-10-14
- **Issue:** #146
- **Implemented by:** #37 (BL-CON-01..04), #196 (BL-CON-05), #197 (BL-CON-06), #198 (BL-CON-07), #199 (BL-CON-08), #200 (BL-CON-09), #164 (BL-CON-10), #366 (BL-SKT-18), #415, #418, #419

## Context

In a parametric, feature-based mechanical CAD modeling system ([ADR-D2](./ADR-D2-modeling-paradigm-and-document-model.md), #143), 2D sketching on reference datum planes ($XY$, $XZ$, $YZ$) and planar solid faces is the foundational generative mechanism for 3D solids (extrude, revolve, sweep, loft) and cutouts (Phase 4C, #36, #37). 

A 2D sketch comprises geometric primitives (points, line segments, circular arcs, circles, and Bézier / B-spline control poles) whose positions, orientations, and dimensions are governed by a coupled system of geometric and dimensional constraints:
- **Geometric constraints:** Coincident (point-to-point, point-on-curve), horizontal, vertical, parallel, perpendicular, tangent, concentric, collinear, symmetric, and midpoint.
- **Dimensional constraints:** Distance (point-to-point, point-to-line), horizontal distance, vertical distance, radius, diameter, and angle between curves.

Mathematically, these constraints form a non-linear system of algebraic equations $F(X) = 0$, where $X \in \mathbb{R}^n$ represents the coordinates and parameters of the sketch entities, and $F: \mathbb{R}^n \to \mathbb{R}^m$ represents the residual constraint vector. Resolving this system requires a robust geometric constraint solver capable of solving under-constrained, fully-constrained, and well-posed systems using numerical optimization methods (such as Levenberg-Marquardt or Powell's Dogleg).

Furthermore, interactive mechanical CAD imposes two fundamentally distinct operational regimes on the constraint solver:
1. **Interactive Drag Solving (60–120 Hz):** When a user or Apple Pencil drags an unconstrained or partially constrained entity (a vertex or curve, #198), the solver must converge in under 16 milliseconds (or 8.3 ms for 120 Hz ProMotion displays) on each pointer event. To provide a predictable, jitter-free user experience, the solver must minimize entity displacement relative to the pre-drag position (a minimal-movement objective: $\min \|X - X_0\|^2$ subject to $F(X) = 0$), avoiding discontinuous topological flipping or sudden jumps.
2. **Parametric Regeneration:** During discrete recomputation triggered by upstream parameter edits (#34, #150), sketches must regenerate deterministically from saved parameters and constraints without interactive input.

Beyond equation solving, a production mechanical CAD constraint system must satisfy critical domain requirements:
- **Degrees-of-Freedom (DOF) Analysis (#196, #366):** The solver must determine the remaining degrees of freedom globally and per entity, driving visual status coloring (e.g., blue for under-constrained, green for fully-constrained) and feature tree status indicators.
- **Typed Error Envelopes and Conflict Diagnosis (#197, #428):** Over-constrained systems or contradictory constraints (e.g., parallel and perpendicular applied to the same pair of lines) must not crash or throw unhandled exceptions. The solver must perform singular value or QR decomposition on the constraint Jacobian to identify over-constrained and mutually conflicting constraint subsets, returning structured diagnostic envelopes to the UI inspector and agent Model Context Protocol (MCP) tools.
- **Driven / Reference Dimensions (#199):** The system must support measurement dimensions that inspect geometric quantities without introducing equations into the solver system.
- **Predictive Snapping Inference (Invariant 9, #37):** Interactive drawing must infer candidate constraints live from pointer trajectory and geometry proximity (`Snapping.swift`, Vertex > Edge > Grid priority).
- **Synergy with 3D Assembly Constraint Solving (#164):** The mathematical formulation, entity abstraction, and error diagnostics established for 2D sketches must lay the structural foundation for 3D assembly mate solving (Phase 7).

Maintainer decisions establish that `made` is licensed under MPL-2.0 ([ADR-D8](./ADR-D8-project-license.md), #145). Direct-download macOS releases permit dynamically linking LGPL-2.1 dependencies (such as OCCT, [ADR-D1](./ADR-D1-canonical-geometry-kernel.md)), whereas viral copyleft licenses (GPLv3) are prohibited from linking into `made`. App Store releases on macOS and iPadOS (#419) require an unencumbered fallback.

A clear architecture decision record is required to select the canonical 2D constraint solver, establish the distribution and fallback strategy, define the engine-neutral Swift interface, and establish execution and error-handling contracts.

## Options Considered

### 1. SolveSpace Geometric Constraint Solver (`libslvs`, GPLv3) — Rejected
SolveSpace contains a compact, highly capable, and well-regarded 2D/3D geometric constraint solver (`libslvs`).
- **Advantages:** Small footprint, fast convergence, proven in open-source CAD, and supports both 2D sketches and 3D assembly linkages.
- **Disadvantages & Rejection Rationale:**
  1. **Strict GPL-3.0-or-later License:** SolveSpace is licensed strictly under GPL-3.0-or-later. Under ADR-D8 (#145), linking GPL code into `made` imposes viral copyleft obligations on the entire application codebase, directly violating `made`'s MPL-2.0 project license and Apple App Store distribution terms (#419).
  2. **Infeasibility of Separate CLI Executable:** While ADR-D5 permits GPL-licensed CAE meshing and simulation solvers to run out-of-process as separate CLI executables via disk file decks, running 2D sketch constraint solving across an external process boundary via disk files or heavy IPC is completely unviable. Interactive pointer and pencil drag solving requires 60–120 Hz update rates with sub-16ms latency. Process launching, serialization, and disk I/O would introduce intolerable frame stutter and latency.

### 2. FreeCAD `planegcs` (LGPL-2.1-or-later) — Accepted as Primary Canonical Solver
FreeCAD's Sketcher module utilizes `planegcs` (Geometric Constraint Solver, originally authored by Juergen Riegel, Przemo Firszt, and Werner Mayer). `planegcs` is an open-source C++ solver implementing Dogleg / Levenberg-Marquardt algorithms specifically tailored for 2D CAD sketches.
- **Advantages:**
  1. **Battle-Tested CAD Maturity:** Developed and tuned over two decades across tens of thousands of real-world industrial CAD models and complex sketch topologies.
  2. **Comprehensive Constraint Support:** Natively supports coincident, point-on-object, horizontal, vertical, parallel, perpendicular, tangent, concentric, symmetric, angle, and distance constraints across points, lines, circles, arcs, and B-spline curves.
  3. **Degrees of Freedom & Diagnostics:** Computes remaining degrees of freedom per entity and identifies both redundant constraints and conflicting constraint subsets via rank analysis of the constraint Jacobian.
  4. **Smooth Interactive Drag Solving:** Implements minimal-movement optimization during interactive drag, preventing solver instability and entity jumping.
  5. **Licensing Compatibility:** Licensed under LGPL-2.1-or-later. Under ADR-D8 (#145), LGPL-2.1 libraries link dynamically into `made` on the exact same terms as OpenCASCADE Technology (OCCT, #82, #418).
- **Packaging:** Integrated as a pre-compiled dynamic framework (`PlaneGCS.xcframework`) or dynamic library, wrapped via a thin C-compatible interface or Swift 6.2 C++ interoperability.

### 3. Clean-Room Pure-Swift Constraint Solver in `libs/` (#415) — Accepted as App Store Fallback
A modular, pure-Swift sparse non-linear constraint solver developed in `libs/` under the clean-room procedure (#415).
- **Advantages:**
  1. **Zero C++ Toolchain Friction:** 100% native Swift 6 code, eliminating C++ bridging, header dependencies, and platform-specific compilation hurdles.
  2. **Unencumbered Licensing for App Store & iPadOS:** Developed from published numerical optimization textbooks (e.g., Nocedal & Wright, *Numerical Optimization*) and public mathematical papers without reading or incorporating GPL/LGPL source code. Fully unencumbered for the Apple App Store on macOS and iPadOS (#84, #419).
  3. **Type-Safe Swift Concurrency:** Direct conformance to Swift 6 strict concurrency (`Sendable`, actors) with zero pointer bridging.
- **Trade-offs:** Implementing a complete, industrial-strength non-linear constraint solver with full redundancy diagnosis from scratch requires substantial numerical engineering. Therefore, like the Swift B-rep engine in ADR-D1 (#420), it serves as the strategic App Store fallback while FreeCAD `planegcs` provides immediate production depth.

## Decision

1. **Rejection of SolveSpace (`libslvs`).** SolveSpace's solver is rejected due to its GPL-3.0 license incompatibility with `made`'s MPL-2.0 license and the unviability of out-of-process execution for 60 Hz drag solving.

2. **Adoption of FreeCAD `planegcs` as Canonical Primary Solver.** `planegcs` (LGPL-2.1-or-later) is adopted as the primary canonical 2D geometric constraint solver for `made`. It will be packaged as a dynamic framework (`PlaneGCS.xcframework`) for direct-download desktop builds (#254) and dynamic linking (#418).

3. **Dual-Engine Distribution Strategy.** In alignment with the geometry kernel strategy in ADR-D1 (#142, #418):
   - Direct-download releases link `planegcs` dynamically as `PlaneGCS.xcframework`.
   - The clean-room pure-Swift constraint solver developed in `libs/` under #415 serves as the fallback for Mac App Store builds (#419) and iPadOS (#84).
   - Dynamic linking, complete build recipes (#426), and open-source attribution in the in-app license window (#425) fulfill LGPL-2.1 compliance.

4. **Strict Engine-Neutral Swift Interface (Invariant 4).** All sketching and constraint abstractions reside entirely in Swift within `MadeCore`:
   - `ConstraintSystem`: Declarative container holding sketch entities and active constraints.
   - `SketchEntity`: Swift enum representing 2D entities (`point`, `lineSegment`, `arc`, `circle`, `splinePole`).
   - `Constraint`: Swift enum representing geometric and dimensional constraints with associated entity identifiers and parameters.
   - `SolverResult`: Swift value type returning solved entity parameters, degrees-of-freedom report, and diagnostic status.
   - No C++ headers, `planegcs` pointers, or external types leak past the solver bridge into `MadeCore`, `DocumentModel`, or UI view models. Both `planegcs` and the pure-Swift fallback conform to this identical interface.

5. **In-Process Background Actor Execution (Invariants 1 & 7).**
   - Constraint solving executes off the main UI thread inside a dedicated Swift background actor (`ConstraintSolverActor`) in `MadeCore`.
   - **Zero-IPC Latency for 60 Hz Drag Solving:** Unlike the multi-second, process-isolated geometry kernel operations in `MadeKernelService` (ADR-D1, #245), 2D constraint solving executes in-process on background actor threads. In-process execution eliminates inter-process communication (XPC) and serialization overhead, achieving the sub-16ms latency required for 60–120 Hz interactive pointer and pencil dragging (#198).
   - **Conflation and Cancellation (Invariant 7):** High-frequency drag events are conflated using unique `JobId` identifiers, dropping intermediate superseded solving requests so only the latest pointer position is resolved.

6. **Degrees-of-Freedom (DOF) Tracking and Sketch State (#196, #366).**
   - The solver calculates the total remaining degrees of freedom as well as entity-specific unconstrained motion directions.
   - Sketches report one of three discrete states:
     - `underConstrained(dof: Int)`: Entity parameters retain unconstrained degrees of freedom. Rendered in status blue.
     - `fullyConstrained`: All degrees of freedom resolved ($DOF = 0$). Rendered in status green.
     - `overConstrained`: Redundant or conflicting constraints exist ($DOF < 0$). Rendered in status red/orange.
   - The state is surfaced in the viewport status bar and the Navigator Feature Tree (#366).

7. **Non-Throwing Typed Diagnostics and Conflict Repair (#197, #428).**
   - In accordance with `MadeCore` error contracts, solver failures do not throw unhandled exceptions.
   - The solver computes Jacobian rank deficiencies and returns typed error envelopes:
     ```swift
     public enum SolverStatus: Sendable, Codable {
         case converged(dof: DOFReport)
         case failedToConverge(reason: NonConvergenceReason)
         case conflicting(conflictingConstraints: [ConstraintId])
         case redundant(redundantConstraints: [ConstraintId])
     }
     ```
   - Conflicting and redundant constraints are highlighted in the Inspector UI (#197) and exposed through agent MCP inspection tools (`cad_get_diagnostics`, #428) for automated agent repair.

8. **Driven / Reference Dimensions (#199).**
   - Dimensions may be marked as driven (`isDriven: true`). Driven dimensions measure and display the current distance or angle without adding equations to the constraint matrix, preventing accidental over-constraint.

9. **Predictive Snapping Inference Integration (Invariant 9, #37).**
   - Live inferencing leverages `MadeCore/Input/Snapping.swift` during drawing and dragging. Candidates are prioritized (Vertex > Edge > Grid) and previewed as visual snap glyphs before being committed as permanent constraints.

10. **Synergy with 3D Assembly Constraint Solving (#164).**
    - The mathematical solver architecture, numerical methods, and typed diagnostic structures developed for 2D sketching establish the foundation for 3D assembly mate solving (coincident, concentric, distance, align) in Phase 7 (#164).

## Consequences

- **Licensing Clarity and Integrity:** Direct-download builds safely utilize `planegcs` under LGPL-2.1 dynamic linking rules without viral copyleft risk (ADR-D8). The clean-room Swift fallback in `libs/` (#415) provides a risk-free path for Mac App Store (#419) and iPadOS distribution (#84).
- **Responsive 60–120 Hz Interactive Sketching:** In-process actor execution delivers sub-16ms convergence for pointer and Apple Pencil dragging (#198), avoiding frame drops and UI freezes.
- **Engine Neutrality (Invariant 4):** UI panels, Metal viewport shaders, scene documents, and agent tools interact solely with pure Swift value types. The underlying solver backend can be switched between `planegcs` and the pure-Swift engine with zero impact on the rest of the application.
- **Robust Error Diagnostics and Agent Autonomy:** Typed diagnostic envelopes allow external AI agents connected via MCP to identify conflicting constraints, remove redundant constraints, and repair broken sketches deterministically.
- **Unblocks Phase 4C Milestones:**
  - #37 (BL-CON-01..04): 2D constraint solver with live inference
  - #196 (BL-CON-05): Degrees of freedom analysis per entity
  - #197 (BL-CON-06): Over-constraint and conflict diagnosis
  - #198 (BL-CON-07): Interactive drag solving with minimal-movement objective
  - #199 (BL-CON-08): Driven and reference dimensions
  - #200 (BL-CON-09): Constraint solver regression test corpus
  - #164 (BL-CON-10): 3D assembly constraint solver architectural foundation
  - #366 (BL-SKT-18): Sketch state visual indicators in Navigator and Viewport
  - #415: Clean-room pure-Swift constraint solver in `libs/`
  - #418: LGPL dynamic framework packaging for App Store verification
  - #419: App Store distribution compliance
