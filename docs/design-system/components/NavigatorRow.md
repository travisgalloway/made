One outline row in the Navigator's Scene list, showing an object's icon, name, kind badge, ID and live parameter summary.

Source [`macos/Sources/MadeApp/NavigatorSidebarView.swift`](../../../macos/Sources/MadeApp/NavigatorSidebarView.swift) (`NavigatorRow`, `NavigatorSketchRow`, `NavigatorDatumPlaneRow`, `NavigatorDatumAxisRow`, `NavigatorDatumPointRow`, `NavigatorDatumCoordinateSystemRow`). Guidelines only, no preview (SwiftUI).

## What the consumer supplies
- A `SceneObject` (or a sketch feature) and the `WorkspaceModel` environment for selection, visibility and lock.

## Anatomy
- A 16pt (`row-icon`) icon column with the kind's SF Symbol in its system tint (box `system-blue`, cylinder `system-orange`, and so on).
- Line one, the name in `body`, a kind badge in `caption2` on `label-secondary` at `opacity-tint-fill` with `radius-xs`, then a warning or error symbol if the feature failed.
- Line two, the ID in monospaced `caption2`, a `label-tertiary` bullet, and the parameter summary in `caption2`, all `label-secondary`.
- Trailing eye and lock buttons with `barControl()`. They appear on hover and stay while the object is hidden or locked.
- Sketch rows add a DOF badge (`badge` style, the DOF color at `opacity-tint-fill`, 1pt stroke at `opacity-tint-stroke`).

## Spacing
- `space-8` between icon and text, `space-6` within a line, `space-2` between lines and as row padding.

## Accessibility
- The row combines into one element whose label reads name, kind, ID, summary and any error, with named actions for hide and lock.
