import { Box, Cylinder, param, type ExpectedSpec } from "made";

const baseWidth = param("baseWidth", 60, { min: 30, max: 120, step: 5, label: "Base Width" });
const depth = param("depth", 40, { min: 20, max: 80, step: 5, label: "Bracket Depth" });
const thickness = param("thickness", 8, { min: 4, max: 16, step: 1, label: "Wall Thickness" });
const wallHeight = param("wallHeight", 45, { min: 25, max: 90, step: 5, label: "Wall Height" });
const holeRadius = param("holeRadius", 4, { min: 2, max: 8, step: 0.5, label: "Mount Hole Radius" });

// Horizontal base plate sitting on Z = 0, extending [0..baseWidth, 0..depth, 0..thickness]
const basePlate = Box(baseWidth, depth, thickness, { center: false });

// Vertical back wall sitting on X = 0, extending [0..thickness, 0..depth, 0..wallHeight]
const verticalWall = Box(thickness, depth, wallHeight, { center: false });

// Two mounting holes through the horizontal base plate along Z
const baseHole1 = Cylinder(holeRadius, thickness + 4, { slices: 32 }).translate(
  baseWidth - 15,
  12,
  thickness / 2
);
const baseHole2 = Cylinder(holeRadius, thickness + 4, { slices: 32 }).translate(
  baseWidth - 15,
  depth - 12,
  thickness / 2
);

// Single centered mounting hole through the vertical wall along X
const wallHole = Cylinder(holeRadius, thickness + 4, { slices: 32 })
  .rotateY(90)
  .translate(thickness / 2, depth / 2, wallHeight - 14);

export const expected: ExpectedSpec = {
  volume: 29841.37,
  area: 10254.56,
  bounds: {
    min: [0, 0, 0],
    max: [60, 40, 45],
  },
  tolerance: 0.01,
};

export default basePlate
  .union(verticalWall)
  .subtract(baseHole1, baseHole2, wallHole);
