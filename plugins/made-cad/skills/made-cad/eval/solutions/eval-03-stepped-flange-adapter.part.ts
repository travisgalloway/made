import { Plane, Sketch, type ExpectedSpec } from "made";

// Eval 03: Revolved stepped flange adapter around the Z axis:
// - 40 mm diameter (R = 20), 6 mm tall base flange from Z = 0 to Z = 6
// - 24 mm diameter (R = 12), 18 mm tall hub from Z = 6 to Z = 24
// - concentric 12 mm diameter (R = 6) through-bore from Z = 0 to Z = 24
const adapter = Sketch(Plane.XZ)
  .polygon([
    [6, 0],
    [20, 0],
    [20, 6],
    [12, 6],
    [12, 24],
    [6, 24],
  ])
  .revolve(360, { slices: 36 });

export const expected: ExpectedSpec = {
  volume: 12900.0,
  area: 5300.0,
  bounds: {
    min: [-20, -20, 0],
    max: [20, 20, 24],
  },
  tolerance: 0.01,
};

export default adapter;
