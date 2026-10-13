# Testing Strategy & Verification

The testing architecture in `made` is built on Swift Package Manager (`swift test`) using **Swift Testing** (`@Test` and `#expect`) and Swift Concurrency testing primitives. The package has one test target, `MadeCoreTests`, with focused suites in [`macos/Tests/MadeCoreTests`](../../macos/Tests/MadeCoreTests).

---

## Test Suites Overview

`MadeCoreTests` has 28 suites and 235 tests. All of them are unit tests that run in process. The package has no XCUITest target and no end-to-end suite, and no test creates a SwiftUI view. `MetalRendererGeometryTests` and `ShaderLibraryTests` create Metal devices, and the renderer tests need Metal 4.

| Suite Name | Target Module | What It Verifies |
| ---------- | ------------- | ---------------- |
| **`CADDSLTests`** | `MadeCore/Scripting` | Cadova-style declarative DSL: the `ShapeNode` each shape, modifier, and operator (`-`, `+`, `&`) builds, and triangulation through `KernelClient`. |
| **`ShapeEvaluationTests`** | `MadeCore/Kernel` | `evaluateShape` (#331): one request per tree, CSG off the main thread, validation limits, failure storing nothing, and conflation. |
| **`EuclidEngineTests`** | `MadeCore/Kernel` | Pure-Swift CSG parametric primitives and watertight boolean evaluations. |
| **`KernelClientTests`** | `MadeCore/Kernel` | Box and cylinder generation, invalid dimensions, 60-ms debounce conflation, and the stale-debounce race (#90). |
| **`GestureArbiterTests`** | `MadeCore/Input` | Invariant 8: lock on first move for one pointer, lock to navigate for two pointers, and a pure tap resolving at release. `CameraTests` covers `PointerRouter`. |
| **`SnappingTests`** | `MadeCore/Input` | Invariant 9: Vertex > Edge > Grid precedence, the 20 px tolerance, and grid rounding to 10 mm with Z unchanged. |
| **`DocumentModelTests`** | `MadeCore/Scene` | Default two-solid scene, add and remove, and `setParam` limits clamping. |
| **`RecomputeFailuresTests`** | `MadeCore/Scene` | The recompute failure message for every `KernelErrorCode`, the cancelled rule, and clearing on success or removal (#109). |
| **`FaultInjectingKernelClientTests`** | `MadeCore/Kernel` | The debug fault injector fails one request with the chosen code, then forwards (#109). |
| **`CADToolsTests`** | `MadeCore/Agent` | Tool registry execution (`cad_add_solid`, `cad_measure`, `cad_boolean_operation`). |
| **`MCPServerTests`** | `MadeCore/Agent` | JSON-RPC 2.0 handshake, tool discovery, a tool call, and the unknown-method error. The tests call `MCPServer` in process. |
| **`CameraTests`**, **`CameraFramingTests`** | `MadeCore/Viewport` | Orbit, pan, zoom, view presets, scene framing, and `PointerRouter` routing. |
| **`GridGeneratorTests`**, **`AxesGeneratorTests`** | `MadeCore/Viewport` | Ground grid and axes indicator geometry. |
| **`ViewportStateTests`**, **`ViewportToolTests`**, **`ViewportCoordinatorTests`** | `MadeCore/Viewport`, `MadeCore/Input` | Viewport state, tool routing, and invalidation reasons including the flat `renderCount` at idle. |
| **`OrientationTests`** | `MadeCore/Viewport` | The right-handed Z-up convention. |
| **`MetalRendererGeometryTests`**, **`ShaderLibraryTests`** | `MadeCore/Viewport` | Offscreen render checks and the bundled shader library. |

---

## Running Automated Tests

Run the complete test suite with `make test`, or directly:

```sh
cd macos
swift test --build-system swiftbuild
```

Run a specific test suite or test case by name:

```sh
cd macos

# Run only CAD DSL tests
swift test --build-system swiftbuild --filter CADDSLTests

# Run a single test case
swift test --build-system swiftbuild --filter KernelClientTests/testInvalidDimensionsFailWithErrorCode
```

Build and run the application:

```sh
cd macos
swift build --build-system swiftbuild
swift run --build-system swiftbuild MadeApp
swift run --build-system swiftbuild MadeApp --mcp-stdio
```

To check the recompute failure message by hand, run a debug build and choose Debug > Fail Next Recompute. Drag the box Width slider. The previous box stays on screen, and the Inspector shows `box-1 failed to recompute (invalid-params): Forced failure` with a matching error line in the console. Drag again, and the message clears as the box resizes.

---

## Git Hooks and Make Targets

`make test` runs the full suite, and `make test FILTER=<name>` runs one suite or test. `make hooks` installs the `.githooks` pre-commit and pre-push hooks. When a change touches `macos/`, the hooks run every suite that calls `MTLCreateSystemDefaultDevice` (`.githooks/run-metal-tests.sh`). A failure or a skipped test blocks the commit or push, because CI runners may have no GPU.

---

## Stdio MCP Protocol Verification

External AI agents can drive `made` through standard I/O pipes. `StdioProcessTests` launches the built `MadeApp --mcp-stdio` executable and checks the handshake, the tool list, a scene edit, and a snapshot. The recipes below repeat those checks by hand. Run them from the repository root after `make build`, with `BIN` set to the built executable:

```sh
BIN=$(cd macos && swift build --build-system swiftbuild --show-bin-path)/MadeApp
```

### 1. Initialize Protocol Handshake
```sh
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | "$BIN" --mcp-stdio
```
**Expected Output**:
```json
{"id":1,"jsonrpc":"2.0","result":{"protocolVersion":"2024-11-05","serverInfo":{"version":"0.1.0","name":"made-native-cad"},"capabilities":{"tools":{}}}}
```

### 2. Tool Enumeration
```sh
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | "$BIN" --mcp-stdio
```
**Expected Output**: JSON list of all 8 CAD tools with their JSON Schema parameters.

### 3. Tool Execution
```sh
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cad_get_scene","arguments":{}}}' | "$BIN" --mcp-stdio
```
**Expected Output**: Live scene graph JSON with object properties and transforms.

### 4. Viewport Snapshot
```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cad_add_solid","arguments":{"type":"box","posZ":40}}}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cad_capture_snapshot","arguments":{}}}' \
  | "$BIN" --mcp-stdio \
  | python3 -c 'import sys, json, base64; [sys.stdout.buffer.write(base64.b64decode(m["result"]["content"][0]["data"])) for m in map(json.loads, sys.stdin) if m.get("id") == 3]' > snapshot.png
sips -g pixelWidth -g pixelHeight snapshot.png
```
**Expected Output**: `pixelWidth: 800` and `pixelHeight: 600`. The PNG shows the grid, the axes, the two default solids, and the added box. Without a Metal 4 device the response is an `isError` result that reads `Snapshot unavailable: no Metal 4 device is available to render the viewport`.

---

## Rendering Observability Contract

`RenderInstrumentation.shared` records submitted frames (`renderCount`, `drawCalls`, `lastReason`) and the viewport HUD displays them. `ViewportCoordinatorTests` reads these values and asserts that `renderCount` stays flat at idle (`testRenderCountStaysFlatAtIdle`). Invariant 2 is partly covered. The remaining check is that `renderCount` advances by one frame once a kernel job settles after an object parameter change.

---

## Related Documentation

- [`invariants.md`](../architecture/invariants.md): How invariants are checked by tests
- [`kernel.md`](../architecture/kernel.md): Conflation and cancellation testing
- [`agent-api.md`](../architecture/agent-api.md): MCP protocol specification
