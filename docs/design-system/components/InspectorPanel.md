The right-hand pane that edits the selected object's identity, transform and dimensions.

Source [`macos/Sources/MadeApp/InspectorPanelView.swift`](../../../macos/Sources/MadeApp/InspectorPanelView.swift). Guidelines only, no preview (SwiftUI).

## Structure
- Opens with a `PaneTabBar` filling the width (Properties, Document).
- Properties is a `.formStyle(.columns)` form with small controls and sections Identity, Transform and Dimensions, titled in `headline`.
- Position and scale use three `CommitNumberField`s each with X, Y and Z captions.
- Each dimension has a millimeter `CommitNumberField` and a 1mm stepper, with accessibility names and values in millimeters.
- With nothing selected, show `ContentUnavailableView` "No Object Selected". Imported meshes show identity and transform only.

## Sketch entities
- Each entity is a card with `space-4` padding, `radius-sm` and a 1pt stroke. Construction geometry gets a dashed divider and a dashed `badge`; projected geometry gets a `system-purple` badge at `opacity-projected`.

## Rules
- Edits go through `DocumentModel.setParam`, which clamps to `DocumentLimits`, and regeneration is debounced. Never bind a field straight to the model.
