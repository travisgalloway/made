# Phase 4 — CAD Depth

**Status**: 🔜 Active Development Target  
**Package Targets**: `MadeCore`, `MadeApp`

Phase 4 expands `made` from a parametric primitive viewer with agentic capabilities into a full-featured Computer-Aided Design application. It builds directly upon the N-object [`DocumentModel`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Scene/DocumentModel.swift), the [`KernelClient`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Kernel/KernelClient.swift) actor, and the [`MetalRenderer`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Viewport/MetalRenderer.swift).

---

## 1. Scene & Document Foundation

The N-object model with a command-shaped mutation API was established in Phase 0–2. Phase 4 extends this with native desktop persistence:

- **4.1 Native `.made` Document Package**:
  - Conforms to Apple's `FileDocument` / `ReferenceFileDocument` protocols with exported UTType `com.made.cad.document`.
  - Serializes scene graphs, parametric feature histories, and embedded STEP assets.
- **4.2 Undo/Redo Engine (Command Pattern)**:
  - Integrates system `UndoManager` with `DocumentModel`'s command API (`addObject`, `removeObject`, `setParam`, `setTransform`).
  - Restoring a previous state issues a command that invalidates only the affected solid.

---

## 2. Geometry Engine Expansion

- **4.3 OCCTSwift B-Rep & STEP Exchange (Tier 2)**:
  - Integrates `SecondMouseAU/OCCTSwift` via pre-built `OCCT.xcframework`.
  - Imports and exports ISO 10303 STEP (AP203/AP214) and IGES boundary representation files.
  - Adds true topological fillets, chamfers, and draft angles.
- **4.4 Multi-Body CSG Boolean Operations**:
  - Builds on Phase 2's `EuclidEngine.subtract/union/intersect` to allow complex tree-based boolean operations across arbitrary solids.

---

## 3. 2D Sketching & Parametric Constraints

- **4.5 2D Sketch Plane & Drawing Engine**:
  - Allows selecting any planar solid face or standard datum plane ($XY$, $XZ$, $YZ$) as an active sketch plane.
  - Interactive drawing of lines, arcs, circles, and Bézier curves.
  - Extrudes closed 2D profiles into 3D solids using pure-Swift path math in Euclid.
- **4.6 2D Geometric Constraint Solver**:
  - Solves 2D geometric constraints: coincident, horizontal/vertical, parallel, perpendicular, tangent, concentric, and dimensional distance.
  - Predictive constraint inference during interactive sketch drawing.

---

## 4. Interaction & Direct Manipulation

- **4.7 3D Transform Gizmos in Metal**:
  - Visual translation axes, rotation rings, and scale handles rendered directly in the Metal 3 viewport.
  - **Two-Physics Rule**: Move/rotate updates the world transform directly without kernel re-tessellation. Resize previews a GPU scale matrix during drag, dispatching exactly one debounced re-tessellation upon release.
- **4.8 Contextual Predictive Commands**:
  - Selecting an edge surfaces fillet/chamfer options; selecting a face surfaces sketch or push-pull tools.
- **4.9 Metal Selection Outlines**:
  - Stencil buffer edge highlighting indicating the active solid selection.

---

## Verification Criteria

1. **Selective Invalidation**: Re-parameterizing an object recalculates only that object's geometry; other solids remain untouched in GPU memory.
2. **Two-Physics Gizmo Drag**: A resize drag issues zero kernel jobs mid-drag and exactly one on release.
3. **Undo/Redo Integrity**: Undo restores previous parameters and transforms, correctly invalidating affected meshes without memory leaks.
4. **STEP Round-Trip**: A STEP file exported from `made` imports cleanly into FreeCAD/Rhino/Fusion360 with exact boundary representation.
