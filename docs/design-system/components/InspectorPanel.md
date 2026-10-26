The right-hand pane that edits the selected object's identity, transform and dimensions.

Source [`macos/Sources/MadeApp/InspectorPanelView.swift`](../../../macos/Sources/MadeApp/InspectorPanelView.swift). Guidelines only, no preview (SwiftUI).

## Structure
- Opens with a `PaneTabBar` filling the width (Attributes, Metadata, Physical, Document).
- Attributes (`.properties`) shows Identity, Transform, Dimensions, and Bounding Box (or active feature, sketch, datum, assembly, or simulation study parameters).
- Metadata (`.metadata`) shows Identity, Standard Properties (Part Number, Description, Revision, Vendor), and Custom Properties.
- Physical (`.physical`) shows Material assignment, Body Color, Material Library browser, and Mass Properties.
- Document (`.document`) shows Document Settings, Units, Tolerances, and Parameters.
- Position and scale use three `CommitNumberField`s each with X, Y and Z captions stacked beneath a secondary caption header so fields fit within narrow inspector widths without clipping.
- Each dimension row places its label, `CommitNumberField`, unit symbol, and `Stepper` on the top row with a full-width `Slider` below so controls never clip.
- With nothing selected, show `ContentUnavailableView` "No Object Selected". Imported meshes show identity and transform only.

## Sketch entities
- Each entity is a card with `space-4` padding, `radius-sm` and a 1pt stroke. Construction geometry gets a dashed divider and a dashed `badge`; projected geometry gets a `system-purple` badge at `opacity-projected`.
- Rows declare `.isButton` accessibility traits, adding `.isSelected` when active.
- Accessibility labels announce entity kind, degrees of freedom status, and construction or projection states.
- Rows support keyboard focus via `.focusable()` and selection via `.onKeyPress(.return)`.
- VoiceOver accessibility actions expose entity selection, construction toggling, and deletion.

## Sketch regions
- Each region row displays region number, computed area in square millimeters, and hole counts.
- Rows declare `.isButton` accessibility traits, adding `.isSelected` when active.
- Accessibility labels announce region number, area, and hole count.
- Rows support keyboard focus via `.focusable()` and selection via `.onKeyPress(.return)`.
- VoiceOver accessibility actions expose region selection and extrusion.

## Rules
- Edits go through `DocumentModel.setParam`, which clamps to `DocumentLimits`, and regeneration is debounced. Never bind a field straight to the model.
