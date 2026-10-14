import { Cylinder, defineParams, type ExpectedSpec } from "made";

const p = defineParams({
  flangeRadius: { default: 25, min: 18, max: 40, step: 1, label: "Flange Radius" },
  flangeThickness: { default: 6, min: 3, max: 12, step: 1, label: "Flange Thickness" },
  barrelRadius: { default: 14, min: 10, max: 20, step: 1, label: "Barrel Radius" },
  totalHeight: { default: 28, min: 15, max: 50, step: 1, label: "Total Height" },
  boreRadius: { default: 8, min: 4, max: 12, step: 0.5, label: "Bore Radius" },
  boltCircleRadius: { default: 19.5, min: 15, max: 32, step: 0.5, label: "Bolt Circle Radius" },
  boltHoleRadius: { default: 2.5, min: 1.5, max: 4, step: 0.25, label: "Bolt Hole Radius" },
});

const flange = Cylinder(p.flangeRadius, p.flangeThickness, {
  slices: 48,
  center: false,
});

const barrel = Cylinder(p.barrelRadius, p.totalHeight, {
  slices: 48,
  center: false,
});

const centerBore = Cylinder(p.boreRadius, p.totalHeight + 4, {
  slices: 48,
}).translate(0, 0, p.totalHeight / 2);

const boltHoleXPos = Cylinder(p.boltHoleRadius, p.flangeThickness + 4, {
  slices: 24,
}).translate(p.boltCircleRadius, 0, p.flangeThickness / 2);

const boltHoleXNeg = Cylinder(p.boltHoleRadius, p.flangeThickness + 4, {
  slices: 24,
}).translate(-p.boltCircleRadius, 0, p.flangeThickness / 2);

const boltHoleYPos = Cylinder(p.boltHoleRadius, p.flangeThickness + 4, {
  slices: 24,
}).translate(0, p.boltCircleRadius, p.flangeThickness / 2);

const boltHoleYNeg = Cylinder(p.boltHoleRadius, p.flangeThickness + 4, {
  slices: 24,
}).translate(0, -p.boltCircleRadius, p.flangeThickness / 2);

export const expected: ExpectedSpec = {
  volume: 19103.25,
  area: 8000.83,
  bounds: {
    min: [-25, -25, 0],
    max: [25, 25, 28],
  },
  tolerance: 0.01,
};

export default flange
  .union(barrel)
  .subtract(centerBore, boltHoleXPos, boltHoleXNeg, boltHoleYPos, boltHoleYNeg);
