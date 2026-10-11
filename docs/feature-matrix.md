# Feature matrix

Date: 2026-10-10
Scope: macos/ (Swift 6 package, targets MadeCore and MadeApp)
Audit run: 20261010-114045

Table 1 lists 122 capabilities with their implementation status. The matrix shows 62 Shipped, 40 In progress, and 20 Planned rows. No row is Deprecated.

Cell values are done, none, or n/a. A cell reads n/a where the layer does not apply to the capability.

- UI is done where a person can reach the capability through a window control or a menu item that has an action.
- API is done where an MCP tool, JSON-RPC method, or public Swift API exposes the capability.
- Data is done where the capability has an in-memory model or cache. No persistent store exists (see Persistence note below).
- Contract is n/a on every row because the repository has no docs/contracts/ directory.
- Status is Shipped only where code is reachable through its entry point. Rows with a stub, no caller, or a stated failure are In progress. Rows with no producer code are Planned.
- KERN-9 is Shipped. The conflation race (finding DSN-efe60d18) was fixed under #90.
- VIEW-1 is Shipped. Metal unavailable state handling (finding UX-661e2517) was fixed under #108.
- Issue holds the GitHub issue number that tracks the capability.

Persistence note. No capability persists a document. The .made file format is planned under #83.

Table 1. Feature matrix, macos/ scope, status as of 2026-10-10. Source: capabilities.md of audit run 20261010-114045.

