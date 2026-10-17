The shared style for every button, menu and field in an in-content bar, applied with the `barControl()` modifier.

Source [`macos/Sources/MadeApp/BarControls.swift`](../../../macos/Sources/MadeApp/BarControls.swift). Guidelines only, no preview (SwiftUI).

## When to use
- On every control inside the viewport header, the status bar, the console footer and the Navigator footer.
- Not in the window toolbar, forms or popovers, which use system styles.

## What it applies
- `.buttonStyle(.borderless)`, `.labelStyle(.iconOnly)`, `.controlSize(.small)`, `.imageScale(.medium)`.
- The bar itself is `BarMetrics.height` (`bar-height`, 36pt), uses `callout` text and sits on `.bar` material.

## Rules
- Give each control a text title and a `.help` string even though only the icon shows.
- Tint toggles with `accent` when on and `label-secondary` when off, as the console toggle does.
