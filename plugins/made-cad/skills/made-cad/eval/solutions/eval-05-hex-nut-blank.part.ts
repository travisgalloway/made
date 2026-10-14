import { Cylinder, Plane, Sketch, type ExpectedSpec } from "made";

// Eval 05: Hexagonal nut blank extruded from a regular hexagon of circumradius 14 mm
// (6 sides) on the XY plane to a height of 10 mm (Z from 0 to 10), with a central
// 12 mm diameter bore along the Z axis.
const hexBody = Sketch(Plane.XY).regularPolygon(14, 6).extrude(10);
const bore = Cylinder(6, 14, { slices: 36 }).translate(0, 0, 5);

export const expected: ExpectedSpec = {
  volume: 3960.0,
  area: 2009.91,
  bounds: {
    min: [-14, -12.124356, 0],
    max: [14, 12.124356, 10],
  },
  tolerance: 0.01,
};

export default hexBody.subtract(bore);
