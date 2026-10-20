# ADR-D10: UI and Viewport Test Strategy

- **Status:** Accepted, 2026-10-20 <!-- Status: Accepted, 2026-10-20 -->
- **Issue:** #549
- **Decides:** End-to-end and UI test architecture, XCUITest harness design, 3D viewport validation layers, offscreen golden image baselines, and GPU gating rules
- **Related decisions:** [ADR-D1: Canonical Geometry Kernel](./ADR-D1-canonical-geometry-kernel.md), [ADR-D2: Modeling Paradigm and Document Model](./ADR-D2-modeling-paradigm-and-document-model.md), [ADR-D9: Fate of Euclid Mesh Path](./ADR-D9-fate-of-euclid-mesh-path.md), Invariants 2 and 8
- **Implemented by:** #550 (QA-UITEST-01 harness), #321 (BL-QA-06 visual regression tests)

## Context

`made` possesses 1,151 unit tests across 85 files (69 in `MadeCoreTests` and 16 in `MadeAppTests`), but lacks a UI test target, an XCUITest bundle, or an end-to-end testing harness for the 3D viewport. In `docs/test-plan.md`, Table 1 marked `E2E / UI` as pending, and 117 capability rows noted the absence of a UI test target.

The 3D viewport is hosted in `CADMTKView` (`MetalKit`), which the macOS accessibility hierarchy exposes as a single opaque element without child accessibility elements. While XCUITest can dispatch clicks and drag gestures to this element, XCUITest cannot inspect camera matrices, rendered solids, or selection state directly. Viewport testing requires offscreen pixel baseline comparisons (goldens) and an in-app telemetry probe (`viewport-probe`) exposed to XCUITest without violating Invariant 2 (on-demand rendering).

Swift Package Manager cannot compile or host a native macOS UI Testing Bundle. Furthermore, hosted GitHub Actions runners (`macos-26`) use paravirtualized displays that lack Metal 4 hardware acceleration. A complete testing strategy must define the harness structure, viewport validation layers, offscreen golden tolerances, telemetry probe contracts, and GPU gating rules for local runs and CI.

## Options Considered: Harness

1. **A checked-in Xcode project for the app, XPC service, and UI tests.**
   - *Pros:* Standard Xcode structure; native UI test hosting.
   - *Cons:* Duplicates assembly logic from `scripts/bundle-app.sh`; introduces drift between `Package.swift` and `project.pbxproj` whenever source files are added or moved.
   - *Verdict:* Rejected.

2. **An XcodeGen `project.yml`.**
   - *Pros:* Generates the Xcode project dynamically from a YAML specification.
   - *Cons:* Requires an external Homebrew toolchain dependency for every developer and CI job; an app target still duplicates the build script.
   - *Verdict:* Rejected.

3. **Tuist.**
   - *Pros:* Modern project generation and caching ecosystem.
   - *Cons:* Adds a heavy third-party dependency for a single test target.
   - *Verdict:* Rejected.

4. **A checked-in `macos/UITests/MadeUITests.xcodeproj` with only a UI test target, launching the script-built `macos/.build/Made.app`.**
   - *Pros:* Tests exercise the exact shipped application bundle, including the kernel XPC service. Requires no extra third-party tools. A synchronized folder keeps `project.pbxproj` stable when adding test files.
   - *Cons:* Requires running `make bundle` before executing UI tests.
   - *Verdict:* Accepted.

## Options Considered: GPU Gating

1. **A self-hosted Apple-silicon runner.**
   - *Pros:* Executes Metal 4 GPU tests in continuous integration.
   - *Cons:* The repository is public, creating security risks with fork pull requests. A developer machine used as a runner would lose focus during test runs.
   - *Verdict:* Rejected for now. Revisit when a dedicated machine exists and execution is restricted to non-fork events.

2. **Run viewport E2E directly inside the pre-push git hook.**
   - *Pros:* Guarantees that every push has passed viewport E2E tests locally.
   - *Cons:* XCUITest takes system focus and sends synthetic keyboard and pointer events, disrupting developer work during a push.
   - *Verdict:* Rejected.

