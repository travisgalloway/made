import { Box, Cylinder, type ExpectedSpec } from "made";

// Eval 01: 60x40x6 mm rectangular mounting plate sitting on the XY plane
// (min corner at [0, 0, 0], max at [60, 40, 6]) with a central 16 mm diameter
// through-hole at [30, 20] and four 6 mm diameter corner mounting holes inset
// 8 mm from each edge.
const plate = Box(60, 40, 6, { center: false });

const centerHole = Cylinder(8, 10, { slices: 32 }).translate(30, 20, 3);
const cornerHole1 = Cylinder(3, 10, { slices: 24 }).translate(8, 8, 3);
const cornerHole2 = Cylinder(3, 10, { slices: 24 }).translate(52, 8, 3);
const cornerHole3 = Cylinder(3, 10, { slices: 24 }).translate(8, 32, 3);
const cornerHole4 = Cylinder(3, 10, { slices: 24 }).translate(52, 32, 3);

export const expected: ExpectedSpec = {
  volume: 12525.0,
  area: 6080.0,
  bounds: {
    min: [0, 0, 0],
    max: [60, 40, 6],
  },
  tolerance: 0.01,
};

export default plate.subtract(
  centerHole,
  cornerHole1,
  cornerHole2,
  cornerHole3,
  cornerHole4
);
