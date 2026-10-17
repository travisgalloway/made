A numeric field that edits a text draft and writes to the model only on Return or focus loss.

Source [`macos/Sources/MadeApp/CommitNumberField.swift`](../../../macos/Sources/MadeApp/CommitNumberField.swift). Guidelines only, no preview (SwiftUI).

## What the consumer supplies
- `label`, the field's accessibility name.
- `value`, the model value to display when not editing.
- `width`, default 56pt.
- `minimum`, an optional lower bound.
- `commit`, called with the parsed value.

## Behavior
- Shows the value with one decimal place and no grouping.
- After commit it shows the model's value, which may have been clamped.

## When to use
- For every numeric input in the Inspector. A field bound directly to the model reformats its text after each keystroke.
