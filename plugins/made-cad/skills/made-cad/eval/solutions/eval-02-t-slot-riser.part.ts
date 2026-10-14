import { Cylinder, Plane, Sketch, type ExpectedSpec } from "made";

// Eval 02: T-shaped riser block extruded 30 mm along Y (centered) from an XZ profile
// (base 40x8 mm from Z = 0..8, upright web 12 mm wide reaching Z = 28),
// with two 6 mm diameter mounting holes through the base flanges at X = +/-14, Y = 0.
const profile = Sketch(Plane.XZ).polygon([
  [-20, 0],
  [20, 0],
  [20, 8],
  [6, 8],
  [6, 28],
  [-6, 28],
  [-6, 8],
  [-20, 8],
]);

const riser = profile.extrude(30, { centered: true });

const leftMountHole = Cylinder(3, 12, { slices: 24 }).translate(-14, 0, 4);
const rightMountHole = Cylinder(3, 12, { slices: 24 }).translate(14, 0, 4);

export const expected: ExpectedSpec = {
  volume: 16350.0,
  area: 5388.92,
  bounds: {
    min: [-20, -15, 0],
    max: [20, 15, 28],
  },
  tolerance: 0.01,
};

export default riser.subtract(leftMountHole, rightMountHole);
