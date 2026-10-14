# Document Model & Scene Graph

The document model in `made` is the single source of truth for all 3D scene objects, parametric feature trees, dimensional configurations, and spatial transformations. It is implemented as an `@Observable` Swift class (`final class DocumentModel: @unchecked Sendable`, with no actor isolation, see #91) in [`DocumentModel.swift`](../../macos/Sources/MadeCore/Scene/DocumentModel.swift) conforming to Invariant 3.

---

## Scene Architecture

Today, `DocumentModel` represents scenes through a flat array of `SceneObject` instances. Under ADR-D2 ([ADR-D2](./adr/ADR-D2-modeling-paradigm-and-document-model.md), #143, #150), `made` transitions to a hybrid history-based modeling paradigm: an ordered linear feature list (`features: [Feature]`) serving as the single source of truth, recording direct manipulation edits as discrete features, with multi-body parts by default. During transition (#150), evaluated output bodies project stable `SolidId` identifiers into `SceneObject` representations so existing MCP tools and UI inspectors continue operating without disruption.

```
┌────────────────────────────────────────────────────────┐
│              DocumentModel (@Observable)               │
│   • Current: objects: [SceneObject] (ordered array)    │
│   • Target (ADR-D2, #150): features: [Feature]         │
│     (multi-body parts, rollback, undo/redo integration)│
└──────────────────────────┬─────────────────────────────┘
                           │ Dispatches Command Mutations
┌──────────────────────────▼─────────────────────────────┐
│                 Command Pattern API                    │
│   • addObject(def:transform:)                          │
│   • removeObject(id:)                                  │
│   • setParam(id:key:value:)                            │
│   • setTransform(id:transform:)                        │
│   • setName / setVisibility / setLocked / setMaterial  │
│   • Target: addFeature / editFeature / rollbackTo      │
└──────────────┬──────────────────────────┬──────────────┘
               │ Reactive Bindings        │ Async Invalidation
┌──────────────▼─────────────┐ ┌──────────▼──────────────┐
│     SwiftUI Inspector      │ │      KernelClient       │
│   (Dimensions, Transforms, │ │  (Tessellates Geometries│
│    Feature Tree #34)       │ │   and Features off-main)│
└────────────────────────────┘ └─────────────────────────┘
```

---

## Object Data Model

Every entity in the scene graph is represented by a `SceneObject`:

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
}
```

Nothing writes `Transform.rotation` or `Transform.scale` yet (#71). The model stores an object name, a visibility flag, a lock flag, and material attributes. Selection is `WorkspaceModel.selectedId` in `MadeApp`, not part of the model (#69).

### Supported Object Types
1. **Parametric Primitives**: Boxes (`width`, `depth`, `height`) and Cylinders (`radius`, `height`).
2. **Imported Placeholder**: `.imported(name:)` carries a name only.
3. **Boolean Result**: `.boolean(op:solidA:solidB:)` records the operation and both operand IDs of a `cad_boolean_operation` result. `DocumentModel.reserveId(for:)` mints its `boolean-<seq>` ID before the kernel call, so the document and the kernel cache share it, and `addObject(_:def:)` adds it on success and installs its mesh in the viewport (#132). The entry is not replayed on kernel regeneration (#35).
4. **Planned**: CSG composites that reference parent operations (#35), and B-Rep solids loaded from STEP or IGES files (#38, #82).

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

The model also exposes `setName(id:name:)`, `setVisibility(id:isVisible:)`, `setLocked(id:isLocked:)`, and `setMaterial(id:material:)`. The Navigator calls the first three. No caller uses `setMaterial` yet, and no edit path enforces `isLocked`.

### Limits Clamping
`DocumentLimits` in `DocumentModel.swift` clamps parameter updates made through `setParam` to fixed ranges (a NaN value becomes the minimum):

| Parameter | Minimum (mm) | Maximum (mm) |
| --------- | ------------ | ------------ |
| Box width, depth, height | 5 | 90 |
| Cylinder radius | 5 | 50 |
| Cylinder height | 5 | 90 |
| World position, per axis (`DocumentLimits.position`) | -10000 | 10000 |

`setParam` and the `cad_add_solid` tool apply the size ranges. The position range is enforced only by `cad_add_solid` and `cad_set_transform`, which reject an out-of-bound position instead of clamping it (#98). Other paths into the model, such as `addObject(def:)` called directly, do not clamp (#104). Unknown keys and `.imported` objects are ignored without an error by the model itself, and the `cad_set_param` handler rejects both before calling it (#97).

---

## Native Document Persistence (`.made`)

Planned (#83, [ADR-D7](./adr/ADR-D7-made-encoding.md)): the document model integrates with Apple's `FileDocument` / `ReferenceFileDocument` protocols as a directory package (`FileWrapper`). No persistence exists today:
- **Uniform Type Identifier**: `com.made.cad.document` (extension: `.made`, conforming to `com.apple.package` and `public.composite-content`).
- **Package Bundle Architecture** ([ADR-D7](./adr/ADR-D7-made-encoding.md), #376):
  - `manifest.json`: Schema version (#237), document settings (#238), and custom metadata (#172).
  - `document.json`: Serialized scene graph, feature list, parameter table (#174), and assembly instances (#161), formatted with sorted keys and 2-space indentation.
  - `parts/`: Plain-text `.part.ts` and `.part.js` part source files that external agents edit directly ([ADR-D6](./adr/ADR-D6-scripting-runtime.md), #435, #427).
  - `assets/`: Embedded STEP/IGES binary data (#38) and external reference descriptors (#160).
  - `cache/`: Regenerable B-rep caches, display meshes, simulation results, and `thumbnail.png` (#248), ignored by Git (#376).

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
