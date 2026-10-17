The resizable log drawer under the viewport, shown and hidden with ⇧⌘Y or the status bar toggle.

Source [`macos/Sources/MadeApp/ConsoleDrawerView.swift`](../../../macos/Sources/MadeApp/ConsoleDrawerView.swift). Guidelines only, no preview (SwiftUI).

## Rows
- Timestamp to milliseconds in `label-secondary`, the level tag in bold at a 52pt column in its level color, the subsystem in `label-secondary`, then the message.
- All in the `console` style, `space-6` apart, separators hidden, 16pt minimum row height.

## Level colors
- INFO `system-blue`, KERNEL `system-purple`, SNAP `system-orange`, AGENT `system-green`, ERROR `system-red`. The tag text always names the level.

## Footer
- A `bar-height` bar with `BarFilterField` and a clear button (`trash`), both with `barControl()`.
