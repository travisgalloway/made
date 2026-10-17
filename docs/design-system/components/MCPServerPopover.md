The popover behind the sparkles toolbar button that starts, stops and describes the in-app MCP server.

Source [`macos/Sources/MadeApp/MCPServerPopoverView.swift`](../../../macos/Sources/MadeApp/MCPServerPopoverView.swift). Guidelines only, no preview (SwiftUI).

## Content
- A `.formStyle(.grouped)` form, with no glass button styles.
- A switch titled "MCP Server" with status "Listening on" and the address, "Off", or "Off" with the error.
- The address, a control to copy the Claude Desktop config, and the registered tool names in `console`.

## Rules
- The toolbar icon turns `system-green` while the server runs. Pair new state with a text or symbol change, not color alone.
