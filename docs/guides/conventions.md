# Engineering Conventions

This document outlines the coding standards, concurrency conventions, and commit policies for `made`.

---

## 1. Swift 6 Concurrency & Type Safety

`made` compiles with Swift 6 strict concurrency checking enabled (`-swift-version 6`).

### Sendable Conformance
- Every struct, enum, or class that crosses an actor or task boundary **must** conform to `Sendable`.
- Avoid mutable reference types in asynchronous signatures. Prefer immutable value types (`struct`).
- Where SDK types lack formal Sendable annotations (e.g., `MTLBuffer` pointers in MetalKit), annotate wrapping structs as `@unchecked Sendable` only after verifying thread-safety invariants by review.

### MainActor vs Background Actors
- Presentation views, gesture handling, and `@Observable DocumentModel` belong on `@MainActor`.
- Math-heavy, tessellation, and I/O tasks execute in background Actors (`KernelClient`).
- Use `await withCheckedContinuation` for adapting legacy asynchronous delegate APIs, and never use blocking waits (`cmdBuffer.waitUntilCompleted()`) inside asynchronous Swift contexts.

---

## 2. Dependency Discipline

- **`MadeCore` is lean by design.**
  - `nicklockwood/Euclid` (0.9.6) is the single core dependency for pure-Swift CSG geometry.
  - No bloated third-party packages for geometry or networking.
  - Standard Apple frameworks are preferred: `MetalKit`, `simd`, `ImageIO`, `UniformTypeIdentifiers`.
- **C++ Framework Boundaries**:
  - The OpenCASCADE integration (`OCCTSwift`) is isolated behind a dedicated framework module. It must never leak raw OpenCASCADE symbols into the SwiftUI presentation layer.

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

- [`invariants.md`](../architecture/invariants.md) — The nine non-negotiable rules
- [`testing.md`](./testing.md) — Unit test structure
