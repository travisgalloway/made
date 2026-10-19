# ADR-D7: .made Document Encoding

- **Status:** Accepted, 2026-10-14
- **Issue:** #149
- **Implemented by:** #83 (native `.made` document via `FileDocument`), #427 (part file reload), #376 (BL-VER-01, git-friendly package layout), #237 (BL-FND-10, schema versioning and migration), #238 (BL-FND-11, document settings), #172 (BL-FND-14, custom properties and metadata), #174 (BL-PAR-01, document parameters table), #160 (BL-FND-15, embedded and linked external references), #161 (BL-ASM-01, assembly document type), #241 (BL-FND-16, crash recovery), #248 (BL-MAC-02, Quick Look preview and thumbnail extensions), #249 (BL-MAC-03, Spotlight indexing), #252 (BL-MAC-08, iCloud documents and Handoff), #377 (BL-VER-02, named versions), #563 (package-relative part and asset paths)

## Context

`made` has no document persistence today. A saved `.made` document must hold the scene graph and feature history, document parameters and settings, TypeScript part source files ([ADR-D6](./ADR-D6-scripting-runtime.md), #148), imported geometry assets such as STEP and IGES files (#38), and derived geometry and simulation outputs (B-rep shapes, tessellated display meshes, thumbnails, and CAE results).

Two workflows set the requirements for the on-disk format:

1. In the Mac MVP, external agents edit `.part.ts` and `.part.js` source files directly on disk, and the open document window watches those files and rebuilds the model when a file is saved (#427). Part source files must therefore remain plain UTF-8 text on the file system, inside a `.made` document package or as standalone files beside it.
2. Users and agents track `.made` documents in Git (#376, BL-VER-01). Manifests, features, parameters, and part source files must produce readable line diffs with stable ordering, while binary caches must be safe to ignore and rebuild.

## Options Considered

1. **A directory package (`FileWrapper` bundle) containing JSON metadata, plain-text part sources, imported assets, and a regenerable binary cache directory.** Accepted. Finder, iPadOS Files, and SwiftUI `DocumentGroup` present the `.made` directory as a single document (`com.made.cad.document`, conforming to `com.apple.package`), while external agents, text editors, and Git read and write the files inside as an ordinary directory.
2. **A single SQLite database file.** Rejected, because a binary database cannot be diffed or merged as plain text in Git (#376), and external agents and editors cannot edit `.part.ts` source files in place (#427) without an extraction and import step.
3. **A single binary archive (such as a ZIP container or a custom binary stream).** Rejected, because a compressed or opaque container hides `.part.ts` files from external agents and file watchers (#427) and turns every save into a binary diff in Git (#376).

## Decision

A `.made` document is a directory package with Uniform Type Identifier `com.made.cad.document` (conforming to `com.apple.package` and `public.composite-content`), read and written through SwiftUI `FileDocument` / `ReferenceFileDocument` and `FileWrapper` (#83). For single-part workflows, `made` can also open and watch a standalone `.part.ts` or `.part.js` file directly without wrapping it in a `.made` package (#427).

### Package Layout

```
MyBracket.made/
  manifest.json        # schema version (#237), document settings (#238), custom metadata (#172)
  document.json        # canonical feature list (#562), parameter table (#174), assembly instances (#161)
  parts/
    bracket.part.ts    # plain-text TypeScript or JavaScript part sources (ADR-D6, #435, #427)
  assets/
    housing.step       # embedded STEP/IGES imports and linked-reference descriptors (#38, #160)
  cache/               # regenerable binary artifacts, ignored by Git (#376)
    brep/              # cached B-rep shapes keyed by content hash
    meshes/            # cached display tessellations
    results/           # cached CAE meshes and solver outputs
    thumbnail.png      # Quick Look and Finder thumbnail (#248)
```

- **Manifest (`manifest.json`).** Records `schemaVersion` (an integer starting at `1`), the writing application version, per-document units and tolerances (#238), and custom properties (#172). Opening an older schema version runs forward migrations in memory before constructing the document model (#237). Opening a newer schema version fails with a clear error message and leaves the open document and the file on disk unchanged (#83, #237).
- **Document definition (`document.json`).** Records the ordered feature list as the sole canonical owner of scene geometry (#562), parameter table (#174), and assembly component instances (#161), referencing scripted parts in `parts/` and imported geometry in `assets/` by relative path and stable ID. When `features` is present, derived scene `objects` and `bodies` are omitted from disk serialization. Decoding a document with explicit `objects` or `bodies` validates that they match the active features projection, throwing `DecodingError.dataCorrupted` on mismatch.
- **Canonical JSON formatting.** `manifest.json` and `document.json` are encoded as UTF-8 with 2-space indentation, lexicographically sorted keys (`JSONEncoder.OutputFormatting` with `.prettyPrinted`, `.sortedKeys`, and `.withoutEscapingSlashes`), and a trailing newline (#376). Collections serialize in deterministic order (tree order for objects and features, and stable ID order for maps and parameter tables) so saving an unchanged document produces an identical byte sequence.
- **Plain-text part source files (`parts/*.part.ts`, `parts/*.part.js`).** Each scripted part lives as an uncompressed UTF-8 file under `parts/`, or as a standalone `.part.ts` / `.part.js` file when working outside a package ([ADR-D6](./ADR-D6-scripting-runtime.md), #435, #427). External agents edit these files directly, and `PartRuntime` resolves relative ES module imports only within the part's directory (ADR-D6).
- **Assets (`assets/`).** Imported STEP and IGES files (#38) and external reference descriptors (#160) live under `assets/` with deterministic filenames.
- **Regenerable binary caches (`cache/`).** B-rep caches (`cache/brep/`), display meshes (`cache/meshes/`), simulation outputs (`cache/results/`), and `cache/thumbnail.png` (#248) are derived from `manifest.json`, `document.json`, `parts/`, and `assets/`. Deleting `cache/` never loses design data. When a cache entry is missing or its content hash does not match the source definition, `made` rebuilds the geometry through `KernelClient` (invariant 1). `made` writes `cache/.gitignore` containing `*` so Git ignores all files in `cache/` by default (#376).

## Consequences

- **Direct agent file editing and live reload (#427, #428, #429).** Because `.made` is an ordinary directory on disk and `parts/*.part.ts` are plain UTF-8 files, external agents edit part files with standard file tools and run `tsc --noEmit` against `made.d.ts` in place (ADR-D6). The open window watches `parts/` and `document.json` for file-system saves, coalesces rapid writes with the 60-ms debounce window, and evaluates updated shapes off the main thread through `KernelClient` (invariants 1, 2, and 7). A failed reload keeps the last valid model visible in the viewport and reports the file, line, and column in the console drawer and over MCP (#427, #428).
- **Git-friendly diffs and merges (#376, #378, #379).** Sorted JSON keys, 2-space indentation, plain-text `.part.ts` sources, and the ignored `cache/` directory keep Git diffs limited to the lines that changed. Visual diff (#378) and branch-and-merge workflows (#379) read `document.json` and `parts/` directly.
- **Kernel-independent persistence.** Because `manifest.json`, `document.json`, `parts/`, and `assets/` store the authoritative design and `cache/` is disposable, documents survive changes to the underlying geometry engine (Euclid today, OCCT in #82, or the Swift B-rep engine in #418) by rebuilding `cache/brep/` and `cache/meshes/` through `KernelClient` (invariant 4).
- **Incremental package writes, autosave, and crash recovery (#83, #241, #377).** `FileWrapper` directory packages integrate with macOS Autosave, Versions (#377), and crash recovery (#241) through `NSFileCoordinator`. Saving an edit updates only the changed JSON or part files without rewriting unmodified `assets/` or `cache/` blobs.
- **Finder, Spotlight, and iCloud integration (#248, #249, #252, #84).** Quick Look extensions (#248) serve `cache/thumbnail.png` and `cache/meshes/` without launching the geometry kernel. Spotlight (#249) indexes `manifest.json`, `document.json`, and `parts/` directly. iCloud Drive (#252) syncs the package across macOS and iPadOS (#84).
- **Architectural invariants hold unchanged.** Document file I/O parses JSON and reads source files off the rendering path, and all geometry regeneration triggered by opening or reloading a document runs asynchronously in `KernelClient` (invariants 1, 3, 4, and 7).
