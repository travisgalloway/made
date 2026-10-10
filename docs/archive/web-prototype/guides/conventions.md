# Conventions

## Code

- **Prefer many small, single-purpose files over few large ones.** Keep every component small.
- **The invariants are cited by number in comments.** When you write code that upholds one, say which — `(invariant 2)`, `per architecture invariant 8`. That is what makes the [invariant list](../architecture/invariants.md) a living contract rather than a document nobody opens. It also means **the numbers can never be reassigned**; see that doc.
- **Comments explain _why_, especially why an alternative was rejected.** This codebase leans on that heavily — `vite.config.ts`, `playwright.config.ts`, and `eslint.config.js` all carry comments explaining what breaks if you "clean them up". Read them before editing them.

## Dependencies

- **pnpm for installs** (`pnpm@10.14.0`). Never npm or yarn to install dependencies. (The one exception is `playwright.config.ts`'s `webServer`, which shells out to `npm run build && npm run preview` — a self-contained test harness detail, not a project install path.)
- **Node >= 24 is a hard requirement.** `brepjs@18` declares it and `.npmrc` sets `engine-strict=true`, so the wrong Node version fails `pnpm install` outright. `.nvmrc` pins it.
- **Before installing any dependency, check its current version and API** rather than trusting a version pinned in these docs. Versions here are guidance, not gospel.

## Commits

```
<type>(<scope>): <description> (#issue) (#PR)
```

The trailing `(#N)` is the **PR**; earlier `(#N)` references are the **issues**. Commits inside a PR carry only issue numbers — the PR number does not exist yet — and the squash-merge subject appends it.

Real examples:

```
feat(input): vertex/edge/grid snapping foundation (#27) (#60)
feat(kernel): Phase 2 kernel core — OCCT worker, transferable meshes, KernelClient (#22, #23, #24) (#58)
fix: Viewport up-axis disagrees with the kernel: Height renders horizontally (#62)
chore: Add CI (GitHub Actions) (#52)
```

- **Types in use:** `feat`, `fix`, `docs`, `test`, `chore`, `ci`.
- **Scopes in use:** `kernel`, `viewport`, `input`, `infra`. Scope is optional.
- **Bodies are explanatory prose, not bullet dumps.** The house style: state what changed, **name the invariant the change upholds**, explain why the alternatives were rejected, and describe how it was verified. "Reintroduced the bug and watched the test fail" is a normal thing to write here.

Keep commits small within a phase, and commit at the end of each phase. See [`../roadmap/phases.md`](../roadmap/phases.md).

## Formatting

Prettier and ESLint, both run by `pnpm lint` in CI. Tabs, single quotes, no trailing commas, 100-column print width.

`docs/` **is** Prettier-checked — these files are authored, not imported verbatim, so they are held to the same standard as the rest of the repo.

## Load-bearing config you should not "simplify"

Three settings in `vite.config.ts` exist for occt-wasm and each is commented in place. Removing any one breaks the WASM load:

- `worker: { format: 'es' }` — Vite's classic/IIFE worker output cannot `import` the WASM asset URL at all.
- `optimizeDeps: { exclude: ['occt-wasm'] }` — esbuild's dep pre-bundling rewrites the emscripten glue in ways that break it.
- `build: { target: 'esnext' }` — the WASM features and top-level await it relies on need a modern target.
