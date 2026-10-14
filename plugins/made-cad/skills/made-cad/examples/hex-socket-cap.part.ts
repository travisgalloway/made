import { Cylinder, Plane, Sketch, param, type ExpectedSpec } from "made";

const headRadius = param("headRadius", 12, { min: 8, max: 20, step: 1 });
const headHeight = param("headHeight", 10, { min: 6, max: 16, step: 1 });
const shankRadius = param("shankRadius", 7, { min: 4, max: 12, step: 0.5 });
const shankLength = param("shankLength", 20, { min: 10, max: 40, step: 2 });
const socketCircumradius = param("socketCircumradius", 6, { min: 3, max: 9, step: 0.5 });
const socketDepth = param("socketDepth", 6, { min: 3, max: 8, step: 0.5 });

// Shank extends from Z = 0 to Z = shankLength
const shank = Cylinder(shankRadius, shankLength, {
  slices: 36,
  center: false,
});

// Socket head sits on top of the shank from Z = shankLength to Z = shankLength + headHeight
const head = Cylinder(headRadius, headHeight, {
  slices: 36,
  center: false,
}).translate(0, 0, shankLength);

// Hexagonal Allen socket recessed into the top of the head
const totalHeight = shankLength + headHeight;
const hexSocketPlane = Plane.offset(Plane.XY, totalHeight - socketDepth);
const hexSocket = Sketch(hexSocketPlane)
  .regularPolygon(socketCircumradius, 6)
  .extrude(socketDepth + 1);

export const expected: ExpectedSpec = {
  volume: 7000.0,
  area: 2747.75,
  bounds: {
    min: [-12, -12, 0],
    max: [12, 12, 30],
  },
  tolerance: 0.01,
};

export default shank.union(head).subtract(hexSocket);
