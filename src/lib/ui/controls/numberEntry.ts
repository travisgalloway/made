// Pure text-entry and keyboard logic for NumberField, no DOM (issue #68) — same rationale as
// scrub.ts: plain functions (and one small state-holding class, mirroring gestureArbiter.ts's
// GestureArbiter) over plain data, unit-testable in the Node-only Vitest project. This is the other
// half of architecture invariant 9 ("precision comes from snapping and typed values"): scrubbing
// gets you close, typed exact entry gets you exact.

export interface EntryRange {
	min?: number;
	max?: number;
}

/**
 * Parses free-typed text into a finite number, clamped to `[min, max]` when given. Returns `null`
 * for empty/whitespace-only text and for anything that doesn't parse to a finite number — including
 * `NaN` and `Infinity` literals, which `Number(...)` would otherwise happily accept. `null` means
 * "not a usable value"; the caller's job is to fall back to the pre-edit value (see
 * `NumberEntryEditor` below), never to silently coerce garbage into 0.
 */
export function parseEntry(text: string, range: EntryRange = {}): number | null {
	const trimmed = text.trim();
	if (trimmed === '') return null;
	const value = Number(trimmed);
	if (!Number.isFinite(value)) return null;
	return clamp(value, range);
}

function clamp(value: number, { min, max }: EntryRange): number {
	let result = value;
	if (min !== undefined) result = Math.max(min, result);
	if (max !== undefined) result = Math.min(max, result);
	return result;
}

/**
 * Rounds `value` to the nearest multiple of `step`. Rounding in integer step-counts (`value / step`)
 * still leaves float dust behind — `Math.round(0.3 / 0.1) * 0.1` is `0.30000000000000004`, not
 * `0.3` — so the result is re-rounded to `step`'s own decimal precision with `toFixed`, which mops up
 * exactly that residual epsilon without a general-purpose decimal library. A non-positive `step`
 * (misconfiguration, not a real field) is treated as "no rounding" rather than dividing by zero.
 */
export function roundToStep(value: number, step: number): number {
	if (step <= 0) return value;
	const rounded = Math.round(value / step) * step;
	return Number(rounded.toFixed(decimalPlaces(step)));
}

function decimalPlaces(step: number): number {
	const text = String(step);
	const dot = text.indexOf('.');
	return dot === -1 ? 0 : text.length - dot - 1;
}

export type ArrowKey = 'ArrowUp' | 'ArrowDown' | 'PageUp' | 'PageDown';

export interface ArrowModifiers {
	shiftKey: boolean;
	altKey: boolean;
}

export interface ArrowIncrementQuery {
	key: ArrowKey;
	step: number;
	modifiers: ArrowModifiers;
}

/** Same coarse/fine multipliers as scrub.ts, so a keyboard nudge and a drag nudge agree on what
 *  "coarse" and "fine" mean for a given field. */
const COARSE_MULTIPLIER = 10;
const FINE_MULTIPLIER = 0.1;

/**
 * The signed value delta for one arrow-key press. Up/PageUp increase, Down/PageDown decrease.
 * PageUp/PageDown are always the coarse jump, matching the convention native `<input
 * type="range">` already gives Home/End/PageUp/PageDown for free — modifiers don't change a Page
 * key's magnitude. On Up/Down, Shift mirrors that coarse jump and Alt gives the fine one; Alt wins
 * if both are held, same tie-break as scrub.ts.
 */
export function arrowIncrement({ key, step, modifiers }: ArrowIncrementQuery): number {
	const direction = key === 'ArrowUp' || key === 'PageUp' ? 1 : -1;
	const magnitude =
		key === 'PageUp' || key === 'PageDown'
			? COARSE_MULTIPLIER
			: modifiers.altKey
				? FINE_MULTIPLIER
				: modifiers.shiftKey
					? COARSE_MULTIPLIER
					: 1;
	return direction * magnitude * step;
}

/**
 * The Esc-revert state transition: capture the value on focus, hand it back on Escape, forget it on
 * commit (Enter or blur). A tiny state machine rather than three loose functions because "is there a
 * pending edit right now" is state that has to survive across several DOM events on the same field —
 * exactly the kind of thing `GestureArbiter` (gestureArbiter.ts) already models this way for gesture
 * decisions, so `NumberField.svelte` follows the same shape: hold one instance, feed it lifecycle
 * calls, trust its return values over any local bookkeeping.
 */
export class NumberEntryEditor {
	private preEdit: number | null = null;

	/** Call when the field gains focus and editing begins. */
	focus(value: number): void {
		this.preEdit = value;
	}

	/** Call on Escape. Returns the value to restore, or `null` if there was no pending edit (an
	 *  Escape that doesn't follow a `focus()` is a no-op, not an error). Clears the pending edit
	 *  either way, matching native form-field Escape behavior of ending the edit outright. */
	escape(): number | null {
		const value = this.preEdit;
		this.preEdit = null;
		return value;
	}

	/** Call on Enter or blur, once the new value has been read and applied. Clears the pending edit
	 *  without producing a revert value. */
	commit(): void {
		this.preEdit = null;
	}

	/** Whether a `focus()` is currently pending a `commit()`/`escape()`. */
	get editing(): boolean {
		return this.preEdit !== null;
	}
}