| ID | Capability | UI | API | Data | Status | Issue | Contract |
| --- | --- | --- | --- | --- | --- | --- | --- |
| VIEW-1 | A user can see the scene in a Metal MTKView (sRGB color, 32-bit depth, dark clear color) hosted in the window on macOS | done | n/a | n/a | Shipped | #108 | n/a |
| VIEW-2 | A user can see the same MTKView on iPadOS through a UIViewRepresentable with multi-touch enabled | none | n/a | n/a | In progress | #84 | n/a |
| VIEW-3 | A user gets on-demand rendering only (`isPaused = true`, `enableSetNeedsDisplay = true`), so the GPU stays idle until a redraw is requested | done | n/a | n/a | Shipped | none | n/a |
| VIEW-4 | A user sees the viewport redraw when SwiftUI state changes (`updateNSView` calls `setNeedsDisplay`) | done | n/a | n/a | Shipped | none | n/a |
| VIEW-5 | A user can trigger a tagged invalidate-and-redraw through `Coordinator.invalidate(reason:)` | none | n/a | n/a | In progress | #94 | n/a |
| VIEW-6 | A user can read live Metal status, render count, draw calls and last invalidate reason in the viewport HUD | done | n/a | n/a | In progress | none | n/a |
| VIEW-7 | A user sees kernel meshes uploaded to `.storageModeShared` Metal buffers | done | n/a | done | Shipped | none | n/a |
| VIEW-8 | A user sees each frame drawn into the MTKView drawable and counted by the instrumentation | done | n/a | n/a | Shipped | none | n/a |
| VIEW-9 | A user sees every solid drawn with depth testing and back-face culling; only the translation of each mesh transform is applied (rotation and scale are ignored) | done | n/a | n/a | In progress | #71 | n/a |
| VIEW-10 | A user sees the scene from a default 3/4 view (eye along (1,-1,0.6) at 150 mm, target (0,0,10)); no UI changes it | done | n/a | n/a | Shipped | none | n/a |
| VIEW-11 | An agent can render an offscreen 800x600 PNG of the scene and receive it as base64 | n/a | done | n/a | In progress | #89 | n/a |
| VIEW-12 | A user sees solids shaded with two directional lights plus ambient (diffuse only) | done | n/a | n/a | Shipped | none | n/a |
| VIEW-13 | A user sees a right-handed Z-up view matrix with +Z as world up | done | n/a | n/a | Shipped | none | n/a |
| VIEW-14 | A user sees a perspective projection with Metal 0..1 depth range | done | n/a | n/a | Shipped | none | n/a |
| VIEW-15 | A developer can read `renderCount`, `drawCalls` and `lastReason` from `RenderInstrumentation.shared` | done | n/a | n/a | Shipped | none | n/a |
| VIEW-16 | A user gets redraws classified as camera, resize, model or interaction; only `model` is ever recorded (A/ContentView.swift:304) | none | n/a | n/a | In progress | #94 | n/a |
| VIEW-17 | A user sees Blinn-Phong specular highlights on solids | none | n/a | n/a | Planned | none | n/a |
| INPUT-1 | A user can have a gesture classified as navigate (more than one pointer) or manipulate (one pointer), locked on the first move and held until all pointers lift | none | done | n/a | In progress | #87 | n/a |
| INPUT-2 | A user can lift the last pointer on a pure tap and have the mode locked at the peak pointer count | none | done | n/a | In progress | #87 | n/a |
| INPUT-3 | A user can use Apple Pencil input that always routes to manipulate and never to navigate | none | done | n/a | In progress | #87 | n/a |
| INPUT-4 | A user can use touch input routed through the multi-pointer arbiter | none | done | n/a | In progress | #87 | n/a |
| INPUT-5 | A user can click or drag with the mouse; movement past 6 px classifies the gesture as navigate, otherwise manipulate (doc states a 3 pt threshold) | none | done | n/a | In progress | #87 | n/a |
| INPUT-6 | A user can snap a point to a 10 mm XY grid with Z unchanged (doc states a 1 mm or 5 mm pitch) | none | done | n/a | In progress | #88, #102 | n/a |
| INPUT-7 | A user can resolve snap candidates by strict priority vertex over edge over grid inside a 20 px tolerance (doc states a 10 mm radius) | none | done | n/a | In progress | #88 | n/a |
| INPUT-8 | A user can orbit, pan and zoom the camera with trackpad, mouse or multi-touch | none | none | n/a | Planned | #87 | n/a |
| INPUT-9 | A user can click or tap a solid in the viewport to select it (picking) | none | none | n/a | Planned | #69 | n/a |
| INPUT-10 | A user can snap to vertices and edges of existing solids while manipulating | none | none | n/a | Planned | #88 | n/a |
| INPUT-11 | A user can two-finger tap to trigger context actions | none | none | n/a | Planned | #42 | n/a |
| KERN-1 | A user or agent can convert a Euclid mesh into an indexed triangle `MeshPayload` in Z-up coordinates | n/a | done | done | Shipped | none | n/a |
| KERN-2 | A user can generate a parametric box mesh (X width, Y depth, Z height) | done | done | n/a | Shipped | none | n/a |
| KERN-3 | A user can generate a parametric cylinder mesh along +Z (32 slices) | done | done | n/a | Shipped | none | n/a |
| KERN-4 | An agent can subtract one solid mesh from another | none | done | n/a | In progress | #35 | n/a |
| KERN-5 | An agent can union two solid meshes | none | done | n/a | In progress | #35 | n/a |
| KERN-6 | An agent can intersect two solid meshes | none | done | n/a | In progress | #35 | n/a |
| KERN-7 | A developer can generate a box mesh with 24 vertices and flat normals by hand | n/a | done | n/a | In progress | none | n/a |
| KERN-8 | A developer can generate a cylinder mesh with side wall and caps by hand | n/a | done | n/a | In progress | none | n/a |
| KERN-9 | A user can request geometry and have requests debounced 60 ms and conflated to one pending job per solid | done | done | n/a | Shipped | #90 | n/a |
| KERN-10 | A user gets non-positive box or cylinder dimensions rejected with `invalidParams` | n/a | done | n/a | Shipped | none | n/a |
| KERN-11 | An agent can cancel a job by ID before it executes | n/a | done | n/a | In progress | none | n/a |
| KERN-12 | A user gets a superseded in-flight result dropped (honest cancellation); the check at :162 compares an ID set synchronously at :97, so only the conflation path at :58 takes effect | n/a | done | n/a | In progress | none | n/a |
| KERN-13 | An agent can dispose a solid's cached payload and pending job | n/a | done | done | In progress | #93 | n/a |
| KERN-14 | A developer can read dispatched, conflated, dropped and completed job counters | n/a | done | n/a | In progress | none | n/a |
| KERN-15 | A user can re-fetch a solid's cached mesh with a tessellate request | n/a | done | done | In progress | none | n/a |
| KERN-16 | A user can import a STEP file (`importStep`); the request always fails with `geometryFailed` "pending OpenCASCADE bridge" | none | none | n/a | In progress | #38 | n/a |
| KERN-17 | A caller gets typed failures (`kernel-init-failed`, `invalid-params`, `geometry-failed`, `unknown-solid`, `cancelled`, `worker-crashed`) instead of thrown errors | n/a | done | n/a | Shipped | none | n/a |
| KERN-18 | A user can keep the previous valid mesh on screen when a kernel job fails | done | done | n/a | Shipped | #109 | n/a |
| KERN-19 | A user can export or import STEP and IGES files, and apply B-Rep fillets, chamfers and draft angles (OCCTSwift Tier 2) | none | none | none | Planned | #82 | n/a |
| DOC-1 | A user can have scene objects of kind box, cylinder or imported (name only) | done | done | done | Shipped | none | n/a |
| DOC-2 | A user gets parameter values clamped to fixed ranges (box 5 to 90 mm, cylinder radius 5 to 50 mm, cylinder height 5 to 90 mm; NaN becomes the minimum); doc states 0.001 to 10,000 mm | done | done | done | Shipped | #104 | n/a |
| DOC-3 | A user sees UI panels update when the document changes (`@Observable` model) | done | n/a | done | Shipped | none | n/a |
| DOC-4 | A user starts with a default scene of `box-1` (40x30x20 mm) and `cylinder-1` (radius 15, height 40 mm) | done | n/a | done | Shipped | none | n/a |
| DOC-5 | An agent can add a box, cylinder or imported object and get an ID of the form `<kind>-<seq>` (first new ID is `-2`) | none | done | done | Shipped | #91 | n/a |
| DOC-6 | An agent can remove an object by ID | none | done | done | In progress | #91, #93, #73 | n/a |
| DOC-7 | A user or agent can set a named parameter on a box or cylinder (unknown keys and imported objects are ignored silently) | done | done | done | Shipped | #91 | n/a |
| DOC-8 | An agent can set an object's world position (the `rotation` and `scale` fields exist but nothing writes them) | none | done | done | In progress | #91, #71 | n/a |
| DOC-9 | A user can give objects a name and a visibility flag | none | none | none | Planned | none | n/a |
| DOC-10 | A user can hold a multi-object selection in the document (`selection: Set<ObjectId>`) | none | none | none | Planned | #69 | n/a |
| DOC-11 | An agent can create CSG composite objects that reference their parent operations | none | none | none | Planned | #35 | n/a |
| DOC-12 | A user can load imported B-Rep solids from STEP or IGES into the scene | none | none | none | Planned | #38, #82 | n/a |
| UI-1 | A user can switch the sidebar between Inspector and AI Copilot with a segmented picker | done | n/a | n/a | Shipped | none | n/a |
| UI-2 | A user can choose the active solid from a menu picker listing all objects | done | n/a | n/a | Shipped | #34 | n/a |
| UI-3 | A user can set box width (X) from the inspector slider with a live mm readout | done | n/a | n/a | Shipped | #106 | n/a |
| UI-4 | A user can set box depth (Y) from the inspector slider | done | n/a | n/a | Shipped | #106 | n/a |
| UI-5 | A user can set box height (Z) from the inspector slider | done | n/a | n/a | Shipped | #106 | n/a |
| UI-6 | A user can set cylinder radius from the inspector slider | done | n/a | n/a | Shipped | #106 | n/a |
| UI-7 | A user can set cylinder height (Z) from the inspector slider | done | n/a | n/a | Shipped | #106 | n/a |
| UI-8 | A user can see an imported solid's name in the inspector (read-only) | done | n/a | n/a | Shipped | none | n/a |
| UI-9 | A user sees the changed solid re-tessellated and redrawn after a slider change (solids at zero position are drawn at x = -25 for `box-1` and +25 otherwise) | done | n/a | n/a | Shipped | #92, #94 | n/a |
| UI-10 | A user sees the initial two-solid scene generated at launch | done | n/a | n/a | Shipped | none | n/a |
| UI-11 | A user can type a prompt in the Copilot field and send it with Return or the send button (disabled when empty) | done | n/a | n/a | Shipped | #105, #107 | n/a |
| UI-12 | A user can read the Copilot transcript with user bubbles, assistant bubbles, a tool badge and auto-scroll | done | n/a | n/a | Shipped | none | n/a |
| UI-13 | A user sees all solids re-tessellated after a Copilot prompt completes | done | n/a | n/a | Shipped | #107 | n/a |
| UI-14 | A user can open one window titled "made - Native CAD" with a unified title bar | done | n/a | n/a | Shipped | none | n/a |
| UI-15 | A user can choose File > New CAD Document (Cmd+N); the action body is empty | none | n/a | n/a | In progress | #83 | n/a |
| UI-16 | A user can choose Geometry > Add Box; the action body is empty | none | n/a | n/a | In progress | #73 | n/a |
| UI-17 | A user can choose Geometry > Add Cylinder; the action body is empty | none | n/a | n/a | In progress | #73 | n/a |
| UI-18 | A user can choose Geometry > Import STEP File... (Cmd+Shift+I); the action body is empty | none | n/a | n/a | In progress | #38 | n/a |
| UI-19 | A user can type exact dimension values in the inspector (numeric fields) | none | n/a | n/a | Planned | #70 | n/a |
| UI-20 | A user can edit an object's X, Y and Z position in the inspector | none | n/a | n/a | Planned | #70 | n/a |
| UI-21 | A user sees an inline warning next to a parameter the kernel rejected | none | n/a | n/a | Planned | #109 | n/a |
| UI-22 | A user can remove a solid from the GUI | none | n/a | n/a | Planned | #73 | n/a |
| UI-23 | A user can run the app on iPadOS 17 | none | n/a | n/a | Planned | #84 | n/a |
| AGENT-1 | An agent can start an MCP server on standard input and output with a fresh document and kernel and no snapshot provider; the SwiftUI window scene is still declared and `exit(0)` runs at end of input | none | done | n/a | In progress | none | n/a |
| AGENT-2 | An agent can list every object with ID, kind, position and parameters | n/a | done | done | Shipped | none | n/a |
| AGENT-3 | An agent can add a box or cylinder with dimensions (clamped) and position; the object is not tessellated in headless mode | n/a | done | done | Shipped | #91, #98 | n/a |
| AGENT-4 | An agent can set one parameter (`width`, `depth`, `height`, `radius`) on a solid; an unknown name reports success and changes nothing (doc names the argument `name`, code uses `param`) | n/a | done | done | Shipped | #91, #97 | n/a |
| AGENT-5 | An agent can move a solid by `posX`, `posY`, `posZ`; the tool description also promises scale, which is not implemented | n/a | done | done | In progress | #91, #98 | n/a |
| AGENT-6 | An agent can delete a solid by ID | n/a | done | done | Shipped | #91 | n/a |
| AGENT-7 | An agent can measure a box or cylinder for bounds, volume and surface area from its parameters (imported solids return the name only) | n/a | done | n/a | Shipped | none | n/a |
| AGENT-8 | An agent can run subtract, union or intersect between two solids (arguments `solidA`, `solidB`, `operation`; doc names `targetId` and `op`); the kernel fails with `unknown-solid` unless both solids were tessellated earlier in the same `KernelClient`, and the result is recorded as `.imported(name:)` under a different ID than the kernel's `csg-` ID, so it is never drawn | n/a | done | n/a | In progress | #99, #100 | n/a |
| AGENT-9 | An agent can capture a viewport PNG as MCP image content; the stdio server registry has no snapshot provider, so the call returns an error | none | done | n/a | In progress | #89 | n/a |
| AGENT-10 | A user can ask the Copilot to measure `box-1` or `cylinder-1` (keywords "measure", "volume", "dimensions of") | done | n/a | n/a | Shipped | none | n/a |
| AGENT-11 | A user can ask the Copilot to add a box, with up to three numbers for width, depth and height, at a random XY position | done | n/a | n/a | Shipped | none | n/a |
| AGENT-12 | A user can ask the Copilot to subtract `cylinder-1` from `box-1` (keywords "subtract", "cut", "drill"); ids are fixed and the result is not drawn | done | n/a | n/a | In progress | #35 | n/a |
| AGENT-13 | A user can ask the Copilot to union `box-1` and `cylinder-1` (keywords "union", "combine", "fuse"); ids are fixed and the result is not drawn | done | n/a | n/a | In progress | #35 | n/a |
| AGENT-14 | A user can ask the Copilot to add a cylinder, with radius and height numbers, at a random XY position | done | n/a | n/a | Shipped | none | n/a |
| AGENT-15 | A user can ask the Copilot to set width, depth, height or radius on `box-1` or `cylinder-1` (keywords "width", "wide", "depth", "height", "tall", "radius") | done | n/a | n/a | Shipped | none | n/a |
| AGENT-16 | A user can ask the Copilot to show the scene (keywords "scene", "list", "show", "what") | done | n/a | n/a | Shipped | none | n/a |
| AGENT-17 | An agent can receive standard JSON-RPC error payloads (-32700, -32600, -32601, -32602, -32603) | n/a | done | n/a | Shipped | #95 | n/a |
| AGENT-18 | An agent can parse one JSON-RPC message string and get a response string (`processMessage`) | n/a | done | n/a | Shipped | #95 | n/a |
| AGENT-19 | An agent can call `initialize` and receive protocol 2024-11-05, server `made-native-cad` 0.1.0 and the tools capability | n/a | done | n/a | Shipped | none | n/a |
| AGENT-20 | An agent can discover the 8 tool schemas | n/a | done | n/a | Shipped | none | n/a |
| AGENT-21 | An agent can invoke any registered tool by name with arguments (missing name gives `-32602`; unknown tool gives an `isError` result) | n/a | done | n/a | Shipped | none | n/a |
| AGENT-22 | An agent can send `notifications/initialized`; the server answers with a response line although a notification expects none | n/a | done | n/a | In progress | #96 | n/a |
| AGENT-23 | An agent can send an unknown method and receive `-32601` | n/a | done | n/a | Shipped | none | n/a |
| AGENT-24 | An agent can drive the server over newline-delimited JSON on stdin and stdout (reads in 64 KB chunks, so a message that crosses a chunk boundary is split) | n/a | done | n/a | In progress | #101 | n/a |
| AGENT-25 | An agent can drive the CAD session in the running GUI window from an external MCP client | none | none | n/a | Planned | none | n/a |
| AGENT-26 | A user can give the Copilot free-form natural language (for example "Make a 50x50 plate and subtract a 10mm hole in the center") | none | n/a | n/a | Planned | none | n/a |
| AGENT-27 | An agent receives `-32603` for a failed geometry operation | n/a | none | n/a | Planned | none | n/a |
| AGENT-28 | An agent can connect over an IPC transport as well as stdio | n/a | none | n/a | Planned | none | n/a |
| DSL-1 | A developer can define any shape through the `CADShape` protocol (`buildMesh`) | n/a | done | n/a | Shipped | none | n/a |
| DSL-2 | A developer can wrap a built mesh as `CSGCompositeShape` | n/a | done | n/a | Shipped | none | n/a |
| DSL-3 | A developer can create `Box(width:depth:height:)` or `Box(x:y:z:)` with an `offset` | n/a | done | n/a | Shipped | none | n/a |
| DSL-4 | A developer can create `Cylinder(radius:height:slices:)` or `Cylinder(diameter:height:slices:)` with an `offset` | n/a | done | n/a | Shipped | none | n/a |
| DSL-5 | A developer can translate a shape with `.translated(x:y:z:)` | n/a | done | n/a | Shipped | none | n/a |
| DSL-6 | A developer can subtract with `.subtracting(_:)` or the builder-closure form | n/a | done | n/a | Shipped | none | n/a |
| DSL-7 | A developer can union with `.union(_:)` or the builder-closure form | n/a | done | n/a | Shipped | none | n/a |
| DSL-8 | A developer can intersect with `.intersecting(_:)` | n/a | done | n/a | Shipped | none | n/a |
| DSL-9 | A developer can convert a shape to a `MeshPayload` with `.toMeshPayload()` | n/a | done | n/a | Shipped | none | n/a |
| DSL-10 | A developer can compose shapes with the operators `-`, `+` and `&` | n/a | done | n/a | Shipped | none | n/a |
| DSL-11 | A developer can use `@CADShapeBuilder` to group shapes; only a single-shape `buildBlock` exists, so multi-statement hierarchies do not compile | n/a | done | n/a | In progress | none | n/a |
| DSL-12 | An agent can author a DSL model and see it in the viewport or the document | n/a | none | n/a | Planned | #85 | n/a |

Findings that map to no capability row.

- #102 (ground grid on Z = 0) has no row. The nearest row is INPUT-6, which lists it.
- #103 (labelled XYZ axes indicator) has no row, because no capability describes it.
