# Phase 3: Agentic Subsystem & MCP Stdio Server

**Status**: In progress. Tools, protocol, and DSL are built. The headless snapshot is not (#89).  
**Package Target**: `MadeCore/Agent`, `MadeCore/Scripting`, `MadeApp`

Phase 3 establishes first-class autonomous AI agent integration in `made`. Instead of requiring external browser testing tools, the native application exposes a standardized **Model Context Protocol (MCP)** interface over standard I/O and over a local TCP listener, and provides a declarative Swift DSL for programmatic CAD modeling.

---

## Delivered Components

### 1. Pure-Swift MCP Implementation
- **Files**: [`MCPProtocol.swift`](../../macos/Sources/MadeCore/Agent/MCPProtocol.swift), [`MCPServer.swift`](../../macos/Sources/MadeCore/Agent/MCPServer.swift)
- **Standard**: Conforms to the 2024-11-05 Model Context Protocol specification.
- **Protocol**: JSON-RPC 2.0 handling `initialize`, `tools/list`, and `tools/call`.
- **Identity**: Identifies as `made-native-cad` v0.1.0.

### 2. Headless Stdio Transport
- **Entrypoint**: [`MadeApp.swift`](../../macos/Sources/MadeApp/MadeApp.swift)
- **Flag**: `--mcp-stdio`
- With this flag, the application listens for JSON-RPC messages on `FileHandle.standardInput` and responds on `FileHandle.standardOutput`. The SwiftUI window scene still launches, so the mode is not fully headless.
- The registry is built with no snapshot provider (`MadeApp.swift`).

### 2a. In-App TCP Transport
- **File**: [`MCPServer.swift`](../../macos/Sources/MadeCore/Agent/MCPServer.swift), started by `WorkspaceModel.toggleMCPServer` from the MCP window.
- The listener uses port 9820 and shares the window's document, kernel, and renderer. The required behavior is loopback-only access. The bind covers all interfaces today (DSN-f5402406, #129).

### 3. Core CAD Tool Registry
- **File**: [`CADTools.swift`](../../macos/Sources/MadeCore/Agent/CADTools.swift)
- Registers 8 strongly-typed tools:
  1. `cad_get_scene`
  2. `cad_add_solid`
  3. `cad_set_param`
  4. `cad_set_transform`
  5. `cad_remove_solid`
  6. `cad_measure`
  7. `cad_boolean_operation`
  8. `cad_capture_snapshot`

### 4. Multimodal Visual Feedback Loop (GUI only)
- **File**: [`MetalRenderer.swift`](../../macos/Sources/MadeCore/Viewport/MetalRenderer.swift)
- Implements `SnapshotProvider` (declared in `CADTools.swift`). The conformance is declared in `Agent/MetalRenderer+SnapshotProvider.swift`.
- Renders an 800x600 offscreen frame, reads the bytes back, and encodes a base64 PNG.
- The GUI registers the renderer as the provider (`WorkspaceModel.swift`). Over `--mcp-stdio` there is no provider, and `cad_capture_snapshot` returns an error (#89).

### 5. Cadova-Inspired Declarative CAD DSL
- **File**: [`CADDSL.swift`](../../macos/Sources/MadeCore/Scripting/CADDSL.swift)
- Allows agents to author parametric shapes using Swift result builders and operators (`-`, `+`, `&`).

---

## Verification Summary

Tested via `cd macos && swift test`:
- `MCPServerTests` (5 tests): initialize, tool listing, one tool call, and the unknown-method error.
- `CADToolsTests`: scene inspection, creation, limits clamping, measurement, and deletion.

Not covered by `swift test`:
- The stdio pipeline. No test starts `MadeApp --mcp-stdio`. The shell recipes in [`testing.md`](../guides/testing.md) are manual.
- `cad_capture_snapshot`, in either mode.

## Planned: File-Edit Agent Workflow (Mac MVP)

In the Mac MVP, external agents edit part source files directly, in the style of [brepjs](https://brepjs.dev/agent/overview). The running app reloads each saved file (#427). Agents then inspect app state over MCP on the loopback listener: diagnostics with file and line, an explicit reload, verification against an `expected` block, and snapshots from named views (#428). A Claude Code plugin skill teaches the edit, reload, verify, and repair loop (#429). Part files are TypeScript with a brepjs-style API, run by JavaScriptCore ([ADR-D6](../architecture/adr/ADR-D6-scripting-runtime.md), #435), and live as plain-text `.part.ts` files inside the `.made` package directory or beside it ([ADR-D7](../architecture/adr/ADR-D7-made-encoding.md), #149). In-app agents on Apple's models wait for V2.

## Open Issues

| Issue | Topic |
| ----- | ----- |
| #89 | Snapshot over `--mcp-stdio` |
| #91 | Agent mutations run off the main actor |
| #95, #96 | Invalid-request code and notification responses |
| #97, #98, #99 | Argument validation for `cad_set_param`, transform and size, and booleans |
| #100 | Boolean result ID unusable by other tools |
| #101 | Messages larger than one read chunk |
| #435, #427, #428, #429 | File-edit agent workflow: TypeScript part runtime, reload, inspection tools, and the plugin skill |
