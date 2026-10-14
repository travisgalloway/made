# ADR-D1: Canonical Geometry Kernel

- **Status:** Accepted, 2026-10-12
- **Issue:** #142
- **Implemented by:** #82 (OCCTSwift B-Rep & STEP exchange), #247 (BL-KRN-13, fate of Euclid mesh path), #418 (OCCT in App Store builds), #420 (Swift B-rep core), #409 (BL-XCH-12, Parasolid and 3DM import), #371 (BL-SRF-06, SubD to NURBS), #285 (BL-OPT-04, lattice and implicit infill)

## Context

`made` currently uses pure-Swift polygonal mesh Constructive Solid Geometry (CSG) via the Euclid library (`EuclidEngine`). While polygonal mesh CSG is adequate for simple box and cylinder rendering and basic boolean operations, mechanical computer-aided design (CAD) requires an exact Boundary Representation (B-rep) kernel.

Mechanical CAD operations require exact analytic surfaces (planes, cylinders, cones, spheres, tori) and Non-Uniform Rational B-Splines (NURBS) joined into a topological data structure of vertices, edges, wires, faces, shells, and solids. Industrial operations cannot be performed reliably or accurately on faceted polygonal meshes:
1. **Topological blends:** Constant-radius and variable-radius rolling-ball fillets, chamfers, draft angles, and thin-wall hollow shells require exact curve and surface offsets and surface-surface intersection curves.
2. **Standard CAD exchange:** ISO 10303 STEP (AP203, AP214, AP242) and IGES formats represent geometry through B-rep topology and NURBS surfaces. Meshes cannot be exported to downstream CAD or CAM systems without loss of precision.
3. **Exact 2D drawings:** Engineering drawings require precise projection of silhouette edges, intersections, and hidden line removal from smooth analytical curves, not faceted polygon edges.
4. **CAE simulation meshing:** High-fidelity finite element analysis (FEA) and computational fluid dynamics (CFD) require volumetric meshing generated from true boundary surfaces, avoiding artificial polygon stress concentrations.

Faceted meshes suffer from cumulative numerical drift across successive boolean operations, non-manifold edge anomalies, and exponential facet explosion during repeated edits.

