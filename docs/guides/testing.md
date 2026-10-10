# Testing Strategy & Verification

The testing architecture in `made` is built on Swift Package Manager (`swift test`) using **XCTest** and Swift Concurrency testing primitives. The package has one test target, `MadeCoreTests`, with focused suites in [`macos/Tests/MadeCoreTests`](../../macos/Tests/MadeCoreTests).

---

## Test Suites Overview

`MadeCoreTests` has 8 suites and 34 tests. All of them are unit tests that run in process. The package has no XCUITest target and no end-to-end suite, and nothing in the test target creates a Metal device or a SwiftUI view.

| Suite Name | Target Module | What It Verifies |
| ---------- | ------------- | ---------------- |
| **`CADDSLTests`** | `MadeCore/Scripting` | Cadova-style declarative DSL, operator overloads (`-`, `+`, `&`), and triangulation. |
| **`EuclidEngineTests`** | `MadeCore/Kernel` | Pure-Swift CSG parametric primitives and watertight boolean evaluations. |
| **`KernelClientTests`** | `MadeCore/Kernel` | Box and cylinder generation, invalid dimensions, 60-ms debounce conflation, and the stale-debounce race (#90). |
| **`GestureArbiterTests`** | `MadeCore/Input` | Invariant 8: lock on first move for one pointer, lock to navigate for two pointers, and a pure tap resolving at release. `PointerRouter` has no test. |
| **`SnappingTests`** | `MadeCore/Input` | Invariant 9: Vertex > Edge > Grid precedence, the 20 px tolerance, and grid rounding to 10 mm with Z unchanged. |
| **`DocumentModelTests`** | `MadeCore/Scene` | Default two-solid scene, add and remove, and `setParam` limits clamping. |
| **`CADToolsTests`** | `MadeCore/Agent` | Tool registry execution (`cad_add_solid`, `cad_measure`, `cad_boolean_operation`). |
| **`MCPServerTests`** | `MadeCore/Agent` | JSON-RPC 2.0 handshake, tool discovery, a tool call, and the unknown-method error. The tests call `MCPServer` in process. |

---

## Running Automated Tests

Run the complete test suite:

```sh
cd macos
swift test
```

Run a specific test suite or test case by name:

```sh
cd macos

# Run only CAD DSL tests
swift test --filter CADDSLTests

# Run a single test case
swift test --filter KernelClientTests/testInvalidDimensionsFailWithErrorCode
```

Build and run the application:

```sh
cd macos
swift build
swift run MadeApp
swift run MadeApp --mcp-stdio
```

---

## Stdio MCP Protocol Verification

External AI agents can drive `made` through standard I/O pipes. No automated test starts the `MadeApp` process, so the checks below are manual shell recipes. Run them from the repository root after `cd macos && swift build`:

### 1. Initialize Protocol Handshake
```sh
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ./macos/.build/debug/MadeApp --mcp-stdio
```
**Expected Output**:
```json
{"id":1,"jsonrpc":"2.0","result":{"protocolVersion":"2024-11-05","serverInfo":{"version":"0.1.0","name":"made-native-cad"},"capabilities":{"tools":{}}}}
```

### 2. Tool Enumeration
```sh
echo '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | ./macos/.build/debug/MadeApp --mcp-stdio
```
**Expected Output**: JSON list of all 8 CAD tools with their JSON Schema parameters.

### 3. Tool Execution
```sh
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cad_get_scene","arguments":{}}}' | ./macos/.build/debug/MadeApp --mcp-stdio
```
**Expected Output**: Live scene graph JSON with object properties and transforms.

---

## Rendering Observability Contract

`RenderInstrumentation.shared` records submitted frames (`renderCount`, `drawCalls`, `lastReason`) and the viewport HUD displays them. No test reads these values yet, so Invariant 2 is not covered by automation. The intended checks, once a test can create a renderer, are:
- At idle, `renderCount` stays flat.
- When an object parameter changes, `renderCount` advances by one frame once the kernel job settles.

---

## Related Documentation

- [`invariants.md`](../architecture/invariants.md): How invariants are checked by tests
- [`kernel.md`](../architecture/kernel.md): Conflation and cancellation testing
- [`agent-api.md`](../architecture/agent-api.md): MCP protocol specification
