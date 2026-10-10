# Spatial Orientation & Coordinate Systems

Spatial orientation in `made` follows the engineering standard: **right-handed Z-up**. This convention is the single source of truth across the entire stack: kernel math, mesh vertices, Metal viewport cameras, transform gizmos, and STEP file exchange.

---

## The Convention

```
       +Z (Up)
        ▲
        │   +Y (Away / Depth)
        │  ▲
        │ /
        │/
        └──────────► +X (Right)
```

- **+X**: Right (width)
- **+Y**: Away / back into the scene (depth)
- **+Z**: Up towards the sky (height)
- **Handedness**: Right-handed ($+X \times +Y = +Z$).

---

## Zero-Permutation Pipeline

Many web and game engines use Y-up coordinates, forcing translators to swap $Y$ and $Z$ axes when communicating with engineering kernels. In `made`, **world space is kernel space**:

1. **Geometry Kernel (Euclid & OCCT)**:
   Generates primitives directly with $Z$ as the extrusion or height axis:
   - Box: $X = \text{width}$, $Y = \text{depth}$, $Z = \text{height}$.
   - Cylinder: Base lies on $XY$ plane, height extends along $+Z$.
2. **Metal 3 Viewport Pipeline**:
   The camera view matrix defines the up vector as $+Z$:
   ```swift
   let up = SIMD3<Float>(0, 0, 1)
   let viewMatrix = Matrix4x4.lookAt(eye: cameraEye, target: cameraTarget, up: up)
   ```
3. **Metal Clip Space (NDC)**:
   Metal Normalized Device Coordinates use a right-handed depth space where $Z \in [0, 1]$ (near = 0, far = 1):
   ```swift
   let projectionMatrix = Matrix4x4.perspective(
       fovyRadians: fov,
       aspectRatio: aspect,
       nearZ: 0.1,
       farZ: 1000.0
   )
   ```
   No runtime axis swapping or normal flipping occurs during tessellation or rendering.

---

## Related Documentation

- [`invariants.md`](./invariants.md) — The tenth convention (unnumbered)
- [`rendering.md`](./rendering.md) — Metal matrix transformations
- [`kernel.md`](./kernel.md) — Parametric primitive generation
