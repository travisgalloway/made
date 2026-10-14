# ADR-D2: Modeling Paradigm and Document Model

- **Status:** Accepted, 2026-10-14
- **Issue:** #143
- **Implemented by:** #150 (BL-FND-01), #34, #39, #83, #144, #170, #175, #235, #239, #301, #314, #332, #151, #157

## Context

`made` currently represents 3D scenes as a flat array of `SceneObject` instances (`DocumentModel.objects`) with primitive command mutations (`addObject`, `removeObject`, `setParam`, `setTransform`). This model was sufficient for the initial viewer and basic agent tool prototyping, but it cannot support mechanical Computer-Aided Design (CAD) workflows.

Mechanical CAD requires:
1. **Parametric history and regeneration:** Geometry is constructed through sequential operations (datum planes, 2D sketches with geometric constraints, profile extrusions and revolves, draft angles, and topological fillets and chamfers). Editing an upstream dimension must replay downstream operations deterministically.
2. **Direct manipulation edits:** Users and AI agents need to perform direct modeling operations (such as moving, offsetting, or deleting faces) on both native features and imported B-rep models (STEP/IGES) without losing parametric replayability.
3. **Multi-body modeling:** Complex parts frequently require multiple disjoint or intersecting solid bodies within a single part coordinate space before combining them with boolean operations.
4. **Assembly separation:** Kinematic mates, degrees of freedom, and bill of materials (BOM) hierarchies belong in assembly documents (Phase 5, #161, BL-ASM-01), distinct from within-part multi-body geometry modeling.

The flat object array model lacks dependency tracking, feature suppression, rollback capability, parameter expressions, and topological entity references. A definitive architecture decision on the modeling paradigm and core document model is required before building the Phase 4 CAD depth capabilities.

## Options Considered

1. **Pure history-based feature list.** Rejected. A strictly procedural feature tree maintains rigid parent-child relationships where geometry is defined exclusively by sketches and parametric operations. While this approach provides strong parameter replayability, it is fragile when topological references break upstream and offers no intuitive workflow for modifying imported STEP or IGES geometry where no feature history exists.
2. **Direct modeling only.** Rejected. Direct modeling allows push-pull manipulation of boundary geometry without an operation history. While highly flexible and tolerant of imported geometry, it discards design intent, parameter formulas, sketch constraints, and procedural regeneration necessary for mechanical engineering and family-of-parts configurations.
3. **Hybrid modeling: History-based feature list recording direct edits as features, with multi-body parts by default.** Accepted. Following modern mechanical CAD design patterns (Fusion 360 and Onshape), geometry is defined by an ordered linear feature list. Direct editing actions (face offset, move face, delete face) do not mutate boundary geometry untracked; they append explicit features to the history list. A single part document naturally supports multiple solid bodies.

## Decision

1. **Adopt the hybrid history-based modeling paradigm.** An ordered linear feature list is the single source of truth for part geometry. Direct editing operations (such as move face, offset face, and delete face) are recorded as discrete, parameter-driven features in the history list. This preserves full parametric replayability while providing direct manipulation flexibility for native and imported geometry.
2. **Multi-body parts by default.** A single part document (`.part.ts` or `document.json`) supports multiple disjoint or interacting solid bodies within its local coordinate space. Features declare whether they create a new body or perform a boolean operation (`join`, `cut`, `intersect`) against target bodies. Assemblies (Phase 5, #161) instantiate parts and define kinematic mates, establishing a clean boundary between part geometry and assembly kinematics.
3. **Replace the flat object array in `DocumentModel` (BL-FND-01 / #150).** Replace `DocumentModel.objects` (`[SceneObject]`) with an ordered collection of features (`features: [Feature]`). Each feature contains a persistent UUID, display name, feature type, expression-backed parameter inputs (BL-PAR-02), typed references (BL-FND-02), suppression state, persisted error status (BL-FND-04), and an evaluated topology map.
4. **Integration with core architecture systems:**
   - **Feature Tree UI (#34):** The navigator renders the ordered feature list with suppression toggles, error indicators, and a draggable rollback marker (#235).
   - **Undo/Redo Engine (#39):** Command mutations (`addFeature`, `removeFeature`, `updateFeature`, `reorderFeatures`) integrate with the system `UndoManager`.
   - **Persistence and `.made` Encoding (#83, ADR-D7):** `document.json` encodes the ordered feature list, parameter tables (#174), and multi-body state with deterministic key sorting and 2-space indentation.
   - **Agent API and MCP Tools (#151):** Agent tooling transitions from primitive solid manipulation to feature-level tools (`cad_create_sketch`, `cad_add_feature`, `cad_edit_feature`, `cad_rollback`).
   - **Topological Naming (#144, ADR-D3):** Downstream features reference faces, edges, and vertices generated by upstream features through query-based topological history rather than unstable geometric indices.
5. **Architectural invariants compliance:**
   - **Invariant 1 (Kernel off main thread):** Feature regeneration walks the ordered list and evaluates geometry asynchronously within the `KernelClient` actor.
   - **Invariant 3 (Imperative viewport):** SwiftUI reactive state drives the feature tree and inspector, while Metal retains evaluated mesh buffers.
   - **Invariant 4 (Engine-neutral interface):** Feature requests pass across the kernel boundary through `KernelRequest` and `KernelResult` without exposing OpenCASCADE or Euclid symbols outside `Kernel/`.
   - **Invariant 7 (Thread-safe state):** `DocumentModel` remains isolated to `@MainActor`, ensuring thread-safe agent mutations and predictable state transitions.
6. **Transition and compatibility strategy:**
   - During migration in #150, evaluated output bodies will project stable `SolidId` identifiers into `SceneObject` representations. This ensures existing MCP tools (`cad_get_scene`, `cad_add_solid`, `cad_set_param`, `cad_remove_solid`) and current UI inspectors continue operating without disruption while feature tree capabilities (#34) and feature tools (#151) land.

## Consequences

- **Design intent preservation:** Parametric parameters, formulas, and sketch constraints remain fully editable throughout the lifecycle of the part.
- **Direct editing flexibility:** Direct edits on imported STEP/IGES bodies or complex native models are first-class citizens in the history timeline.
- **Clean assembly boundary:** Multi-body parts handle complex within-part geometry and boolean modeling. Assemblies handle multi-component positioning, kinematic joints, and exploded views without conflating within-part solid construction.
- **Asynchronous regeneration performance:** The dependency graph (BL-FND-03 / #175) enables selective re-evaluation: changing a feature recomputes only that feature and its downstream dependents off the main UI thread.
- **Unblocks downstream CAD depth foundation:**
  - #150 (BL-FND-01): Replace object array with ordered feature list
  - #34: Feature tree UI over document model
  - #39: Undo/redo on document model
  - #83: Native `.made` document package persistence ([ADR-D7](./ADR-D7-made-encoding.md))
  - #144: Topological naming strategy (ADR-D3)
  - #170 (BL-FND-02): Typed reference model for feature inputs
  - #175 (BL-FND-03): Dependency graph and incremental regeneration
  - #235 (BL-FND-05): Rollback marker
  - #239 (BL-FND-12): Multi-body model within a part
  - #301 (BL-PRT-20): Datum planes
  - #314 (BL-PRT-24): Primitive solids as features
  - #332 (BL-SCR-04): DSL targets the feature list
  - #151 (BL-AGT-04): Feature-level agent tools
  - #157 (BL-SIM-01): Study model and tree
