import { Plane, Sketch, type ExpectedSpec } from "made";

// Revolved V-groove pulley around the Z axis.
// Profile coordinates on Plane.XZ are [radius, z], with all radii > 0 to leave a central bore.
const boreRadius = 6;
const outerRadius = 24;
const grooveBottomRadius = 17;
const height = 16;

const pulley = Sketch(Plane.XZ)
  .polygon([
    [boreRadius, 0],
    [outerRadius, 0],
    [outerRadius, 4],
    [grooveBottomRadius, height / 2],
    [outerRadius, height - 4],
    [outerRadius, height],
    [boreRadius, height],
  ])
  .revolve(360, { slices: 36 });

export const expected: ExpectedSpec = {
  volume: 23213.29,
  area: 7251.32,
  bounds: {
    min: [-24, -24, 0],
    max: [24, 24, 16],
  },
  tolerance: 0.01,
};

export default pulley;
