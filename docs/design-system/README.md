# Design System

The visual rules for `made`, with the tokens in [`tokens.json`](./tokens.json) and a guideline page per view in [`components/`](./components/). Read it before building or restyling UI, or before choosing a color for anything drawn in the viewport. [`ui-controls.md`](../architecture/ui-controls.md) covers layout and control conventions; this page covers color, type, space and shape.

made is a native macOS CAD and engineering app. Its interface is SwiftUI on macOS 26, modeled on Xcode, around a dark Metal 4 viewport. Build anything for made so it reads as part of the Mac, then let the viewport carry the color.

## Content fundamentals

- Write the product name in lowercase, `made`, set in code style in docs and as plain lowercase text in UI.
- Use title case for commands, buttons and menu items ("Add Box", "Add Cylinder", "Open Part…", "Reset View (Isometric)", "Hide Object").
- Use sentence case for descriptions and hints ("Add a 3D solid primitive or open a part script to begin modeling.", "Click solid to select").
- Name things by what the engineer sees. Objects carry a name, a kind and a monospaced ID ("box-1", "Box", "40 × 20 × 10 mm").
- Lead status text with a short label and a value ("Render: 128", "Snap: endpoint", "Units: mm", "Regen: 4.2 ms").
- Give every icon-only button a text title and a `.help` string, for VoiceOver and tooltips.
- No emoji. Use SF Symbols for every glyph.

## Visual foundations

### Two surfaces

- Chrome follows the system. Use macOS semantic colors (`label`, `label-secondary`, `separator`, `window-background`, `control-background`, `accent`) and system materials (`.bar`, `.regularMaterial`, `.ultraThinMaterial`) so light and dark appearance, accent color and Increase Contrast come from the OS.
- The viewport is always dark. Fill it with `viewport-background` in both appearances and draw geometry with the viewport tokens only.
- The `system-*`, `label*`, `separator`, `fill-quaternary` and `*-background` tokens are Apple's reference values for previewing outside the app. In Swift, use the semantic API (`.secondary`, `Color.red`, `.separator`), never these hex values.

### Viewport color

- Draw the ground grid in `grid-minor`, with `grid-major` for major lines and the center lines.
- Color the axes `axis-x`, `axis-y` and `axis-z` (Z is world up). Color gizmo handles `gizmo-x`, `gizmo-y` and `gizmo-z`, and switch the dragged handle to `gizmo-active`.
- Fill new solids with `solid-default`.
- Draw edges in `edge-shaded` over shaded solids, `edge-wireframe` in Wireframe and Hidden Line modes, and `edge-hidden` for occluded edges.
- Outline the selection in `selection` (orange) and the hovered preselection in `preselection` (cyan). Never swap these two.
- Draw command previews in `command-preview`, and in `command-preview-cut` for subtractive commands. Show sketch regions in `sketch-region`, and `sketch-region-hover` under the pointer.

### Status color

- Snaps each own a color and a glyph shape, `snap-endpoint` through `snap-grid`. The shape always comes with the color, and the snap label names the kind, so a snap never depends on hue alone.
- Sketch constraint state uses `system-blue` for under-constrained, `system-green` for fully constrained, `system-red` for over-constrained and `system-purple` for inactive. Always pair the color with its symbol (`pencil.and.ruler`, `checkmark.circle.fill`, `exclamationmark.triangle.fill`) and its text.
- Warnings use `system-orange` with `exclamationmark.triangle.fill`; errors use `system-red` with `exclamationmark.circle.fill`.
- Console log levels tag INFO `system-blue`, KERNEL `system-purple`, SNAP `system-orange`, AGENT `system-green` and ERROR `system-red`.
- The MCP toolbar button turns green while the server runs. Its label and help text do not change yet, which the 2026-10-11 UX review flags; give new state indicators a text or symbol change as well.
- `system-green` and `system-red` differ by hue more than lightness. Keep them paired with symbols and words.

### Type

- Set all text in SF Pro through SwiftUI text styles. Use `callout` in every in-content bar, `body` for object names, `caption2` for kinds, IDs and summaries, `headline` for the command HUD title and Inspector section titles, and `title2` bold only for the largest heading.
- Use the `badge` style (9pt semibold) for DOF, Construction and Projected badges.
- Use SF Mono for identifiers, snap labels and the console (`snap-label`, `console`, `id`). Set numbers in bars with `.monospacedDigit()` so telemetry does not jitter.
- On the web, `type.families` maps SF Pro and SF Mono to the system stacks. No font files ship, because they are system fonts.

### Space, size and shape

