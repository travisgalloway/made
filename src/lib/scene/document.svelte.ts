// The document model (issue #65): the client-side model of what the user has built, replacing
// the two hard-wired solids in the old `params.svelte.ts`. It holds N scene objects — each an
// `{ id, def, transform }` — behind a small command-shaped mutation API
// (`addObject`/`removeObject`/`setParam`/`setTransform`), rather than five hand-rolled scalar
// `$state` fields. See docs/architecture/document-model.md.
//
// Everything here is plain and structured-clone-safe: no `three` import, and no *runtime* kernel
// dependency (no KernelClient/comlink/brepjs). Type-only imports of the wire-contract types from
// the zero-import `$lib/kernel/types` are fine and expected — that module exists precisely to be
// shared this way (invariants 3, 4).
//
// `def` is a discriminated union on purpose: adding a solid kind (imported, brep-script) forces
// every consumer's switch to be reconsidered, exactly as the kernel's closed unions do.
//
// No history stack here — the foundation's only obligation is that no mutation bypasses the four
// commands below. #39 adds `createHistory(doc)` as an additive wrapper that records their
// inverses, not a refactor of this model.
//
// Follows SceneModel.svelte.ts's/SnapModel.svelte.ts's factory + getters + `$state` convention.
// Requires the `.svelte.ts` suffix because `createDocumentModel` uses `$state`.
import type { BoxParams, CylinderParams, SolidId } from '$lib/kernel/types';

export type ObjectId = SolidId;

export interface Transform {
	position: [number, number, number];
	rotation: [number, number, number, number]; // quaternion
	scale: [number, number, number];
}

export type ObjectDef =
	| { kind: 'box'; params: BoxParams }
	| { kind: 'cylinder'; params: CylinderParams }
	| { kind: 'imported'; name: string }; // Phase 4 STEP import (#38); the solid lives in the worker
// reserved: { kind: 'brep-script'; source: string } — see docs/architecture/agent-api.md

export interface SceneObject {
	id: ObjectId;
	def: ObjectDef;
	transform: Transform;
}

const IDENTITY_TRANSFORM: Transform = {
	position: [0, 0, 0],
	rotation: [0, 0, 0, 1],
	scale: [1, 1, 1]
};

/** Stable across the document's lifetime — created once, re-tessellated many times as sliders
 *  move. Exported so Scene.svelte's kernel requests and its per-solid geometry/BVH bookkeeping
 *  agree on which solid is which. */
export const BOX_SOLID_ID: SolidId = 'box-1';
export const CYLINDER_SOLID_ID: SolidId = 'cylinder-1';

interface Range {
	min: number;
	max: number;
}

/** Kept modest (rather than e.g. 0..1000) so the box and cylinder — offset a fixed distance apart
 *  in Scene.svelte — stay visually separated across the whole slider range. */
export const BOX_LIMITS: Record<keyof BoxParams, Range> = {
	width: { min: 5, max: 90 },
	depth: { min: 5, max: 90 },
	height: { min: 5, max: 90 }
};

export const CYLINDER_LIMITS: Record<keyof CylinderParams, Range> = {
	radius: { min: 5, max: 50 },
	height: { min: 5, max: 90 }
};

const DEFAULT_BOX: BoxParams = { width: 40, depth: 30, height: 20 };
const DEFAULT_CYLINDER: CylinderParams = { radius: 15, height: 40 };

function clamp(value: number, range: Range): number {
	if (Number.isNaN(value)) return range.min;
	return Math.min(range.max, Math.max(range.min, value));
}

/** Pure — clamps a single box param into its declared range. Exported (and unit-tested in
 *  document.spec.ts) so a slider can never send an out-of-range or malformed value to the kernel,
 *  independent of whatever `min`/`max` the `<input type="range">` element itself declares. */
export function clampBoxParam(key: keyof BoxParams, value: number): number {
	return clamp(value, BOX_LIMITS[key]);
}

/** Pure — the cylinder counterpart of {@link clampBoxParam}. */
export function clampCylinderParam(key: keyof CylinderParams, value: number): number {
	return clamp(value, CYLINDER_LIMITS[key]);
}

export interface DocumentModel {
	readonly objects: readonly SceneObject[];
	paramsFor(id: ObjectId): BoxParams | CylinderParams | undefined;
	addObject(def: ObjectDef, transform?: Transform): ObjectId;
	removeObject(id: ObjectId): void;
	setParam(id: ObjectId, key: string, value: number): void;
	setTransform(id: ObjectId, transform: Transform): void;
}

/**
 * Builds the document model. `objects` is one `$state` array (rather than the five hand-rolled
 * scalar primitives `params.svelte.ts` used) — Svelte 5 deep-proxies its entries, so reading
 * `obj.def.params.width` inside an `$effect` subscribes at field granularity, which is exactly
 * what Scene.svelte's per-solid request `$effect`s need. Deliberately not `$state.raw`: raw would
 * only subscribe on array-reference replacement, defeating the field-granular subscription this
 * whole design depends on.
 */
export function createDocumentModel(): DocumentModel {
	const objects = $state<SceneObject[]>([
		{
			id: BOX_SOLID_ID,
			def: { kind: 'box', params: { ...DEFAULT_BOX } },
			transform: { ...IDENTITY_TRANSFORM }
		},
		{
			id: CYLINDER_SOLID_ID,
			def: { kind: 'cylinder', params: { ...DEFAULT_CYLINDER } },
			transform: { ...IDENTITY_TRANSFORM }
		}
	]);

	// Monotonic, not Math.random()/Date.now(), so generated ids are deterministic in tests. Seeded
	// past the two default objects above — both default ids end in "-1", so starting at 0 would
	// make the first `addObject({ kind: 'box' })` collide with BOX_SOLID_ID.
	let seq = 1;

	return {
		get objects() {
			return objects;
		},
		paramsFor(id) {
			const obj = objects.find((o) => o.id === id);
			if (!obj) return undefined;
			// A fresh spread, never the Svelte proxy directly — the proxy does not survive
			// structuredClone/postMessage and throws at the worker boundary (document-model.md,
			// state-and-errors.md). This is the one lesson that has to survive the move from
			// params.svelte.ts.
			if (obj.def.kind === 'box') return { ...obj.def.params };
			if (obj.def.kind === 'cylinder') return { ...obj.def.params };
			return undefined;
		},
		addObject(def, transform = IDENTITY_TRANSFORM) {
			seq += 1;
			const id: ObjectId = `${def.kind}-${seq}`;
			objects.push({ id, def, transform: { ...transform } });
			return id;
		},
		removeObject(id) {
			const index = objects.findIndex((o) => o.id === id);
			if (index === -1) return;
			objects.splice(index, 1);
		},
		setParam(id, key, value) {
			const obj = objects.find((o) => o.id === id);
			if (!obj) return;
			if (obj.def.kind === 'box') {
				if (!(key in obj.def.params)) return;
				obj.def.params[key as keyof BoxParams] = clampBoxParam(key as keyof BoxParams, value);
			} else if (obj.def.kind === 'cylinder') {
				if (!(key in obj.def.params)) return;
				obj.def.params[key as keyof CylinderParams] = clampCylinderParam(
					key as keyof CylinderParams,
					value
				);
			}
			// 'imported' has no params — a no-op, not a throw.
		},
		setTransform(id, transform) {
			const obj = objects.find((o) => o.id === id);
			if (!obj) return;
			obj.transform = { ...transform };
		}
	};
}
