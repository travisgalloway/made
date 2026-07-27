// Pure pointer-delta -> numeric value delta, no DOM (issue #68). `NumberField.svelte` owns pointer
// capture, `touch-action`, and text-selection suppression during a drag-to-scrub gesture and calls
// this once per `pointermove`; this module owns only the arithmetic, in the style of
// `gestureArbiter.ts` and `snapping.ts` — plain functions over plain data, so it unit-tests in the
// Node-only Vitest project with no DOM shim (docs/guides/testing.md).
//
// Architecture invariant 9 — "precision comes from snapping and typed values, not steady fingers" —
// is why the modifier multipliers exist at all: an unmodified drag is deliberately coarse (few
// pixels per step), and Alt is the escape hatch into fine, steady-fingers precision when that's too
// blunt, while Shift goes the other way for sweeping through a wide range fast. Typed exact entry
// (numberEntry.ts) is the other half of invariant 9; scrubbing is never the only way to hit an exact
// value.
//
// Axis convention: horizontal drag only (`dx`). This is the common CAD/DAW idiom for a scrub field —
// left increases, right... no, right increases, left decreases — read left-to-right like the value
// itself increasing. A vertical component is deliberately not read: `NumberField`'s grip sits inside
// normal document flow, and folding `dy` into the delta would make the gesture fight vertical page
// scroll on touch, which this repo already treats as sacred (see `gestureArbiter.ts`, invariant 8).

export interface ScrubModifiers {
	shiftKey: boolean;
	altKey: boolean;
}

export interface ScrubQuery {
	/** Horizontal pointer movement since the previous sample, in CSS pixels. Positive is rightward. */
	dx: number;
	/** The field's step size — one unit of value per `PIXELS_PER_STEP` pixels of drag, before the
	 *  modifier multiplier is applied. */
	step: number;
	modifiers: ScrubModifiers;
}

/** Pixels of horizontal drag that move the value by one un-modified `step`. Deliberately coarse
 *  (not 1:1) so a scrub gesture covers a useful range across a comfortable drag distance — see the
 *  module docstring on invariant 9. */
export const PIXELS_PER_STEP = 4;

/** Shift = coarse (10 steps per `PIXELS_PER_STEP`), Alt = fine (a tenth of a step). Alt wins when
 *  both are held, since asking for fine precision is the more deliberate of the two asks. */
const COARSE_MULTIPLIER = 10;
const FINE_MULTIPLIER = 0.1;

/** Converts one sample of horizontal drag into a value delta. Callers accumulate this across a drag
 *  (or apply it directly to the last committed value each sample, whichever fits their pointer-event
 *  bookkeeping) — this function is stateless and knows nothing about the gesture's start or end. */
export function scrubDelta({ dx, step, modifiers }: ScrubQuery): number {
	const multiplier = modifiers.altKey
		? FINE_MULTIPLIER
		: modifiers.shiftKey
			? COARSE_MULTIPLIER
			: 1;
	return (dx / PIXELS_PER_STEP) * step * multiplier;
}
