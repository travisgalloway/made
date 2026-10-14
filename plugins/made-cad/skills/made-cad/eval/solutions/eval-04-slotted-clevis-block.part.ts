import { Box, Cylinder, type ExpectedSpec } from "made";

// Eval 04: Clevis fork block of outer dimensions 36x24x32 mm (centered on X and Y,
// Z from 0 to 32) with a 12 mm wide U-slot cut into the top 20 mm along Y
// (Z from 12 to 32) and an 8 mm diameter cross-pin hole along the X axis at Z = 22.
const outerBlock = Box(36, 24, 32, { center: [0, 0, 16] });
const forkSlot = Box(12, 28, 22, { center: [0, 0, 23] });
const pinHole = Cylinder(4, 40, { slices: 32 })
  .rotateY(90)
  .translate(0, 0, 22);

export const expected: ExpectedSpec = {
  volume: 20680.0,
  area: 6450.44,
  bounds: {
    min: [-18, -12, 0],
    max: [18, 12, 32],
  },
  tolerance: 0.01,
};

export default outerBlock.subtract(forkSlot, pinHole);
