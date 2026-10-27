---
name: made-cad
description: Author, reload, inspect, and verify parametric 3D CAD parts (.part.ts and .part.js) in made over MCP. Trigger when creating or editing .part.ts or .part.js files, using the "made" CAD module, connecting to made on 127.0.0.1:9820, or calling cad_reload, cad_get_diagnostics, cad_verify, cad_capture_snapshot, cad_measure, or scene tools.
---

# Authoring and Verifying Parametric Parts in made

This skill documents the `.part.ts` and `.part.js` part workflow for `made`, including the `"made"` TypeScript/JavaScript API, the `export const expected` verification contract, the MCP server connection on `127.0.0.1:9820`, every MCP tool exposed by `made`, a copyable gallery of example parts, and a benchmark evaluation set.

## 1. MCP Connection and Transport

`made` exposes a Model Context Protocol (MCP, protocol version `2024-11-05`) server over two transports:

1. **Local TCP Server (`127.0.0.1:9820`)**: When the `made` macOS app is running, it listens on TCP host `127.0.0.1` port `9820` using newline-delimited JSON-RPC 2.0 messages (one UTF-8 JSON object per `\n`-terminated line, up to 16 MiB per line).
2. **Standard Input/Output (`--mcp-stdio`)**: Launch `Made --mcp-stdio` to communicate over `stdin` and `stdout` using the same newline-delimited JSON-RPC 2.0 framing.

