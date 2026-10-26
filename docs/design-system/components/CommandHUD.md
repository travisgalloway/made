The floating card that runs a modeling command, placed next to the geometry it acts on.

Source [`macos/Sources/MadeApp/CommandHUDOverlayView.swift`](../../../macos/Sources/MadeApp/CommandHUDOverlayView.swift) and `CommandPanelView.swift`. Guidelines only, no preview (SwiftUI).

## What the consumer supplies
- A `CommandSession` with a title, selection slots and inputs. `CommandHUDPlacement` positions the card so it avoids the target's screen rectangle.

## Anatomy
- Header, `wrench.and.screwdriver` in the tint color, the command title in `headline`, and a trailing `xmark.circle.fill` dismiss button (`command-panel-close-button`).
- Selection section, "Selection" in `subheadline` `label-secondary`, then one row per slot. The active slot fills with `accent` at `opacity-active` and `radius-sm`. A filled slot shows the object name in `callout`; an empty one shows "Click solid to select" in `caption`.
- Inputs, stacked with `space-8`, filtered by `CommandSession.visibleInputs` (`inputVisibilityPredicate`) so only inputs relevant to the selected mode or type are shown.

## Card
- 280pt width, `space-8` padding, `.regularMaterial`, `radius-lg`, 1pt `separator` border, `shadow-hud`.
- Draggable across the viewport via `DragGesture` and clamped to a 12pt viewport margin via `CommandHUDOverlayView.clampedPosition`.
- While a command with a 3D preview handler (`onPreviewUpdate != nil`) runs, the viewport draws its preview in `command-preview` or `command-preview-cut`.

## Heads-up dimension labels

Heads-up dimension labels render active feature dimensions directly in the Metal viewport overlay canvas.

Source [`macos/Sources/MadeApp/DimensionLabelsOverlayView.swift`](../../../macos/Sources/MadeApp/DimensionLabelsOverlayView.swift) and [`macos/Sources/MadeCore/Viewport/CommandHUDPlacement.swift`](../../../macos/Sources/MadeCore/Viewport/CommandHUDPlacement.swift).

### Pill badge presentation
- Background `.regularMaterial` inside a capsule border.
- Border 1pt `.separator`.
- Typography `.caption.monospacedDigit()`.
- Content shows the numeric value formatted to precision plus unit.
- Position clamped to a 16pt margin inside viewport edges. Colliding labels offset along the screen Y-axis or X-axis to keep each badge distinct and clickable.

### Inline edit interaction
- Clicking a pill badge switches the badge to an inline `CommitNumberField` with an active accent outline.
- Pressing Return commits the value to the matching numeric parameter in `CommandSession` and returns the badge to its pill state.
- Pressing Escape restores the prior value and returns the badge to its pill state.

