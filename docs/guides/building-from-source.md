# Building from Source and Modifying Dependencies

This guide provides instructions for building `made` from source and relinking the application with modified dependencies.

The `made` application is licensed under the Mozilla Public License 2.0 (MPL-2.0). Bundled dependencies include `OCCTSwift` (OpenCASCADE Technology), which is licensed under the GNU Lesser General Public License 2.1 (LGPL-2.1). In accordance with LGPL-2.1 requirements and Architecture Decision Record ADR-D8, users have the right to modify `OCCTSwift` and relink `made` against the modified library.

## Prerequisites and Toolchain Requirements

Building `made` from source requires the following environment:

| Requirement | Specification |
| --- | --- |
| Operating System | macOS 26 or later |
| Hardware Architecture | Apple Silicon (M-series processors), required by the Metal 4 renderer |
| Development Environment | Xcode 26 or later |
| Swift Language Version | Swift 6 (`swift-tools-version: 6.2` in `Package.swift`) |
| Rendering Toolchain | Metal Toolchain, required for build-time MSL shader compilation |
| Build Utilities | GNU Make and Command Line Tools |

Install the required Metal Toolchain component using Xcode:

```sh
xcodebuild -downloadComponent MetalToolchain
```

Alternatively, run the repository setup target:

```sh
make setup
```

The `make setup` command configures the Metal Toolchain and sets up the local git hooks.

## Standard Build and Packaging Commands

Commands can be run from the repository root using `make`, or directly from the `macos/` directory using the `swift` command.

When invoking `swift` commands directly, you must pass `--build-system swiftbuild`. The default Swift 6.3 native build system only copies `Shaders.metal` instead of compiling Metal shading language files. Passing `--build-system swiftbuild` ensures that shaders are compiled into the resource bundle. When running `swift` from the repository root, include the `--package-path macos` flag.

### Building the Native Binaries

Compile the application and core libraries:

```sh
make build
```

Equivalent direct Swift command:

```sh
cd macos && swift build --build-system swiftbuild
```

### Running Test Suites

Run the complete unit test suite:

```sh
make test
```

To run a specific test suite, pass the `FILTER` parameter:

```sh
make test FILTER=LicenseCatalogTests
```

Equivalent direct Swift command:

```sh
cd macos && swift test --build-system swiftbuild --filter LicenseCatalogTests
```

### Assembling the Application Bundle

The `MadeApp` executable relies on an out-of-process geometry service named `MadeKernelService.xpc`. macOS launch services require XPC services to reside inside an application bundle at `Contents/XPCServices/`. Running `swift run` executes only the unbundled binary with an in-process fallback kernel.

Assemble the full application bundle using the bundle target:

```sh
make bundle
```

This target runs `macos/scripts/bundle-app.sh`. The script performs the following tasks:
1. Validates that `MadeApp`, `MadeKernelService`, and the resource bundle exist in the build directory.
2. Compiles application icons using `actool`.
3. Creates the directory layout at `macos/.build/Made.app`.
4. Copies the executable binaries, Info.plist manifests, entitlements, and resources.
5. Embeds `MadeKernelService.xpc` inside `Contents/XPCServices/`.
6. Signs the bundle inside-out using the specified signing identity.

### Running the Application

Launch the assembled application bundle:

```sh
make run
```

To launch the application with the embedded Model Context Protocol (MCP) server listening on standard input and output:

```sh
make run-mcp
```

## Code Signing for Local Execution

### macOS Signing

By default, `macos/scripts/bundle-app.sh` signs the application bundle and the embedded XPC service with ad-hoc signatures (`SIGNING_IDENTITY="-"`). Ad-hoc signing enables local execution on the host machine without requiring an Apple Developer account.

To sign the bundle with a specific Apple Development certificate or Developer ID:

```sh
SIGNING_IDENTITY="Apple Development: Developer Name (TEAMID)" make bundle
```

The script signs the embedded `MadeKernelService.xpc` with `MadeKernelService.entitlements` first, verifies its signature, and then signs the outer `Made.app` bundle with `MadeApp.entitlements`. When a named identity is provided, the script includes a secure timestamp.

### iPadOS Signing with a Free Apple ID

The `macos/Package.swift` manifest declares support for `.iOS(.v26)`. To build and run the application on an iPad using a personal Apple ID:

