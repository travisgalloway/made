# Feature matrix

Date: 2026-10-11
Scope: macos/ (Swift 6 package, targets MadeCore and MadeApp)
Audit run: 20261011-195134

Table 1 lists 153 capabilities with their implementation status. The matrix shows 95 Shipped, 40 In progress, 12 Planned, and 6 Deprecated rows.

Cell values are done, none, or n/a. A cell reads n/a where the layer does not apply to the capability.

- UI is done where a person can reach the capability through a window control or a menu item that has an action.
- API is done where an MCP tool, JSON-RPC method, or public Swift API exposes the capability.
- Data is done where the capability has an in-memory model or cache. No persistent store exists (see Persistence note below).
- Contract is n/a on every row because the repository has no docs/contracts/ directory.
- Status is Shipped only where code is reachable through its entry point. Rows with a stub, no caller, or a stated failure are In progress. Rows with no producer code are Planned.
- Status is Deprecated where an earlier row's producer code no longer exists. The row names where the capability went.
- Issue holds the GitHub issue number that tracks the capability. A blank cell has no tracking issue.
- KERN-9 is Shipped. The conflation race (finding DSN-efe60d18) was fixed under #90.
- VIEW-1 is Shipped. Metal unavailable state handling (finding UX-661e2517) was fixed under #108.
- INPUT-8 is Shipped. Orbit, pan, and zoom navigation with mouse and trackpad was implemented under #87.
- INPUT-6, INPUT-7, and INPUT-10 are Shipped. Viewport drag snapping to vertices, edges, and ground grid was implemented under #88.
- WORKSPACE-1 is In progress. The unified multi-pane workspace layout (#118) shipped the toolbar, Navigator, viewport header, Inspector, and console drawer. Each side pane has a tab bar with one tab, and the Inspector's Properties tab is one form, and the viewport header breadcrumb is a static label.
- UI-1, UI-11, UI-12, UI-13, UI-15, and UI-18 are Deprecated. The Copilot tab and the File and Geometry menu items were removed in #124.
- AGENT-10, AGENT-11, AGENT-14, AGENT-15, and AGENT-16 are In progress with UI none. `InAppAgentController` has no host view since #124 (decision AGENT-10).

Persistence note. No capability persists a document. The .made file format is planned under #83.

Table 1. Feature matrix, macos/ scope, status as of 2026-10-11. Source: capabilities.md of audit run 20261011-195134.

| ID | Capability | UI | API | Data | Status | Issue | Contract |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VIEW-1 | A user can see the scene in a Metal MTKView (sRGB color, 32-bit depth, dark clear color) hosted in the window on macOS | done | n/a | n/a | Shipped | #108 | n/a |
| VIEW-2 | A user can see the same MTKView on iPadOS through a UIViewRepresentable with multi-touch enabled | none | n/a | n/a | In progress | #84 | n/a |
| VIEW-3 | A user gets on-demand rendering only (`isPaused = true`, `enableSetNeedsDisplay = true`), so the GPU stays idle until a redraw is requested | done | n/a | n/a | Shipped |  | n/a |
| VIEW-4 | A user sees the viewport redraw when workspace state changes (mesh update, hide or show, remove, transform edit, perspective change) through `invalidateViewport` (prior wording: `updateNSView` calls `setNeedsDisplay`; that call no longer exists) | done | n/a | n/a | Shipped |  | n/a |
| VIEW-5 | A user can trigger a tagged invalidate-and-redraw through `Coordinator.invalidate(reason:)` | done | n/a | n/a | Shipped | #94 | n/a |
| VIEW-6 | A user can read live Metal status, render count, draw calls, last invalidate reason, active tool and snap kind in the viewport status bar | done | n/a | n/a | Shipped |  | n/a |
| VIEW-7 | A user sees kernel meshes uploaded to `.storageModeShared` Metal buffers | done | n/a | done | Shipped |  | n/a |
| VIEW-8 | A user sees each frame drawn into the MTKView drawable and counted by the instrumentation | done | n/a | n/a | Shipped |  | n/a |
| VIEW-9 | A user sees every solid drawn with depth testing and back-face culling; only the translation of each mesh transform is applied (rotation and scale are ignored, including the Inspector scale fields) | done | n/a | n/a | In progress | #71 | n/a |
| VIEW-10 | A user sees the scene from a default 3/4 view (eye along (1,-1,0.6) at 150 mm, target (0,0,10)) and can return to it with Reset View or H (prior wording said no UI changes it) | done | n/a | n/a | Shipped |  | n/a |
| VIEW-11 | An agent can render an offscreen 800x600 PNG of the scene and receive it as base64; the GUI's TCP server uses the window renderer (provider set at A/WorkspaceModel.swift:69), and `--mcp-stdio` uses an offscreen renderer that tessellates the document before each capture | n/a | done | n/a | Shipped | #89 | n/a |
| VIEW-12 | A user sees solids shaded with two directional lights plus ambient (diffuse only) | done | n/a | n/a | Shipped |  | n/a |
| VIEW-13 | A user sees a right-handed Z-up view matrix with +Z as world up | done | n/a | n/a | Shipped |  | n/a |
| VIEW-14 | A user sees a perspective projection with Metal 0..1 depth range | done | n/a | n/a | Shipped |  | n/a |
| VIEW-15 | A developer can read `renderCount`, `drawCalls` and `lastReason` from `RenderInstrumentation.shared` | done | n/a | n/a | Shipped |  | n/a |
| VIEW-16 | A user gets redraws classified as camera, resize, model or interaction; `camera`, `model` and `interaction` are recorded, `resize` is never raised (no producer of `.resize`) | done | n/a | n/a | In progress | #94 | n/a |
| VIEW-17 | A user sees Blinn-Phong specular highlights on solids | none | n/a | n/a | Planned |  | n/a |
| VIEW-18 | A user sees a ground grid on Z = 0 (10 mm pitch, 300 mm extent, origin lines highlighted) | done | done | n/a | Shipped | #102 | n/a |
| VIEW-19 | A user sees a labelled XYZ axes indicator at the origin | done | done | n/a | Shipped | #103 | n/a |
| VIEW-20 | A user can zoom in, zoom out, zoom to fit the visible solids, and reset the view from the toolbar or with =, -, F and H | done | done | n/a | Shipped |  | n/a |
| VIEW-21 | A user can switch the camera to a Perspective, Top, Front, Right or Isometric preset from the View Angle menu in the toolbar | done | done | n/a | Shipped |  | n/a |
| VIEW-22 | A user sees a colored marker at the active snap point (amber vertex, cyan edge, green grid) while dragging under the Select tool | done | n/a | n/a | Shipped |  | n/a |
| VIEW-23 | A user sees an "Initializing Metal 4" progress view, and a "Metal Unavailable" message with the reason (no device, pipeline failed, device lost) when Metal 4 cannot start or the device is removed | done | n/a | n/a | Shipped |  | n/a |
| VIEW-24 | A developer can force the no-GPU path with `--force-no-gpu`, `--no-gpu`, `--disable-metal`, or `MADE_FORCE_NO_GPU` and `MADE_DISABLE_METAL` | n/a | done | n/a | Shipped |  | n/a |
| VIEW-25 | A developer can switch the renderer to an orthographic projection with `MetalRenderer.projectionMode`; no caller sets it and no UI control existss | none | done | n/a | In progress | #128 | n/a |
| VIEW-26 | A maintainer gets a failing swift test run when a Viewport file references an Agent or Scene type | n/a | n/a | n/a | Shipped | #317 | n/a |
| INPUT-1 | A user can have a gesture classified as navigate (more than one pointer) or manipulate (one pointer), locked on the first move and held until all pointers lift; `GestureArbiter` is reached only by the `.touch` path of `PointerRouter`, and the macOS view feeds only `.mouse` and `.pen` events | done | done | n/a | In progress | #87 | n/a |
| INPUT-2 | A user can lift the last pointer on a pure tap and have the mode locked at the peak pointer count | done | done | n/a | In progress | #87 | n/a |
| INPUT-3 | A user can use Apple Pencil input that always routes to manipulate and never to navigate; the macOS view reuses the `.pen` channel for non-navigating mouse drags (A/CADMetalViewRepresentable.swift:247), and no Pencil source exists | none | done | n/a | In progress | #87 | n/a |
| INPUT-4 | A user can use touch input routed through the multi-pointer arbiter | none | done | n/a | In progress | #87 | n/a |
| INPUT-5 | A user can click or drag with the mouse; movement past 6 px classifies the gesture as navigate, otherwise manipulate (doc states a 3 pt threshold in earlier text) | done | done | n/a | Shipped | #87 | n/a |
| INPUT-6 | A user can snap a point to a 10 mm XY grid with Z unchanged (doc states a 1 mm or 5 mm pitch in earlier text) | done | done | n/a | Shipped | #88, #102 | n/a |
| INPUT-7 | A user can resolve snap candidates by strict priority vertex over edge over grid inside a 20 px tolerance (doc states a 10 mm radius in earlier text) | done | done | n/a | Shipped | #88 | n/a |
| INPUT-8 | A user can orbit, pan and zoom the camera with trackpad (two-finger scroll pans, Option or Command scroll and pinch zoom), mouse (wheel zooms) or modifier and button drags; multi-touch is not wired | done | done | n/a | Shipped | #87 | n/a |
| INPUT-9 | A user can click or tap a solid in the viewport to select it (picking) | none | none | n/a | Planned | #69 | n/a |
| INPUT-10 | A user can snap to vertices and edges of existing solids while manipulating | done | done | n/a | Shipped | #88 | n/a |
| INPUT-11 | A user can two-finger tap to trigger context actions | none | none | n/a | Planned | #42 | n/a |
| INPUT-12 | A user can pick a Select, Orbit, Pan or Zoom tool from the toolbar or with V, O, P and Z, and a plain left-drag follows the tool while modifier navigation keeps working | done | done | n/a | Shipped |  | n/a |
| INPUT-13 | A user sees the viewport cursor follow the active tool (arrow, crosshair, open hand, resize) and a closed hand during a pan drag | done | n/a | n/a | Shipped |  | n/a |
| KERN-1 | A user or agent can convert a Euclid mesh into an indexed triangle `MeshPayload` in Z-up coordinates | n/a | done | done | Shipped |  | n/a |
| KERN-2 | A user can generate a parametric box mesh (X width, Y depth, Z height) | done | done | n/a | Shipped |  | n/a |
| KERN-3 | A user can generate a parametric cylinder mesh along +Z (32 slices) | done | done | n/a | Shipped |  | n/a |
| KERN-4 | An agent can subtract one solid mesh from another | none | done | n/a | In progress | #35 | n/a |
| KERN-5 | An agent can union two solid meshes | none | done | n/a | In progress | #35 | n/a |
| KERN-6 | An agent can intersect two solid meshes | none | done | n/a | In progress | #35 | n/a |
| KERN-7 | A developer can generate a box mesh with 24 vertices and flat normals by hand | n/a | done | n/a | In progress |  | n/a |
| KERN-8 | A developer can generate a cylinder mesh with side wall and caps by hand | n/a | done | n/a | In progress |  | n/a |
| KERN-9 | A user can request geometry and have requests debounced 60 ms and conflated to one pending job per solid | done | done | n/a | Shipped | #90 | n/a |
| KERN-10 | A user gets non-positive box or cylinder dimensions rejected with `invalidParams` | n/a | done | n/a | Shipped |  | n/a |
| KERN-11 | An agent can cancel a job by ID before it executes; cancelling a job that is executing in the kernel service ends the service and returns `cancelled` | n/a | done | done | In progress | #245 | n/a |
| KERN-12 | A user gets a superseded in-flight result dropped (honest cancellation); `executePending` awaits the engine, so a newer job for the same solid can start meanwhile and the older result resolves as `cancelled` | n/a | done | n/a | In progress |  | n/a |
| KERN-13 | A user or agent can dispose a solid's cached payloads, active job, and pending job | n/a | done | done | Shipped | #93 | n/a |
| KERN-14 | A developer can read dispatched, conflated, dropped and completed job counters | n/a | done | n/a | In progress |  | n/a |
| KERN-15 | A user can re-fetch a solid's cached mesh with a tessellate request | n/a | done | done | In progress |  | n/a |
| KERN-16 | A user can import a STEP file (`importStep`); the request always fails with `geometryFailed` "pending OpenCASCADE bridge" | none | none | n/a | In progress | #38 | n/a |
| KERN-17 | A caller gets typed failures (`kernel-init-failed`, `invalid-params`, `geometry-failed`, `unknown-solid`, `cancelled`, `worker-crashed`) instead of thrown errors; the kernel service produces `kernel-init-failed` (no session, breaker open) and `worker-crashed` (service stopped during the job) | n/a | done | n/a | Shipped | #245 | n/a |
| KERN-18 | A user can keep the previous valid mesh on screen when a kernel job fails | done | done | n/a | Shipped | #109 | n/a |
| KERN-20 | A user keeps the window and document when the geometry kernel crashes; the kernel runs in an XPC service, meshes return as shared memory, and the app relaunches the service and regenerates every solid from the document | done | done | done | Shipped | #245 | n/a |
| KERN-21 | A developer can evaluate a shape-description tree (box, cylinder, sphere, cone, extrude, revolve, translate, rotate, scale, boolean) in one kernel request, validated against depth, node, slice and profile limits, on the kernel actor | n/a | done | n/a | Shipped | #331, #435 | n/a |
| KERN-19 | A user can export or import STEP and IGES files, and apply B-Rep fillets, chamfers and draft angles (OCCTSwift Tier 2) | none | none | none | Planned | #82 | n/a |
| DOC-1 | A user can have scene objects of kind box, cylinder, imported (name only), boolean (operation and operand IDs), or part (`.part.ts` / `.part.js` file URL and last good `ShapeNode`) | done | done | done | Shipped | #427 | n/a |
| DOC-2 | A user gets parameter values clamped to fixed ranges when an object is added and when a parameter is set (box 5 to 90 mm, cylinder radius 5 to 50 mm, cylinder height 5 to 90 mm; NaN becomes the minimum) | done | done | done | Shipped | #104 | n/a |
| DOC-3 | A user sees UI panels update when the document changes (`@Observable` model) | done | n/a | done | Shipped |  | n/a |
| DOC-4 | A user starts with a default scene of `box-1` (40x30x20 mm) and `cylinder-1` (radius 15, height 40 mm) | done | n/a | done | Shipped |  | n/a |
| DOC-5 | An agent can add a box, cylinder or imported object and get an ID of the form `<kind>-<seq>` (first new ID is `-2`); a boolean result gets `boolean-<seq>` from the same sequence, and an ID is never reused after removal | none | done | done | Shipped |  | n/a |
| DOC-6 | An agent can remove an object by ID; removal through the Navigator or `cad_remove_solid` frees the kernel cache; renderer mesh pruning is tracked in #73 | none | done | done | In progress | #93, #73 | n/a |
| DOC-7 | A user or agent can set a named parameter on a box or cylinder (unknown keys and imported objects are ignored silently) | done | done | done | Shipped |  | n/a |
| DOC-8 | An agent can set an object's world position; the Inspector also writes scale; `rotation` has no writer and the renderer applies only translation | none | done | done | In progress | #71 | n/a |
| DOC-9 | A user can give objects a name and a visibility flag | done | done | done | Shipped |  | n/a |
| DOC-10 | A user can hold a multi-object selection in the document (`selection: Set<ObjectId>`) | none | none | none | Planned | #69 | n/a |
| DOC-11 | An agent can create CSG composite objects that reference their parent operations | none | none | none | Planned | #35 | n/a |
| DOC-12 | A user can load imported B-Rep solids from STEP or IGES into the scene | none | none | none | Planned | #38, #82 | n/a |
| DOC-13 | A user can lock or unlock an object (`isLocked` flag); nothing reads the flag, so a locked object can still be edited, moved and removed | done | done | done | In progress | #127 | n/a |
| DOC-14 | A user sees each object drawn in its material color (`MaterialAttributes.color`, default light blue); `setMaterial` has no caller, so the color cannot change | none | done | done | In progress | #137 | n/a |
| DOC-15 | An agent tool call changes the document on the main actor, so it cannot race a SwiftUI read of the same document; the stdio and TCP transports both hop through the `@MainActor` registry | none | done | done | Shipped | #91 | n/a |
| UI-1 | A user can switch the sidebar between Inspector and AI Copilot with a segmented picker | none | n/a | n/a | Deprecated |  | n/a |
| UI-2 | A user can choose the selected solid by clicking a row in the Navigator's Scene list (was a menu picker "Active Solid"; moved) | done | n/a | n/a | Shipped | #34 | n/a |
| UI-3 | A user can set box width (X) from the inspector numeric field or 1-mm stepper | done | n/a | n/a | Shipped | #106, #446 | n/a |
| UI-4 | A user can set box depth (Y) from the inspector numeric field or stepper | done | n/a | n/a | Shipped | #106, #446 | n/a |
| UI-5 | A user can set box height (Z) from the inspector numeric field or stepper | done | n/a | n/a | Shipped | #106, #446 | n/a |
| UI-6 | A user can set cylinder radius from the inspector numeric field or stepper | done | n/a | n/a | Shipped | #106, #446 | n/a |
| UI-7 | A user can set cylinder height (Z) from the inspector numeric field or stepper | done | n/a | n/a | Shipped | #106, #446 | n/a |
| UI-8 | A user can see an imported solid's name in the inspector (read-only) | done | n/a | n/a | Shipped |  | n/a |
| UI-9 | A user sees the changed solid re-tessellated and redrawn after a dimension change, using the solid's current transform, color and visibility; a solid removed during the recompute stays removed (solids at zero position are drawn at x = -25 for `box-1` and +25 otherwise) | done | n/a | n/a | Shipped | #92, #94 | n/a |
| UI-10 | A user sees the initial two-solid scene generated at launch | done | n/a | n/a | Shipped |  | n/a |
| UI-11 | A user can type a prompt in the Copilot field and send it with Return or the send button (disabled when empty) | none | n/a | n/a | Deprecated | #105, #107 | n/a |
| UI-12 | A user can read the Copilot transcript with user bubbles, assistant bubbles, a tool badge and auto-scroll | none | n/a | n/a | Deprecated |  | n/a |
| UI-13 | A user sees all solids re-tessellated after a Copilot prompt completes | none | n/a | n/a | Deprecated | #107 | n/a |
| UI-14 | A user can open one window with a unified toolbar (title hidden, default 1440x900, label "Untitled Project"); the "made - Native CAD" title no longer exists | done | n/a | n/a | Shipped |  | n/a |
| UI-15 | A user can choose File > New CAD Document (Cmd+N) | none | n/a | n/a | Deprecated | #83 | n/a |
| UI-16 | A user can add a box from the GUI (was Geometry > Add Box with an empty action; moved to Navigator Add > Box Solid, fixed 30x30x30 mm) | done | n/a | n/a | Shipped | #73 | n/a |
| UI-17 | A user can add a cylinder from the GUI (was Geometry > Add Cylinder; moved to Navigator Add > Cylinder Solid, radius 12, height 35 mm) | done | n/a | n/a | Shipped | #73 | n/a |
| UI-18 | A user can choose Geometry > Import STEP File... (Cmd+Shift+I) | none | n/a | n/a | Deprecated | #38 | n/a |
| UI-19 | A user can type exact dimension values in the inspector (numeric fields with a 1-mm stepper, clamped to `DocumentLimits`) | done | n/a | n/a | Shipped | #446 | n/a |
| UI-20 | A user can edit an object's X, Y and Z position in the inspector | done | n/a | n/a | Shipped | #70 | n/a |
| UI-21 | A user sees an inline warning next to a parameter the kernel rejected | done | n/a | done | Shipped | #109 | n/a |
| UI-22 | A user can remove a solid from the GUI | done | n/a | n/a | Shipped | #73 | n/a |
| UI-23 | A user can run the app on iPadOS 17 | none | n/a | n/a | Planned | #84 | n/a |
| UI-24 | A user can show or hide the Navigator, Console and Inspector panes from toolbar toggle buttons | done | n/a | n/a | Shipped |  | n/a |
| UI-25 | A user can toggle the sidebar and the inspector from the standard View menu commands | done | n/a | n/a | Shipped |  | n/a |
| UI-26 | A user can filter the Navigator's Scene list by object name or ID, with an empty-result message | done | n/a | n/a | Shipped |  | n/a |
| UI-27 | A user can hide or show an object from the Navigator eye button or the context menu, and the viewport and snapping skip hidden objects | done | n/a | n/a | Shipped |  | n/a |
| UI-28 | A user can lock or unlock an object from the Navigator lock button or context menu; the flag is stored and shown only (see DOC-13) | done | n/a | n/a | In progress |  | n/a |
| UI-29 | A user can rename an object in the Inspector Identity section and read its ID and kind | done | n/a | n/a | Shipped |  | n/a |
| UI-30 | A user can edit an object's X, Y and Z scale in the inspector (floor 0.01); the value is stored but the renderer ignores scale (see VIEW-9) | done | n/a | n/a | In progress | #136 | n/a |
| UI-31 | A user can read a timestamped, level-colored console log (INFO, KERNEL, SNAP, AGENT, ERROR) with auto-scroll in the resizable console pane (⇧⌘Y or the status-bar button); entries also go to the unified log | done | n/a | n/a | Shipped |  | n/a |
| UI-32 | A user can filter console entries by message, subsystem or level | done | n/a | n/a | Shipped |  | n/a |
| UI-33 | A user can clear the console log | done | n/a | n/a | Shipped |  | n/a |
| UI-34 | A user can open or close the Model Context Protocol window from a toolbar button that turns green while the server runs | done | n/a | n/a | Shipped |  | n/a |
| UI-35 | A user can start or stop the in-app MCP server from the MCP popover switch and read its address (127.0.0.1:9820) | done | n/a | n/a | Shipped |  | n/a |
| UI-36 | A user can copy a Claude Desktop config snippet from the MCP popover; the snippet launches `swift run ... --mcp-stdio`, which drives a separate document, not the window's session, and uses the process working directory | done | n/a | n/a | In progress |  | n/a |
| UI-37 | A user can read the registered CAD tool names and the TCP address in the MCP popover | done | n/a | n/a | Shipped |  | n/a |
| UI-38 | A user can open an Open Source Licenses window from the app menu or the Help menu and read the `made` MPL-2.0 text, each bundled library or helper's name, version, copyright and exact license text from bundled resource files, and links to the source repository and build-from-source guide | done | done | done | Shipped | #425 | n/a |
| AGENT-1 | An agent can start an MCP server on standard input and output with a fresh document and kernel and an offscreen snapshot renderer (none without a Metal 4 device); the SwiftUI window scene is still declared and `exit(0)` runs at end of input | none | done | n/a | In progress |  | n/a |
| AGENT-2 | An agent can list every object with ID, kind, position and parameters | n/a | done | done | Shipped |  | n/a |
| AGENT-3 | An agent can add a box or cylinder with dimensions (clamped) and position; a wrong-typed or non-finite argument or an out-of-bound position returns an error; the solid is registered with the kernel and drawn in the viewport when a mesh sink is attached | n/a | done | done | Shipped | #132 | n/a |
| AGENT-4 | An agent can set one parameter (`width`, `depth`, `height`, `radius`) on a solid; an invalid name for the solid kind, an imported solid, an unknown ID, or a non-finite value returns an error, and the success message reports the clamped value; the solid is recomputed and redrawn in the viewport when a mesh sink is attached (doc names the argument `name`, code uses `param`) | n/a | done | done | Shipped | #97, #132 | n/a |
| AGENT-5 | An agent can move a solid by `posX`, `posY`, `posZ`; a wrong-typed or non-finite argument or an out-of-bound position returns an error; the GUI mesh transform is updated and the viewport is invalidated | n/a | done | done | Shipped | #132 | n/a |
| AGENT-6 | An agent can delete a solid by ID; the GUI drops the mesh and releases the kernel cache | n/a | done | done | Shipped |  | n/a |
| AGENT-7 | An agent can measure a box or cylinder for bounds, volume and surface area from its parameters (imported solids return the name only) | n/a | done | n/a | Shipped |  | n/a |
| AGENT-8 | An agent can run subtract, union or intersect between two solids (arguments `solidA`, `solidB`, `operation`); an operand missing from the document or identical operands return an error before the kernel is called; pending recomputes for the operands are settled before the kernel boolean runs, and the result is recorded as a `boolean` object (operation and operand IDs) under the ID the reply reports, which is also the kernel's ID and which `cad_measure`, `cad_set_transform`, `cad_remove_solid` and `cad_get_scene` accept, and is installed as a mesh in the viewport | n/a | done | done | Shipped | #132 | n/a |
| AGENT-9 | An agent can capture a viewport PNG as MCP image content, optionally from a named camera preset (`front`, `top`, `right`, `isometric`, `perspective`) without mutating the interactive viewport camera; works in the GUI through the TCP server and over `--mcp-stdio`, where `HeadlessSnapshotProvider` tessellates the document into an offscreen renderer before each capture; without a Metal 4 device or with an invalid view name the tool returns an `isError` result | none | done | n/a | Shipped | #89, #428 | n/a |
| AGENT-10 | A user can ask the Copilot to measure `box-1` or `cylinder-1` (keywords "measure", "volume", "dimensions of"); the controller has no caller since #124 | none | n/a | n/a | In progress |  | n/a |
| AGENT-11 | A user can ask the Copilot to add a box, with up to three numbers for width, depth and height, at a random XY position | none | n/a | n/a | In progress |  | n/a |
| AGENT-12 | A user can ask the Copilot to subtract `cylinder-1` from `box-1` (keywords "subtract", "cut", "drill"); ids are fixed and the result is not drawn | done | n/a | n/a | In progress | #35 | n/a |
| AGENT-13 | A user can ask the Copilot to union `box-1` and `cylinder-1` (keywords "union", "combine", "fuse"); ids are fixed and the result is not drawn | done | n/a | n/a | In progress | #35 | n/a |
| AGENT-14 | A user can ask the Copilot to add a cylinder, with radius and height numbers, at a random XY position | none | n/a | n/a | In progress |  | n/a |
| AGENT-15 | A user can ask the Copilot to set width, depth, height or radius on `box-1` or `cylinder-1` (keywords "width", "wide", "depth", "height", "tall", "radius") | none | n/a | n/a | In progress |  | n/a |
| AGENT-16 | A user can ask the Copilot to show the scene (keywords "scene", "list", "show", "what") | none | n/a | n/a | In progress |  | n/a |
| AGENT-17 | An agent can receive standard JSON-RPC error payloads. -32700 for text that is not JSON, -32600 for JSON that is not a valid request, -32601 for an unknown method, -32602 for `tools/call` without a name, -32603 when a result cannot be encoded. Every response carries `id`, null when unknown | n/a | done | n/a | Shipped | #95 | n/a |
| AGENT-18 | An agent can parse one JSON-RPC message string and get a response string (`processMessage`). Non-JSON text returns -32700 with a null id. Valid JSON that is not a request object returns -32600, echoing the id when it is a string or an integer | n/a | done | n/a | Shipped | #95 | n/a |
| AGENT-19 | An agent can call `initialize` and receive protocol 2024-11-05, server `made-native-cad` 0.1.0 and the tools capability | n/a | done | n/a | Shipped |  | n/a |
| AGENT-20 | An agent can discover the 11 tool schemas (`cad_get_scene`, `cad_add_solid`, `cad_set_param`, `cad_set_transform`, `cad_remove_solid`, `cad_measure`, `cad_boolean_operation`, `cad_reload`, `cad_get_diagnostics`, `cad_verify`, `cad_capture_snapshot`) | n/a | done | n/a | Shipped | #428 | n/a |
| AGENT-21 | An agent can invoke any registered tool by name with arguments (missing name gives `-32602`; unknown tool gives an `isError` result) | n/a | done | n/a | Shipped |  | n/a |
| AGENT-22 | An agent can send a notification such as `notifications/initialized` and receives no response line | n/a | done | n/a | Shipped | #96 | n/a |
| AGENT-23 | An agent can send an unknown method and receive `-32601` | n/a | done | n/a | Shipped |  | n/a |
| AGENT-24 | An agent can drive the server over newline-delimited JSON on stdin and stdout, or over the TCP socket. Both transports buffer input in `MCPLineFramer` until a newline completes a message, so a message up to 16 MiB may span reads. A line that is not UTF-8 gets -32700. A longer line gets -32700, and over TCP the connection then closes | n/a | done | n/a | Shipped | #101 | n/a |
| AGENT-25 | An agent can drive the CAD session in the running GUI window from an external MCP client: the GUI registry shares the window's document, kernel and renderer, so adds, parameter edits, transform moves, boolean operations and removals update the Navigator, Inspector and viewport on `@MainActor` | done | done | n/a | Shipped | #132 | n/a |
| AGENT-26 | A user can give the Copilot free-form natural language (for example "Make a 50x50 plate and subtract a 10mm hole in the center") | none | n/a | n/a | Planned |  | n/a |
| AGENT-27 | An agent receives `-32603` for a failed geometry operation | n/a | none | n/a | Planned |  | n/a |
| AGENT-28 | An agent can connect over an IPC transport as well as stdio: a local TCP listener (`NWListener(using: .tcp, on: 9820)`) exists; it sets no loopback restriction although the MCP popover states 127.0.0.1, and it has no authentication | n/a | done | n/a | In progress |  | n/a |
| AGENT-29 | An agent can re-evaluate a part file now (or open and evaluate a part file path, or reload all open parts) over MCP with `cad_reload` and receive structured evaluation metadata on success or an `isError` result with `file`, `line`, `column`, and `message` diagnostics on failure | n/a | done | done | Shipped | #428 | n/a |
| AGENT-30 | An agent can inspect the last evaluation errors and warnings for open part files over MCP with `cad_get_diagnostics`, each with `file`, `line`, `column`, and `message` | n/a | done | done | Shipped | #428 | n/a |
| AGENT-31 | An agent can verify solids over MCP with `cad_verify`, checking that each solid's mesh is `closed`, `manifold`, and `positiveVolume`, and comparing measured `volume`, `area`, and `bounds` against an `export const expected` block within tolerance (`isError: true` with measured and expected values on failure) | n/a | done | done | Shipped | #428 | n/a |
| AGENT-32 | An external agent can install the `made-cad` Claude Code plugin skill (`SKILL.md`, `references/made.d.ts`, gallery `examples/*.part.ts`, and `eval/` benchmark set) to author `.part.ts` files with an `export const expected` block and run the edit, `cad_reload`, `cad_get_diagnostics`, `cad_verify`, and `cad_capture_snapshot` repair loop over MCP on `127.0.0.1:9820` or `--mcp-stdio` | n/a | done | done | Shipped | #429 | n/a |
| DSL-1 | A developer can define any shape through the `CADShape` protocol (`shapeDescription`) | n/a | done | n/a | Shipped | #331 | n/a |
| DSL-2 | A developer can wrap a shape description as `CSGCompositeShape` | n/a | done | n/a | Shipped | #331 | n/a |
| DSL-3 | A developer can create `Box(width:depth:height:)` or `Box(x:y:z:)` with an `offset` | n/a | done | n/a | Shipped |  | n/a |
| DSL-4 | A developer can create `Cylinder(radius:height:slices:)` or `Cylinder(diameter:height:slices:)` with an `offset` | n/a | done | n/a | Shipped |  | n/a |
| DSL-5 | A developer can translate a shape with `.translated(x:y:z:)` | n/a | done | n/a | Shipped |  | n/a |
| DSL-6 | A developer can subtract with `.subtracting(_:)` or the builder-closure form | n/a | done | n/a | Shipped |  | n/a |
| DSL-7 | A developer can union with `.union(_:)` or the builder-closure form | n/a | done | n/a | Shipped |  | n/a |
| DSL-8 | A developer can intersect with `.intersecting(_:)` | n/a | done | n/a | Shipped |  | n/a |
| DSL-9 | A developer can evaluate a shape through `KernelClient` with `.evaluate(on:solidId:)` | n/a | done | n/a | Shipped | #331 | n/a |
| DSL-10 | A developer can compose shapes with the operators `-`, `+` and `&` | n/a | done | n/a | Shipped |  | n/a |
| DSL-11 | A developer can use `@CADShapeBuilder` to group shapes; only a single-shape `buildBlock` exists, so multi-statement hierarchies do not compile | n/a | done | n/a | In progress |  | n/a |
| DSL-12 | An agent can author a DSL model and see it in the viewport or the document | done | done | done | Shipped | #85, #427 | n/a |
| DSL-13 | A developer or user can evaluate a `.part.ts` or `.part.js` script in a restricted JavaScriptCore runtime on a background thread (`PartRuntime`), with TypeScript type stripping, relative ES module imports inside the part directory, the `made` CAD API (primitives, 2D sketches on planes, extrude, revolve, booleans, transforms, named parameters, and optional `expected` block), source-mapped file/line/column diagnostics, `JobId` cancellation, and bundled `made.d.ts` type definitions | done | done | done | Shipped | #435, #427 | n/a |
| DSL-14 | A user or agent can open a `.part.ts` or `.part.js` part source file in the window and have edits on disk (including relative helper modules) coalesced with a 60-ms debounce, re-evaluated off the main thread through `PartRuntime` and `KernelClient`, and redrawn once in the viewport on success while keeping the last good model on screen and reporting `file:line:column` diagnostics in the console and Inspector on failure | done | done | done | Shipped | #427 | n/a |
| WORKSPACE-1 | A user can work in one unified multi-pane window: a `NavigationSplitView` with Navigator sidebar, viewport detail with a header bar and status bar, trailing Inspector, and a resizable bottom console. The matrix prose also names a "multi-tab inspector" and a "3D viewport jump bar"; the Navigator and Inspector each have a tab bar with one tab (Scene, Properties), and the Properties tab is one Form with three sections and the header breadcrumb "Scene > name" is a static label | done | n/a | n/a | In progress | #118 | n/a |

Findings that map to no capability row: None.
