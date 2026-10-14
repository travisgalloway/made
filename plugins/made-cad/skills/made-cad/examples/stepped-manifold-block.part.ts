import { Box, Cone, Cylinder, Sphere, intersect, subtract, union, type ExpectedSpec } from "made";

// Stepped manifold block demonstrating functional CSG (union, subtract, intersect)
// and all 3D primitives (Box, Cylinder, Sphere, Cone).
const block = Box(50, 36, 24, { center: [0, 0, 12] });
const boundingSphere = Sphere(34, { slices: 32, center: [0, 0, 12] });

// Chamfered block body via intersection with a sphere
const body = intersect(block, boundingSphere);

// Top port boss + conical funnel entry
const topBoss = Cylinder(10, 6, { slices: 32, center: [0, 0, 27] });
const funnelCut = Cone(7, 4, { slices: 32, center: [0, 0, 28.5] });

// Vertical and horizontal intersecting fluid passages
const verticalPassage = Cylinder(5, 36, { slices: 32, center: [0, 0, 15] });
const crossPassage = Cylinder(5, 60, { slices: 32 })
  .rotateY(90)
  .translate(0, 0, 12);

export const expected: ExpectedSpec = {
  volume: 39449.81,
  area: 10028.86,
  bounds: {
    min: [-25, -18, 0],
    max: [25, 18, 30],
  },
  tolerance: 0.01,
};

export default subtract(
  union(body, topBoss),
  verticalPassage,
  crossPassage,
  funnelCut
);
