<script lang="ts">
	// Collapsible group header for dense inspector panels (issue #68). Plain DOM, never imports
	// `three` — architecture invariant 3, mechanically checked for every file under
	// `src/lib/ui/controls/` by the `no-restricted-imports` rule added to eslint.config.js alongside
	// this issue.
	//
	// The header is a real `<button type="button">`, not a clickable `<div>`, so it is keyboard-
	// reachable and gets a native focus outline for free (with a visible focus-ring override below,
	// never `outline: none` without a replacement). `aria-expanded`/`aria-controls` are the two bits
	// of state a plain button doesn't supply on its own, and they are hand-rolled here rather than
	// reached for from a headless lib — ui-controls.md's component strategy reserves Bits UI/Melt UI
	// for cases where rolling accessibility by hand is a real cost (popovers, the virtualized feature
	// tree); a disclosure widget is not one of them.
	//
	// One-way data flow (see ParamsPanel.svelte): `open` is owned by whatever mounts this, not by
	// local `$state`, so a parent inspector can coordinate several sections (e.g. "collapse all")
	// without fighting internal state. `children` is this repo's first typed `Snippet` prop — until
	// now only `{@render children()}` in `+layout.svelte` existed, with no local type annotation.
	import type { Snippet } from 'svelte';

	let {
		title,
		open,
		onToggle,
		children
	}: { title: string; open: boolean; onToggle: (open: boolean) => void; children: Snippet } =
		$props();

	const contentId = $props.id();
</script>

<section class="wade-section">
	<button
		type="button"
		class="wade-section__header"
		aria-expanded={open}
		aria-controls={contentId}
		onclick={() => onToggle(!open)}
	>
		<span
			class="wade-section__chevron {open ? 'wade-section__chevron--open' : ''}"
			aria-hidden="true"
		>
			&#9656;
		</span>
		<span class="wade-section__title">{title}</span>
	</button>
	{#if open}
		<div id={contentId} class="wade-section__body">
			{@render children()}
		</div>
	{/if}
</section>

<style>
	.wade-section {
		border-bottom: 1px solid var(--wade-border);
	}

	.wade-section:last-child {
		border-bottom: none;
	}

	.wade-section__header {
		display: flex;
		align-items: center;
		gap: var(--wade-space-2);
		width: 100%;
		padding: var(--wade-space-2) 0;
		border: none;
		background: none;
		color: var(--wade-text);
		font-family: var(--wade-font-family);
		font-size: var(--wade-font-size);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		cursor: pointer;
	}

	.wade-section__header:focus-visible {
		outline: 2px solid var(--wade-focus-ring);
		outline-offset: 2px;
	}

	.wade-section__chevron {
		display: inline-block;
		opacity: 0.7;
		transition: transform 0.1s ease-out;
	}

	.wade-section__chevron--open {
		transform: rotate(90deg);
	}

	.wade-section__body {
		display: flex;
		flex-direction: column;
		gap: var(--wade-space-2);
		padding-bottom: var(--wade-space-2);
	}
</style>
