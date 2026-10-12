# ADR-D8: Project License

- **Status:** Accepted, 2026-10-12
- **Issue:** #145
- **Dependent decisions:** #146 (ADR-D4, 2D constraint solver), #147 (ADR-D5, CAE solver and mesher integration)

## Context

`made` is a non-commercial hobby project, and releases are free. The license obligations below apply to distribution whether or not anyone pays. The repository had no LICENSE file. The license choice decides which third-party geometry, solver, and meshing code `made` can link, and how.

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
- GPL solvers and meshers, such as CalculiX and Gmsh, run as separate executables driven by input and result files (#147).
- Release builds bundle those executables in `MadeApp.app/Contents/Helpers/` (#413). Each one is signed and notarized, and ships with its license text. Each GPL binary also needs its corresponding source, published or offered in writing. The bundled GPL programs rule out the App Store for this build.
- A binary release must ship the LGPL text and the license notices of every bundled library.
- Each new dependency records its license in the pull request that adds it.

## Distribution Plan

The maintainer set this plan on 2026-10-12.

| Stage | Build | Dependencies | Updates |
| --- | --- | --- | --- |
| Mac MVP | Signed, notarized direct download (#254) | OCCT in process, and GPL solver and mesher binaries bundled as helpers (#413) | Manual. The user installs a newer download. |
| Longer term | App Store, on macOS and iPadOS (#419) | Swift reimplementations in `libs/` replace the incompatible dependencies | Through the App Store |

The longer-term stage depends on these issues:

- #414: a contributor license agreement (CLA), in place before the first outside pull request. Without one, contributed LGPL code cannot ship under App Store terms.
- #415: the `libs/` directory and its clean-room procedure. A port keeps the license of its source, so each reimplementation is written from published papers and specifications, with its references in `PROVENANCE.md`.
- #416 and #417: Swift replacements for the CAE solver and the volume mesher.
- #418 and #420 to #424: a Swift B-rep engine that replaces OCCT in App Store builds. The maintainer chose on 2026-10-12 to reimplement only the capabilities `made` needs: NURBS geometry and topology, tessellation, booleans, STEP AP214 and AP242, and fillet, chamfer, and shell. Sources may include papers, the ISO 10303 standards, and permissive projects such as Truck (Apache-2.0). OCCT source may not be used. The direct-download Mac build keeps OCCT, and both engines sit behind the kernel interface (invariant 4).
