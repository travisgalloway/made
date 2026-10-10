# Document Model & Scene Graph

The document model in `made` is the single source of truth for all 3D scene objects, parametric feature trees, dimensional configurations, and spatial transformations. It is implemented as an `@Observable` Swift class (`final class DocumentModel: @unchecked Sendable`, with no actor isolation, see #91) in [`DocumentModel.swift`](../../macos/Sources/MadeCore/Scene/DocumentModel.swift) conforming to Invariant 3.

---

## Scene Architecture

```
┌────────────────────────────────────────────────────────┐
│              DocumentModel (@Observable)               │
│   • objects: [SceneObject] (ordered array)             │
│   (no selection set, no UndoManager yet)               │
└──────────────────────────┬─────────────────────────────┘
                           │ Dispatches Command Mutations
┌──────────────────────────▼─────────────────────────────┐
│                 Command Pattern API                    │
│   • addObject(def:transform:)                          │
│   • removeObject(id:)                                  │
│   • setParam(id:key:value:)                            │
│   • setTransform(id:transform:)                        │
└──────────────┬──────────────────────────┬──────────────┘
               │ Reactive Bindings        │ Async Invalidation
┌──────────────▼─────────────┐ ┌──────────▼──────────────┐
│     SwiftUI Inspector      │ │      KernelClient       │
│   (Dimensions, Transforms) │ │  (Tessellates Geometries│
└────────────────────────────┘ └─────────────────────────┘
```

---

## Object Data Model

Every entity in the scene graph is represented by a `SceneObject`:

```swift
public struct SceneObject: Identifiable, Sendable, Equatable {
    public let id: ObjectId              // typealias for SolidId
    public var def: ObjectDef            // .box, .cylinder, .imported(name:)
    public var transform: Transform      // position, rotation, scale
}

public enum ObjectDef: Sendable, Equatable {
    case box(BoxParams)                  // width, depth, height
    case cylinder(CylinderParams)        // radius, height
    case imported(name: String)
}
```

Nothing writes `Transform.rotation` or `Transform.scale` yet (#71). The model has no object name, visibility flag, or boolean-result type. Selection is a `@State var selectedId` in `ContentView`, not part of the model (#69).

### Supported Object Types
1. **Parametric Primitives**: Boxes (`width`, `depth`, `height`) and Cylinders (`radius`, `height`).
2. **Imported Placeholder**: `.imported(name:)` carries a name only. The `cad_boolean_operation` tool records its result as an `.imported` object under a different ID than the kernel result (#99, #100).
3. **Planned**: CSG composites that reference parent operations (#35), and B-Rep solids loaded from STEP or IGES files (#38, #82).

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

### Limits Clamping
`DocumentLimits` in `DocumentModel.swift` clamps parameter updates made through `setParam` to fixed ranges (a NaN value becomes the minimum):

| Parameter | Minimum (mm) | Maximum (mm) |
| --------- | ------------ | ------------ |
| Box width, depth, height | 5 | 90 |
| Cylinder radius | 5 | 50 |
| Cylinder height | 5 | 90 |

`setParam` and the `cad_add_solid` tool apply these ranges. Other paths into the model, such as `addObject(def:)` called directly, do not clamp (#104). Unknown keys and `.imported` objects are ignored without an error.

---

## Native Document Persistence (`.made`)

Planned (#83): the document model integrates with Apple's `FileDocument` protocol. No persistence exists today:
- **Uniform Type Identifier**: `com.made.cad.document` (extension: `.made`).
- **Package Bundle Architecture**:
  - `document.json`: Serialized scene graph hierarchy, parameters, and transforms.
  - `history.json`: Parametric feature tree and undo/redo operations.
  - `assets/`: Embedded STEP/IGES binary data for imported components.

---

## Related Documentation

- [`invariants.md`](./invariants.md): Invariant 3 (imperative viewport state)
- [`kernel.md`](./kernel.md): How document mutations dispatch kernel requests
- [`ui-controls.md`](./ui-controls.md): SwiftUI inspector bindings
