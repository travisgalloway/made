<script lang="ts">
	// Lives inside <Canvas> (mounted by Viewport.svelte), so `useThrelte()` and Threlte's own
	// context hooks are available here. Owns the camera, lights, orbit controls, the scene's
	// geometry sources, and (issues #16-#19, #48) input routing, picking, the gizmo and instancing.
	// The geometry/camera references below are load-once, not per-frame (invariant 3) — nothing
	// here is written to on every tick.
	//
	// Two geometry sources, chosen by `settings.kernel` (issue #25):
	//   - kernel ON (default): a KernelClient-driven box + cylinder, computed off-thread by
	//     kernel.worker.ts and streamed back as `MeshPayload`s. The KernelClient is created inside
	//     an `$effect`, never at module scope — `new Worker` doesn't exist during SvelteKit's
	//     SSR/shell pass.
	//   - kernel OFF (`?kernel=off`, or a fatal kernel init error at runtime): exactly the Phase 1
	//     scene — the STL sample part, no worker booted at all. This is what keeps
	//     `viewport.e2e.ts`/`webgpu.e2e.ts` fast and untouched, and is a real graceful-degradation
	//     path, not just a test convenience.
	// Both scenes keep the instanced bolts (issue #48) — they're procedural decoration, not tied to
	// either geometry source.
	import { T, useThrelte } from '@threlte/core';
	import { OrbitControls, TransformControls, useOrbitControls } from '@threlte/extras';
	import {
		Box3,
		SphereGeometry,
		TOUCH,
		Vector3,
		type BufferGeometry,
		type Mesh,
		type InstancedMesh,
		type Object3D,
		type PerspectiveCamera
	} from 'three';
	import type { TransformControls as TransformControlsImpl } from 'three/examples/jsm/controls/TransformControls.js';
	import { MeshBasicNodeMaterial, MeshStandardNodeMaterial } from 'three/webgpu';
	import { createKernelClient } from '$lib/kernel/createKernelClient';
	import type { KernelClient } from '$lib/kernel/KernelClient';
	import { toBufferGeometry } from '$lib/kernel/geometry';
	import type { BoxParams, CylinderParams } from '$lib/kernel/types';
	import { BOX_SOLID_ID, CYLINDER_SOLID_ID, type DocumentModel } from '$lib/scene/document.svelte';
	import { settings } from '$lib/settings/settings.svelte';
	import { createAxesIndicator } from './axes';
	import { frameBox } from './framing';
	import { GIZMO_SIZE } from './gizmo';
	import { allGeometriesIndexed, BOLT_POSITIONS, createBoltInstances } from './instancing';
	import { DEFAULT_VIEW_DIRECTION, installZUpWorld } from './orientation';
	import { invalidateFor } from './renderLoop';
	import { loadSampleMesh } from './sampleMesh';
	import { buildBoundsTree, installBVHAcceleration, Picker, type PointerKind } from './picking';
	import { PointerRouter, type PointerType } from '$lib/input/pointerRouter';
	import type { GestureDecision } from '$lib/input/gestureArbiter';
	import { createSceneModel } from '$lib/scene/SceneModel.svelte';
	import { createSnapModel } from '$lib/scene/SnapModel.svelte';
	import {
		DEFAULT_GRID_SPACING,
		DEFAULT_SNAP_TOLERANCE_PX,
		resolveSnapAtPointer,
		type SnapKind
	} from '$lib/input/snapping';

	let { documentModel }: { documentModel: DocumentModel } = $props();

	// One-time global prototype patch (idempotent) — see picking.ts.
	installBVHAcceleration();

	// Makes +Z the world's up axis (idempotent) — see orientation.ts. At module scope, not in an
	// $effect, because `Object3D.DEFAULT_UP` is copied into each instance's `up` at construction:
	// this has to run before the camera and controls below are built, or they would stay Y-up in a
	// Z-up world.
	installZUpWorld();

	const { invalidate, dom, size } = useThrelte();
	const orbitControls = useOrbitControls();
	const sceneModel = createSceneModel(invalidate);
	const snapModel = createSnapModel(invalidate);
	const router = new PointerRouter();
	const picker = new Picker();

	let camera = $state.raw<PerspectiveCamera>();

	// The `?kernel=off` / Phase 1 fallback scene.
	let geometry = $state.raw<BufferGeometry>();
	let mesh = $state.raw<Mesh>();

	// The kernel-driven scene (issue #25). `kernelFatal` is what turns a kernel init failure into a
	// live fallback to the STL scene above, rather than a permanently blank viewport.
	let boxGeometry = $state.raw<BufferGeometry>();
	let boxMesh = $state.raw<Mesh>();
	let cylinderGeometry = $state.raw<BufferGeometry>();
	let cylinderMesh = $state.raw<Mesh>();
	let kernelClient = $state.raw<KernelClient>();
	let kernelFatal = $state(false);
	let useKernel = $derived(settings.kernel && !kernelFatal);

	let boltMesh = $state.raw<InstancedMesh>();
	let axesObject = $state.raw<Object3D>();
	let transformControls = $state.raw<TransformControlsImpl>();
	let gizmoDragging = $state(false);

	// The camera's opening pose, before anything is loaded and `frameBox` takes over. Derived from
	// the same 3/4 direction `frameBox` defaults to (orientation.ts), so the initial view and the
	// framed view look at the scene from the same angle rather than snapping between two.
	const INITIAL_CAMERA_DISTANCE = 10;
	const initialCameraPosition = DEFAULT_VIEW_DIRECTION.clone()
		.normalize()
		.multiplyScalar(INITIAL_CAMERA_DISTANCE)
		.toArray();

	// A stable local binding for the template's {#if} to narrow against, and for the pointer
	// handlers below to read without going through the SceneModel getter twice.
	let selectedObject = $derived(sceneModel.selected);

	// Whichever objects are actually pickable right now — one mesh in the fallback scene, up to two
	// in the kernel scene. Both `Picker.pick()` and hover/selection highlighting key off this.
	let pickableObjects = $derived<Object3D[]>(
		useKernel
			? ([boxMesh, cylinderMesh].filter((o): o is Mesh => o !== undefined) as Object3D[])
			: mesh
				? [mesh]
				: []
	);

	// Snapping (issue #27) is wired only into the kernel scene, not the `?kernel=off` fallback:
	// adding a ground grid + marker there would add draw calls to the exact-drawCalls assertion in
	// viewport.e2e.ts (EXPECTED_DRAW_CALLS === 3), which that suite always exercises. The snapping
	// library itself (src/lib/input/snapping.ts) has no kernel dependency either way — this is
	// purely about which demo scene shows it, not a limitation of the feature. See e2e/snapping.e2e.ts,
	// which drives the kernel scene instead.
	let snapMeshes = $derived<Mesh[]>(
		useKernel ? ([boxMesh, cylinderMesh].filter((o): o is Mesh => o !== undefined) as Mesh[]) : []
	);

	const SNAP_MARKER_COLORS: Record<SnapKind, number> = {
		vertex: 0xffcc33, // amber — the highest-priority, most precise snap kind
		edge: 0x33c3ff, // cyan
		grid: 0x7ccf7c // green
	};
	const snapMarkerGeometry = new SphereGeometry(1.5, 16, 16);
	const snapMarkerMaterial = new MeshBasicNodeMaterial({ color: SNAP_MARKER_COLORS.vertex });

	// Recolors the marker per the current snap kind, so a user can tell *why* it snapped — the
	// difference between a vertex/edge/grid lock, not just that one happened (invariant 9).
	$effect(() => {
		const current = snapModel.current;
		if (!current) return;
		snapMarkerMaterial.color.setHex(SNAP_MARKER_COLORS[current.kind]);
	});

	const material = new MeshStandardNodeMaterial({
		color: 0x9fb4c7,
		roughness: 0.55,
		metalness: 0.1
	});

	const boxMaterial = new MeshStandardNodeMaterial({
		color: 0x9fb4c7,
		roughness: 0.55,
		metalness: 0.1
	});

	const cylinderMaterial = new MeshStandardNodeMaterial({
		color: 0x8a9fb0,
		roughness: 0.5,
		metalness: 0.15
	});

	// Distinct finish from the bracket/kernel solids so the repeated hardware (issue #48) reads as
	// separate parts, not more of the bracket/solids themselves.
	const boltMaterial = new MeshStandardNodeMaterial({
		color: 0x51565c,
		roughness: 0.35,
		metalness: 0.85
	});

	/** Applies the selected/hovered emissive tint (or none) to `mat`, matching whether `object` is
	 *  the scene model's current selection/hover target. */
	function applyHighlight(mat: MeshStandardNodeMaterial, object: Object3D | undefined) {
		const isSelected = object !== undefined && sceneModel.selected === object;
		const isHovered = object !== undefined && sceneModel.hovered === object;
		if (isSelected) {
			mat.emissive.setRGB(0.32, 0.22, 0.02);
		} else if (isHovered) {
			mat.emissive.setRGB(0.14, 0.14, 0.14);
		} else {
			mat.emissive.setRGB(0, 0, 0);
		}
	}

	// Selection/hover feedback is a plain material tweak — no ShaderMaterial/onBeforeCompile, so it
	// stays within the TSL-only constraint. Runs whenever the view-model changes; SceneModel's own
	// setters already invalidated for this transient interaction, so this doesn't invalidate again.
	$effect(() => {
		let isSelected: boolean;
		let isHovered: boolean;

		if (useKernel) {
			applyHighlight(boxMaterial, boxMesh);
			applyHighlight(cylinderMaterial, cylinderMesh);
			isSelected =
				(boxMesh !== undefined && sceneModel.selected === boxMesh) ||
				(cylinderMesh !== undefined && sceneModel.selected === cylinderMesh);
			isHovered =
				(boxMesh !== undefined && sceneModel.hovered === boxMesh) ||
				(cylinderMesh !== undefined && sceneModel.hovered === cylinderMesh);
		} else {
			applyHighlight(material, mesh);
			isSelected = mesh !== undefined && sceneModel.selected === mesh;
			isHovered = mesh !== undefined && sceneModel.hovered === mesh;
		}

		// Exposed for the e2e selection test, same pattern as renderCount/backend in renderLoop.ts.
		if (typeof window !== 'undefined' && window.__wade) {
			window.__wade.selected = isSelected;
			window.__wade.hovered = isHovered;
		}
	});

	// The `?kernel=off` / fallback scene: the Phase 1 STL sample part. Only runs while the kernel
	// scene isn't in play — either because `settings.kernel` was off from the start, or because
	// `kernelFatal` flipped true after a kernel init failure (see the kernel `$effect` below).
	$effect(() => {
		if (useKernel) return;

		let cancelled = false;

		loadSampleMesh().then(({ geometry: loaded }) => {
			if (cancelled) return;

			buildBoundsTree(loaded);
			geometry = loaded;
			invalidateFor(invalidate, 'model');

			if (!camera) return;

			loaded.computeBoundingBox();
			const box = loaded.boundingBox ?? new Box3();
			const { position, target } = frameBox({ box, fovDegrees: camera.fov, aspect: camera.aspect });

			camera.position.copy(position);
			const controls = orbitControls.current;
			if (controls) {
				controls.target.copy(target);
				controls.update();
			} else {
				camera.lookAt(target);
			}
			invalidateFor(invalidate, 'camera');
		});

		return () => {
			cancelled = true;
		};
	});

	// The kernel-driven scene (issues #25, #26). Creating the client here — inside an `$effect`,
	// never at module scope — is what keeps `new Worker` out of the SSR/shell pass. Only runs when
	// the kernel is enabled at all; a later `kernelFatal` flip doesn't tear this down (there is
	// nothing more for it to do once it has already reported the fatal error), it only redirects
	// the fallback `$effect` above into loading the STL scene instead.
	$effect(() => {
		if (!settings.kernel) return;

		const client = createKernelClient();
		kernelClient = client;

		let meshCount = 0;
		if (typeof window !== 'undefined' && window.__wade) {
			window.__wade.kernelReady = false;
			window.__wade.kernelMeshCount = 0;
		}

		const offMesh = client.onMesh((solidId, payload) => {
			const nextGeometry = toBufferGeometry(payload);
			buildBoundsTree(nextGeometry);

			// Dispose the outgoing geometry (and its BVH) once replaced — a slider drag would
			// otherwise leak one BufferGeometry per tick.
			if (solidId === BOX_SOLID_ID) {
				const previous = boxGeometry;
				boxGeometry = nextGeometry;
				previous?.disposeBoundsTree();
				previous?.dispose();
			} else if (solidId === CYLINDER_SOLID_ID) {
				const previous = cylinderGeometry;
				cylinderGeometry = nextGeometry;
				previous?.disposeBoundsTree();
				previous?.dispose();
			}

			meshCount += 1;
			if (typeof window !== 'undefined' && window.__wade) {
				window.__wade.kernelMeshCount = meshCount;
			}

			// Exactly one invalidate() per completed update (invariant 2, issue #25's AC) — the
			// debounce/conflation in KernelClient is what guarantees onMesh fires once per settled,
			// non-superseded request rather than once per input event.
			invalidateFor(invalidate, 'model');
		});

		const offError = client.onError((error) => {
			if (typeof window !== 'undefined' && window.__wade) {
				window.__wade.kernelError = error.message;
			}
			// The only fatal case: OCCT itself never booted. Anything else (e.g. invalid slider
			// params) is a per-request failure, not a reason to abandon the kernel scene.
			if (error.code === 'kernel-init-failed') {
				kernelFatal = true;
			}
		});

		client.warmup().then(() => {
			// `KernelClient.warmup()` never rejects on a typed kernel failure (it routes that
			// through `onError`, awaited above in the same microtask chain before this resolves) —
			// only reaching here with `kernelFatal` still false means it actually succeeded.
			if (kernelFatal) return;
			if (typeof window !== 'undefined' && window.__wade) {
				window.__wade.kernelReady = true;
			}
		});

		return () => {
			offMesh();
			offError();
			client.dispose();
			if (kernelClient === client) kernelClient = undefined;

			// KernelClient.dispose() only tears down this client's own bookkeeping/listeners, not
			// the worker-side solids (see its docstring) — this demo scene never actually removes a
			// solid mid-session, so no `KernelWorkerApi.dispose(solidId)` call is needed here; the
			// whole worker is torn down along with `client`.
			if (boxGeometry) {
				boxGeometry.disposeBoundsTree();
				boxGeometry.dispose();
				boxGeometry = undefined;
			}
			if (cylinderGeometry) {
				cylinderGeometry.disposeBoundsTree();
				cylinderGeometry.dispose();
				cylinderGeometry = undefined;
			}
		};
	});

	// Narrows `documentModel.paramsFor()`'s union return by structural shape, rather than casting —
	// both objects in the default document always resolve to their own kind here, but this stays
	// correct even if #66's generalized Scene calls it against an id whose kind isn't known statically.
	function narrowBoxParams(params: BoxParams | CylinderParams | undefined): BoxParams | undefined {
		return params && 'width' in params ? params : undefined;
	}

	function narrowCylinderParams(
		params: BoxParams | CylinderParams | undefined
	): CylinderParams | undefined {
		return params && 'radius' in params ? params : undefined;
	}

	// Sends the box solid's current params whenever they change, once the client exists. Runs once
	// immediately when `kernelClient` first becomes defined (sending the initial params), and again
	// on every subsequent slider edit — debounced/conflated inside KernelClient itself (issue #26).
	// `documentModel.paramsFor()` always returns a fresh plain object, never the Svelte proxy
	// (document.svelte.ts) — that's what lets it cross the postMessage boundary inside `request()`.
	$effect(() => {
		const client = kernelClient;
		if (!client) return;
		const params = narrowBoxParams(documentModel.paramsFor(BOX_SOLID_ID));
		if (!params) return;
		client.request({ type: 'box', solidId: BOX_SOLID_ID, params });
	});

	$effect(() => {
		const client = kernelClient;
		if (!client) return;
		const params = narrowCylinderParams(documentModel.paramsFor(CYLINDER_SOLID_ID));
		if (!params) return;
		client.request({ type: 'cylinder', solidId: CYLINDER_SOLID_ID, params });
	});

	// Frames the camera on the kernel scene exactly once, the first time all three of the box,
	// cylinder and bolts have mounted — never again after, so later slider-driven updates stay at
	// exactly one invalidate() each (issue #25's AC) instead of also re-triggering a camera fit.
	let hasFramedKernelScene = false;
	$effect(() => {
		if (!useKernel || hasFramedKernelScene) return;
		if (!camera || !boxMesh || !cylinderMesh || !boltMesh) return;

		hasFramedKernelScene = true;
		const box = new Box3();
		box.expandByObject(boxMesh);
		box.expandByObject(cylinderMesh);
		box.expandByObject(boltMesh);
		const { position, target } = frameBox({ box, fovDegrees: camera.fov, aspect: camera.aspect });

		camera.position.copy(position);
		const controls = orbitControls.current;
		if (controls) {
			controls.target.copy(target);
			controls.update();
		} else {
			camera.lookAt(target);
		}
		invalidateFor(invalidate, 'camera');
	});

	// Bolts are procedural (issue #48), so unlike the sample mesh above they need no async load —
	// built once on mount, and it's a legitimate "model changed" invalidation like the mesh load.
	$effect(() => {
		const instanced = createBoltInstances(BOLT_POSITIONS, boltMaterial);
		boltMesh = instanced;
		invalidateFor(invalidate, 'model');

		return () => {
			instanced.geometry.dispose();
		};
	});

	// The origin axes indicator (see axes.ts). Built in an `$effect`, never at module scope, because
	// its labels are canvas textures and `document` doesn't exist during SvelteKit's SSR/shell pass
	// — the same constraint that keeps `new Worker` out of module scope above. Only mounted in the
	// kernel scene, alongside the grid, for the draw-call reason documented on `snapMeshes`.
	$effect(() => {
		if (!useKernel) return;

		const axes = createAxesIndicator();
		axesObject = axes.object;
		invalidateFor(invalidate, 'model');

		return () => {
			axes.dispose();
			axesObject = undefined;
		};
	});

	// Exposed for e2e (orientation.e2e.ts), same pattern as the rest of window.__wade.
	$effect(() => {
		if (typeof window === 'undefined' || !window.__wade) return;
		window.__wade.axesPresent = axesObject !== undefined;
	});

	// Screen-space projection hook for e2e (orientation.e2e.ts). Reads the camera at call time
	// rather than capturing a snapshot, so a test can orbit and re-project against the moved camera.
	$effect(() => {
		const activeCamera = camera;
		if (!activeCamera) return;
		if (typeof window === 'undefined' || !window.__wade) return;

		window.__wade.projectToNdc = (point) => {
			const projected = new Vector3(...point).project(activeCamera);
			return [projected.x, projected.y];
		};
	});

	// The box's world-space size, republished on every re-tessellation. This is what makes the
	// up-axis convention assertable from a test: `boxExtents[2]` is the Height param, because Height
	// is Z (orientation.ts). Reads `boxGeometry` explicitly — the mesh object is reused across
	// updates while its geometry is swapped, so depending on `boxMesh` alone would not re-run this.
	$effect(() => {
		const mesh = boxMesh;
		const geometry = boxGeometry;
		if (!mesh || !geometry) return;
		if (typeof window === 'undefined' || !window.__wade) return;

		const size = new Box3().setFromObject(mesh).getSize(new Vector3());
		window.__wade.boxExtents = [size.x, size.y, size.z];
	});

	// <TransformControls>'s own autoPauseControls (default true) already disables the registered
	// OrbitControls for as long as `dragging` is true — that alone is what stops a gizmo drag from
	// also orbiting the camera (invariant 8). This listener tracks the same flag locally so the
	// pointer handlers below can treat an in-progress gizmo drag as the `manipulate` gesture it is,
	// instead of reacting to whatever mode the router computed for the underlying mouse/touch drag
	// (see onPointerMove/onPointerRelease).
	$effect(() => {
		const controls = transformControls;
		if (!controls) return;

		const onDraggingChanged = (event: { value: unknown }) => {
			gizmoDragging = Boolean(event.value);
		};
		controls.addEventListener('dragging-changed', onDraggingChanged);
		return () => controls.removeEventListener('dragging-changed', onDraggingChanged);
	});

	// Exposed for e2e (issues #19, #48), same pattern as renderCount/backend in renderLoop.ts.
	$effect(() => {
		if (typeof window === 'undefined' || !window.__wade) return;
		window.__wade.gizmoVisible = selectedObject !== null;
	});

	$effect(() => {
		if (!boltMesh) return;
		if (typeof window === 'undefined' || !window.__wade) return;
		window.__wade.boltCount = BOLT_POSITIONS.length;

		const roots: Object3D[] = useKernel
			? [boxMesh, cylinderMesh, boltMesh].filter((o) => o !== undefined)
			: [mesh, boltMesh].filter((o) => o !== undefined);
		window.__wade.allIndexed = allGeometriesIndexed(roots);
	});

	// Exposed for e2e (issue #27), same pattern as the rest of window.__wade.
	$effect(() => {
		if (typeof window === 'undefined' || !window.__wade) return;
		const current = snapModel.current;
		window.__wade.snapKind = current?.kind ?? null;
		window.__wade.snapPoint = current
			? [current.point.x, current.point.y, current.point.z]
			: undefined;
	});

	function toPointerType(pointerType: string): PointerType {
		if (pointerType === 'pen') return 'pen';
		if (pointerType === 'touch') return 'touch';
		return 'mouse';
	}

	function localPoint(event: PointerEvent): { x: number; y: number } {
		const rect = dom.getBoundingClientRect();
		return { x: event.clientX - rect.left, y: event.clientY - rect.top };
	}

	function pick(event: PointerEvent, pointerKind: PointerKind): Object3D | null {
		if (!camera || pickableObjects.length === 0) return null;
		const { x, y } = localPoint(event);
		const { width, height } = size.current;
		return picker.pick({ x, y, pointerKind, width, height, camera, objects: pickableObjects });
	}

	// Snapping (issue #27) is a hover/manipulate-channel concern, not a camera one (invariant 8) —
	// it clears while an active gesture has locked to `navigate` (an orbit/pan in progress) or while
	// the gizmo is being dragged (that's its own manipulate gesture already giving its own visual
	// feedback), exactly mirroring the hover-picking gate right below this function's call site.
	function updateSnap(event: PointerEvent, decision: GestureDecision) {
		if (!useKernel || !camera || gizmoDragging || decision.mode === 'navigate') {
			snapModel.setSnap(null);
			return;
		}

		const { x, y } = localPoint(event);
		const { width, height } = size.current;
		const result = resolveSnapAtPointer({
			pointer: { x, y },
			width,
			height,
			camera,
			meshes: snapMeshes,
			gridSpacing: DEFAULT_GRID_SPACING,
			tolerancePx: DEFAULT_SNAP_TOLERANCE_PX
		});
		snapModel.setSnap(result);
	}

	// Invariant 8 (navigation and editing never share a gesture): three.js's OrbitControls treats
	// pen exactly like mouse (both go through its `_onMouseDown` path), which would let a pen drag
	// orbit the camera — pen must always be the precise create/edit channel instead. Registering our
	// own listener on `dom` with `capture: true` guarantees it runs during the capture phase, before
	// OrbitControls' own (bubble-phase) listener on the same element ever sees the event — capture
	// always completes, top-down through ancestors of the real target (the canvas), before bubbling
	// begins, regardless of listener registration order. Calling `stopPropagation()` there for pen
	// pointers means OrbitControls never receives them at all; touch and mouse are left untouched so
	// OrbitControls keeps driving camera navigation for them exactly as it already does (with
	// single-finger touch orbit disabled below, since that must go to selection/manipulation instead).
	function onPointerDown(event: PointerEvent) {
		const pointerType = toPointerType(event.pointerType);
		if (pointerType === 'pen') event.stopPropagation();

		const { x, y } = localPoint(event);
		router.handle({ type: 'down', pointerType, pointer: { pointerId: event.pointerId, x, y } });
	}

	function onPointerMove(event: PointerEvent) {
		const pointerType = toPointerType(event.pointerType);
		if (pointerType === 'pen') event.stopPropagation();

		const { x, y } = localPoint(event);
		const decision = router.handle({
			type: 'move',
			pointerType,
			pointer: { pointerId: event.pointerId, x, y }
		});

		updateSnap(event, decision);

		// A gizmo drag is the `manipulate` gesture in progress (invariant 8) — never let it also
		// drive hover picking against the underlying mesh, regardless of what mode the router
		// computed for the mouse/touch drag that's operating the gizmo.
		if (gizmoDragging) return;

		// Hover is only meaningful while nothing has locked to navigate — an active orbit/pan must
		// never also drive hover picking (invariant 8), and this is also what keeps a plain
		// mouse-move-with-no-buttons-down (decision.mode stays null) able to hover at all.
		sceneModel.setHovered(decision.mode === 'navigate' ? null : pick(event, pointerType));
	}

	function onPointerRelease(type: 'up' | 'cancel') {
		return (event: PointerEvent) => {
			const pointerType = toPointerType(event.pointerType);
			if (pointerType === 'pen') event.stopPropagation();

			const decision = router.handle({ type, pointerType, pointerId: event.pointerId });

			// A gizmo drag ending is a manipulate gesture finishing, not a selection click — running
			// the selection pick here (which only tests the bare mesh, not the gizmo) could wrongly
			// deselect the object right after transforming it.
			if (gizmoDragging) return;

			if (type === 'up' && decision.mode === 'manipulate') {
				sceneModel.setSelected(pick(event, pointerType));
			}
		};
	}

	$effect(() => {
		const onUp = onPointerRelease('up');
		const onCancel = onPointerRelease('cancel');
		const opts = { capture: true } as const;

		dom.addEventListener('pointerdown', onPointerDown, opts);
		dom.addEventListener('pointermove', onPointerMove, opts);
		dom.addEventListener('pointerup', onUp, opts);
		dom.addEventListener('pointercancel', onCancel, opts);

		return () => {
			dom.removeEventListener('pointerdown', onPointerDown, opts);
			dom.removeEventListener('pointermove', onPointerMove, opts);
			dom.removeEventListener('pointerup', onUp, opts);
			dom.removeEventListener('pointercancel', onCancel, opts);
		};
	});
