The icon tab bar at the top of a side pane, wrapping `NSSegmentedControl` so segments can stretch.

Source [`macos/Sources/MadeApp/PaneTabs.swift`](../../../macos/Sources/MadeApp/PaneTabs.swift). Guidelines only, no preview (SwiftUI).

## What the consumer supplies
- `label`, the accessibility label of the control.
- `selection`, a binding to a `PaneTab` enum value. Each case gives a `title` and an SF Symbol `systemImage`.
- `fillsWidth`, false for the Navigator (left-aligned), true for the Inspector (segments fill the pane).

## Layout
- `space-10` horizontal and `space-6` vertical padding.

## Tabs today
- Navigator has Scene (`cube`), Construction (`ruler`), and Simulation (`waveform.path.ecg`).
- Inspector has Attributes (`slider.horizontal.3`), Metadata (`tag`), Physical (`scalemass`), and Document (`doc.text`).
- A new pane view is a new enum case, never a new control.
