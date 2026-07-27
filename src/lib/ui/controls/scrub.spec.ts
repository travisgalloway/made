import { describe, expect, it } from 'vitest';
import { PIXELS_PER_STEP, scrubDelta, type ScrubModifiers } from './scrub';

const NO_MODIFIERS: ScrubModifiers = { shiftKey: false, altKey: false };
const SHIFT: ScrubModifiers = { shiftKey: true, altKey: false };
const ALT: ScrubModifiers = { shiftKey: false, altKey: true };
const BOTH: ScrubModifiers = { shiftKey: true, altKey: true };

describe('scrubDelta', () => {
	it('returns zero for zero movement', () => {
		expect(scrubDelta({ dx: 0, step: 1, modifiers: NO_MODIFIERS })).toBe(0);
	});

	it('moves by one step per PIXELS_PER_STEP pixels with no modifiers', () => {
		expect(scrubDelta({ dx: PIXELS_PER_STEP, step: 1, modifiers: NO_MODIFIERS })).toBe(1);
		expect(scrubDelta({ dx: PIXELS_PER_STEP * 3, step: 1, modifiers: NO_MODIFIERS })).toBe(3);
	});

	it('scales with the field step size', () => {
		expect(scrubDelta({ dx: PIXELS_PER_STEP, step: 5, modifiers: NO_MODIFIERS })).toBe(5);
	});

	it('is negative for leftward movement', () => {
		expect(scrubDelta({ dx: -PIXELS_PER_STEP, step: 1, modifiers: NO_MODIFIERS })).toBe(-1);
	});

	it('multiplies by 10 when Shift is held (coarse)', () => {
		expect(scrubDelta({ dx: PIXELS_PER_STEP, step: 1, modifiers: SHIFT })).toBe(10);
	});

	it('multiplies by 0.1 when Alt is held (fine)', () => {
		expect(scrubDelta({ dx: PIXELS_PER_STEP, step: 1, modifiers: ALT })).toBeCloseTo(0.1);
	});

	it('prefers Alt (fine) over Shift (coarse) when both are held', () => {
		expect(scrubDelta({ dx: PIXELS_PER_STEP, step: 1, modifiers: BOTH })).toBeCloseTo(0.1);
	});

	it('is linear in dx for a fixed step and modifier state', () => {
		const half = scrubDelta({ dx: PIXELS_PER_STEP / 2, step: 1, modifiers: NO_MODIFIERS });
		const full = scrubDelta({ dx: PIXELS_PER_STEP, step: 1, modifiers: NO_MODIFIERS });
		expect(half).toBeCloseTo(full / 2);
	});
});
