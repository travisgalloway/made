# Document Model & Scene Graph

The document model in `made` is the single source of truth for all 3D scene objects, parametric feature trees, dimensional configurations, and spatial transformations. It is implemented as an `@Observable` Swift class in [`DocumentModel.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Scene/DocumentModel.swift) conforming to Invariant 3.

---

## Scene Architecture

```
┌────────────────────────────────────────────────────────┐
│              DocumentModel (@Observable)               │
│   • objects: [ObjectId: SceneObject]                   │
│   • selection: Set<ObjectId>                           │
│   • undoManager: UndoManager                           │
└──────────────────────────┬─────────────────────────────┘
                           │ Dispatches Command Mutations
┌──────────────────────────▼─────────────────────────────┐
│                 Command Pattern API                    │
│   • addObject(...)                                     │
│   • removeObject(id:)                                  │
│   • setParam(id:name:value:)                           │
│   • setTransform(id:position:)                         │
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
public struct SceneObject: Identifiable, Sendable {
    public let id: ObjectId
    public var name: String
    public var type: ObjectType          // .box, .cylinder, .booleanResult
    public var params: [String: Float]   // width, depth, height, radius
    public var position: SIMD3<Float>    // 3D world position
    public var isVisible: Bool
}
```

### Supported Object Types
1. **Parametric Primitives**: Boxes (`width`, `depth`, `height`) and Cylinders (`radius`, `height`).
2. **CSG Composites**: Boolean evaluation results (`subtract`, `union`, `intersect`) referencing parent operations.
3. **Imported Solids**: Direct B-Rep solids loaded from industry-standard STEP or IGES files.

---

## Command Mutation API

All modifications to the scene must traverse the explicit command API rather than mutating property dictionaries directly:

```swift
// Create an object
let boxId = document.addObject(
    name: "Bracket Base",
    type: .box,
    params: ["width": 40, "depth": 30, "height": 10],
    position: SIMD3<Float>(0, 0, 0)
)

// Update dimension with automatic limits clamping
document.setParam(id: boxId, name: "width", value: 45)

// Update world transform
document.setTransform(id: boxId, position: SIMD3<Float>(10, 0, 0))

// Delete object
document.removeObject(id: boxId)
```

### Limits Clamping
The document model clamps all parameter updates to valid engineering envelopes (e.g., minimum dimensions of $0.001\text{ mm}$, maximum of $10{,}000\text{ mm}$). This guarantees that degenerate zero- or negative-volume geometry requests never reach the geometry kernel.

---

## Native Document Persistence (`.made`)

In Phase 4, the document model integrates with Apple's `FileDocument` protocol:
- **Uniform Type Identifier**: `com.made.cad.document` (extension: `.made`).
- **Package Bundle Architecture**:
  - `document.json`: Serialized scene graph hierarchy, parameters, and transforms.
  - `history.json`: Parametric feature tree and undo/redo operations.
  - `assets/`: Embedded STEP/IGES binary data for imported components.

---

## Related Documentation

- [`invariants.md`](./invariants.md) — Invariant 3 (imperative viewport state)
- [`kernel.md`](./kernel.md) — How document mutations dispatch kernel requests
- [`ui-controls.md`](./ui-controls.md) — SwiftUI inspector bindings
