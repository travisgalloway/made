# ADR-D8: Project License

- **Status:** Accepted, 2026-10-12
- **Issue:** #145
- **Dependent decisions:** #146 (ADR-D4, 2D constraint solver), #147 (ADR-D5, CAE solver and mesher integration), #418 (OCCT in App Store builds)

## Context

`made` is a non-commercial hobby project, and releases are free. The license obligations below apply to distribution whether or not anyone pays. The repository had no LICENSE file. The license choice decides which third-party geometry, solver, and meshing code `made` can link, and how. The project plans a direct-download Mac release first and App Store releases on macOS and iPadOS later.

## Options Considered

1. MIT. Accepted first on 2026-10-12, then replaced the same day.
2. LGPL-2.1-or-later. Accepted second, then replaced the same day. Code contributed under the LGPL would have needed a contributor license agreement (CLA) before it could ship under App Store terms.
3. GPLv3. Rejected, because it would exclude the App Store and closed programs that use `made`.
4. MPL-2.0. Accepted.

## Decision

`made`'s own code is released under the Mozilla Public License, version 2.0 (SPDX `MPL-2.0`). The text is in [`LICENSE`](../../../LICENSE) at the repository root.

MPL-2.0 is a file-level copyleft. Changes to `made`'s own files stay open source, and larger works that use `made` may use other licenses. VLC for iOS uses the same model, with an MPL-2.0 app and LGPL libraries on the App Store.

## Consequences

- MIT-licensed dependencies link without restriction. Euclid and Cadova are both MIT.
- LGPL-2.1 libraries, such as OCCT and OCCTSwift (#82), link into the app statically or dynamically. The public source and build instructions (#426) let users rebuild `made` with a modified library, which satisfies the LGPL relinking requirement.
- Prefer LGPL-2.1 dependencies to LGPL-3.0. LGPLv3 requires installation information that is hard to provide on iOS.
- LGPL code from other projects, such as FreeCAD planegcs (#146), links on the same terms.
- GPL code must not link into the app. SolveSpace's solver (GPLv3) is therefore excluded for #146.
- GPL solvers and meshers, such as CalculiX and Gmsh, run as separate executables driven by input and result files (#147).
- Each build shows an in-app "Open Source Licenses" window with the exact license text and copyright notice of every bundled component (#425).
- Each new dependency records its license in the pull request that adds it.

### Remaining App Store risk

LGPL-2.1 section 10 forbids imposing further restrictions on recipients, and Apple's usage rules arguably do. Public source does not resolve that conflict. Apps such as VLC ship LGPL libraries on the App Store anyway, and enforcement depends on the copyright holder objecting. #418 decides whether App Store builds keep OCCT or use the Swift B-rep engine (#420 to #424).

## Distribution Plan

The maintainer set this plan on 2026-10-12.

| Stage | Build | Dependencies | Updates |
| --- | --- | --- | --- |
| Mac MVP | Signed, notarized direct download (#254) | OCCT in the app, and GPL solver and mesher programs bundled in `MadeApp.app/Contents/Helpers/` (#413) | Manual. The user installs a newer download. |
| Longer term | App Store, on macOS and iPadOS (#419) | OCCT in the app, and Swift solver and mesher packages in `libs/` in place of the GPL programs | Through the App Store |

The bundled GPL programs in the Mac MVP each ship with their license text and a source offer. They rule out the App Store for that build, and iOS cannot start other programs.

The longer-term stage depends on these issues:

- #415: the `libs/` directory and its clean-room procedure. A port keeps the license of its source, so each reimplementation is written from published papers and specifications, with its references in `PROVENANCE.md`.
- #416 and #417: Swift replacements for the CAE solver and the volume mesher.
- #418: whether App Store builds keep OCCT. Keeping OCCT is the primary option. The Swift B-rep engine (#420 to #424) is the fallback if the LGPL risk becomes a problem. Its sources may include papers, the ISO 10303 standards, and permissive projects such as Truck (Apache-2.0). OCCT source may not be used.
- #425 and #426: the license window and the build-from-source guide.

A CLA (#414) is no longer required, because contributions under MPL-2.0 can ship under App Store terms.
