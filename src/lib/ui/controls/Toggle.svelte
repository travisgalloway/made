<script lang="ts">
	// Native checkbox toggle (issue #68). Plain DOM, never imports `three` (invariant 3). A native
	// `<input type="checkbox">`, wrapped in a `<label>`, is the whole implementation on purpose: it
	// already supplies keyboard (Space to toggle, Tab to focus), the accessible role, and the checked
	// state for free — see ui-controls.md's "reach for a headless lib only where accessibility is
	// genuinely hard"; a checkbox is the textbook case where it is not.
	//
	// One-way data flow, matching ParamsPanel.svelte's established shape: `checked` comes in as a
	// prop, `onchange` reports the new value out. No `$bindable` — see numberEntry.ts's module doc
	// for why this repo doesn't reach for that idiom here.
	let {
		checked,
		label,
		onchange,
		disabled = false
	}: {
		checked: boolean;
		label: string;
		onchange: (checked: boolean) => void;
		disabled?: boolean;
	} = $props();
</script>

<label class="wade-toggle" class:wade-toggle--disabled={disabled}>
	<input
		type="checkbox"
		{checked}
		{disabled}
		onchange={(event) => onchange((event.currentTarget as HTMLInputElement).checked)}
	/>
	<span class="wade-toggle__label">{label}</span>
</label>

<style>
	.wade-toggle {
		display: inline-flex;
		align-items: center;
		gap: var(--wade-space-2);
		color: var(--wade-text);
		font-family: var(--wade-font-family);
		font-size: var(--wade-font-size);
		line-height: var(--wade-line-height);
		cursor: pointer;
	}

	.wade-toggle--disabled {
		cursor: not-allowed;
		opacity: 0.5;
	}

	input[type='checkbox'] {
		width: 1rem;
		height: 1rem;
		accent-color: var(--wade-accent);
	}

	input[type='checkbox']:focus-visible {
		outline: 2px solid var(--wade-focus-ring);
		outline-offset: 2px;
	}
</style>