</script>

<T.PerspectiveCamera
	makeDefault
	bind:ref={camera}
	position={initialCameraPosition}
	fov={50}
	near={0.1}
	far={2000}
>
	<!-- touches.ONE disabled: a single finger must select/manipulate, never orbit (invariant 8).
	     Two fingers keep the native dolly+pan navigate behavior. Mouse buttons are left at their
	     three.js defaults (desktop drag-to-orbit). -->
	<OrbitControls touches={{ ONE: null, TWO: TOUCH.DOLLY_PAN }} />
</T.PerspectiveCamera>

<!-- HemisphereLight shines from its own +Y by default; in this Z-up world (orientation.ts) that
     would light the scene sideways, so it's rotated to put its sky hemisphere overhead. The
     directional key light is simply positioned high on +Z instead. -->
<T.HemisphereLight intensity={0.75} groundColor={0x3a3a3a} rotation={[Math.PI / 2, 0, 0]} />
<T.DirectionalLight position={[6, -4, 10]} intensity={1.4} />

{#if useKernel}
	{#if boxGeometry}
		<T.Mesh
			bind:ref={boxMesh}
			geometry={boxGeometry}
			material={boxMaterial}
			position={[-60, 0, 0]}
		/>
	{/if}
	{#if cylinderGeometry}
		<T.Mesh
			bind:ref={cylinderMesh}
			geometry={cylinderGeometry}
			material={cylinderMaterial}
			position={[60, 0, 0]}
		/>
	{/if}

	<!-- Ground grid (issue #27): the visible surface `snapToGrid` quantizes onto, and what makes
	     the grid-snap acceptance criterion checkable by hand, not just by reading the source.
	     GridHelper is authored in the XZ plane (three.js's Y-up default); rotating it a quarter turn
	     about X lays it on the XY plane (Z = 0), which is this world's ground — see orientation.ts
	     and snapping.ts's GROUND_PLANE, the two of which must agree for a grid snap to land on the
	     line the user actually sees. -->
	<T.GridHelper args={[300, 300 / DEFAULT_GRID_SPACING]} rotation={[Math.PI / 2, 0, 0]} />

	<!-- Origin axes indicator: labelled X/Y/Z triad at the center of the grid, so the Z-up
	     convention is legible in the viewport rather than only in orientation.ts. -->
	{#if axesObject}
		<T is={axesObject} />
	{/if}

	<!-- Snap indicator: follows the pointer and locks to the nearest vertex/edge/grid point,
	     color-coded per kind (see SNAP_MARKER_COLORS) so the "why" of a snap is visible, not
	     magic (invariant 9). Position updates flow from updateSnap() -> snapModel, which only
	     invalidates on an actual change — see SnapModel.svelte.ts. -->
	{#if snapModel.current}
		<T.Mesh
			geometry={snapMarkerGeometry}
			material={snapMarkerMaterial}
			position={[snapModel.current.point.x, snapModel.current.point.y, snapModel.current.point.z]}
		/>
	{/if}
{:else if geometry}
	<T.Mesh bind:ref={mesh} {geometry} {material} />
{/if}

{#if boltMesh}
	<T is={boltMesh} />
{/if}

{#if selectedObject}
	<TransformControls
		object={selectedObject}
		size={GIZMO_SIZE}
		bind:controls={transformControls}
		onobjectChange={() => invalidateFor(invalidate, 'interaction')}
	/>
{/if}
