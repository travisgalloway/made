import { describe, expect, it } from 'vitest';
import {
	arrowIncrement,
	NumberEntryEditor,
	parseEntry,
	roundToStep,
	type ArrowModifiers
} from './numberEntry';

const NO_MODIFIERS: ArrowModifiers = { shiftKey: false, altKey: false };
const SHIFT: ArrowModifiers = { shiftKey: true, altKey: false };
const ALT: ArrowModifiers = { shiftKey: false, altKey: true };

describe('parseEntry', () => {
	it('parses a plain integer', () => {
		expect(parseEntry('42')).toBe(42);
	});

	it('parses a decimal', () => {
		expect(parseEntry('3.5')).toBe(3.5);
	});

	it('trims surrounding whitespace', () => {
		expect(parseEntry('  10  ')).toBe(10);
	});

	it('parses a leading-negative number', () => {
		expect(parseEntry('-7')).toBe(-7);
	});

	it('returns null for empty text', () => {
		expect(parseEntry('')).toBeNull();
	});

	it('returns null for whitespace-only text', () => {
		expect(parseEntry('   ')).toBeNull();
	});

	it('returns null for non-numeric text', () => {
		expect(parseEntry('abc')).toBeNull();
	});

	it('returns null for a NaN literal', () => {
		expect(parseEntry('NaN')).toBeNull();
	});

	it('returns null for an Infinity literal', () => {
		expect(parseEntry('Infinity')).toBeNull();
		expect(parseEntry('-Infinity')).toBeNull();
	});

	it('clamps to min when the parsed value is below it', () => {
		expect(parseEntry('2', { min: 5 })).toBe(5);
	});

	it('clamps to max when the parsed value is above it', () => {
		expect(parseEntry('100', { max: 50 })).toBe(50);
	});

	it('leaves an in-range value untouched', () => {
		expect(parseEntry('25', { min: 5, max: 50 })).toBe(25);
	});
});

describe('roundToStep', () => {
	it('rounds to the nearest whole step', () => {
		expect(roundToStep(7, 5)).toBe(5);
		expect(roundToStep(8, 5)).toBe(10);
	});

	it('rounds to the nearest fractional step without leaving float dust', () => {
		expect(roundToStep(0.3, 0.1)).toBe(0.3);
		expect(Object.is(roundToStep(0.3, 0.1), 0.30000000000000004)).toBe(false);
	});

	it('returns the value already exactly on-step unchanged', () => {
		expect(roundToStep(15, 5)).toBe(15);
	});

	it('does not divide by zero for a non-positive step', () => {
		expect(roundToStep(4.2, 0)).toBe(4.2);
	});
});

describe('arrowIncrement', () => {
	it('increments by one step on ArrowUp with no modifiers', () => {
		expect(arrowIncrement({ key: 'ArrowUp', step: 1, modifiers: NO_MODIFIERS })).toBe(1);
	});

	it('decrements by one step on ArrowDown with no modifiers', () => {
		expect(arrowIncrement({ key: 'ArrowDown', step: 1, modifiers: NO_MODIFIERS })).toBe(-1);
	});

	it('scales with the field step size', () => {
		expect(arrowIncrement({ key: 'ArrowUp', step: 5, modifiers: NO_MODIFIERS })).toBe(5);
	});

	it('is a coarse (10x) jump on Shift+ArrowUp', () => {
		expect(arrowIncrement({ key: 'ArrowUp', step: 1, modifiers: SHIFT })).toBe(10);
	});

	it('is a fine (0.1x) jump on Alt+ArrowUp', () => {
		expect(arrowIncrement({ key: 'ArrowUp', step: 1, modifiers: ALT })).toBeCloseTo(0.1);
	});

	it('always takes a coarse jump on PageUp, ignoring modifiers', () => {
		expect(arrowIncrement({ key: 'PageUp', step: 1, modifiers: NO_MODIFIERS })).toBe(10);
		expect(arrowIncrement({ key: 'PageUp', step: 1, modifiers: ALT })).toBe(10);
	});

	it('always takes a coarse jump on PageDown, ignoring modifiers', () => {
		expect(arrowIncrement({ key: 'PageDown', step: 1, modifiers: NO_MODIFIERS })).toBe(-10);
		expect(arrowIncrement({ key: 'PageDown', step: 1, modifiers: SHIFT })).toBe(-10);
	});
});

describe('NumberEntryEditor', () => {
	it('is not editing before any focus', () => {
		const editor = new NumberEntryEditor();
		expect(editor.editing).toBe(false);
	});

	it('is editing after focus, and returns the captured value on escape', () => {
		const editor = new NumberEntryEditor();
		editor.focus(12);
		expect(editor.editing).toBe(true);
		expect(editor.escape()).toBe(12);
	});

	it('is no longer editing after escape', () => {
		const editor = new NumberEntryEditor();
		editor.focus(12);
		editor.escape();
		expect(editor.editing).toBe(false);
	});

	it('returns null from escape when there is no pending edit', () => {
		const editor = new NumberEntryEditor();
		expect(editor.escape()).toBeNull();
	});

	it('clears the pending edit on commit without returning a revert value', () => {
		const editor = new NumberEntryEditor();
		editor.focus(12);
		editor.commit();
		expect(editor.editing).toBe(false);
	});

	it('captures a fresh value on each new focus, independent of prior edits', () => {
		const editor = new NumberEntryEditor();
		editor.focus(1);
		editor.commit();
		editor.focus(99);
		expect(editor.escape()).toBe(99);
	});
});
