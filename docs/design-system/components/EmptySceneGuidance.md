The card shown over an empty viewport, offering direct actions to start modeling.

Source [`macos/Sources/MadeApp/EmptySceneGuidanceOverlayView.swift`](../../../macos/Sources/MadeApp/EmptySceneGuidanceOverlayView.swift). Guidelines only, no preview (SwiftUI).

## Content
- A `ContentUnavailableView` titled "Empty Scene" with `cube.transparent`.
- Description "Add a 3D solid primitive or open a part script to begin modeling."
- Bordered regular-size buttons "Add Box" (`shippingbox`), "Add Cylinder" (`cylinder`) and "Open Part…" (`curlybraces`), `space-10` apart.

## Card
- `space-24` padding, `.regularMaterial`, `radius-xl`, 1pt `separator` border, `shadow-card`, centered in the viewport.

## Rules
- Every empty state offers the action that ends it, not only an explanation.