A typical JSON-RPC handshake sends `initialize` followed by `notifications/initialized`, then invokes tools with `tools/call`:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-code","version":"1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cad_reload","arguments":{"file":"/absolute/path/to/bracket.part.ts"}}}
```

## 2. The `.part.ts` / `.part.js` File Format

Part files use the `.part.ts` or `.part.js` extension and execute inside a deterministic, sandboxed JavaScriptCore runtime (`PartRuntime`) off the main thread.

### Runtime Constraints and Determinism

- Import CAD primitives, sketches, booleans, transforms, and parameter helpers from `"made"`.
- Relative ES module imports (`import { helper } from "./utils.ts"`) inside the same part directory (and subdirectories) are supported. Parent directory traversal (`..`), absolute paths, and external npm packages are rejected.
- Network, filesystem, timer, and process globals (`fetch`, `XMLHttpRequest`, `WebSocket`, `fs`, `process`, `require`, `setTimeout`, `setInterval`) are disabled.
- `Math.random()` uses a deterministic seeded generator and `Date.now()` returns a fixed epoch timestamp so repeated evaluations produce identical geometry.
- TypeScript type annotations, `interface` declarations, `type` aliases, and `import type` statements are stripped with line-preserving source mapping so syntax and runtime errors report exact `file`, `line`, and `column` locations.
- Full TypeScript type declarations are bundled at [references/made.d.ts](references/made.d.ts). Run `tsc --noEmit` against `references/made.d.ts` before reloading to catch type errors early.

### Coordinate System and Centering Conventions

`made` uses a right-handed Z-up coordinate system with dimensions in millimeters (`mm`):
- **X axis**: width (right is `+X`)
- **Y axis**: depth (back is `+Y`)
- **Z axis**: height / up (up is `+Z`)

Primitive centering behavior depends on the `center` option:
- **`Box(width, depth, height, options?)`**:
  - Default (`center` omitted or `true`): centered at `[0, 0, 0]`, spanning `[-width/2..width/2, -depth/2..depth/2, -height/2..height/2]`.
  - `{ center: false }`: minimum corner sits at `[0, 0, 0]`, spanning `[0..width, 0..depth, 0..height]`.
  - `{ center: [x, y, z] }`: centered at `[x, y, z]`.
- **`Cylinder(radius, height, options?)`** and **`Cone(radius, height, options?)`**:
  - Default (`center` omitted or `true`): centered at `[0, 0, 0]`, axis along Z, spanning `Z` from `-height/2` to `+height/2`.
  - `{ center: false }`: base sits on the XY plane at `Z = 0`, spanning `Z` from `0` to `height` (`[-radius..radius, -radius..radius, 0..height]`).
  - `{ center: [x, y, z] }`: centered at `[x, y, z]`.
  - `{ slices: number }`: radial tessellation count (default `32`). `Cone` also accepts `{ topRadius: number }` for frustums.
- **`Sphere(radius, options?)`**:
  - Default (`center` omitted or `true`): centered at `[0, 0, 0]`, spanning `[-radius..radius]` on all axes.
  - `{ center: false }`: bottom rests on `Z = 0`, centered at `[0, 0, radius]`.
  - `{ center: [x, y, z] }`: centered at `[x, y, z]`.
  - `{ slices: number }`: tessellation count (default `32`).

### 2D Sketches, Extrusion, and Revolution

Create 2D profiles on a construction plane using `Sketch(plane?)`:
- **Built-in Planes**:
  - `Plane.XY`: origin `[0, 0, 0]`, normal `[0, 0, 1]`, xAxis `[1, 0, 0]` (extrudes along `+Z`).
  - `Plane.XZ`: origin `[0, 0, 0]`, normal `[0, 1, 0]`, xAxis `[1, 0, 0]` (extrudes along `+Y`).
  - `Plane.YZ`: origin `[0, 0, 0]`, normal `[1, 0, 0]`, xAxis `[0, 1, 0]` (extrudes along `+X`).
  - `Plane.offset(plane, distance)`: shifts `plane` along its normal by `distance`.
  - `Plane.custom(origin, normal, xAxis?)`: custom construction plane.
- **Closed Profile Helpers**:
  - `.rectangle(width, height, { center?: [x, y] | boolean })` (centered at `[0, 0]` by default; `{ center: false }` places minimum corner at `[0, 0]`).
  - `.roundedRectangle(width, height, radius, { detail?: number, center?: [x, y] | boolean })`.
  - `.circle(radius, { segments?: number, center?: [x, y] })`.
  - `.regularPolygon(radius, sides, { center?: [x, y] })`.
  - `.polygon([[x0, y0], [x1, y1], ...])`.
- **Path Drawing**:
  - `.moveTo(x, y)`, `.lineTo(x, y)`, `.arcTo(endX, endY, radius, { clockwise?: boolean, segments?: number })`, `.close()`, `.translate(dx, dy)`.
- **Sweep Operations**:
  - `.extrude(distance, { centered?: boolean })` or `extrude(sketch, distance, { centered?: boolean })`.
  - `.revolve(angleDegrees?, { slices?: number })` or `revolve(sketch, angleDegrees?, { slices?: number })`. `angleDegrees` defaults to `360`. For profiles on `Plane.XZ` revolved around the Z axis, all profile X coordinates (radial distance) must be `>= 0`.

### Boolean Operations and Transforms

Every `Shape` supports both method chaining and functional helpers:
- **Booleans**:
  - `a.union(b, ...)` or `union(a, b, ...)` (alias `fuse`)
  - `a.subtract(b, ...)` or `subtract(a, b, ...)` (aliases `cut`, `difference`)
  - `a.intersect(b, ...)` or `intersect(a, b, ...)` (aliases `common`, `intersection`)
- **Transforms**:
  - `shape.translate(x, y, z)` or `shape.translate([x, y, z])` or `translate(shape, [x, y, z])`
  - `shape.rotate(angleDegrees, [ax, ay, az])` or `rotate(shape, angleDegrees, [ax, ay, az])`
  - `shape.rotateX(angleDegrees)`, `shape.rotateY(angleDegrees)`, `shape.rotateZ(angleDegrees)`
  - `shape.scale(factor)` or `shape.scale(sx, sy, sz)` or `scale(shape, factor)`

### Parameters and Default Export

Declare adjustable parameters with `param(name, defaultValue, options?)` or `defineParams(schema)`:

```ts
import { Box, Cylinder, param, type ExpectedSpec } from "made";

const width = param("width", 50, { min: 20, max: 100, step: 5, label: "Plate Width" });
const holeRadius = param("holeRadius", 5, { min: 2, max: 15, step: 0.5 });

export default Box(width, 50, 8, { center: false }).subtract(
  Cylinder(holeRadius, 12).translate(width / 2, 25, 4)
);
```

Export the resulting `Shape` (or a zero-argument builder function `() => Shape`) as `export default`.

## 3. The `export const expected` Verification Block

Every `.part.ts` file authored by an agent should export an `expected` block conforming to `ExpectedSpec`. `cad_verify` compares the tessellated solid against these expectations:

```ts
import { type ExpectedSpec } from "made";

