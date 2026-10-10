# Engineering Conventions

This document outlines the coding standards, concurrency conventions, and commit policies for `made`.

## Commands

Run every command from the `macos/` directory:

```sh
cd macos
swift build
swift test
swift test --filter <TestClass>
swift run MadeApp
swift run MadeApp --mcp-stdio
```

The `pnpm` commands in the repository root belong to the archived web prototype (`src/`, `e2e/`). They do not build or test the native application.

---

---

## 1. Swift 6 Concurrency & Type Safety

`macos/Package.swift` sets `swift-tools-version: 6.0`, which selects the Swift 6 language mode and its concurrency checking.

### Sendable Conformance
- Every struct, enum, or class that crosses an actor or task boundary **must** conform to `Sendable`.
- Avoid mutable reference types in asynchronous signatures. Prefer immutable value types (`struct`).
- Where SDK types lack formal Sendable annotations (e.g., `MTLBuffer` pointers in MetalKit), annotate wrapping structs as `@unchecked Sendable` only after verifying thread-safety invariants by review.

### MainActor vs Background Actors
- Target: presentation views, gesture handling, and `@Observable DocumentModel` belong on `@MainActor`. Today only the two `Coordinator` classes carry `@MainActor`; `DocumentModel`, `GestureArbiter`, and `PointerRouter` are `@unchecked Sendable` (#91).
- Math-heavy and tessellation tasks execute in the `KernelClient` actor.
- Use `await withCheckedContinuation` for adapting legacy asynchronous delegate APIs, and never use blocking waits (`cmdBuffer.waitUntilCompleted()`) inside asynchronous Swift contexts.

---

## 2. Dependency Discipline

- **`MadeCore` is lean by design.**
  - `nicklockwood/Euclid` (0.9.6) is the single core dependency for pure-Swift CSG geometry.
  - No bloated third-party packages for geometry or networking.
  - Standard Apple frameworks are preferred: `MetalKit`, `simd`, `ImageIO`, `UniformTypeIdentifiers`.
- **C++ Framework Boundaries**:
  - Planned (#82): the OpenCASCADE integration (`OCCTSwift`) will sit behind a dedicated framework module. It must not leak raw OpenCASCADE symbols into the SwiftUI presentation layer. `Package.swift` does not declare it yet.

---

## 3. The 9 Architectural Invariants

- **The numbers are permanent.** Comments and unit tests cite invariants by number (1 to 9). Never renumber existing invariants.
- If a proposed feature appears to require violating an invariant, stop and document the trade-off rather than introducing workarounds.

---

## 4. Conventional Commits

Commits must follow the Conventional Commits specification:

```
<type>(<scope>): <short description> (#<issue>)

[optional body explaining design rationale]
```

### Allowed Types
- `feat`: A new user-facing or agent-facing capability.
- `fix`: A bug fix or regression remediation.
- `refactor`: Code changes that neither fix a bug nor add a feature.
- `docs`: Documentation updates in `docs/` or README files.
- `test`: Adding or correcting tests.
- `perf`: Performance optimization.

---

## Related Documentation

- [`invariants.md`](../architecture/invariants.md): The nine non-negotiable rules
- [`testing.md`](./testing.md): Unit test structure
