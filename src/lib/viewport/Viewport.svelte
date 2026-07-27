<script lang="ts">
	// Owns the Threlte <Canvas> and the renderer. The canvas itself is imperative (invariant 3):
	// no geometry or per-frame state lives in `$state` here — `renderMode` only ever takes one of
	// two values across the renderer's whole lifetime (manual until WebGPU init resolves, then
	// on-demand), it does not change per frame.
	import { Canvas } from '@threlte/core';
	import { WebGPURenderer } from 'three/webgpu';
	import type { DocumentModel } from '$lib/scene/document.svelte';
	import { settings } from '$lib/settings/settings.svelte';
	import { instrumentRenderer, publishBackend } from './renderLoop';
	import Scene from './Scene.svelte';

	// Threaded through from +page.svelte (which owns it, since ParamsPanel — a sibling of this
	// component — needs the same instance) down to Scene.svelte, which is the only thing inside
	// the Canvas that actually reads it (issue #25, generalized to N objects in #65).
	let { documentModel }: { documentModel: DocumentModel } = $props();

	// Starts 'manual' so no frame can be issued before renderer.init() resolves (#12); flips to
	// 'on-demand' once it does, which is the mode invalidate() actually drives (#13).
	let renderMode = $state<'manual' | 'on-demand'>('manual');
</script>

<div class="viewport">
	{#key settings.forceWebGL}
		<Canvas
			{renderMode}
			dpr={[1, 2]}
			createRenderer={(canvas) => {
				renderMode = 'manual';

				const renderer = new WebGPURenderer({
					canvas,
					antialias: true,
					forceWebGL: settings.forceWebGL
				});
				instrumentRenderer(renderer);

				renderer.init().then(() => {
					// The backend is only decided once init resolves — WebGPURenderer silently falls back
					// to WebGL2 when WebGPU is unavailable or forceWebGL is set.
					publishBackend(renderer);
					renderMode = 'on-demand';
				});

				return renderer;
			}}
		>
			<Scene {documentModel} />
		</Canvas>
	{/key}
</div>

<style>
	.viewport {
		width: 100dvw;
		height: 100dvh;
		margin: 0;
		overflow: hidden;
	}

	/* The app must own every gesture from the first frame (issue #17 wires the actual input
	   routing; this is the one-line style on the element this PR creates). */
	.viewport :global(canvas) {
		touch-action: none;
	}
</style>
