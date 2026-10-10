# Testing Strategy & Verification

The testing architecture in `made` is built on Swift Package Manager (`swift test`) using **XCTest** and Swift Concurrency testing primitives. Tests are organized into focused test suites in [`macos/Tests/MadeCoreTests`](file:///Users/travisgalloway/github/wade/macos/Tests/MadeCoreTests).

---

## Test Suites Overview

There are 8 core test suites in `MadeCoreTests`, executing in approximately 0.2 seconds:

| Suite Name | Target Module | What It Verifies |
| ---------- | ------------- | ---------------- |
| **`CADDSLTests`** | `MadeCore/Scripting` | Cadova-style declarative DSL, operator overloads (`-`, `+`, `&`), and triangulation. |
| **`EuclidEngineTests`** | `MadeCore/Kernel` | Pure-Swift CSG parametric primitives and watertight boolean evaluations. |
| **`KernelClientTests`** | `MadeCore/Kernel` | Swift Actor concurrency, 60 ms debounce conflation, and honest cancellation. |
| **`GestureArbiterTests`** | `MadeCore/Input` | Invariant 8: 3.0 pt movement threshold, mode locking, and pointer type routing. |
| **`SnappingTests`** | `MadeCore/Input` | Invariant 9: Vertex > Edge > Grid priority queue, tolerance limits, and coordinate rounding. |
| **`DocumentModelTests`** | `MadeCore/Scene` | Invariant 3: `@Observable` N-object model, limits clamping, and command mutations. |
| **`CADToolsTests`** | `MadeCore/Agent` | Tool registry execution (`cad_add_solid`, `cad_measure`, `cad_boolean_operation`). |
| **`MCPServerTests`** | `MadeCore/Agent` | JSON-RPC 2.0 handshake, tool schema discovery, and error code mapping (`made-native-cad`). |

---

## Running Automated Tests

Run the complete test suite:

```sh
cd macos
swift test
```

Run a specific test suite or test case by name:

```sh
# Run only CAD DSL tests
swift test --filter CADDSLTests

# Run a single test case
swift test --filter testBooleanDifferenceProducesWatertightMesh
```

---

## Stdio MCP Protocol Verification

External AI agents interact with `made` headlessly via standard I/O pipes. You can verify this pipeline manually or in continuous integration scripts:

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

To verify Invariant 2 (on-demand rendering), `RenderInstrumentation.shared` tracks all submitted frames:
- At idle, `renderCount` **must remain completely flat**.
- A test that simulates mouse moves without crossing the 3.0 pt movement threshold asserts that `renderCount` does not advance.
- When an object parameter changes, `renderCount` must advance by **exactly one frame** once the kernel job settles.

---

## Related Documentation

- [`invariants.md`](../architecture/invariants.md) — How invariants are checked by tests
- [`kernel.md`](../architecture/kernel.md) — Conflation and cancellation testing
- [`agent-api.md`](../architecture/agent-api.md) — MCP protocol specification