3. **Local runs through a make target, plus a pre-push check of the pass record.**
   - *Pros:* `make test-viewport` runs when invoked by the developer and writes a pass record keyed to the git tree hash. The pre-push hook reads the record, runs no UI tests, and blocks a push that touches viewport or app sources without a passing record.
   - *Cons:* Requires a manual run of `make test-viewport` before pushing changes to relevant paths.
   - *Verdict:* Accepted.

## Decision

### 1. Harness Architecture and Execution

1. UI tests reside in `macos/UITests/`, outside all Swift Package Manager target paths.
2. The project contains a single UI Testing Bundle, `MadeUITests`, with a single shared scheme. The project leaves `TEST_TARGET_NAME` unset.
3. Tests launch the application through `XCUIApplication(url:)`. The path is read from the `MADE_APP_PATH` environment variable, defaulting to `macos/.build/Made.app`.
4. UI tests use XCTest, because Swift Testing cannot drive `XCUIApplication`.
5. Every UI test launch supplies the `--ui-testing` command-line argument. Under `--ui-testing`, the application uses an isolated private `UserDefaults` suite and a dedicated temporary recovery directory (`MADE_RECOVERY_DIR`).

### 2. Spike Results

1. **Spike 1 (Out-of-target application launching):** `MadeUITests.xcodeproj` with no host target application (`TEST_TARGET_NAME` unset) launches `Made.app` via `XCUIApplication(url:)` under ad-hoc code signing. This setup functions without special entitlements or provisioning profiles.
2. **Spike 2 (Hosted CI Accessibility and Automation Mode):** Headless panel E2E tests execute cleanly under Automation Mode on hosted GitHub Actions `macos-26` runners when launched with `--force-no-gpu`. Interactive permission dialogs do not stall execution. Viewport tests requiring Metal 4 are skipped on hosted CI.

### 3. Viewport Test Layers

| Layer | Proves | Mechanism | Runs on |
| --- | --- | --- | --- |
| 1. Math and state | Camera, picking rays, snapping, gesture arbiter, tool routing, viewport state machine, invalidation reasons | Swift Testing in `MadeCoreTests`, no device | Everywhere, including hosted CI |
| 2. Offscreen goldens | The renderer draws the expected pixels for fixed scenes | `MetalRenderer` offscreen render compared to a stored PNG within a tolerance | Metal 4 only: hooks and local runs; hosted CI skips it |
| 3. In-app viewport E2E | Real input reaches the viewport, and its effects reach the panels | XCUITest coordinate clicks and drags on `viewport-canvas`, read back through the `viewport-probe` value | Metal 4 only: `make test-viewport` |
| 4. Invariant checks in E2E | Invariants 2 and 8 hold in the shipped app | Layer 3 assertions on probe fields | Metal 4 only: `make test-viewport` |
| Panel E2E | Menus, Navigator, Inspector, and the no-GPU state | XCUITest launched with `--force-no-gpu` | Everywhere, including hosted CI |

### 4. Layer 2: Offscreen Goldens

1. Reference golden images reside in `macos/Tests/Goldens/<Suite>/<test>.png`, outside the test target source paths. A shared test helper resolves golden files using `#filePath`.
2. Each golden scene fixes these parameters:
   - Dimensions: 800 by 600 pixels;
   - Camera preset;
   - Grid and axes settings;
   - Display mode;
   - Solid colors.
3. Reference scenes cover:
   - The default two-solid scene at the isometric preset;
   - A box in each display mode;
   - The selection outline;
   - The grid and axes alone.
4. Tolerance: A pixel comparison fails when any individual color channel differs by more than 8 out of 255. A test comparison fails when more than 0.1 percent of pixels fail. Issue #321 may adjust these thresholds and record the final values.
5. Recording workflow: Setting `MADE_RECORD_GOLDENS=1` writes the actual rendered image over the reference golden and records an issue, ensuring that a recording run never passes. A reviewer inspects the updated PNG in the pull request diff.
6. Diff output: On comparison failure, the test helper writes `actual.png`, `expected.png`, and `diff.png` to `macos/.build/golden-failures/`, and attaches them to the Swift Testing result.
7. Device check: Suites invoke `MTLCreateSystemDefaultDevice`, so existing git hooks execute them automatically on hardware supporting Metal.

