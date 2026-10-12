# ADR-D8: Project License

- **Status:** Accepted, 2026-10-12
- **Issue:** #145
- **Dependent decisions:** #146 (ADR-D4, 2D constraint solver), #147 (ADR-D5, CAE solver and mesher integration)

## Context

The repository had no LICENSE file. The license choice decides which third-party geometry, solver, and meshing code `made` can link, and how.

## Options Considered

1. A permissive license (MIT or Apache 2.0). MIT was accepted first, then replaced on the same day. Under MIT, the LGPL OpenCASCADE kernel would have to stay a separately replaceable dynamic library.
2. A weak copyleft license (LGPL-2.1-or-later). OpenCASCADE (OCCT) and FreeCAD use this family.
3. A strong copyleft license (GPLv3).
4. A proprietary license.

## Decision

`made` is released under the GNU Lesser General Public License, version 2.1 or (at your option) any later version (SPDX `LGPL-2.1-or-later`). The text is in [`LICENSE`](../../../LICENSE) at the repository root.

Version 2.1 matches OCCT. The "or later" clause keeps LGPL-3.0 code compatible.

## Consequences

- MIT-licensed dependencies link without restriction. Euclid and Cadova are both MIT.
- LGPL-2.1 code, such as OCCT and OCCTSwift (#82), can link into `made` statically or dynamically. The `made` source stays available under the LGPL, so users can rebuild and relink the combined app. A static `OCCT.xcframework` is therefore acceptable.
- LGPL code from other projects, such as FreeCAD planegcs (#146), can link in process on the same terms.
- GPL code in process would make each distributed `made` binary subject to the GPL. SolveSpace's solver (GPLv3) is therefore excluded for #146, unless a later ADR accepts that.
- GPL solvers and meshers, such as CalculiX, run as separate executables driven by input files (#147). Bundling one still requires its license text and source offer.
- A binary release must ship the LGPL text and the license notices of every bundled library.
- Each new dependency records its license in the pull request that adds it.
