# Exchange Test Corpus

This directory contains reference CAD exchange models for STEP, IGES, and STL regression verification. Each file exercises kernel geometry import, boundary representation measurement, unit normalization, and expected failure handling.

## Model Catalog and Provenance

| Filename | Format | Source Unit | License | Description and Provenance |
|---|---|---|---|---|
| `nist_ftc06_prismatic.step` | STEP AP203/AP214 | mm | CC0-1.0 | Stepped prismatic benchmark derived from NIST CAx-IF Form Feature Test Case 06 (FTC-06). Features a base block of 60x40x30 mm with a 30x40x15 mm rectangular step cutout. |
| `cube_inches.step` | STEP AP203 | in | CC0-1.0 | Unit cube reference model authored with 1.0x1.0x1.0 inch extents to verify linear and volumetric imperial-to-metric unit scaling. |
| `cylinder_metric.iges` | IGES 5.3 | mm | CC0-1.0 | Metric right circular cylinder with radius of 10 mm and height of 20 mm in B-Rep representation. |
| `box_metric_ascii.stl` | ASCII STL | mm | CC0-1.0 | Metric 10x10x10 mm box consisting of 12 planar triangular facets with outward normal vectors. |
| `wedge_inches_binary.stl` | Binary STL | in | CC0-1.0 | Right triangular prism wedge with 1.0x1.0x1.0 inch bounds consisting of 8 binary-encoded triangular facets. |
| `unsupported_ap242_pmi.step` | STEP AP242 | mm | CC0-1.0 | STEP AP242 semantic Product and Manufacturing Information (PMI) reference file tracking expected failure issue #403. |

## Licensing

All corpus models in this directory are released under Creative Commons Zero v1.0 Universal (CC0-1.0) Public Domain Dedication.
