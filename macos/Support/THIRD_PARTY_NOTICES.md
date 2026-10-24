# Third-Party Notices and Open Source Licenses

This document contains licensing notices, copyright statements, and source distribution offers for third-party software components included with `made`.

## Component Inventory

| Component | Version | License | SPDX Identifier | Copyright | Homepage |
| --- | --- | --- | --- | --- | --- |
| made | 0.1.0 | Mozilla Public License 2.0 | `MPL-2.0` | Copyright (C) 2026 Travis Galloway | https://github.com/travisgalloway/made |
| Euclid | 0.9.6 | MIT License | `MIT` | Copyright (c) 2018 Nick Lockwood | https://github.com/nicklockwood/Euclid |
| OCCTSwift | 3.0.0 | GNU Lesser General Public License v2.1 | `LGPL-2.1-only` | Copyright (c) 2024-2026 SecondMouseAU | https://github.com/SecondMouseAU/OCCTSwift |
| CalculiX (ccx) | 2.21 | GNU General Public License v2.0 or later | `GPL-2.0-or-later` | Copyright (C) 1998-2023 Guido Dhondt | https://github.com/Dhondtguido/CalculiX |
| Gmsh | 4.13.1 | GNU General Public License v2.0 or later | `GPL-2.0-or-later` | Copyright (C) 1997-2024 Christophe Geuzaine and Jean-Francois Remacle | https://gmsh.info |

## Written Offer for Corresponding Source Code

Certain components distributed alongside `made` are licensed under the GNU Lesser General Public License version 2.1 (LGPL-2.1) or the GNU General Public License version 2.0 or later (GPL-2.0-or-later).

CalculiX (`ccx`) and Gmsh (`gmsh`) are distributed as independent helper executable programs inside `Made.app/Contents/Helpers/`. They operate as isolated external subprocesses exchanging data via input decks and result files on disk, constituting mere aggregation under Section 2 of GPL-2.0.

In accordance with Section 3(b) of the GNU General Public License version 2.0 and Section 3 of the GNU Lesser General Public License version 2.1, the distributors of `made` offer to provide any third party a complete machine-readable copy of the corresponding source code for the bundled versions of CalculiX (`ccx`), Gmsh (`gmsh`), and OCCTSwift, for a period of at least three years from the date of release distribution.

Corresponding source code is publicly accessible at the following repository locations:
- CalculiX (`ccx` 2.21): https://github.com/Dhondtguido/CalculiX
- Gmsh (4.13.1): https://gitlab.onelab.info/gmsh/gmsh
- OCCTSwift (3.0.0): https://github.com/SecondMouseAU/OCCTSwift
- Made: https://github.com/travisgalloway/made

Instructions for compiling, verifying, and replacing these components are documented in the build guide:
https://github.com/travisgalloway/made/blob/main/docs/guides/building-from-source.md

## Component Licenses

### Euclid

```text
MIT License

Copyright (c) 2018 Nick Lockwood

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### OCCTSwift

Licensed under the GNU Lesser General Public License version 2.1.
Full license text is available in `Made.app/Contents/Resources/MadeNative_MadeCore.bundle/Resources/OCCTSwift-LGPL-2.1.txt` and online at:
https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html

### CalculiX (ccx)

Licensed under the GNU General Public License version 2.0 or later.
Full license text is available in `Made.app/Contents/Resources/MadeNative_MadeCore.bundle/Resources/CalculiX-GPL-2.0.txt` and online at:
https://www.gnu.org/licenses/old-licenses/gpl-2.0.html

### Gmsh

Licensed under the GNU General Public License version 2.0 or later.
Full license text is available in `Made.app/Contents/Resources/MadeNative_MadeCore.bundle/Resources/Gmsh-GPL-2.0.txt` and online at:
https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
