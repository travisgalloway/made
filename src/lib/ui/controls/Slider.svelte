<script lang="ts">
	// Native range slider (issue #68). The DOM root is a real `<input type="range">` — never a
	// custom track/thumb built from `<div>`s — precisely so #70 can drop this in for
	// ParamsPanel.svelte's five `data-testid`'d inputs (box-width, box-depth, box-height,
	// cylinder-radius, cylinder-height) without breaking `setSlider()` in `e2e/kernel.e2e.ts:54` and
	// `e2e/orientation.e2e.ts:57`, both of which set `.value` directly and dispatch a synthetic
	// bubbling `input` event — a hand-rolled slider would not receive that the same way. `testid` is
	// a plain pass-through prop for exactly that reason.
	//
	// The one behavior a native range doesn't give for free is a *modifier-aware* arrow-key step
	// (Shift coarse, Alt fine) — browsers only ever step Up/Down/Left/Right by the plain `step`
	// attribute — and Esc-to-revert mid-edit. Both are hand-rolled here with the same pure
	// `numberEntry.ts` helpers `NumberField` uses, so the two controls agree on what "coarse" and
	// "fine" mean (architecture invariant 9).
	//
	// One-way data flow (see ParamsPanel.svelte): `value` in, `onchange` out, no `$bindable`.
	import { arrowIncrement, NumberEntryEditor, roundToStep, type ArrowKey } from './numberEntry';

	let {
		value,
		min,
		max,
		step = 1,
		label,
		onchange,
		testid
	}: {
		value: number;
		min: number;
		max: number;
		step?: number;
		label: string;
		onchange: (value: number) => void;
		testid?: string;
	} = $props();

	const editor = new NumberEntryEditor();
	const ARROW_KEYS: readonly ArrowKey[] = ['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown'];

	function clampRound(next: number): number {
		return roundToStep(Math.min(max, Math.max(min, next)), step);
	}

	function onFocus() {
		editor.focus(value);
	}

	function onBlur() {
		editor.commit();
	}

	function onInput(event: Event) {
		onchange(Number((event.currentTarget as HTMLInputElement).value));
	}

	function onKeyDown(event: KeyboardEvent) {
		if (event.key === 'Escape') {
			const reverted = editor.escape();
			if (reverted !== null && reverted !== value) {
				event.preventDefault();
				onchange(reverted);
			}
			return;
		}
		if (!isArrowKey(event.key)) return;
		// Plain (unmodified) Up/Down/Page keys already work via the native `step`/`min`/`max` —
		// only override when a modifier asks for a different magnitude than the browser gives.
		if (!event.shiftKey && !event.altKey) return;
		event.preventDefault();
		const delta = arrowIncrement({
			key: event.key,
			step,
			modifiers: { shiftKey: event.shiftKey, altKey: event.altKey }
		});
		onchange(clampRound(value + delta));
	}

	function isArrowKey(key: string): key is ArrowKey {
		return (ARROW_KEYS as readonly string[]).includes(key);
	}
</script>

<label class="wade-slider">
	<span class="wade-slider__label">
		{label} <b class="wade-slider__value">{value}</b>
	</span>
	<input
		type="range"
		{min}
		{max}
		{step}
		{value}
		data-testid={testid}
		oninput={onInput}
		onfocus={onFocus}
		onblur={onBlur}
		onkeydown={onKeyDown}
	/>
</label>

<style>
	.wade-slider {
		display: flex;
		flex-direction: column;
		gap: var(--wade-space-1);
		color: var(--wade-text);
		font-family: var(--wade-font-family);
		font-size: var(--wade-font-size);
		line-height: var(--wade-line-height);
	}

	.wade-slider__label {
		display: flex;
		justify-content: space-between;
	}

	.wade-slider__value {
		color: var(--wade-text-muted);
	}

	input[type='range'] {
		width: 100%;
		accent-color: var(--wade-accent);
	}

	input[type='range']:focus-visible {
		outline: 2px solid var(--wade-focus-ring);
		outline-offset: 2px;
	}
</style>