export const expected: ExpectedSpec = {
  volume: 29841.37,
  area: 10254.56,
  bounds: {
    min: [0, 0, 0],
    max: [60, 40, 45],
  },
  tolerance: 0.01,
};
```

Supported fields in `expected`:
- `volume` (`number`, optional): expected volume in $\text{mm}^3$, checked within relative `tolerance` (`|measured - expected| <= max(|expected|, 1e-9) * tolerance`).
- `area` or `surfaceArea` (`number`, optional): expected total surface area in $\text{mm}^2$, checked within relative `tolerance`.
- `bounds` (`{ min: [x, y, z], max: [x, y, z] }`, optional): expected axis-aligned bounding box in $\text{mm}$. Each coordinate is checked within `max(maxExtent * tolerance, 1e-4)` where `maxExtent` is the largest expected box dimension.
- `tolerance` (`number`, optional): relative tolerance fraction (default `0.01`, which is 1%).

Only the keys `volume`, `area`, `surfaceArea`, `bounds`, and `tolerance` are valid on `expected`. Unknown keys trigger an evaluation warning in `cad_get_diagnostics`.

## 4. MCP Tools Reference

`made` registers 19 MCP tools in `CADToolRegistry`:

| Tool Name | Purpose | Arguments |
| --- | --- | --- |
| `cad_reload` | Re-evaluate an open part immediately, open and evaluate a `.part.ts`/`.part.js` file from disk, or reload all open parts. | `id?: string` (solid UUID), `file?: string` (absolute path to `.part.ts`/`.part.js`). Omit both to reload all open parts. |
| `cad_get_diagnostics` | Return the last evaluation `errors` and `warnings` (each with `file`, `line`, `column`, `message`) for open part files. | `id?: string` (filter by solid UUID), `file?: string` (filter by file path). |
| `cad_verify` | Verify one solid or all solids in the scene for `closed`, `manifold`, `positiveVolume`, zero evaluation errors, and agreement with `export const expected` within `tolerance`. Returns `isError: true` with measured and expected values when any check fails. | `id?: string` (solid UUID). Omit to verify all solids in the scene. |
| `cad_capture_snapshot` | Render the current 3D viewport to an 800x600 PNG image (returned as MCP `image/png` base64 content). | `view?: "front" \| "top" \| "right" \| "isometric" \| "perspective"`. Omit to use the active camera. |
| `cad_measure` | Measure exact tessellated `volume`, `surfaceArea`, and `boundingBox` (`min`, `max`, `size`) for a solid. | `id: string` (required solid UUID). |
| `cad_get_scene` | List all objects in the scene with their `id`, `name`, `primitiveType`, `parameters`, `transform`, or `partFilePath`. | None (`{}`). |
| `cad_add_solid` | Add a primitive solid (`box`, `cylinder`) directly to the scene. | `type: "box" \| "cylinder"`, `width?: number`, `depth?: number`, `height?: number`, `radius?: number`, `posX?: number`, `posY?: number`, `posZ?: number`. |
| `cad_set_param` | Update a numeric parameter on a primitive solid or feature (including extrude distance) and regenerate its mesh. | `id: string` (solid ID or feature UUID, required), `param: string` (required), `value: number` (required). |
| `cad_set_transform` | Set the 3D world position of a solid. | `id: string` (required), `posX?: number`, `posY?: number`, `posZ?: number`. |
| `cad_remove_solid` | Remove a solid from the scene (and stop its file watcher if it is a part). | `id: string` (required). |
| `cad_boolean_operation` | Combine two existing scene solids using CSG `union`, `subtract`, or `intersect`. | `operation: "union" \| "subtract" \| "intersect"`, `solidA: string`, `solidB: string`, `name?: string`. |
| `cad_rollback` | Roll the timeline marker backward or forward. Features after the marker are excluded from scene projection and evaluation. | `index?: number` (0-based feature index), `solidId?: string` (solid UUID or "end"). |
| `cad_create_sketch` | Create a new 2D sketch on a plane (XY, XZ, YZ, or datum plane) with optional initial geometric entities. | `plane?: string` ("XY", "XZ", "YZ", or datum plane ID/name), `entities?: object[]`. |
| `cad_add_sketch_entity` | Add a 2D geometric entity (line, arc, circle, ellipse, elliptical arc, or text) to an existing sketch. | `sketchId: string` (required), `type: "line" \| "arc" \| "circle" \| "ellipse" \| "ellipticalArc" \| "text"` (required), coordinates (`startX`, `startY`, `endX`, `endY`, `centerX`, `centerY`, `radius`, `radiusX`, `radiusY`, `rotationAngle`, `startAngle`, `endAngle`, `clockwise`, `text`, `fontName`, `fontSize`, `originX`, `originY`, `isConstruction`). |
| `cad_add_constraint` | Apply a geometric constraint between entities in a sketch. | `sketchId: string` (required), `type: string` (required), `entityIds: string[]` (required), `referenceEntityId?: string`. |
| `cad_extrude` | Extrude a closed 2D sketch into a 3D parametric solid. | `sketchId: string` (required), `distance: number` (required), `isSymmetric?: boolean`, `draftAngle?: number`, `regionId?: string`. |
| `cad_fillet` | Apply a topological fillet blend to a solid edge by topological reference or UUID. | `solidId: string` (required), `edge: string` (required label or UUID), `radius: number` (required). |
| `cad_query_tree` | Query the document feature history tree, parameters, output solids, and topological references. | `featureId?: string` (optional feature UUID). |
| `cad_query_topology` | Query 3D topological sub-elements (faces, edges, vertices) with persistent IDs, surface and curve types, normal vectors, centroids, areas, and lengths. | `solidId?: string` (optional solid ID), `featureId?: string` (optional feature UUID), `elementType?: "face" \| "edge" \| "vertex"` (optional filter). |
| `reorder_features` (`cad_reorder_features`) | Reorder features in the document timeline according to the provided list of feature UUIDs, validating that no feature precedes its dependencies. | `feature_ids: string[]` (required ordered list of feature UUIDs). |
| `offset_sketch_entities` (`cad_offset_sketch_entities`) | Offset connected chains, lines, circles, or arcs in a 2D sketch by a perpendicular distance, generating parallel, concentric, and corner coincident constraints. | `sketchId: string` (required), `distance: number` (required), `entityIds?: string[]`. |
| `mirror_sketch_entities` (`cad_mirror_sketch_entities`) | Reflect sketch entities across an axis line in a 2D sketch, inverting arc sweep chirality and generating symmetric and axis coincident constraints. | `sketchId: string` (required), `mirrorLineId: string` (required), `entityIds?: string[]`. |
| `linear_pattern_sketch_entities` (`cad_linear_pattern_sketch_entities`) | Replicate sketch entities in a 1D or 2D linear pattern with specified directions, spacing, and counts, generating parallel and equal constraints. | `sketchId: string` (required), `spacing1: number` (required), `count1: number` (required), `dir1X?: number`, `dir1Y?: number`, `spacing2?: number`, `count2?: number`, `dir2X?: number`, `dir2Y?: number`, `entityIds?: string[]`. |
| `circular_pattern_sketch_entities` (`cad_circular_pattern_sketch_entities`) | Replicate sketch entities in a circular pattern around a center point with count and angular span, generating equal constraints. | `sketchId: string` (required), `centerX: number` (required), `centerY: number` (required), `count: number` (required), `totalAngle?: number`, `equalSpacing?: boolean`, `entityIds?: string[]`. |
| `fillet_sketch_corner` (`cad_fillet_sketch_corner`) | Round a 2D sketch corner between two intersecting lines with a tangent circular arc, trimming lines and generating tangent and coincident constraints. | `sketchId: string` (required), `line1Id: string` (required), `line2Id: string` (required), `radius: number` (required). |
| `chamfer_sketch_corner` (`cad_chamfer_sketch_corner`) | Bevel a 2D sketch corner between two intersecting lines with a straight segment, trimming lines and generating coincident constraints. | `sketchId: string` (required), `line1Id: string` (required), `line2Id: string` (required), `distance1: number` (required), `distance2?: number`, `angle?: number`. |
| `cad_import_dxf_to_sketch` (`import_dxf_to_sketch`) | Import AutoCAD 2000 ASCII DXF geometry (lines, arcs, circles, ellipses, bulged polylines, splines, text) into a 2D sketch with optional unit scaling, layer filtering, and endpoint welding. | `sketchId: string` (required), `dxfContent?: string`, `filePath?: string`, `unit?: string`, `scale?: number`, `offsetX?: number`, `offsetY?: number`, `layers?: string[]`, `weldEndpoints?: boolean`, `markConstruction?: boolean`. |
| `cad_import_svg_to_sketch` (`import_svg_to_sketch`) | Import Scalable Vector Graphics (SVG) geometry (lines, rectangles, circles, ellipses, polylines, polygons, Bézier curves, arcs) into a 2D sketch with optional unit scaling, layer filtering, and endpoint welding. | `sketchId: string` (required), `svgContent?: string`, `filePath?: string`, `unit?: string`, `scale?: number`, `offsetX?: number`, `offsetY?: number`, `dpi?: number`, `invertY?: boolean`, `layers?: string[]`, `weldEndpoints?: boolean`, `markConstruction?: boolean`, `curveIntervals?: number`. |
| `cad_place_image_underlay` (`place_image_underlay`) | Place a reference raster image underlay on a 2D sketch plane with specified dimensions, position, rotation, and opacity. | `sketchId: string` (required), `imageBase64?: string`, `filePath?: string`, `name?: string`, `positionX?: number`, `positionY?: number`, `width?: number`, `height?: number`, `rotation?: number`, `opacity?: number`, `preserveAspectRatio?: boolean`. |
| `cad_calibrate_image_underlay` (`calibrate_image_underlay`) | Calibrate the scale and position of a sketch image underlay using two reference points and a target distance. | `sketchId: string` (required), `underlayId: string` (required), `point1X: number` (required), `point1Y: number` (required), `point2X: number` (required), `point2Y: number` (required), `targetDistance: number` (required). |

## 5. The Agent Workflow Loop: Edit -> Reload -> Diagnostics -> Verify -> Snapshot -> Repair

Follow this closed-loop workflow whenever creating or modifying a part:

1. **Author the `.part.ts` file**:
   - Select the closest pattern from `examples/` if applicable.
   - Compute or estimate the expected bounding box, volume, and surface area, and write `export const expected: ExpectedSpec = { ... }`.
   - Remember that subtracting a hole of radius $r$ and length $L$ through a plate removes $\pi r^2 L$ of volume, removes $2 \pi r^2$ of flat end-cap area, and adds $2 \pi r L$ of cylindrical bore wall area. Remember also that faceted cylinders with $N$ segments have polygon area $\frac{1}{2} N r^2 \sin(2\pi / N)$ rather than $\pi r^2$.
2. **Optional Type-Check (`tsc --noEmit`)**:
   - If `tsc` is available, run `tsc --noEmit --strict` with `references/made.d.ts` included to catch signature mismatches before runtime evaluation.
3. **Reload in `made` (`cad_reload`)**:
   - Call `cad_reload` with `{"file": "/absolute/path/to/part.part.ts"}`.
   - Record the returned `id` (solid UUID) and check `status`.
4. **Inspect Diagnostics (`cad_get_diagnostics`)**:
   - If `cad_reload` returned `isError: true` or non-empty `warnings`, call `cad_get_diagnostics` with `{"id": "<solidId>"}`.
   - Every diagnostic provides `file`, `line`, `column`, and `message`. Fix syntax, import, or runtime errors at the reported line before proceeding.
5. **Run Geometric & Contract Verification (`cad_verify`)**:
   - Call `cad_verify` with `{"id": "<solidId>"}`.
   - Confirm that:
     - `closed` is `true` (every directed triangle edge has an opposite-direction partner).
     - `manifold` is `true` (every undirected edge is shared by exactly two triangles and no face is degenerate).
     - `positiveVolume` is `true` (signed volume $> 0$, confirming outward face normals).
     - `checks` (`volume`, `area`, `bounds`) all have `passed: true`.
   - If an `expected` check fails, inspect `measured` vs. `expected` in the response:
     - A wrong `bounds` range usually indicates a centering mismatch (`{ center: false }` vs. centered at origin) or an axis rotation error (`rotateX` vs. `rotateY`).
     - A wrong `volume` after a boolean `subtract` usually means the cutting tool did not intersect the target solid (check tool translation coordinates) or only partially penetrated the wall (extend tool length by $+2$ to $+4\text{ mm}$ beyond both faces).
6. **Visual Verification (`cad_capture_snapshot`)**:
   - Call `cad_capture_snapshot` with `{"view": "isometric"}` and at least one orthographic projection (`"front"`, `"top"`, or `"right"`).
   - Inspect the PNG snapshot to confirm that through-holes, slots, bosses, and symmetries match the design intent.
7. **Surgical Repair**:
   - Modify only the smallest responsible expression in the `.part.ts` file and repeat from Step 3 until `cad_reload`, `cad_get_diagnostics`, `cad_verify`, and `cad_capture_snapshot` all pass cleanly.

## 6. Example Part Gallery

Copy or adapt from the verified reference parts in `examples/`:

- [examples/mounting-bracket.part.ts](examples/mounting-bracket.part.ts): L-shaped mounting bracket built with `Box({ center: false })`, `Cylinder`, `rotateY`, `union`, `subtract`, and `param(...)` declarations.
- [examples/flanged-bushing.part.ts](examples/flanged-bushing.part.ts): Cylindrical flanged sleeve bearing with a central bore and 4-bolt mounting circle using `defineParams(...)` and `Cylinder({ center: false })`.
- [examples/slotted-standoff.part.ts](examples/slotted-standoff.part.ts): Rounded rectangular standoff block sketched on `Plane.XY` with `Sketch.roundedRectangle(...).extrude(...)` and an obround center slot.
- [examples/revolved-pulley.part.ts](examples/revolved-pulley.part.ts): V-groove pulley wheel created by sketching a cross-section polygon on `Plane.XZ` and calling `.revolve(360, { slices: 36 })`.
- [examples/hex-socket-cap.part.ts](examples/hex-socket-cap.part.ts): Socket head cap screw blank combining `Cylinder` bodies with a recessed hexagonal Allen socket sketched on an offset plane (`Plane.offset(Plane.XY, ...)` + `.regularPolygon(r, 6).extrude(...)`).
- [examples/stepped-manifold-block.part.ts](examples/stepped-manifold-block.part.ts): Multi-port fluid manifold block demonstrating functional CSG (`union`, `subtract`, `intersect`) across `Box`, `Sphere`, `Cylinder`, and `Cone`.

## 7. Evaluation Benchmark Set

The evaluation set in [eval/requests.json](eval/requests.json) and `eval/solutions/` provides five end-to-end part authoring tasks with natural-language prompts, target bounding boxes, and reference `.part.ts` solutions that pass `cad_verify`:

1. `eval-01-perforated-plate` ([eval/solutions/eval-01-perforated-plate.part.ts](eval/solutions/eval-01-perforated-plate.part.ts)): 60x40x6 mm rectangular plate on the XY plane with a central 16 mm bore and four 6 mm corner holes.
2. `eval-02-t-slot-riser` ([eval/solutions/eval-02-t-slot-riser.part.ts](eval/solutions/eval-02-t-slot-riser.part.ts)): T-profile riser block sketched on `Plane.XZ`, extruded 30 mm centered along Y, with two base flange mounting holes.
3. `eval-03-stepped-flange-adapter` ([eval/solutions/eval-03-stepped-flange-adapter.part.ts](eval/solutions/eval-03-stepped-flange-adapter.part.ts)): Revolved stepped flange and hub with a concentric 12 mm through-bore around the Z axis.
4. `eval-04-slotted-clevis-block` ([eval/solutions/eval-04-slotted-clevis-block.part.ts](eval/solutions/eval-04-slotted-clevis-block.part.ts)): 36x24x32 mm clevis fork block with an upper U-slot and horizontal cross-pin hole.
5. `eval-05-hex-nut-blank` ([eval/solutions/eval-05-hex-nut-blank.part.ts](eval/solutions/eval-05-hex-nut-blank.part.ts)): Extruded regular hexagon nut blank (circumradius 14 mm, height 10 mm) with a central 12 mm bore.
