# made — Documentation

**`made`** (**m**acOS-native **A**ided **D**esign and **E**ngineering) is a native CAD application for Apple platforms (macOS 14+, iPadOS 17+) engineered with Swift 6, Metal 3, Euclid CSG, a Cadova-inspired declarative CAD DSL, and an embedded Model Context Protocol (MCP) server for autonomous AI workflows.

---

## Start Here

**Read [`architecture/invariants.md`](./architecture/invariants.md) first.** Nine non-negotiable rules govern this codebase, most are checked by tests and compiler rules, and source code comments cite them by number.

Then navigate based on your task:

| If you are… | Read |
| ----------- | ---- |
| New to the project | [invariants](./architecture/invariants.md) → [threading model](./architecture/threading-model.md) → [roadmap](./roadmap/phases.md) |
| Touching geometry or CSG booleans | [kernel](./architecture/kernel.md) |
| Touching the viewport or Metal shaders | [rendering](./architecture/rendering.md) + [orientation](./architecture/orientation.md) |
| Touching pointer input, gestures, or snapping | [input](./architecture/input.md) |
| Connecting an AI agent or editing the MCP server | [agent-api](./architecture/agent-api.md) |
| Building inspector controls or scene state | [ui-controls](./architecture/ui-controls.md) + [document-model](./architecture/document-model.md) |
| Handling errors or kernel failures | [state and errors](./architecture/state-and-errors.md) |
| Writing tests or running verification | [testing](./guides/testing.md) |
| About to open a PR | [conventions](./guides/conventions.md) |
| Picking up the next engineering milestone | [roadmap](./roadmap/phases.md) → [Phase 4](./roadmap/phase-4-cad-depth.md) |

---

## Technical Stack

| Concern | Implementation Choice |
| ------- | --------------------- |
| **Language** | Swift 6 (`-strict-concurrency=complete`) |
| **UI Framework** | SwiftUI (Universal macOS 14+ & iPadOS 17+) |
| **3D Rendering** | Metal 3, MetalKit (`MTKView`), custom MSL shaders |
| **Memory Architecture** | Apple Silicon Unified Memory (`.storageModeShared`) |
| **Geometry Kernel (Tier 1)** | Pure-Swift CSG (`nicklockwood/Euclid` 0.9.6) |
| **Geometry Kernel (Tier 2)** | OpenCASCADE B-Rep & STEP/IGES (`OCCTSwift`) |
| **Agent Interface** | Model Context Protocol (JSON-RPC 2.0 stdio transport) |
| **CAD Scripting DSL** | Cadova-inspired declarative Swift (`@resultBuilder`) |
| **Testing** | Swift Package Manager (`swift test`), XCTest |

---

## Repository Layout

```
macos/
  Package.swift           # Swift 6 Package manifest defining MadeCore & MadeApp
  Sources/
    MadeCore/             # Core engineering library
      Kernel/             # Geometry generators, CSG engine, KernelClient actor
      Viewport/           # Metal 3 renderer, shaders, render loop instrumentation
      Input/              # Pointer router, gesture arbiter, priority snapping
      Scene/              # @Observable DocumentModel, scene commands
      Agent/              # MCP protocol, server, CAD tools registry
      Scripting/          # Cadova-inspired declarative Swift CAD DSL
      Platform/           # Universal AppKit / UIKit platform abstraction shims
    MadeApp/              # Application executable target
      MadeApp.swift       # SwiftUI @main entrypoint & --mcp-stdio handler
      ContentView.swift   # Viewport, inspector controls, AI copilot sidebar
      CADMetalViewRepresentable.swift # Universal MTKView representable
  Tests/
    MadeCoreTests/        # 8 unit test suites (DSL, CSG, Arbiter, Snapping, MCP)
docs/
  architecture/           # Canonical architecture reference specifications
  roadmap/                # Phased delivery status and backlog migration audit
  guides/                 # Testing and engineering conventions
  archive/web-prototype/  # Archived documentation for original web prototype
```

---

## Historical Archive

The original web proof-of-concept (SvelteKit + brepjs/OpenCascade WASM + three.js WebGPU) documentation is preserved in [`docs/archive/web-prototype/`](./archive/web-prototype/README.md).
