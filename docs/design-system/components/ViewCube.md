The orientation cube in the viewport corner, with a home button and a hover label for the region under the pointer.

Source [`macos/Sources/MadeApp/ViewCubeOverlayView.swift`](../../../macos/Sources/MadeApp/ViewCubeOverlayView.swift). Guidelines only, no preview (SwiftUI).

## Parts
- Home button, `house` at 10pt medium (`cube-home`) in `label-secondary`, on an 18pt (`cube-home-size`) chip of `window-background` at 0.8 opacity with `radius-sm` and a 0.5pt `label` hairline at `opacity-active`. Help text "Reset View (Isometric)".
- Region label, the region name in `cube-label` (8pt semibold) and `label-secondary`, on a capsule of `window-background` at 0.85 opacity with the same hairline.

## Rules
- The cube chips sit on the dark viewport in both appearances; keep their backing so the label stays legible.
