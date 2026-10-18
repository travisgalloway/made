A capsule filter field with a leading filter symbol, as in Xcode's navigator and debug-area footers.

Source [`macos/Sources/MadeApp/BarControls.swift`](../../../macos/Sources/MadeApp/BarControls.swift). Guidelines only, no preview (SwiftUI).

## What the consumer supplies
- `text`, a `Binding<String>`.
- `prompt`, the placeholder, default "Filter".

## Anatomy
- `line.3.horizontal.decrease.circle` in `label-secondary`, a plain `TextField`, and an `xmark.circle.fill` clear button that shows only when text is present.
- `space-4` between parts, `space-6` by `space-3` padding, `fill-quaternary` capsule (`radius-capsule`), `barControl()` applied.

## When to use
- In the Navigator footer and the console footer. Filters match as the user types; there is no submit.