### 5. Layer 3: Viewport Telemetry Probe

1. `CADMTKView` sets its accessibility identifier to `viewport-canvas`.
2. Exclusively when launched with `--ui-testing`, `CADMTKView` exposes `viewport-probe` as its accessibility value. The value consists of semicolon-joined `key=value` pairs.
3. Probe fields:
   - `state`: Current viewport lifecycle state.
   - `renders`, `draws`, `reason`: Telemetry counters and last invalidation reason from `RenderInstrumentation.shared`.
   - `selection`: Current selection identifier or empty.
   - `mode`: The active or last locked `GestureMode`.
   - `switches`: Count of mode switches within the last gesture.
   - `eye` and `target`: Camera position and focal target, rounded to 0.01 mm.
   - `hits`: Projected center coordinates of visible solids formatted as normalized viewport offsets.
4. The probe value updates after each draw. Setting the accessibility value does not invalidate the view, preserving Invariant 2.
5. Tests interact with the viewport via `coordinate(withNormalizedOffset:)` using offsets from `hits` instead of hardcoded screen points.
6. Viewport element screenshots at fixed window dimensions with coarse tolerance remain a parked follow-on slice (QA-VPT-04).

### 6. Layer 4: Invariants in End-to-End Tests

1. **Invariant 2 (On-demand rendering):** Following scene settlement, `renders` remains unchanged for 1 second with no incoming pointer or keyboard input.
2. **Invariant 8 (Navigation vs manipulation locking):** An orbit drag initiating on empty space and crossing over a solid updates `eye`, preserves `selection`, and reports `mode=navigate` with `switches=0`.

### 7. Gating Rules

1. GPU-only UI tests invoke `XCTSkipUnless` on a Metal 4 capability check.
2. `make test-viewport` sets `MADE_UI_REQUIRE_METAL4=1`, which converts skips into test failures.
3. Upon a clean pass, `make test-viewport` writes `macos/.build/viewport-pass/<tree-hash>`.
4. The pre-push git hook inspects the pass record whenever a push touches any of these four paths:
   - `macos/Sources/MadeApp/`
   - `macos/Sources/MadeCore/Viewport/`
   - `macos/Sources/MadeCore/Input/`
   - `macos/UITests/`
5. The pre-push hook runs no UI tests directly, avoiding keyboard and pointer focus disruption. Developers can bypass this check with `git push --no-verify`.

## Consequences

- **Hosted CI:** The `swift` job retains Layer 1 unit tests and `ShaderLibraryTests`. Layer 2 tests skip on hosted runners. A new `ui-tests` job builds the application with `make bundle` and executes Panel E2E tests with `--force-no-gpu` under a 20-minute timeout. Hosted CI does not execute Layer 3 or Layer 4 tests.
- **Git Hooks:** The pre-commit hook is unchanged. The pre-push hook adds the tree-hash pass-record verification. Hooks never launch XCUITest.
- **Local Development:** `make test-ui` and `make test-viewport` take system window focus and dispatch synthetic input. Developers must avoid typing or moving the pointer during test execution. Initial execution requires granting macOS Accessibility permissions and approving Automation Mode.
- **Bundle Script:** `scripts/bundle-app.sh` remains the sole assembly mechanism and must continue functioning in CI environments.
- **Issue Alignment:** Issue #321 is redefined as the Layer 2 golden implementation ticket (`BL-QA-06`) and depends on #549. Issue #550 implements the initial XCUITest harness (`QA-UITEST-01`).
- **Test Plan Updates:** `docs/test-plan.md` Table 1 updates the `E2E / UI` decision from pending to the layered strategy. Gating notes document Layers 3 and 4.
- **Accessibility Identifier Standard:** User interface elements follow the `<area>-<element>[-<id>]` naming convention, assigned as test slices require them.
