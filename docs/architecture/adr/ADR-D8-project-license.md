# ADR-D8: Project License

- **Status:** Accepted, 2026-10-12
- **Issue:** #145
- **Dependent decisions:** #146 (ADR-D4, 2D constraint solver), #147 (ADR-D5, CAE solver and mesher integration)

## Context

The repository had no LICENSE file. The license choice decides which third-party geometry, solver, and meshing code `made` can link, and how.

## Options Considered

1. A permissive license (MIT or Apache 2.0).
2. A copyleft license (GPLv3).
3. A proprietary license.

## Decision

`made` is released under the MIT License. The text is in [`LICENSE`](../../../LICENSE) at the repository root.

## Consequences

- MIT-licensed dependencies link without restriction. Euclid and Cadova are both MIT.
- LGPL-2.1 code, such as OpenCASCADE (OCCT) and OCCTSwift (#82), is compatible when it is dynamically linked. Users must be able to replace the LGPL library, and the app must ship its license and notices.
- GPL code cannot link into the `made` process. SolveSpace's solver (GPLv3) is therefore excluded for #146. FreeCAD planegcs (LGPL) is allowed under the same terms as OCCT.
- GPL solvers and meshers, such as CalculiX, run as separate executables driven by input files (#147). Bundling one still requires its license text and source offer.
- Each new dependency records its license in the pull request that adds it.
