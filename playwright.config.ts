import { defineConfig } from '@playwright/test';

// Five projects, because "a frame rendered" is true on *either* graphics backend and so cannot by
// itself prove invariant 5 (WebGPU by default, WebGL2 as the escape hatch). Each project pins down
// one part of the suite:
//
//   chromium — no WebGPU flag, so navigator.gpu is absent and the renderer takes its automatic
//              WebGL2 fallback. Keeps that fallback exercised rather than merely theoretical.
//              Runs against `?kernel=off` (issue #25) — the Phase 1 scene only.
//   webgpu   — --enable-unsafe-webgpu, which is sufficient on its own: Chrome ships a SwiftShader
//              WebGPU backend, so a headless CI runner with no GPU still gets a real adapter — no
//              Vulkan driver install and no GPU runner required. Also runs against `?kernel=off`;
//              which backend gets used is orthogonal to the kernel.
//   kernel   — the kernel-driven parametric scene (issues #25, #26). Its own project because it's
//              the one suite that has to wait on the ~22 MB occt-wasm module compiling on first
//              load, so it gets a much longer default test timeout than the other two — without
//              this, the fast suites above would either inherit that timeout needlessly or the
//              kernel suite would flake under their tighter one.
//   snapping — vertex/edge/grid snapping (issue #27). Wired only into the kernel-driven scene (see
//              Scene.svelte), so it navigates to `/` and waits on the same occt-wasm module as the
//              'kernel' project — hence the same longer timeout, as its own project rather than
//              folded into 'kernel' so a testMatch change to one can't accidentally pick up the
//              other's spec file.
//   orientation — the world's right-handed Z-up convention (viewport/orientation.ts): that the box
//              params move the axes they claim to, that the ground plane really is Z = 0, and that
//              the axes indicator is mounted only in the kernel scene. Kernel-driven, so same
//              longer timeout and same own-project rationale as 'snapping'.
//
// --enable-gpu is what decides *which* adapter you get. Headless Chromium disables the GPU by
// default and hands back SwiftShader even on a machine with a perfectly good one; with the flag, a
// developer machine resolves to real hardware (metal-3 on Apple silicon) while a GPU-less CI runner
// still degrades to SwiftShader. That is why the hardware-acceleration assertion in webgpu.e2e.ts
// can pass locally and skip on CI rather than being impossible everywhere.
//
// WebGPU requires a secure context; http://localhost:4173 qualifies.
export default defineConfig({
	webServer: { command: 'npm run build && npm run preview', port: 4173 },
	projects: [
		{
			name: 'chromium',
			testMatch: '**/viewport.e2e.ts'
		},
		{
			name: 'webgpu',
			testMatch: '**/webgpu.e2e.ts',
			use: { launchOptions: { args: ['--enable-unsafe-webgpu', '--enable-gpu'] } }
		},
		{
			name: 'kernel',
			testMatch: '**/kernel.e2e.ts',
			timeout: 150_000
		},
		{
			name: 'snapping',
			testMatch: '**/snapping.e2e.ts',
			timeout: 150_000
		},
		{
			name: 'orientation',
			testMatch: '**/orientation.e2e.ts',
			timeout: 150_000
		}
	]
});
