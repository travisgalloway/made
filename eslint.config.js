import prettier from 'eslint-config-prettier';
import path from 'node:path';
import js from '@eslint/js';
import svelte from 'eslint-plugin-svelte';
import { defineConfig, includeIgnoreFile } from 'eslint/config';
import globals from 'globals';
import ts from 'typescript-eslint';

const gitignorePath = path.resolve(import.meta.dirname, '.gitignore');

export default defineConfig(
	includeIgnoreFile(gitignorePath),
	js.configs.recommended,
	ts.configs.recommended,
	svelte.configs.recommended,
	prettier,
	svelte.configs.prettier,
	{
		languageOptions: { globals: { ...globals.browser, ...globals.node } },
		rules: {
			// typescript-eslint strongly recommend that you do not use the no-undef lint rule on TypeScript projects.
			// see: https://typescript-eslint.io/troubleshooting/faqs/eslint/#i-get-errors-from-the-no-undef-rule-about-global-variables-not-being-defined-even-though-there-are-no-typescript-errors
			'no-undef': 'off'
		}
	},
	{
		files: ['**/*.svelte', '**/*.svelte.ts', '**/*.svelte.js'],
		languageOptions: {
			parserOptions: {
				projectService: true,
				extraFileExtensions: ['.svelte'],
				parser: ts.parser
			}
		}
	},
	{
		// Override or add rule settings here, such as:
		// 'svelte/button-has-type': 'error'
		rules: {}
	},
	{
		// Architecture invariant 1 (issue #1): no brepjs/OCCT symbol may execute on the main
		// thread — `kernel.worker.ts` is the one file allowed to name either package. Using the
		// base (non-TS) `no-restricted-imports` rather than `@typescript-eslint/no-restricted-
		// imports` is deliberate: the base rule also flags `import type`, so "no brepjs symbol
		// reachable from the main thread" stays true even for type-only imports, and the
		// invariant is defensible as "the string `brepjs` appears in exactly one file" — a claim
		// CI (`pnpm lint`) actually checks, not just a comment.
		files: ['src/**'],
		ignores: ['src/lib/kernel/kernel.worker.ts'],
		rules: {
			'no-restricted-imports': [
				'error',
				{ patterns: ['brepjs', 'brepjs/*', 'occt-wasm', 'occt-wasm/*'] }
			]
		}
	},
	{
		// The worker has no DOM, no renderer, and no SvelteKit runtime — it only ever talks to
		// the main thread through the typed `KernelRequest`/`KernelResult` wire contract in
		// `./types`, never by reaching for app-side modules directly.
		files: ['src/lib/kernel/kernel.worker.ts'],
		rules: {
			'no-restricted-imports': [
				'error',
				{ patterns: ['three', 'three/*', '@threlte/*', '$app/*', '$lib/*'] }
			]
		}
	},
	{
		// Architecture invariant 3 (issue #68): the in-house control kit is plain DOM and never
		// imports `three` — reactive state drives UI panels only, geometry and per-frame state
		// never live behind a `$state` these controls could reach into. Until this rule existed,
		// invariant 3 was only *asserted* ("`ParamsPanel.svelte` never imports `three`. Reviewed,
		// not automated.", per invariants.md) — this makes it *checked*, matching invariants 1,
		// 2, 4, 5, and 6. Same base (non-TS) `no-restricted-imports` rule as the brepjs/occt-wasm
		// ban above, for the same reason: it also flags `import type`, so the invariant holds
		// even for type-only imports.
		files: ['src/lib/ui/**'],
		rules: {
			'no-restricted-imports': ['error', { patterns: ['three', 'three/*', '@threlte/*'] }]
		}
	}
);