1. Open `macos/Package.swift` in Xcode 26.
2. Connect your iPad to your Mac with a cable, or select an iPad simulator destination.
3. In the Xcode scheme selector, choose `MadeApp` and select the connected iPad device.
4. Navigate to the project settings under Signing & Capabilities.
5. Select "Automatically manage signing" and choose your Personal Team associated with your free Apple ID.
6. Xcode creates a free provisioning profile and installs the application onto the device.

Provisioning profiles created with a free Apple ID remain valid for 7 days. After 7 days, the application will no longer launch until re-deployed through Xcode. On iPadOS, geometry operations execute in process within the main application because iPadOS does not provide third-party XPC services.

## Modifying and Relinking LGPL Dependencies

`made` depends on `OCCTSwift`, a Swift package wrapping the OpenCASCADE Technology B-rep kernel. The following steps explain how to replace the pinned dependency with a modified version and relink the application.

### Pinned Dependency Identification

Each release corresponds to pinned package revisions recorded in `macos/Package.resolved`. Open `macos/Package.resolved` to identify the pinned revision:

```json
{
  "identity" : "occtswift",
  "kind" : "remoteSourceControl",
  "location" : "https://github.com/SecondMouseAU/OCCTSwift.git",
  "state" : {
    "revision" : "0c9f9274e4ff2a4fd422291a45b3560161dbbe64",
    "version" : "3.0.0"
  }
}
```

### Swift Package Manager Local Overrides

To check out an editable copy of `OCCTSwift`, use the `swift package edit` command:

```sh
swift package --package-path macos edit OCCTSwift
```

SwiftPM checks out the package source code into `macos/Packages/OCCTSwift`. When building the project, SwiftPM uses this local directory instead of the remote Git repository.

Alternatively, you can clone `OCCTSwift` to a separate location and update `macos/Package.swift` to reference the local path:

```swift
// In macos/Package.swift
dependencies: [
    .package(url: "https://github.com/nicklockwood/Euclid.git", from: "0.9.6"),
    .package(path: "../path/to/local/OCCTSwift")
]
```

### Modifying OCCTSwift Sources or Binaries

Navigate to `macos/Packages/OCCTSwift`. You can edit the Swift bindings, update C++ interop interfaces, or replace underlying OpenCASCADE dynamic libraries and xcframeworks.

For example, you can edit `macos/Packages/OCCTSwift/Sources/OCCTSwift/OCCTBridge.swift` to adjust geometry evaluations, or substitute customized binaries in the package root.

### Rebuilding and Relinking

After applying changes to the dependency, rebuild the application bundle:

```sh
make bundle
```

SwiftPM detects changes in `macos/Packages/OCCTSwift`, compiles the updated source files, and relinks `MadeCore`, `MadeApp`, and `MadeKernelService` with the modified library.

### Verifying the Relinked Binary

Verify that the application bundle contains the modified binaries:

1. Check binary modification timestamps:
   ```sh
   ls -la macos/.build/Made.app/Contents/MacOS/MadeApp
   ls -la macos/.build/Made.app/Contents/XPCServices/MadeKernelService.xpc/Contents/MacOS/MadeKernelService
   ```
2. Inspect linked libraries:
   ```sh
   otool -L macos/.build/Made.app/Contents/MacOS/MadeApp
   ```
3. Test custom behavior: If you introduced an observable log statement or version string in your modified `OCCTSwift`, run `make run` or execute the test suite to observe the modified output:
   ```sh
   make test FILTER=KernelClientTests
   ```

### Reverting Local Overrides

To discard local overrides and return to the original pinned dependency, run:

```sh
swift package --package-path macos unedit OCCTSwift
```

SwiftPM removes the `macos/Packages/OCCTSwift` directory and resumes using the pinned remote package. If `macos/Package.resolved` was modified during the edit, restore the original file:

```sh
git checkout macos/Package.resolved
```

## Release Tag Mappings

Official releases of `made` are marked in the Git repository using semantic version tags (`v*`, such as `v0.1.0`).

Each release tag points to the exact commit used to generate the published application binaries. The `macos/Package.resolved` file committed at that tag records the exact revisions of all package dependencies, including `OCCTSwift`.

To inspect or build from source for a specific published release:

```sh
git checkout tags/v0.1.0
make bundle
```

This ensures that the build artifacts match the source and dependency versions of the official distribution.
