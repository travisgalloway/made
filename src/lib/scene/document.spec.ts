import { describe, expect, it } from 'vitest';
import {
	BOX_LIMITS,
	BOX_SOLID_ID,
	CYLINDER_LIMITS,
	CYLINDER_SOLID_ID,
	clampBoxParam,
	clampCylinderParam,
	createDocumentModel
} from './document.svelte';

// The pure clamping helpers are exercised directly below, carried over unchanged from the old
// params.spec.ts. `createDocumentModel()` itself uses `$state`, which — unlike the old
// params.svelte.ts's `createParamsModel()` — turns out to work fine when imported from a plain
// `.spec.ts` in the Node `server` Vitest project: the runes compiler plugin transforms based on
// the *imported* file's `.svelte.ts` suffix, not the importing file's extension, so no DOM/jsdom
// is needed to construct or read from the model. So, unlike its predecessor, the command API
// below is unit-tested directly rather than only via e2e.

describe('clampBoxParam', () => {
	it('passes a value already within range through unchanged', () => {
		expect(clampBoxParam('width', 40)).toBe(40);
	});

	it('clamps a value below the minimum up to the minimum', () => {
		expect(clampBoxParam('depth', -5)).toBe(BOX_LIMITS.depth.min);
	});

	it('clamps a value above the maximum down to the maximum', () => {
		expect(clampBoxParam('height', 10_000)).toBe(BOX_LIMITS.height.max);
	});

	it('falls back to the minimum for NaN input (e.g. a malformed slider value)', () => {
		expect(clampBoxParam('width', Number.NaN)).toBe(BOX_LIMITS.width.min);
	});
});

describe('clampCylinderParam', () => {
	it('passes a value already within range through unchanged', () => {
		expect(clampCylinderParam('radius', 15)).toBe(15);
	});

	it('clamps a value below the minimum up to the minimum', () => {
		expect(clampCylinderParam('radius', -1)).toBe(CYLINDER_LIMITS.radius.min);
	});

	it('clamps a value above the maximum down to the maximum', () => {
		expect(clampCylinderParam('height', 10_000)).toBe(CYLINDER_LIMITS.height.max);
	});

	it('falls back to the minimum for NaN input', () => {
		expect(clampCylinderParam('radius', Number.NaN)).toBe(CYLINDER_LIMITS.radius.min);
	});
});

describe('createDocumentModel default contents', () => {
	it('starts with the box and cylinder objects the app renders today', () => {
		const doc = createDocumentModel();
		expect(doc.objects).toHaveLength(2);
		expect(doc.objects[0]).toMatchObject({ id: BOX_SOLID_ID, def: { kind: 'box' } });
		expect(doc.objects[1]).toMatchObject({ id: CYLINDER_SOLID_ID, def: { kind: 'cylinder' } });
	});
});

describe('paramsFor', () => {
	it('returns a fresh object on every call, never the Svelte proxy', () => {
		const doc = createDocumentModel();
		const first = doc.paramsFor(BOX_SOLID_ID);
		const second = doc.paramsFor(BOX_SOLID_ID);
		expect(first).not.toBe(second);
		expect(first).toEqual(second);
	});

	it('returns undefined for an unknown id', () => {
		const doc = createDocumentModel();
		expect(doc.paramsFor('nope')).toBeUndefined();
	});

	it('returns undefined for an imported object, which has no params', () => {
		const doc = createDocumentModel();
		const id = doc.addObject({ kind: 'imported', name: 'part.step' });
		expect(doc.paramsFor(id)).toBeUndefined();
	});
});

describe('setParam', () => {
	it('clamps a box param and is reflected in the next paramsFor read', () => {
		const doc = createDocumentModel();
		doc.setParam(BOX_SOLID_ID, 'width', 10_000);
		expect(doc.paramsFor(BOX_SOLID_ID)).toMatchObject({ width: BOX_LIMITS.width.max });
	});

	it('clamps a cylinder param and is reflected in the next paramsFor read', () => {
		const doc = createDocumentModel();
		doc.setParam(CYLINDER_SOLID_ID, 'radius', -1);
		expect(doc.paramsFor(CYLINDER_SOLID_ID)).toMatchObject({ radius: CYLINDER_LIMITS.radius.min });
	});

	it('is a silent no-op for an unknown id', () => {
		const doc = createDocumentModel();
		expect(() => doc.setParam('nope', 'width', 40)).not.toThrow();
		expect(doc.paramsFor('nope')).toBeUndefined();
	});

	it('is a silent no-op for a key invalid for the object kind', () => {
		const doc = createDocumentModel();
		doc.setParam(BOX_SOLID_ID, 'radius', 20);
		expect(doc.paramsFor(BOX_SOLID_ID)).toEqual({ width: 40, depth: 30, height: 20 });
	});
});

describe('addObject / removeObject', () => {
	it('addObject returns a distinct id, appends to objects, and applies an identity transform default', () => {
		const doc = createDocumentModel();
		const before = doc.objects.length;
		const id = doc.addObject({ kind: 'box', params: { width: 10, depth: 10, height: 10 } });

		expect(id).not.toBe(BOX_SOLID_ID);
		expect(id).not.toBe(CYLINDER_SOLID_ID);
		expect(doc.objects).toHaveLength(before + 1);

		const added = doc.objects.find((o) => o.id === id);
		expect(added?.transform).toEqual({
			position: [0, 0, 0],
			rotation: [0, 0, 0, 1],
			scale: [1, 1, 1]
		});
	});

	it('addObject returns a distinct id on each call', () => {
		const doc = createDocumentModel();
		const first = doc.addObject({ kind: 'box', params: { width: 10, depth: 10, height: 10 } });
		const second = doc.addObject({ kind: 'box', params: { width: 10, depth: 10, height: 10 } });
		expect(first).not.toBe(second);
	});

	it('removeObject removes the object', () => {
		const doc = createDocumentModel();
		const id = doc.addObject({ kind: 'box', params: { width: 10, depth: 10, height: 10 } });
		doc.removeObject(id);
		expect(doc.objects.find((o) => o.id === id)).toBeUndefined();
	});

	it('removeObject is a no-op for an unknown id', () => {
		const doc = createDocumentModel();
		const before = doc.objects.length;
		expect(() => doc.removeObject('nope')).not.toThrow();
		expect(doc.objects).toHaveLength(before);
	});
});

describe('setTransform', () => {
	it('round-trips a transform write', () => {
		const doc = createDocumentModel();
		const transform = {
			position: [1, 2, 3] as [number, number, number],
			rotation: [0, 0, 0.7071, 0.7071] as [number, number, number, number],
			scale: [2, 2, 2] as [number, number, number]
		};
		doc.setTransform(BOX_SOLID_ID, transform);
		expect(doc.objects.find((o) => o.id === BOX_SOLID_ID)?.transform).toEqual(transform);
	});

	it('is a silent no-op for an unknown id', () => {
		const doc = createDocumentModel();
		expect(() =>
			doc.setTransform('nope', { position: [0, 0, 0], rotation: [0, 0, 0, 1], scale: [1, 1, 1] })
		).not.toThrow();
	});
});
