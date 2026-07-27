<script lang="ts">
	// Typed exact entry + drag-to-scrub number field (issue #68) — architecture invariant 9
	// ("precision comes from snapping and typed values, not steady fingers") made literal in a single
	// control: the `<input>` is where an exact value is typed, the `label` doubles as a drag grip for
	// coarse adjustment, and neither is the only way in.
	//
	// The `<input>` is `type="text"`, not `type="number"` — a native number input silently discards
	// keystrokes it can't parse as it types, which would fight `numberEntry.ts`'s own parse/clamp/
	// revert rules (reject non-numeric, `NaN`/`Infinity` handling, Esc-revert) rather than compose
	// with them. Because a plain textbox carries none of `type="number"`'s implicit `spinbutton` role
	// or `aria-value*` semantics, this component hand-rolls both (`role="spinbutton"`,
	// `aria-valuenow`/`valuemin`/`valuemax`, `aria-label`) — the AC calls this out explicitly for
	// controls where "the native element does not supply them", unlike `Slider`/`Toggle`, which lean
	// on `<input type="range">`/`type="checkbox">` for it.
	//
	// Typing is staged, not applied per keystroke: `text` tracks raw keystrokes so a user can type
	// "-", "3.", or an empty string mid-edit without the field fighting them, and `numberEntry.ts`'s
	// `parseEntry`/`roundToStep` only run on commit (Enter or blur). Escape restores the value
	// captured on focus via `NumberEntryEditor` — that state transition is exactly why that class
	// exists as more than three loose functions, see numberEntry.ts.
	//
	// Drag-to-scrub uses pointer capture on the grip so the gesture keeps tracking even if the
	// pointer leaves the grip's bounding box mid-drag (a fast horizontal flick easily outruns a
	// narrow label). `touch-action: none` and `user-select: none` on the grip keep the gesture from
	// fighting the browser's own touch-scroll and text-selection behavior — the AC's "must not fight
	// text selection" — while the `<input>` itself keeps normal text selection for typed entry.
	//
	// One-way data flow (see ParamsPanel.svelte): `value` in, `onchange` out, no `$bindable`.
	import {
		arrowIncrement,
		NumberEntryEditor,
		parseEntry,
		roundToStep,
		type ArrowKey
	} from './numberEntry';
	import { scrubDelta } from './scrub';

	let {
		value,
		min,
		max,
		step = 1,
		label,
		onchange
	}: {
		value: number;
		min?: number;
		max?: number;
		step?: number;
		label: string;
		onchange: (value: number) => void;
	} = $props();

	// Deliberate: `text` is an editable buffer seeded from `value` once, then kept in sync by the
	// `$effect` below only while not `editing`. A `$derived` would recompute from `value` on every
	// change and could never hold a typed-but-uncommitted keystroke, which is the entire point of
	// staging commit until Enter/blur.
	// svelte-ignore state_referenced_locally
	let text = $state(String(value));
	let editing = $state(false);

	const editor = new NumberEntryEditor();
	const ARROW_KEYS: readonly ArrowKey[] = ['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown'];

	// While not actively being edited, the displayed text always tracks the committed value —
	// including changes that came from outside (the drag grip, another control, undo/redo).
	$effect(() => {
		if (!editing) text = String(value);
	});

	function clampRound(next: number): number {
		let clamped = next;
		if (min !== undefined) clamped = Math.max(min, clamped);
		if (max !== undefined) clamped = Math.min(max, clamped);
		return roundToStep(clamped, step);
	}

	function onFocus() {
		editing = true;
		editor.focus(value);
	}

	function onInput(event: Event) {
		text = (event.currentTarget as HTMLInputElement).value;
	}

	function commit(target: HTMLInputElement) {
		const parsed = parseEntry(text, { min, max });
		if (parsed !== null) onchange(roundToStep(parsed, step));
		// An unparseable entry is silently discarded, not coerced — the `$effect` above resyncs
		// `text` to the last-committed `value` once `editing` flips false below.
		editing = false;
		editor.commit();
		target.blur();
	}

	function onBlur() {
		if (editing) {
			editing = false;
			editor.commit();
		}
	}

	function onKeyDown(event: KeyboardEvent) {
		const target = event.currentTarget as HTMLInputElement;
		if (event.key === 'Enter') {
			event.preventDefault();
			commit(target);
			return;
		}
		if (event.key === 'Escape') {
			event.preventDefault();
			const reverted = editor.escape();
			editing = false;
			if (reverted !== null) {
				text = String(reverted);
				if (reverted !== value) onchange(reverted);
			}
			target.blur();
			return;
		}
		if (!isArrowKey(event.key)) return;
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

	// Drag-to-scrub, tracked with a plain (non-reactive) closure variable rather than `$state` — it
	// is pointer bookkeeping the template never reads, not UI state, so making it reactive would
	// just cost extra dirty-checking for no benefit.
	let dragOrigin: { pointerId: number; x: number; value: number } | null = null;

	function onGripPointerDown(event: PointerEvent) {
		if (event.button !== 0) return;
		(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId);
		dragOrigin = { pointerId: event.pointerId, x: event.clientX, value };
	}

	function onGripPointerMove(event: PointerEvent) {
		if (!dragOrigin || dragOrigin.pointerId !== event.pointerId) return;
		const delta = scrubDelta({
			dx: event.clientX - dragOrigin.x,
			step,
			modifiers: { shiftKey: event.shiftKey, altKey: event.altKey }
		});
		onchange(clampRound(dragOrigin.value + delta));
	}

	function endDrag(event: PointerEvent) {
		if (!dragOrigin || dragOrigin.pointerId !== event.pointerId) return;
		(event.currentTarget as HTMLElement).releasePointerCapture(event.pointerId);
		dragOrigin = null;
	}
</script>

<span class="wade-number-field">
	<span
		class="wade-number-field__grip"
		aria-hidden="true"
		onpointerdown={onGripPointerDown}
		onpointermove={onGripPointerMove}
		onpointerup={endDrag}
		onpointercancel={endDrag}
	>
		{label}
	</span>
	<input
		type="text"
		inputmode="decimal"
		role="spinbutton"
		class="wade-number-field__input"
		aria-label={label}
		aria-valuenow={value}
		aria-valuemin={min}
		aria-valuemax={max}
		value={text}
		oninput={onInput}
		onfocus={onFocus}
		onblur={onBlur}
		onkeydown={onKeyDown}
	/>
</span>

<style>
	.wade-number-field {
		display: inline-flex;
		align-items: stretch;
		height: var(--wade-control-height);
		border: 1px solid var(--wade-border);
		border-radius: var(--wade-radius-sm);
		overflow: hidden;
		font-family: var(--wade-font-family);
		font-size: var(--wade-font-size);
	}

	.wade-number-field__grip {
		display: flex;
		align-items: center;
		padding: 0 var(--wade-space-2);
		background: var(--wade-surface-raised);
		color: var(--wade-text-muted);
		cursor: ew-resize;
		touch-action: none;
		user-select: none;
		white-space: nowrap;
	}

	.wade-number-field__input {
		flex: 1;
		min-width: 0;
		border: none;
		padding: 0 var(--wade-space-2);
		background: var(--wade-surface);
		color: var(--wade-text);
		font: inherit;
	}

	.wade-number-field__input:focus-visible {
		outline: 2px solid var(--wade-focus-ring);
		outline-offset: -2px;
	}
</style>
