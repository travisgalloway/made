# Coordinate convention: right-handed Z-up

`src/lib/viewport/orientation.ts` is the single source of truth. Read it before touching anything that positions, rotates, or aims.

## The convention

**Right-handed, Z-up.**

| Axis | Meaning | Direction        |
| ---- | ------- | ---------------- |
| X    | width   | right            |
| Y    | depth   | away from viewer |
| Z    | height  | up               |

"Front" is −Y. The ground plane is Z = 0. This matches AutoCAD, SketchUp, and Blender.

**Units are millimetres.** brepjs — and therefore OCCT — works in millimetres by convention: `box(40, 20, 10)` is a 40×20×10 mm box. wade applies no scale factor at the kernel boundary, so a three.js unit is a millimetre throughout the app, same as the coordinate axes above: one convention, chosen once, at the seam.

Read the exported constants rather than writing vectors inline:

```ts
export const WORLD_UP = new Vector3(0, 0, 1);
export const GROUND_NORMAL = new Vector3(0, 0, 1);
export const DEFAULT_VIEW_DIRECTION = new Vector3(1, -1, 0.6); // 3/4 view, front-right, above
```

## Why: world space _is_ kernel space

OCCT — and therefore brepjs — is right-handed Z-up. `box(width, depth, height)` puts height on Z.

three.js defaults to Y-up. Had we kept that, every mesh crossing the worker boundary would need a rotation applied, and every snap point read off the scene would need one un-applied, forever, at every call site.

By choosing Z-up for the world instead, **the two spaces are identical**. A kernel mesh mounts with zero rotation. A snap point can be handed to the kernel as-is. There is no conversion layer at the seam, and there never needs to be one.

The cost is paid once, at the boundary with three.js, and is audited below.

## The bug that produced this doc

Issues #61 / #62, fixed in `0aa820c`.

No convention had ever been _chosen_ — the app simply inherited three.js's Y-up default while the kernel was Z-up. The visible symptom: **the Height slider rendered as a horizontal beam**, and the cylinder lay on its side.

The instructive part is why it survived so long. The geometry was _always correct_ — the kernel produced exactly the right vertices. The error lived in the **camera's idea of up**. That means no world-space assertion could ever have caught it, which is why the regression suite (`e2e/orientation.e2e.ts`, its own Playwright project) asserts through `window.__wade.projectToNdc` — a projection into screen space — and through `boxExtents[2]`, the one world-space number that tracks the Height parameter.

## `installZUpWorld()` must run at module scope

```ts
export function installZUpWorld(): void; // sets Object3D.DEFAULT_UP
```

**Call it at module or script scope — never inside an `$effect`.** `Object3D.DEFAULT_UP` is copied into each object's own `up` at _construction_ time. Running it after the camera exists leaves a Y-up camera sitting in a Z-up world, which is precisely the original bug.

It is idempotent, so calling it from more than one module is safe.

## The three.js defaults that fight this

Each is corrected exactly once, at the boundary. Do not scatter these fixes.

| What               | Authored as    | Correction                                                      |
| ------------------ | -------------- | --------------------------------------------------------------- |
| `GridHelper`       | XZ plane       | Mounted with `rotation={[Math.PI / 2, 0, 0]}` in `Scene.svelte` |
| `CylinderGeometry` | Y-axis aligned | `rotateX(Math.PI / 2)` **on the geometry** in `instancing.ts`   |
| `HemisphereLight`  | shines from +Y | Rotated in `Scene.svelte`                                       |
| Sample STL         | Y-up           | `geometry.rotateX(Math.PI / 2)` at load in `sampleMesh.ts`      |

Note the `CylinderGeometry` case: the rotation is baked into the _geometry_, not into each instance. That keeps every instance transform a plain translation — which matters, because instance matrices are per-object and geometry is shared.

## Related

- [`rendering.md`](./rendering.md) — `window.__wade.projectToNdc` and why it exists
- [`input.md`](./input.md) — `snapping.ts` builds its ground plane from `GROUND_NORMAL`
- [`invariants.md`](./invariants.md#a-tenth-convention-unnumbered) — why this is a named convention rather than invariant 10
