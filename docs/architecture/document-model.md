# Document Model & Scene Graph

The document model in `made` is the single source of truth for all 3D scene objects, parametric feature trees, dimensional configurations, and spatial transformations. It is implemented as an `@Observable` Swift class (`final class DocumentModel: @unchecked Sendable`, with no actor isolation, see #91) in [`DocumentModel.swift`](../../macos/Sources/MadeCore/Scene/DocumentModel.swift) conforming to Invariant 3.

---

## Scene Architecture

Under ADR-D2 ([ADR-D2](./adr/ADR-D2-modeling-paradigm-and-document-model.md), #143, #150), `made` adopts a hybrid history-based modeling paradigm: an ordered linear feature list (`features: [Feature]`) serving as the canonical source of truth for part geometry, recording direct manipulation edits as discrete features, with multi-body parts by default. Active, non-suppressed features project stable `SolidId` identifiers into `SceneObject` representations (`objects: [SceneObject]`) so existing MCP tools, viewport rendering, and UI inspectors continue operating without disruption while feature tree UI (#34) and feature tools (#151) land.

```
┌────────────────────────────────────────────────────────┐
│              DocumentModel (@Observable)               │
│   • Canonical: features: [Feature] (ordered list)      │
│   • Projected: objects: [SceneObject] (active solids)  │
│     (multi-body parts, suppression, undo/redo)         │
└──────────────────────────┬─────────────────────────────┘
                           │ Dispatches Command Mutations
┌──────────────────────────▼─────────────────────────────┐
│                 Command Pattern API                    │
│   • addFeature / removeFeature / updateFeature         │
│   • setFeatureSuppressed / setFeatureError             │
│   • addObject / removeObject / setParam / setTransform │
│   • setName / setVisibility / setLocked / setMaterial  │
└──────────────┬──────────────────────────┬──────────────┘
               │ Reactive Bindings        │ Async Invalidation
┌──────────────▼─────────────┐ ┌──────────▼──────────────┐
│     SwiftUI Inspector      │ │      KernelClient       │
│   (Dimensions, Transforms, │ │  (Tessellates Geometries│
│    Feature Tree #34)       │ │   and Features off-main)│
└────────────────────────────┘ └─────────────────────────┘
```

---

## Feature Data Model

The canonical source of truth for part geometry is `Feature` in [`Feature.swift`](../../macos/Sources/MadeCore/Scene/Feature.swift):

```swift
public struct Feature: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var operation: FeatureOperation
    public var inputExpressions: [String: FeatureExpression]
    public var references: [TopologicalReference]
    public var isSuppressed: Bool
    public var errorState: FeatureErrorState?
    public var generatedTopology: [String: TopologicalReference]
    public var outputSolidId: SolidId?
    public var transform: Transform
    public var isVisible: Bool
    public var isLocked: Bool
    public var material: MaterialAttributes
}

public enum FeatureOperation: Sendable, Codable, Equatable {
    case primitive(PrimitiveFeatureData) // .box(BoxParams), .cylinder(CylinderParams)
    case sketch(SketchFeatureData)
    case extrude(ExtrudeFeatureData)
    case boolean(BooleanFeatureData)
    case part(PartFeatureData)
    case imported(ImportedFeatureData)
}
```

Each feature holds:
1. **Persistent UUID (`id`)**: Stable identity across sessions, undo/redo, and direct edits.
2. **Display Name (`name`)**: User-facing name shown in the Feature Tree (#34).
3. **Operation (`operation`)**: Concrete geometry construction step (`primitive`, `sketch`, `extrude`, `boolean`, `part`, `imported`).
4. **Input Expressions (`inputExpressions`, BL-PAR-02)**: Parameter inputs stored as formulas and evaluated numeric values (`FeatureExpression`).
5. **Typed References (`references`, BL-FND-02)**: Query-based topological sub-element references (`TopologicalReference`) conforming to ADR-D3.
6. **Suppression Flag (`isSuppressed`)**: Toggles feature inclusion, excluding geometry from projected objects and skipping kernel regeneration.
7. **Persisted Error State (`errorState`, BL-FND-04)**: Diagnostics (`FeatureErrorState`) recorded when regeneration or reference binding fails.
8. **Generated-Topology Map (`generatedTopology`)**: Queryable sub-element map (`face:top`, `face:bottom`, etc.) resolved by downstream features.

---

## Multi-Body Model within a Part (BL-FND-12)

In parametric CAD systems adhering to ADR-D2 ([ADR-D2](./adr/ADR-D2-modeling-paradigm-and-document-model.md), #143, #150), part geometry is constructed from an ordered linear history timeline of features (`DocumentModel.features: [Feature]`), supporting multi-body parts by default. A complex mechanical part frequently contains multiple disjoint or interacting solid and surface bodies within a single local coordinate space before combining them with downstream operations.

### Body Representation & Operations

First-class body definitions reside in [`Body.swift`](../../macos/Sources/MadeCore/Scene/Body.swift):

```swift
public typealias BodyId = SolidId

public enum BodyType: String, Sendable, Codable, Equatable, CaseIterable {
    case solid
    case surface
}

public enum BodyOperation: String, Sendable, Codable, Equatable, CaseIterable {
    case create
    case add
    case cut
    case intersect
}

public struct Body: Identifiable, Sendable, Codable, Equatable {
    public let id: BodyId
    public var name: String
    public var type: BodyType
    public var isVisible: Bool
    public var isLocked: Bool
    public var material: MaterialAttributes
    public var transform: Transform

    public var color: SIMD4<Float> { get set }
}
```

1. **Persistent Body Identity**: Each body holds a persistent `BodyId` (`SolidId`), display name, topological type (`.solid` or `.surface`), visibility, locked state, material attributes, color property, and spatial transform.
2. **Feature Operation Modes**: Every 3D feature in the timeline declares its operation mode via `bodyOperation: BodyOperation`:
   - `.create`: Mints a distinct, new body in the part.
   - `.add`: Joins/unites feature geometry into an existing target body (`BooleanOp.union`).
   - `.cut`: Subtracts feature geometry from an existing target body (`BooleanOp.subtract`).
   - `.intersect`: Intersects feature geometry with an existing target body (`BooleanOp.intersect`).
3. **Target Body Binding & Dependency Tracking**: Features modifying an existing target body record `targetBodyId: BodyId?`. The document dependency graph tracks this reference as an upstream dependency (`directDependencies(of:)`), ensuring proper topological execution order.
4. **Timeline Synchronization**: `DocumentModel` dynamically synchronizes `bodies: [Body]` during timeline replay and object projection (`syncObjectsFromFeatures()`). Mutator APIs (`setBodyVisibility`, `setBodyName`, `setBodyMaterial`, `setBodyColor`, `setBodyLocked`) integrate with `UndoManager` and enforce lock protections.
5. **Reference Validation**: `ReferenceResolver.validateReferences` validates `targetBodyId` for non-create operations, rejecting missing target bodies (`.missingTargetBody`), nonexistent bodies (`.bodyNotFound`), self-references (`.selfReference`), forward references (`.forwardReference`), and suppressed targets (`.targetFeatureSuppressed`).
6. **Backward-Compatible Persistence**: `.made` package storage (`DocumentData`) decodes existing documents without body fields seamlessly, defaulting feature body operation to `.create` and reconstructing `bodies` without data loss.

---

## Object Data Model (Synchronized Projection)

Every active, non-suppressed solid in the scene graph is projected into a `SceneObject`:

```swift
public struct SceneObject: Identifiable, Sendable, Equatable {
    public let id: ObjectId              // typealias for SolidId
    public var name: String
    public var def: ObjectDef            // .box, .cylinder, .imported(name:), .boolean(op:solidA:solidB:)
    public var transform: Transform      // position, rotation, scale
    public var isVisible: Bool
    public var isLocked: Bool
    public var material: MaterialAttributes
}

public enum ObjectDef: Sendable, Equatable {
    case box(BoxParams)                  // width, depth, height
    case cylinder(CylinderParams)        // radius, height
    case imported(name: String)
    case boolean(op: BooleanOp, solidA: ObjectId, solidB: ObjectId)
    case part(url: URL, shape: ShapeNode?)
}
```

The model stores an object name, a visibility flag, a lock flag, and material attributes. Selection is stored in `DocumentModel.selectedId` in `MadeCore` with a no-op on unchanged values (invariant 2), and delegated to by `WorkspaceModel.selectedId` (#69).

### Supported Object Types
1. **Parametric Primitives**: Boxes (`width`, `depth`, `height`) and Cylinders (`radius`, `height`).
2. **Imported Placeholder**: `.imported(name:)` carries a name only.
3. **Boolean Result**: `.boolean(op:solidA:solidB:)` records the operation and both operand IDs (`DOC-11`). `DocumentModel.reserveId(for:)` mints its `boolean-<seq>` ID before the kernel call, so the document and the kernel cache share it. `DocumentModel.dependentObjects(of:)` queries direct and transitive dependents in topological order. When operands are edited, recomputations cascade to dependent booleans; when operands are removed, dependent booleans recompute and record typed `unknownSolid` errors. Kernel regeneration replays base solids before recomputing booleans in topological order (#35).
4. **Scripted Parts**: `.part(url:shape:)` references a `.part.ts` or `.part.js` file on disk with its evaluated shape tree (#427).
5. **Planned**: B-Rep solids loaded from STEP or IGES files (#38, #82).

---

## Command Mutation API

All modifications to the scene must traverse the explicit command API rather than mutating property dictionaries directly:

```swift
// Create an object (IDs have the form <kind>-<seq>)
let boxId = document.addObject(
    def: .box(BoxParams(width: 40, depth: 30, height: 10)),
    transform: .identity
)

// Update dimension with automatic limits clamping
document.setParam(id: boxId, key: "width", value: 45)

// Update world transform
var t = Transform.identity
t.position = SIMD3<Float>(10, 0, 0)
document.setTransform(id: boxId, transform: t)

// Delete object
document.removeObject(id: boxId)
```

The model also exposes entity mutators for features, bodies, and scene objects:
- `setFeatureName(id:name:)`: Guards `!isLocked` (returning `.failure(.objectLocked)`), trims whitespace, rejects empty names, registers `"Rename Feature"` undo/redo, and propagates name updates to projected scene objects and bodies (BL-FND-13, #240).
- `setFeatureVisibility(id:isVisible:)`: Permits visibility toggling on both unlocked and locked features, registers `"Show Feature"` / `"Hide Feature"` undo/redo, and propagates to projected scene objects and bodies.
- `setFeatureLocked(id:isLocked:)`: Mutates feature lock state and registers `"Lock Feature"` / `"Unlock Feature"` undo/redo.
- `setBodyName(id:name:)` and `setName(id:name:)`: Guard `!isLocked`, trim whitespace, reject empty/whitespace-only strings, register `"Rename Body"` undo/redo, and update corresponding features and scene objects.
- `setBodyVisibility(id:isVisible:)` and `setVisibility(id:isVisible:)`: Permit visibility toggling even when locked, registering `"Show Body"` / `"Hide Body"` undo/redo.
- `WorkspaceModel` synchronizes `viewportManager.renderer?.hiddenSolidIds` on direct mutation and reconciles during `undo()`, `redo()`, and document loading/resetting (`syncHiddenSolidIds()`).
- Mutators `setParam`, `setTransform`, `setMaterial`, and `removeObject` guard `!isLocked` and return `Result<Void, DocumentMutationError>`, returning `.failure(.objectLocked(id))` if locked. Non-existent IDs return `.failure(.objectNotFound(id))`.

### Limits Clamping
`DocumentLimits` in `DocumentModel.swift` clamps parameter updates made through `setParam` to fixed ranges (a NaN value becomes the minimum):

| Parameter | Minimum (mm) | Maximum (mm) |
| --------- | ------------ | ------------ |
| Box width, depth, height | 5 | 90 |
| Cylinder radius | 5 | 50 |
| Cylinder height | 5 | 90 |
| World position, per axis (`DocumentLimits.position`) | -10000 | 10000 |

Both `setParam` and `addObject` apply the size ranges via `DocumentLimits`. The position range is enforced only by `cad_add_solid` and `cad_set_transform`, which reject an out-of-bound position instead of clamping it (#98). Unknown keys and `.imported` objects are ignored without an error by the model itself, and the `cad_set_param` handler rejects both before calling it (#97).

---

## Native Document Persistence (`.made`)

Implemented (#83, [ADR-D7](./adr/ADR-D7-made-encoding.md)): the document model integrates with Apple's `FileDocument` protocol via `MadeDocument` and `MadePackage` as a directory package (`FileWrapper`):
- **Uniform Type Identifier**: `com.made.cad.document` (extension: `.made`, conforming to `com.apple.package` and `public.composite-content`). Registered in `Info.plist` and declared via `UTType.madeDocument`.
- **Package Bundle Architecture** ([ADR-D7](./adr/ADR-D7-made-encoding.md), #376):
  - `manifest.json`: Schema version (`schemaVersion: 1`), application version, unit settings, and kernel tolerances.
  - `document.json`: Serialized `DocumentData` (canonical JSON with sorted keys, 2-space indentation, trailing newline, clamping `DocumentLimits` on decode).
  - `parts/`: Plain-text `.part.ts` and `.part.js` part source files that external agents edit directly ([ADR-D6](./adr/ADR-D6-scripting-runtime.md), #435, #427).
  - `assets/`: Embedded STEP/IGES binary data (#38) and external reference descriptors (#160).
  - `cache/`: Regenerable B-rep caches, display meshes, simulation results, and `thumbnail.png` (#248), ignored by Git via `cache/.gitignore` containing `*` (#376).
- **Workspace Integration & Autosave**:
  - `WorkspaceModel` manages document lifecycle: New (⌘N), Open (⌘O), Save (⌘S), Save As (⇧⌘S).
  - Window title tracks document filename (or "Untitled CAD Document" when unsaved), displaying document modification state in the window close button and proxy icon.
  - Background autosave debounces document mutations (`autosaveDebounceNanoseconds`), writing asynchronously when an existing document file URL is bound.
  - Corrupt packages or unsupported future schema versions surface clean error feedback without corrupting active memory state.

---

## Undo / Redo Architecture

`DocumentModel` integrates AppKit / Foundation `UndoManager` to provide native, symmetric undo/redo operations (`DOC-16`, #39) accessible via standard macOS shortcuts (**⌘Z** and **⇧⌘Z**) and `EditMenuCommands`:

1. **Undo Registration & Scoping**:
   - Every mutating command API (`addObject`, `addPart`, `removeObject`, `setParam`, `setTransform`) registers its inverse action on `DocumentModel.undoManager`.
   - Undo and redo replay guards against locked objects (`isLocked`), aborting replay if the target is locked.
   - Deleting an object records its full `SceneObject` definition, properties, and array index; undoing removal calls `insertObject(_:at:actionName:)` to restore the object with its exact, identical `ObjectId` preserved without allocating a new sequence ID.
   - Any new mutating edit automatically clears redo history via native `UndoManager` semantics.

2. **Continuous Interaction & Coalescing**:
   - For continuous interactive controls (e.g. dragging dimension sliders in `InspectorPanelView`), `beginInteractiveParamEdit(id:key:)` captures the snapshot before dragging starts and pauses automatic per-tick undo registration.
   - Intermediate drag updates change the model and update the viewport live.
   - Upon release, `endInteractiveParamEdit(id:key:)` resumes undo registration and commits a single coalesced undo step bridging the initial value to the final value.

3. **Selective Re-tessellation & Viewport Integration**:
   - `DocumentModel` dispatches `DocumentMutation` notifications via `onUndoRedoMutation` callback during undo/redo replay.
   - `WorkspaceModel` observes mutations and executes selective invalidation:
     - **Parameter, Add, and Remove**: Triggers selective re-tessellation only for the affected solid, preserving unrelated cached geometries.
     - **Transform**: Directly updates the Metal renderer instance buffer and recalculates bounding boxes without dispatching kernel jobs (0 kernel dispatches, adhering to Invariant 3).

4. **Reactive State Tracking**:
   - Changes to the undo stack (`NSUndoManagerDidUndoChange`, `NSUndoManagerDidRedoChange`, `NSUndoManagerCheckpoint`) increment `@Observable private(set) var undoStateVersion: UInt64`, dynamically refreshing `canUndo`, `canRedo`, `undoActionTitle`, and `redoActionTitle` in the Edit menu.

---

## Open Decisions

None at this time.

---

## Decided

- ADR-D2 (#143) is decided. A history-based feature list with direct edits recorded as features and multi-body parts by default replaces the flat object array (BL-FND-01 / #150). Features evaluate sequentially in `KernelClient` off the main thread (invariant 1), while `DocumentModel` remains on `@MainActor` (invariant 7) ([ADR-D2](./adr/ADR-D2-modeling-paradigm-and-document-model.md)).
- ADR-D3 (#144) is decided. Topological naming references in the feature list use query-based generation history rather than unstable integer indices, preserving references across upstream dimension edits ([ADR-D3](./adr/ADR-D3-topological-naming.md), #152, #170).
- ADR-D7 (#149) is decided. A `.made` document is a directory package (`com.made.cad.document`) containing canonical JSON (`manifest.json`, `document.json`), plain-text part sources (`parts/*.part.ts`), imported assets (`assets/`), and a regenerable, Git-ignored binary cache directory (`cache/`) ([ADR-D7](./adr/ADR-D7-made-encoding.md), #83, #427, #376).

---

## Related Documentation

- [ADR-D2: Modeling Paradigm and Document Model](./adr/ADR-D2-modeling-paradigm-and-document-model.md)
- [ADR-D3: Topological Naming Strategy](./adr/ADR-D3-topological-naming.md)
- [`invariants.md`](./invariants.md): Invariant 3 (imperative viewport state)
- [`kernel.md`](./kernel.md): How document mutations dispatch kernel requests
- [`ui-controls.md`](./ui-controls.md): SwiftUI inspector bindings
