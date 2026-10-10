# Agent API & Model Context Protocol (MCP)

`made` integrates first-class autonomous AI agent capabilities into the core application. Agents can inspect the 3D scene, create and modify parametric geometry, execute boolean operations, script models using a declarative Swift DSL, and visually verify their work through a closed multimodal feedback loop.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│           External Agents (Claude, Cursor, CLI)        │
└──────────────────────────┬─────────────────────────────┘
                           │ JSON-RPC 2.0 (stdio or IPC)
┌──────────────────────────▼─────────────────────────────┐
│                       MCPServer                        │
│   • Conforms to MCP Spec (2024-11-05)                  │
│   • Request Routing: initialize, tools/list, tools/call│
└──────────────────────────┬─────────────────────────────┘
                           │ Tool Invocations
┌──────────────────────────▼─────────────────────────────┐
│                    CADToolRegistry                     │
│   • cad_get_scene            • cad_remove_solid        │
│   • cad_add_solid            • cad_measure             │
│   • cad_set_param            • cad_boolean_operation  │
│   • cad_set_transform        • cad_capture_snapshot    │
└──────────────┬──────────────────────────┬──────────────┘
               │ Live Mutation            │ Snapshot Request
┌──────────────▼─────────────┐ ┌──────────▼──────────────┐
│       DocumentModel        │ │      MetalRenderer      │
│   (@Observable Scene Graph)│ │   (Offscreen PNG Pass)  │
└────────────────────────────┘ └──────────┬──────────────┘
                                          │ Base64 Image
                               ┌──────────▼──────────────┐
                               │ Multimodal Vision Loop  │
                               │ (Visual Inspection)     │
                               └─────────────────────────┘
```

---

## 1. Model Context Protocol (MCP) Integration

`made` implements the Model Context Protocol natively in pure Swift ([`MCPProtocol.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Agent/MCPProtocol.swift) and [`MCPServer.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Agent/MCPServer.swift)).

### Headless Stdio Transport
The application executable can run headlessly as an MCP server:

```sh
MadeApp --mcp-stdio
```

External LLM harnesses connect standard I/O pipes to this process to discover tools and command the CAD application without requiring browser wrappers or external servers.

### Configuration for Claude Desktop / Cursor
Add `made` to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "made-cad": {
      "command": "/path/to/made/macos/.build/debug/MadeApp",
      "args": ["--mcp-stdio"]
    }
  }
}
```

---

## 2. Core CAD Tools

The [`CADToolRegistry`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Agent/CADTools.swift#L8) provides 8 strongly typed tools:

| Tool Name | Parameters | Description |
| --------- | ---------- | ----------- |
| `cad_get_scene` | None | Returns the full scene hierarchy, object IDs, parametric dimensions, and 3D positions in JSON format. |
| `cad_add_solid` | `type` ("box" \| "cylinder"), dimensions (`width`, `depth`, `height`, `radius`), position (`posX`, `posY`, `posZ`) | Instantiates a new parametric solid in the document. |
| `cad_set_param` | `id`, `name`, `value` | Updates a specific parameter on a solid, automatically clamped within safe engineering limits. |
| `cad_set_transform` | `id`, `posX`, `posY`, `posZ` | Updates the 3D world position of a solid. |
| `cad_remove_solid` | `id` | Deletes a solid from the document. |
| `cad_measure` | `id` | Returns calculated volume, bounding extents, and estimated surface area. |
| `cad_boolean_operation` | `targetId`, `op` ("subtract" \| "union" \| "intersect"), `solidA`, `solidB` | Performs a CSG boolean operation between two solids and stores the result. |
| `cad_capture_snapshot` | None | Renders an offscreen Metal 3 viewport frame and returns a base64 PNG data URI. |

---

## 3. Multimodal Visual Verification Loop

Numerical verification (measuring volume and bounding box) is necessary but insufficient for complex CAD parts. Visual artifacts such as inverted normals, unexpected chamfers, or incorrect clearances require optical inspection.

### The Agent Verify Cycle
```mermaid
sequenceDiagram
    participant Agent as LLM Agent
    participant MCP as MadeApp (MCP)
    participant Kernel as KernelClient (Actor)
    participant GPU as Metal 3 Viewport

    Agent->>MCP: tools/call ("cad_add_solid", {box})
    MCP->>Kernel: makeBox(...)
    Kernel-->>MCP: MeshPayload
    Agent->>MCP: tools/call ("cad_boolean_operation", {subtract})
    MCP->>Kernel: booleanOperation(...)
    Kernel-->>MCP: MeshPayload
    Agent->>MCP: tools/call ("cad_capture_snapshot", {})
    MCP->>GPU: Offscreen Render Pass
    GPU-->>MCP: Base64 PNG
    MCP-->>Agent: {image: "data:image/png;base64,..."}
    Note over Agent: Agent visually verifies geometry and iterates
```

---

## 4. Cadova-Inspired Declarative CAD DSL

In addition to discrete MCP tool calls, agents can generate complete CAD models programmatically using the declarative Swift DSL in [`CADDSL.swift`](file:///Users/travisgalloway/github/wade/macos/Sources/MadeCore/Scripting/CADDSL.swift):

```swift
import MadeCore

// Declarative CSG modeling with native operators:
let mountingBracket = Box(width: 50, depth: 50, height: 10)
    - Cylinder(radius: 6, height: 20)
    + Box(width: 10, depth: 10, height: 5).translated(x: 20)

let meshPayload = mountingBracket.toMeshPayload()
```

### DSL Features
- **Operator Overloads**: `-` for CSG subtraction, `+` for CSG union, and `&` for intersection.
- **Fluent Transforms**: `.translated(x:y:z:)` and parameter setters.
- **Result Builders**: `@CADShapeBuilder` allows composite hierarchy definitions compatible with Swift 6 and Claude Code generation.

---

## Related Documentation

- [`rendering.md`](./rendering.md) — Snapshot generation pipeline
- [`kernel.md`](./kernel.md) — CSG boolean execution
- [`document-model.md`](./document-model.md) — Scene mutation APIs