- Every in-content bar is `bar-height` (36pt) with `space-10` horizontal padding and `space-10` between items, split by 16pt dividers.
- Apply `barControl()` to every bar button: borderless, icon only, small control size.
- Badges take `space-4` by `space-1` padding and `radius-xs`. A neutral badge fills with `label-secondary` at `opacity-tint-fill`; a DOF badge fills with its color at `opacity-tint-fill` and strokes 1pt at `opacity-tint-stroke`.
- Floating cards over the viewport use `.regularMaterial`, a 1pt `separator` border and a shadow (`radius-lg` and `shadow-hud` for the command HUD, `radius-xl`, `space-24` padding and `shadow-card` for the empty scene).
- Filter fields are capsules (`radius-capsule`) filled with `fill-quaternary`.
- Values stay exact. 3pt and 4pt corners are both in use; do not round them to one step.

### Layout

- The window is a `NavigationSplitView` with the Navigator on the left, the viewport in the middle and the Inspector on the right, plus a resizable console under the viewport.
- Toolbar groups render as one glass capsule each, separated by `ToolbarSpacer(.fixed)`. The viewport tool picker is the only segmented control.
- Side panes open with an icon tab bar (`PaneTabBar`). Navigator tabs are left-aligned; Inspector tabs fill the pane width.

## Iconography

- Use SF Symbols everywhere, at `.imageScale(.medium)` in bars.
- Each object kind has its own symbol and system tint in the Navigator, for example `shippingbox.fill` in blue for a box, `cylinder.fill` in orange for a cylinder, `curlybraces.square.fill` in teal for a part script and `cube.transparent` in purple for an imported mesh. A sketch's symbol and tint follow its constraint state.
- Snap glyphs are custom 1.5pt stroked shapes drawn at 8 to 12pt (square, triangle, circle with cross, X, diamond, bars, plus). They are not SF Symbols.
- The app icon is [`img/icon.png`](../../img/icon.png), a 1024px raster with no vector version; the same image is the layer in [`img/made.icon/`](../../img/made.icon/). It is a translucent glass M, outlined in `icon-edge`, standing on a ground grid (`icon-grid`) over a dark navy field (`icon-navy`, darkening to `icon-navy-deep` at the corners). Its faces run from `icon-glass-shade` to `icon-glass`, and bolt-hole rings in `icon-ice` mark each corner of the M. Use the file at 1024px or smaller; never redraw, recolor or upscale it. There is no separate wordmark; set the name in lowercase SF Pro.

## Files

- [`tokens.json`](./tokens.json) holds every color (light and dark), text style, spacing step, size, radius, shadow and opacity, each with a usage note naming where the code uses it. `meta` records the source files and commit.
- [`components/`](./components/) holds one guideline page per view. Each names its Swift source and the tokens it uses.

| View | Page |
| ---- | ---- |
| `BarControl` | [BarControl.md](./components/BarControl.md) |
| `BarFilterField` | [BarFilterField.md](./components/BarFilterField.md) |
| `PaneTabBar` | [PaneTabBar.md](./components/PaneTabBar.md) |
| `NavigatorRow` | [NavigatorRow.md](./components/NavigatorRow.md) |
| `ViewportStatusBar` | [ViewportStatusBar.md](./components/ViewportStatusBar.md) |
| `SnapOverlay` | [SnapOverlay.md](./components/SnapOverlay.md) |
| `ViewCube` | [ViewCube.md](./components/ViewCube.md) |
| `CommandHUD` | [CommandHUD.md](./components/CommandHUD.md) |
| `EmptySceneGuidance` | [EmptySceneGuidance.md](./components/EmptySceneGuidance.md) |
| `InspectorPanel` | [InspectorPanel.md](./components/InspectorPanel.md) |
| `CommitNumberField` | [CommitNumberField.md](./components/CommitNumberField.md) |
| `ConsoleDrawer` | [ConsoleDrawer.md](./components/ConsoleDrawer.md) |
| `MCPServerPopover` | [MCPServerPopover.md](./components/MCPServerPopover.md) |

## Sources and gaps

- Synced from `main@f539e33`. The app has no token file or asset catalog, so colors, sizes and radii were read from literals in the SwiftUI and Metal sources listed in `tokens.json` `meta`. The `icon-*` colors are sampled from the raster icon and are approximate. When one of those literals changes, update `tokens.json` in the same commit.
- System colors, label colors and text style sizes are Apple reference values for use outside the app, not values from this repo. Accent follows the user's setting. In Swift, use the semantic API.
- No font files. SF Pro and SF Mono are system fonts.
- Component pages are guidelines only, with no previews, because the views are SwiftUI.
- Skipped values. `outlineWidth` 0.008 and edge line widths (1.2, 3.0) are viewport-space, not UI tokens. Gizmo sizes (`defaultGizmoArrowLength` and the like) and the 10mm grid spacing are model units.
