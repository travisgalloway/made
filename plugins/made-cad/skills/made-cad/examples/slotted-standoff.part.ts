import { Box, Cylinder, Plane, Sketch, param, type ExpectedSpec } from "made";

const length = param("length", 70, { min: 40, max: 120, step: 5 });
const width = param("width", 30, { min: 20, max: 60, step: 2 });
const height = param("height", 12, { min: 6, max: 24, step: 1 });
const cornerRadius = param("cornerRadius", 6, { min: 2, max: 10, step: 1 });
const slotLength = param("slotLength", 26, { min: 10, max: 50, step: 2 });
const slotRadius = param("slotRadius", 4, { min: 2, max: 8, step: 0.5 });

// Extrude a rounded rectangular body on the XY plane from Z = 0 to Z = height
const body = Sketch(Plane.XY)
  .roundedRectangle(length, width, cornerRadius, { detail: 6 })
  .extrude(height);

// Center obround through-slot formed by a box bridging two cylinders
const slotBridge = Box(slotLength, slotRadius * 2, height + 4).translate(
  0,
  0,
  height / 2
);
const slotEndLeft = Cylinder(slotRadius, height + 4, { slices: 32 }).translate(
  -slotLength / 2,
  0,
  height / 2
);
const slotEndRight = Cylinder(slotRadius, height + 4, { slices: 32 }).translate(
  slotLength / 2,
  0,
  height / 2
);

// End mounting holes
const mountLeft = Cylinder(3, height + 4, { slices: 24 }).translate(
  -length / 2 + 10,
  0,
  height / 2
);
const mountRight = Cylinder(3, height + 4, { slices: 24 }).translate(
  length / 2 - 10,
  0,
  height / 2
);

export const expected: ExpectedSpec = {
  volume: 21047.54,
  area: 7159.23,
  bounds: {
    min: [-35, -15, 0],
    max: [35, 15, 12],
  },
  tolerance: 0.01,
};

export default body.subtract(
  slotBridge,
  slotEndLeft,
  slotEndRight,
  mountLeft,
  mountRight
);
