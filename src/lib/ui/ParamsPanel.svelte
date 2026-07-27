<script lang="ts">
	// The first UI component in the repo (issue #25): a dev/demo overlay with sliders bound to the
	// kernel-driven box and cylinder objects in `src/lib/scene/document.svelte.ts` (issue #65).
	// Mounted as a plain HTML sibling of <Viewport /> in +page.svelte, not inside the Threlte
	// <Canvas> subtree — this is ordinary DOM, not scene content, and per architecture invariant 3
	// it never touches `three`.
	//
	// Sized to its content and pinned to a corner (not a full-screen overlay), so it never needs a
	// `pointer-events` trick to stay out of the viewport's way: everything outside its own bounding
	// box is untouched, and the canvas underneath keeps receiving orbit/pick pointer events exactly
	// as it does with no panel mounted at all.
	import { BOX_SOLID_ID, CYLINDER_SOLID_ID, type DocumentModel } from '$lib/scene/document.svelte';
	import type { BoxParams, CylinderParams } from '$lib/kernel/types';

	let { model }: { model: DocumentModel } = $props();

	// Fresh reads each render, same fresh-object guarantee `paramsFor` itself makes — see
	// document.svelte.ts. #65 keeps the panel hard-wired to the two default objects; #67
	// generalizes this into a per-object inspector.
	let box = $derived(model.paramsFor(BOX_SOLID_ID) as BoxParams);
	let cylinder = $derived(model.paramsFor(CYLINDER_SOLID_ID) as CylinderParams);

	function onBoxInput(key: keyof BoxParams) {
		return (event: Event) => {
			model.setParam(BOX_SOLID_ID, key, Number((event.currentTarget as HTMLInputElement).value));
		};
	}

	function onCylinderInput(key: keyof CylinderParams) {
		return (event: Event) => {
			model.setParam(
				CYLINDER_SOLID_ID,
				key,
				Number((event.currentTarget as HTMLInputElement).value)
			);
		};
	}
</script>

<div class="params-panel">
	<section>
		<h2>Box</h2>
		<label>
			<span>Width <b>{box.width}</b></span>
			<input
				type="range"
				min="5"
				max="90"
				value={box.width}
				oninput={onBoxInput('width')}
				data-testid="box-width"
			/>
		</label>
		<label>
			<span>Depth <b>{box.depth}</b></span>
			<input
				type="range"
				min="5"
				max="90"
				value={box.depth}
				oninput={onBoxInput('depth')}
				data-testid="box-depth"
			/>
		</label>
		<label>
			<span>Height <b>{box.height}</b></span>
			<input
				type="range"
				min="5"
				max="90"
				value={box.height}
				oninput={onBoxInput('height')}
				data-testid="box-height"
			/>
		</label>
	</section>
	<section>
		<h2>Cylinder</h2>
		<label>
			<span>Radius <b>{cylinder.radius}</b></span>
			<input
				type="range"
				min="5"
				max="50"
				value={cylinder.radius}
				oninput={onCylinderInput('radius')}
				data-testid="cylinder-radius"
			/>
		</label>
		<label>
			<span>Height <b>{cylinder.height}</b></span>
			<input
				type="range"
				min="5"
				max="90"
				value={cylinder.height}
				oninput={onCylinderInput('height')}
				data-testid="cylinder-height"
			/>
		</label>
	</section>
</div>

<style>
	.params-panel {
		position: fixed;
		top: 1rem;
		right: 1rem;
		z-index: 10;
		width: 220px;
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
		padding: 0.75rem 1rem;
		border-radius: 0.5rem;
		background: rgba(20, 22, 26, 0.72);
		color: #e6e9ee;
		font:
			12px/1.4 system-ui,
			sans-serif;
	}

	h2 {
		margin: 0 0 0.35rem;
		font-size: 12px;
		font-weight: 600;
		opacity: 0.8;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	label {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		margin-bottom: 0.4rem;
	}

	label:last-child {
		margin-bottom: 0;
	}

	label span {
		display: flex;
		justify-content: space-between;
	}

	input[type='range'] {
		width: 100%;
	}
</style>
