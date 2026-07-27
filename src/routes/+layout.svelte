<script lang="ts">
	import '../app.css';
	// The repo's first design tokens (issue #68) — imported here, alongside app.css, because this is
	// the app's only CSS entry point; every component's scoped <style> block reaches these `:root`
	// vars from wherever it's mounted. See tokens.css's own header comment for the full rationale.
	import '$lib/ui/controls/tokens.css';
	import favicon from '$lib/assets/favicon.svg';

	let { children } = $props();
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
</svelte:head>

{@render children()}
