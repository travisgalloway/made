# Phase 4: CAD Depth

**Status**: In progress. No Phase 4 issue is closed.  
**Package Targets**: `MadeCore`, `MadeApp`

Phase 4 expands `made` from a parametric primitive viewer with agentic capabilities into a full-featured Computer-Aided Design application. It builds on the N-object [`DocumentModel`](../../macos/Sources/MadeCore/Scene/DocumentModel.swift), the [`KernelClient`](../../macos/Sources/MadeCore/Kernel/KernelClient.swift) actor, and the [`MetalRenderer`](../../macos/Sources/MadeCore/Viewport/MetalRenderer.swift).

---

## Milestone Layout

Phase 4 splits into six milestones. [`phases.md`](./phases.md) gives the goal of each milestone and of Phases 5 to 8, and the GitHub milestones hold the issues.

| Milestone | Name |
| --------- | ---- |
| Phase 4.0 | Architecture Decisions |
| Phase 4A | Native Scene & Interaction Foundation |
| Phase 4B | B-Rep Engine, STEP Exchange & Document Persistence |
| Phase 4C | 2D Sketching & Constraint Solver |
| Phase 4D | Pencil Precision, Contextual UI & Agent REPL |
| Phase 4E | Part Features & MVP Exchange |

Phase 4.0 records the open decisions that gate the milestones after it.

---

## 1. Scene & Document Foundation

The document model holds an ordered array of objects with `addObject`, `removeObject`, `setParam`, and `setTransform`. The 4.N labels below are local to this page. GitHub issue titles use a different numbering, so the cited issue number is the key.

- Open scene work: generalize the scene and inspector (#66, #67), selection (#69, #70), add and remove objects (#73), feature tree (#34).

- **4.1 Native `.made` Document Package** (#83, [ADR-D7](../architecture/adr/ADR-D7-made-encoding.md)):
  - Conforms to Apple's `FileDocument` / `ReferenceFileDocument` protocols with exported UTType `com.made.cad.document`.
  - Directory package containing canonical JSON (`manifest.json`, `document.json`), plain-text `.part.ts` sources (`parts/`), embedded STEP/IGES assets (`assets/`), and a Git-ignored binary cache (`cache/`).
- **4.2 Undo/Redo Engine (Command Pattern)** (#39):
  - Integrates system `UndoManager` with `DocumentModel`'s command API (`addObject`, `removeObject`, `setParam`, `setTransform`).
  - Restoring a previous state issues a command that invalidates only the affected solid.

---

## 2. Geometry Engine Expansion

- **4.3 OCCTSwift B-Rep & STEP Exchange (Tier 2)** (#82, #38, [ADR-D1](../architecture/adr/ADR-D1-canonical-geometry-kernel.md)):
  - Integrates `SecondMouseAU/OCCTSwift` via pre-built `OCCT.xcframework` as the canonical B-rep kernel ([ADR-D1](../architecture/adr/ADR-D1-canonical-geometry-kernel.md), #142).
  - Imports and exports ISO 10303 STEP (AP203/AP214) and IGES boundary representation files.
  - Adds true topological fillets, chamfers, and draft angles.
- **4.4 Multi-Body CSG Boolean Operations** (#35):
  - Builds on `EuclidEngine.subtract/union/intersect` to allow complex tree-based boolean operations across arbitrary solids.

---

## 3. 2D Sketching & Parametric Constraints

- **4.5 2D Sketch Plane & Drawing Engine** (#36):
  - Allows selecting any planar solid face or standard datum plane ($XY$, $XZ$, $YZ$) as an active sketch plane.
  - Interactive drawing of lines, arcs, circles, and Bézier curves.
  - Extrudes closed 2D profiles into 3D solids using pure-Swift path math in Euclid.
- **4.6 2D Geometric Constraint Solver** (#37):
  - Solves 2D geometric constraints: coincident, horizontal/vertical, parallel, perpendicular, tangent, concentric, and dimensional distance.
  - Predictive constraint inference during interactive sketch drawing.

---

## 4. Interaction & Direct Manipulation

- **4.7 3D Transform Gizmos in Metal** (#71, #72):
  - Visual translation axes, rotation rings, and scale handles rendered directly in the Metal 4 viewport.
  - **Two-Physics Rule**: Move/rotate updates the world transform directly without kernel re-tessellation. Resize previews a GPU scale matrix during drag, dispatching exactly one debounced re-tessellation upon release.
- **4.8 Contextual Predictive Commands** (#41, #42, #43, #44):
  - Selecting an edge surfaces fillet/chamfer options; selecting a face surfaces sketch or push-pull tools.
- **4.9 Metal Selection Outlines** (#40, #45):
  - Stencil buffer edge highlighting indicating the active solid selection.

---

## Verification Criteria

1. **Selective Invalidation**: Re-parameterizing an object recalculates only that object's geometry; other solids remain untouched in GPU memory.
2. **Two-Physics Gizmo Drag**: A resize drag issues zero kernel jobs mid-drag and exactly one on release.
3. **Undo/Redo Integrity**: Undo restores previous parameters and transforms, correctly invalidating affected meshes without memory leaks.
4. **STEP Round-Trip**: A STEP file exported from `made` imports cleanly into FreeCAD/Rhino/Fusion360 with exact boundary representation.