Maintainer decisions on 2026-10-11 and 2026-10-12 established that `made` is licensed under MPL-2.0 ([ADR-D8](./ADR-D8-project-license.md), #145). Direct-download Mac releases link LGPL-2.1 dependencies such as OpenCASCADE Technology (OCCT). App Store releases on macOS and iPadOS (#419) face potential ambiguity regarding LGPL-2.1 terms and App Store distribution rules. A clear decision on the canonical geometry kernel, its interface boundaries, and its App Store distribution strategy is required.

## Options Considered

1. **OpenCASCADE Technology (OCCT) via `OCCTSwift` (#82).** Accepted as the primary canonical kernel. OCCT is a mature, production-proven industrial CAD kernel with full B-rep topology, surface-surface intersection algorithms, advanced modeling operations (fillets, chamfers, drafts, shells, booleans), and robust STEP/IGES exchange. Bridged to Swift through `SecondMouseAU/OCCTSwift` using a pre-compiled `OCCT.xcframework`. It is licensed under LGPL-2.1, which is compatible with `made`'s MPL-2.0 license when dynamically linked.
2. **Clean-room pure-Swift B-rep engine in `libs/` (#420 to #424).** Accepted as the App Store fallback. A modular Swift B-rep implementation developed under the clean-room procedure (#415) using published textbooks (such as Piegl and Tiller, *The NURBS Book*), ISO 10303 standards, and permissively licensed projects (Truck under Apache-2.0, openNURBS). It contains zero OCCT code and avoids all LGPL risk. Building a complete B-rep kernel from scratch is a multi-year effort, so it serves as a fallback while OCCT provides immediate production capabilities.
3. **Commercial Parasolid license.** Rejected. Parasolid is an industry-standard commercial B-rep kernel. Commercial licensing fees are prohibitive for open-source and hobby projects. Closed-source binary distribution restrictions conflict with open community contributions and direct-download transparency.
4. **Retaining Mesh CSG (Euclid / Manifold) as canonical.** Rejected. Polygonal mesh representations cannot represent exact curved surfaces. Polygonal boolean operations introduce facet artifacts, fail downstream STEP exchange requirements, and cannot support feature-based mechanical modeling operations such as fillets or draft angles.
5. **Truck (Apache-2.0, Rust) via C FFI.** Rejected as the primary kernel. Truck provides an open-source B-rep framework in Rust, but its boolean operations and STEP import contain open defects, and it lacks an engine for fillets and chamfers. Truck remains an allowed reference source for algorithm design in the clean-room Swift fallback.

## Decision

1. **Adopt OCCT as the canonical B-rep geometry kernel.** OpenCASCADE Technology, integrated via `SecondMouseAU/OCCTSwift` (#82), is adopted as the primary and canonical geometry kernel for all part modeling in `made`.
2. **Maintain a dual-engine distribution strategy.** 
   - Both direct-download Mac builds (#254) and App Store builds (#418, #419) will ship OCCT packaged as a dynamic framework (`OCCT.xcframework`).
   - Source code availability and build-from-source instructions (#426) satisfy LGPL-2.1 relinking requirements. An in-app open source license window displays the LGPL text and copyright notices (#425).
   - If Apple App Store terms or legal challenges prevent shipping OCCT under LGPL-2.1 on the App Store, the clean-room Swift B-rep engine (#420 to #424) in `libs/` will activate as the App Store fallback (#418).
3. **Strict adherence to the engine-neutral interface (Invariant 4).** UI, viewport, scene graph, scripting, and agent subsystems interact exclusively through `KernelClientProtocol`, `KernelRequest`, and `KernelResult` defined in [`macos/Sources/MadeCore/Kernel/Types.swift`](../../../macos/Sources/MadeCore/Kernel/Types.swift). No OCCT types (such as `TopoDS_Shape` or `gp_Pnt`) or Euclid types leak past the kernel boundary into `MadeCore`. Both OCCT and the Swift fallback conform to this wire contract.
4. **Process isolation and serial execution (Invariants 1 & 7).** OCCT handles, C++ allocators, and topological data structures are not safe for concurrent multithreaded mutation. All OCCT operations execute inside the dedicated `MadeKernelService` XPC service process (#245). Calls execute on a single serial executor queue within the service. Internal multi-threading managed entirely inside OCCT (such as parallel `BRepMesh` tessellation) is permitted.
5. **Dynamic framework packaging.** OCCT is linked as a dynamic `xcframework` rather than a static library, ensuring clean binary separation and complying with LGPL-2.1 dynamic linking guidelines.
6. **Euclid demotion and permanent Tier 1 role ([ADR-D9](./ADR-D9-fate-of-euclid-mesh-path.md), #247).** Euclid is demoted from the canonical kernel to the Tier 1 pure-Swift fast CSG preview engine and unit test backend. Per [ADR-D9](./ADR-D9-fate-of-euclid-mesh-path.md) (#247), Euclid is permanently retained for sub-millisecond interactive parameter scrubbing, procedural shape tree previews, and zero-C++ test execution, while OCCT serves as the Tier 2 canonical B-Rep kernel.

## Consequences

- **Architectural boundaries:** UI and scene models remain completely decoupled from third-party geometry libraries. The application cannot accidentally rely on OCCT-specific APIs outside `Kernel/`.
- **Fault isolation:** Because OCCT runs in the separate `MadeKernelService` XPC process, unexpected C++ exceptions, memory faults, or geometry kernel crashes terminate only the worker service and do not crash `MadeApp` (Invariant 1). The client automatically restarts the service and recovers the scene.
- **Concurrency safety:** Serial execution within the kernel service eliminates data races in OCCT's shared topological structures (Invariant 7). `KernelClient` manages the 60 ms debounce conflation window and honest job cancellation before requests enter the kernel.
- **CAD depth unblocked:** Adopting OCCT unblocks dependent Phase 4 and Phase 5 milestones:
  - OCCT framework bridge and initial STEP import (#82)
  - Full STEP and IGES import and export (#38, #404)
  - Exact topological fillets and chamfers (#35)
  - Persistent topological naming (#144)
  - Thin-wall shell and draft angle operations (#152, #183)
  - Cross-section clipping and measurement tools (#201, #243)
  - SubD cage conversion to NURBS surfaces (#371)
  - External CAD format translation (#409)
  - Conformal lattice infill generation (#285)
- **Licensing clarity:** The MPL-2.0 project license cleanly separates `made`'s application code from LGPL-2.1 dynamic libraries. The clean-room Swift B-rep fallback (#418, #420 to #424) provides an insurance path against App Store distribution obstacles.
