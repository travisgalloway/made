# Entitlement Review and Distribution Security

This document records the security posture, Hardened Runtime configuration, entitlement rationale, and update safety guarantees for direct-download Developer ID releases of Made.

## Security Posture

Made distributes outside the Mac App Store as a signed and notarized application bundle under ADR-D8. Apple Gatekeeper requires Developer ID code signing, Hardened Runtime (`--options runtime`), a secure timestamp (`--timestamp`), and an Apple notarization ticket stapled to the distribution archives.

Direct-download distribution does not enforce macOS App Sandbox restrictions. Because App Sandbox is not enabled for direct distribution, the application operates under standard POSIX file system permissions and loopback networking permissions.

## Entitlement Configuration

The application bundle and its embedded helper services declare minimal Hardened Runtime entitlements in property lists under `macos/Support/`.

### MadeApp (`macos/Support/MadeApp.entitlements`)

| Entitlement | Value | Rationale |
| --- | --- | --- |
| `com.apple.security.cs.allow-jit` | `true` | Allows JavaScriptCore to allocate executable memory for JIT compilation. `PartRuntime` in `MadeCore` evaluates `.part.ts` and `.part.js` parametric CAD scripts via JavaScriptCore. Hardened Runtime blocks JIT compilation without this entitlement, causing process termination during script evaluation. |
| `com.apple.security.cs.allow-unsigned-executable-memory` | `false` | Prevents the application from overriding page protection to execute arbitrary unsigned memory. Script execution relies strictly on JavaScriptCore system frameworks. |
| `com.apple.security.cs.disable-library-validation` | `false` | Enforces that all linked dynamic libraries and frameworks must be signed by Apple or by the same Developer ID team. |

### MadeKernelService (`macos/Support/MadeKernelService.entitlements`)

| Entitlement | Value | Rationale |
| --- | --- | --- |
| `com.apple.security.cs.allow-jit` | `false` | The kernel service performs geometry operations via native Swift and C++ libraries (Euclid, OCCT) and does not host a JavaScript runtime. |
| `com.apple.security.cs.allow-unsigned-executable-memory` | `false` | Prevents unsigned executable memory allocation in the geometry worker process. |
| `com.apple.security.cs.disable-library-validation` | `false` | Enforces library validation on all dynamic libraries loaded into the kernel process. |

## Network Access Review

The embedded Model Context Protocol (MCP) server in `MCPServer.swift` binds a TCP listener to port 9820. The server restricts incoming connections to the local loopback interface by configuring `NWParameters.requiredInterfaceType = .loopback` (#129).

Because the application is distributed outside the App Sandbox, loopback socket binding does not require explicit networking entitlements. If an App Sandbox build is introduced for the Mac App Store in issue #419, the `com.apple.security.network.server` entitlement will be required to permit local socket binding.

Outgoing network requests are not initiated by the core CAD engine. Crash recovery and telemetry do not transmit data over the network.

## File System Access

User CAD packages (`.made`), STEP exchange files (`.step`), and part scripts (`.part.ts`) are opened and saved through standard AppKit open and save panels or command-line arguments.

Under direct-download distribution, file access operates under standard POSIX user permissions. The application accesses files in directories readable by the user without requiring security-scoped bookmarks or sandbox powerbox entitlements.

## Update Safety and Persistence

Replacing `Made.app` in `/Applications` with an updated release build preserves all persistent user state.

### Preferences and Settings

Application preferences, navigation presets, unit settings, and kernel tolerances are stored in `UserDefaults` under the application domain `com.made.app`. macOS stores these preferences at:

`~/Library/Preferences/com.made.app.plist`

Installing a new version of `Made.app` does not delete or overwrite preference property lists. The new application version reads the existing keys and applies default values only for newly added configuration fields.

### User Documents and Recent Items

User CAD files and packages are stored in user-selected directories outside the application bundle. Updating the binary has no effect on user directories.

Recent document history is managed by `NSDocumentController` and maintained in standard AppKit shared state across application updates. Crash recovery snapshots are persisted in user application support directories and remain intact across binary updates.
