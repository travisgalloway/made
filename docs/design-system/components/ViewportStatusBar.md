The telemetry bar under the viewport, laid out like Xcode's editor status bar, ending with the console toggle.

Source [`macos/Sources/MadeApp/ViewportStatusBar.swift`](../../../macos/Sources/MadeApp/ViewportStatusBar.swift). Guidelines only, no preview (SwiftUI).

## Contents, in order
- Metal state, `bolt.fill` "Metal 4" in `system-green` when ready and `system-yellow` otherwise, or `bolt.slash.fill` "Metal unavailable" in `system-red`.
- Render count, draw calls, last invalidation cause, active tool.
- Snap kind in its `snap-*` color, or "Snap: none".
- Units, sketch DOF status (symbol and text in the DOF color), selection count, last regeneration time.
- A spacer, then the console toggle (`rectangle.bottomthird.inset.filled`) in `accent` when shown.

## Style
- `callout` with `.monospacedDigit()`, `label-secondary` by default, on `.bar`.
- `bar-height`, `space-10` padding and gaps, 16pt dividers between items.
