The glyph and label drawn at the pointer when the snapping engine finds a target.

Source [`macos/Sources/MadeApp/SnapOverlayView.swift`](../../../macos/Sources/MadeApp/SnapOverlayView.swift). Guidelines only, no preview (SwiftUI).

## What the consumer supplies
- A `SnapResult` with a kind and a screen point. The overlay converts Metal's bottom-left coordinates to SwiftUI's top-left and ignores hit testing.

## Glyphs
- Each kind has a 1.5pt stroked shape and a color. Endpoint and vertex a square (`snap-endpoint`, `snap-vertex`), midpoint a triangle (`snap-midpoint`), center a circle with cross (`snap-center`), intersection an X (`snap-intersection`), quadrant a diamond (`snap-quadrant`), edge bars (`snap-edge`), grid a plus (`snap-grid`).
- Glyphs are 10pt square, the midpoint 12 by 10pt and the grid 8pt.

## Label
- A 4pt dot in the snap color and the capitalized kind in `snap-label`, `label` color.
- `space-6` by `space-2` padding on `.ultraThinMaterial`, `radius-sm`, `shadow-label`.
- Offset 36pt right of and 14pt above the point, clamped 16pt from the top.

## Rules
- Never show a snap by color alone; the shape and label carry the kind.
