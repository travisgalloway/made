The floating card that runs a modeling command, placed next to the geometry it acts on.

Source [`macos/Sources/MadeApp/CommandHUDOverlayView.swift`](../../../macos/Sources/MadeApp/CommandHUDOverlayView.swift) and `CommandPanelView.swift`. Guidelines only, no preview (SwiftUI).

## What the consumer supplies
- A `CommandSession` with a title, selection slots and inputs. `CommandHUDPlacement` positions the card so it avoids the target's screen rectangle.

## Anatomy
- Header, `wrench.and.screwdriver` in the tint color and the command title in `headline`.
- Selection section, "Selection" in `subheadline` `label-secondary`, then one row per slot. The active slot fills with `accent` at `opacity-active` and `radius-sm`. A filled slot shows the object name in `callout`; an empty one shows "Click solid to select" in `caption`.
- Inputs, stacked with `space-8`.

## Card
- `hud-width` (260pt), `space-8` padding, `.regularMaterial`, `radius-lg`, 1pt `separator` border, `shadow-hud`.
- While a command runs, the viewport draws its preview in `command-preview` or `command-preview-cut`.
