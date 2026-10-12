# Test plan

Date: 2026-10-11
Scope: macos/ (Swift package, test target MadeCoreTests)
Audit run: 20261011-195134

The plan covers 149 capabilities. The MadeCoreTests target holds 18 Swift Testing files with 128 tests, and every file imports MadeCore. The audit did not run `swift test`, so pass and fail status is unobserved.

Of the 149 capabilities, 85 have at least one unit or integration reference. Another 45 wired or partial capabilities have no reference of any kind. The remaining 19 are 13 claimed-only capabilities, which need no test until built, and 6 removed capabilities.

The audit found `KernelClientTests.testRapidRequestsConflateToLatestValue` flaky and a race in `KernelClient.executePending` (DSN-efe60d18). #90 fixed both. The test now enqueues requests in a fixed order, and `testStaleDebounceDoesNotStrandNewerRequest` covers the race.

Five capabilities have a test-only gap and no ticket: AGENT-1, AGENT-5, AGENT-8, DOC-8, and VIEW-22. Their rows in Table 2 name the gap.

Table 1 gives the class decisions. Table 2 gives the per-capability coverage.

Table 1. Test class decisions, macos/ scope, 2026-10-11.

| Class | Decision | Evidence |
| --- | --- | --- |
| Unit | clean for MadeCore logic (128 tests); n/a-by-construction for MadeApp | No test imports `MadeApp` (the executable target). `WorkspaceModel`, `NavigatorSidebarView`, `InspectorPanelView`, `ConsoleDrawerView`, `MCPServerView` and `CADMetalViewRepresentable` have no unit coverage, so every UI row depends on this. |
| Integration | in-process only; process-level absent | In-process: `MCPServerTests` (server to registry to document and kernel), `CADToolsTests`, and Metal 4 gated renderer tests (`GridGeneratorTests`, `AxesGeneratorTests`, `MetalRendererGeometryTests`) that drive renderer to snapshot to PNG, and `testSnapshotViaCADTools*` that drive registry to renderer. Process-level (stdio pipes, TCP client) is a gap, not n/a: `docs/guides/testing.md:56` documents manual stdio recipes and `Makefile:38` has `run-mcp`, so the class is corroborated and absent. Probe: grep for `Pipe()`, `Process()`, `XCUI`, `NWConnection`, `runStdio` in Tests found only the string `9820` context in MCPServerTests (`testStartAndStopTCPServer`, port 19820, start and stop only). |
| E2E / UI | n/a for UI; absent for stdio | No XCUITest target, no UITests directory, no `.xctestplan`, no Xcode project for the app (only Euclid's vendored one under `.build/checkouts`); `Package.swift` declares one test target (line 36); CI runs only `swift build --build-tests` and `swift test`. No second signal says a UI test class should exist, so UI E2E is n/a. The stdio E2E has a second signal (manual recipe) and is reported as a gap on AGENT-1 and AGENT-24. |

Gating note: the renderer integration tests are gated by `.enabled(if: MetalTestSupport.isMetal4Available)`. They skip on hosted CI runners, where the paravirtual GPU lacks Metal 4. Integration coverage of VIEW-7 to VIEW-12, VIEW-18, VIEW-19, VIEW-22, and AGENT-9 therefore runs only on a local Apple-silicon machine. `ShaderLibraryTests.testBundledLibraryHasEveryShaderEntryPoint` runs on any Metal device.

Table 2. Per-capability test coverage, macos/ scope, 2026-10-11. Source: closure pass C.

| ID | Unit | Integration | E2E | Edge cases covered | Gaps |
| --- | --- | --- | --- | --- | --- |
| VIEW-1 | ViewportStateTests.swift: testInitialStateIsInitializing, testStateResolverLogic, testNoDevicePathProducesUnavailableNoDevice, testForceNoGPUSeam, testPipelineCreationFailedProducesUnavailable, testDeviceLostAfterLaunchTransition, testDeviceLostViaNotification | none | none (no UI test target) | no device, pipeline failure, device lost | Only the state machine is tested. MTKView configuration (sRGB, 32-bit depth, clear color) in CADMetalViewRepresentable is unasserted. |
| VIEW-2 | none | none | none (no UI test target) | none | No test references this capability. Compiled only under #if os(iOS); Package.swift lists macOS only. |
| VIEW-3 | ViewportCoordinatorTests.swift: testRenderCountStaysFlatAtIdle (stub target) | none | none (no UI test target) | render count flat at idle | isPaused and enableSetNeedsDisplay on the real MTKView are never asserted. |
| VIEW-4 | ViewportCoordinatorTests.swift: testMeshSwapTriggersRedrawThroughCoordinator, testFailedKernelResultDoesNotRedraw, testWindowMinimizedSuppressesRedrawDuringUpdate, testRemovingSolidRedrawsOnce, testTwoMeshesSettleInSameFrame | none | none (no UI test target) | failed result, minimized window, two meshes in one frame | Tests drive ViewportCoordinator with a stub target. WorkspaceModel.invalidateViewport (MadeApp) and the Inspector, Navigator and perspective paths are not exercised. |
| VIEW-5 | ViewportCoordinatorTests.swift: testInvalidateReasonClassification, testCameraInvalidationAdvancesRedrawCountByExactlyOne | none | none (no UI test target) | all four reasons; exactly one redraw per camera invalidate | The MadeApp Coordinator.invalidate wrapper is not tested; only the MadeCore ViewportCoordinator. |
| VIEW-6 | ViewportCoordinatorTests.swift: testRenderInstrumentationTelemetry (data source only) | none | none (no UI test target) | record and reset | HUD view, status text wiring, active tool and snap kind fields are untested. |
| VIEW-7 | none | MetalRendererGeometryTests.swift: testBoxRendersInsideItsProjectedBounds, testBoxShowsItsTopFaceToACameraAbove (Metal 4 gated); GridGeneratorTests.swift: testSolidsRestingOnGroundPlaneSnapshot, testDefaultSceneWithSolidsAndGridSnapshot | none (no UI test target) | none | createMesh is exercised but .storageModeShared is never asserted. All renderer tests skip where Metal 4 is absent (CI). |
| VIEW-8 | none | MetalRendererGeometryTests.swift: testBoxRendersInsideItsProjectedBounds, testBoxShowsItsTopFaceToACameraAbove (Metal 4 gated); AxesGeneratorTests.swift: testMetalRendererAxesIntegration, testOriginHiddenBehindSolidSnapshot, testSnapshotLookingAlongEachAxis (Metal 4 gated) | none (no UI test target) | none | Offscreen snapshot draws only. The MTKView draw(in:) path and the renderCount and drawCalls increments after a real draw are not asserted. |
| VIEW-9 | none | MetalRendererGeometryTests.swift: testBoxRendersInsideItsProjectedBounds, testBoxShowsItsTopFaceToACameraAbove (Metal 4 gated); AxesGeneratorTests.swift: testOriginHiddenBehindSolidSnapshot; GridGeneratorTests.swift: testSolidsRestingOnGroundPlaneSnapshot | none (no UI test target) | inside-out box detection (culling); axes occluded by solid (depth) | Rotation and scale being ignored is not asserted; no test pins the translation-only behavior. |
| VIEW-10 | CameraTests.swift: testInitialCameraState, testCameraPresets | none | none (no UI test target) | default eye direction and distance | Reset View toolbar button and key H are untested. |
| VIEW-11 | none | AxesGeneratorTests.swift: testMetalRendererAxesIntegration, testOriginHiddenBehindSolidSnapshot, testSnapshotLookingAlongEachAxis (Metal 4 gated); AxesGeneratorTests.swift: testSnapshotViaCADToolsIncludesAxes; GridGeneratorTests.swift: testSnapshotViaCADTools (Metal 4 gated); MetalRendererGeometryTests.swift: testBoxRendersInsideItsProjectedBounds, testBoxShowsItsTopFaceToACameraAbove (Metal 4 gated) | none (no UI test target) | PNG magic bytes; image/png content; 800x600 fixture | Output dimensions are not asserted. The nil-provider error result is not called (ViewportStateTests.testKernelRunsWithoutRenderer builds a nil-provider registry but never calls cad_capture_snapshot). |
| VIEW-12 | none | MetalRendererGeometryTests.swift: testBoxShowsItsTopFaceToACameraAbove (lit top face brightness) | none (no UI test target) | none | The two lights and ambient term are not asserted separately. |
| VIEW-13 | OrientationTests.swift: testLookAtPutsEyeAtOriginAndTargetDownNegativeZ, testLookAtKeepsWorldUpPointingUpOnScreen; CameraTests.swift: testViewKeepsPlusZWorldUpWithNoRollAfterGestureSequence; AxesGeneratorTests.swift: testZAxisMatchesOrientationWorldUp | none | none (no UI test target) | no roll after gesture sequence | None. |
| VIEW-14 | OrientationTests.swift: testPerspectiveMatchesMetalZeroToOneForm, testPerspectiveMapsNearAndFarToDepthZeroAndOne | none | none (no UI test target) | near maps to 0, far to 1 | None. |
| VIEW-15 | ViewportCoordinatorTests.swift: testRenderInstrumentationTelemetry, testInvalidateReasonClassification | none | none (no UI test target) | reset clears lastReason | None. |
| VIEW-16 | ViewportCoordinatorTests.swift: testInvalidateReasonClassification, testCameraInvalidationAdvancesRedrawCountByExactlyOne | none | none (no UI test target) | all four reasons tagged | .resize has no producer in app code; the test tags it by hand. |
| VIEW-17 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| VIEW-18 | GridGeneratorTests.swift: testDefaultGridProperties, testAllVerticesLieOnGroundPlaneZZero, testGridLinesAreParallelToAxesAndStepBySpacing, testCenterAxesAreMajor, testSnappedPointsLieOnGridLines, testInvalidDimensionsReturnEmpty | GridGeneratorTests.swift: testMetalRendererGridIntegration, testCameraBelowPlaneSnapshot, testSolidsRestingOnGroundPlaneSnapshot, testDefaultSceneWithSolidsAndGridSnapshot (Metal 4 gated) | none (no UI test target) | on Z=0, spacing, major axes, invalid dimensions return empty, updateGrid re-snapshot | 10 mm pitch and 300 mm extent defaults asserted only through testDefaultGridProperties; HUD or toggle absent. |
| VIEW-19 | AxesGeneratorTests.swift: testDefaultAxesProperties, testZAxisMatchesOrientationWorldUp, testAxisColorsAreDistinct, testLabelPositionsArePastLineTips, testInvalidDimensionsReturnEmpty, testCameraLookingAlongAxesDoesNotProduceNaN, testCameraLookingAlongZAxisViewMatrix, testLabelsStayReadableWhenCameraZooms | AxesGeneratorTests.swift: testMetalRendererAxesIntegration, testOriginHiddenBehindSolidSnapshot, testSnapshotLookingAlongEachAxis (Metal 4 gated) | none (no UI test target) | NaN-free along each axis, label size under zoom, occlusion, invalid dimensions | None. |
| VIEW-20 | CameraFramingTests.swift: testBoundsIncludeEachMeshTranslation, testBoundsOfAnEmptySceneAreNil, testFramingCentresTargetAndKeepsViewDirection, testFramedSphereFitsBothFieldsOfView, testFramingClampsToCameraDistanceLimits; CameraTests.swift: testZoomChangesDistance, testZoomStopsAtMinAndMaxDistance, testZoomZeroOrOneLeavesCameraUnchanged | none | none (no UI test target) | empty scene; min and max distance clamp; zero zoom | fitToScene, zoomStep, the toolbar buttons and the =, -, F, H keys (MadeApp) are untested. |
| VIEW-21 | CameraTests.swift: testCameraPresets | none | none (no UI test target) | distance and axis side for each preset | The Picker, WorkspaceModel.applyPerspective and the switch to orthographic for non-perspective presets are untested; Isometric direction is not asserted. |
| VIEW-22 | none | none | none (no UI test target) | none | Test-only gap, no ticket. No test references this capability. Snap resolution is tested (SnappingTests) but marker geometry (MetalRenderer.swift:263) and the draw call (:456) are not. |
| VIEW-23 | ViewportStateTests.swift: testInitialStateIsInitializing, testNoDevicePathProducesUnavailableNoDevice, testDeviceLostAfterLaunchTransition, testViewportStateDescriptions | none | none (no UI test target) | each unavailable reason text | The SwiftUI views (ViewportCanvasView.swift:65) are untested; only the state and status strings. |
| VIEW-24 | ViewportStateTests.swift: testForceNoGPUSeam | none | none (no UI test target) | seam forces nil device | Argument and environment parsing (ViewportState.swift:78, :81, :85) is not tested; the test sets the static seam directly. |
| VIEW-25 | CameraTests.swift: testMakeOrthographicProjection; CameraFramingTests.swift (orthographic half-extents at line 44) | none | none (no UI test target) | none | MetalRenderer.projectionMode (MetalRenderer.swift:83, :380) is not asserted. |
| INPUT-1 | GestureArbiterTests.swift: testSinglePointerDragLocksManipulateOnMove, testTwoPointersLockNavigateOnMove, testSecondPointerJoiningLockedGestureDoesNotChangeMode, testPointersDroppingInLockedNavigateDoesNotChangeMode, testCancelledGestureResetsArbiter | none | none (no UI test target) | lock holds when pointers join or drop; cancel resets | Arbiter has no caller in MadeApp; no wiring test. |
| INPUT-2 | GestureArbiterTests.swift: testPureTapDecidesAtReleaseUsingPeakCount, testSinglePointerPureTapDecidesManipulateAtRelease | none | none (no UI test target) | peak 1 and peak 2 taps | None at unit level; no caller in MadeApp. |
| INPUT-3 | CameraTests.swift: testPointerRouterPenAlwaysManipulate | none | none (no UI test target) | pen move locks manipulate | The macOS view reuse path is untested. |
| INPUT-4 | none | none | none (no UI test target) | none | No test references this capability. PointerRouter touch events are not exercised. |
| INPUT-5 | CameraTests.swift: testPointerRouterClickVsDragThreshold | none | none (no UI test target) | 6 px threshold | MadeApp does not route mouse events through PointerRouter; no wiring test. |
| INPUT-6 | SnappingTests.swift: testGridSnapRoundsXYAndPreservesZ, testNegativeCoordinatesAndHalfPitchTies; GridGeneratorTests.swift: testSnappedPointsLieOnGridLines | none | none (no UI test target) | negative coordinates, half-pitch ties, Z kept | None. |
| INPUT-7 | SnappingTests.swift: testPriorityVertexBeatsCloserEdgeAndGrid, testEdgeBeatsCloserGrid, testCandidateBeyondToleranceIsIgnored, testEmptyCandidateListReturnsNoSnap, testEqualPriorityCandidatesResolveByDistance, testCandidateAtExactToleranceBoundaryIsIncluded, testCandidateJustBeyondToleranceIsExcluded, testResolveSnapAtPointerEndToEnd | none | none (no UI test target) | priority order, empty list, tie, exact tolerance boundary | None. |
| INPUT-8 | CameraTests.swift: testOrbitChangesAzimuthAndElevation, testOrbitZeroMovementLeavesCameraUnchanged, testOrbitPitchStopsBeforePoleSoViewNeverFlips, testPanMovesPositionAndTargetEqually, testPanZeroMovementLeavesCameraUnchanged, testZoomChangesDistance, testZoomStopsAtMinAndMaxDistance, testPointerRouterScrollAndMagnifyEvents, testCancelledGestureLeavesValidCamera; ViewportToolTests.swift: testModifierNavigationWorksUnderEveryTool | none | none (no UI test target) | pole clamp, zero movement, distance clamp, cancel | NSEvent translation in CADMetalViewRepresentable (scroll, magnify, modifiers) is untested. |
| INPUT-9 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| INPUT-10 | SnappingTests.swift: testCandidateGenerationFromBoxMesh, testCandidateGenerationFromCylinderMesh, testMeshTransformAffectsCandidatePositions, testClosestPointOnSegment, testScreenPointToRayAndGroundPlaneIntersection, testProjectToScreenRejectsBehindCamera, testRemovingSolidDropsItsCandidates, testResolveSnapAtPointerEndToEnd | none | none (no UI test target) | behind-camera projection, transformed meshes, solid removal | Hidden-object skipping (UI-27) is not tested. |
| INPUT-11 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| INPUT-12 | ViewportToolTests.swift: testPlainPrimaryDragFollowsTheTool, testModifierNavigationWorksUnderEveryTool, testShiftPrimaryDragUnderSelectStillManipulates, testOnlyManipulateIsNotNavigation, testShortcutKeysAreUniqueAndCaseInsensitive, testZoomDragUpMovesCloser | none | none (no UI test target) | all tools, all buttons, case-insensitive keys, zero drag | The toolbar picker and handleKeyDown (MadeApp) are untested. |
| INPUT-13 | none | none | none (no UI test target) | none | No test references this capability. Cursor selection lives in MadeApp (AppKit). |
| KERN-1 | EuclidEngineTests.swift: testMakeBoxGeneratesValidEuclidMesh, testMakeCylinderGeneratesValidEuclidMesh | none | none (no UI test target) | index count = 3 x triangles; positions = normals | Z-up vertex positions are not asserted. |
| KERN-2 | EuclidEngineTests.swift: testMakeBoxGeneratesValidEuclidMesh; KernelClientTests.swift: testMakeBoxGeneratesIndexedTriangles, testRapidRequestsConflateToLatestValue (extent X = 30); CADDSLTests.swift: testDeclarativeBoxCreation; MetalRendererGeometryTests.swift (projected bounds) | none | none (no UI test target) | valid mesh; X extent after rapid requests | Depth to Y and height to Z mapping is not asserted directly. |
| KERN-3 | EuclidEngineTests.swift: testMakeCylinderGeneratesValidEuclidMesh; KernelClientTests.swift: testMakeCylinderGeneratesValidNormals; CADDSLTests.swift: testDeclarativeCylinderCreation | none | none (no UI test target) | valid mesh and normals | Axis along +Z and 32 slices are not asserted. |
| KERN-4 | EuclidEngineTests.swift: testBooleanDifferenceProducesWatertightMesh; CADDSLTests.swift: testDeclarativeSubtractionOperator, testDeclarativeMethodChaining | none | none (no UI test target) | non-empty result | Test name claims watertight but asserts triangle count only; disjoint and empty-result cases are untested. |
| KERN-5 | EuclidEngineTests.swift: testBooleanUnionCombinesMeshes; CADDSLTests.swift: testDeclarativeUnionOperator | none | none (no UI test target) | overlapping boxes | Disjoint union is untested. |
| KERN-6 | CADDSLTests.swift: testDeclarativeIntersectionOperator (via DSL only) | none | none (no UI test target) | box and cylinder overlap | EuclidEngine.intersect has no direct test; empty intersection is untested. |
| KERN-7 | none | none | none (no UI test target) | none | No test references this capability. Geometry.swift hand-built box has no test and no caller. |
| KERN-8 | none | none | none (no UI test target) | none | No test references this capability. Geometry.swift hand-built cylinder has no test and no caller. |
| KERN-9 | KernelClientTests.swift: testRapidRequestsConflateToLatestValue, testStaleDebounceDoesNotStrandNewerRequest | none | none (no UI test target) | three ordered requests: two cancelled, one dispatched; stale debounce keeps newer job | Per-solid isolation (two solids pending at once) is untested. Test result not re-run in this read-only pass. |
| KERN-10 | KernelClientTests.swift: testInvalidDimensionsFailWithErrorCode | none | none (no UI test target) | negative box width gives invalidParams | Zero, NaN and cylinder dimensions are untested. |
| KERN-11 | none | none | none (no UI test target) | none | No test references this capability. KernelClient.cancel(jobId) is never called by a test; .cancelled results in KernelClientTests come from conflation. |
| KERN-12 | KernelClientTests.swift: testRapidRequestsConflateToLatestValue, testStaleDebounceDoesNotStrandNewerRequest | none | none (no UI test target) | superseded results return .cancelled | The in-flight (post-dispatch) drop at KernelClient.swift:175 is not exercised. |
| KERN-13 | none | none | none (no UI test target) | none | No test references this capability. dispose has no caller. |
| KERN-14 | KernelClientTests.swift: testRapidRequestsConflateToLatestValue | none | none (no UI test target) | conflated == 2, dispatched == 1 | dropped and completed counters are unasserted. |
| KERN-15 | none | none | none (no UI test target) | none | No test references this capability. The tessellate request is never issued by a test. |
| KERN-16 | none | none | none (no UI test target) | none | No test references this capability. importStep always returns geometryFailed; the failure is untested. |
| KERN-17 | KernelClientTests.swift: testInvalidDimensionsFailWithErrorCode, testRapidRequestsConflateToLatestValue | none | none (no UI test target) | invalidParams and cancelled | unknownSolid, geometryFailed, kernelInitFailed and workerCrashed are never asserted. |
| KERN-18 | SolidMeshApplierTests.swift (testFailedResultInstallsNothing) | none | none (no UI test target) | failed result installs nothing | The WorkspaceModel.recomputeSolid call site (MadeApp) is untested. The failure stays silent, tracked by #109. |
| KERN-19 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| DOC-1 | DocumentModelTests.swift: testInitialDocumentHasTwoDefaultSolids, testAddAndRemoveObject | none | none (no UI test target) | box and cylinder | The imported kind is untested. |
| DOC-2 | DocumentModelTests.swift: testSetParamClampsWithinLimits; CADToolsTests.swift: testSetParamClampsAndUpdates | none | none (no UI test target) | below min and above max for box width | Cylinder ranges and NaN-to-minimum are untested. |
| DOC-3 | none | none | none (no UI test target) | none | No test references this capability. No test observes @Observable change tracking. |
| DOC-4 | DocumentModelTests.swift: testInitialDocumentHasTwoDefaultSolids; CADToolsTests.swift: testGetSceneReturnsDefaultSolids, testMeasureReturnsCorrectVolume (40x30x20) | none | none (no UI test target) | ids and box volume | Cylinder default radius 15 and height 40 are not asserted. |
| DOC-5 | DocumentModelTests.swift: testAddAndRemoveObject; CADToolsTests.swift: testAddSolidCreatesNewBox | none | none (no UI test target) | box- prefix, count 3 | Cylinder and imported IDs and the sequence number are untested. |
| DOC-6 | DocumentModelTests.swift: testAddAndRemoveObject; CADToolsTests.swift: testRemoveSolidDeletesFromDocument | none | none (no UI test target) | remove default box | Removing an unknown ID is untested; kernel cache disposal has no caller and no test. |
| DOC-7 | DocumentModelTests.swift: testSetParamClampsWithinLimits; MCPServerTests.swift: testToolsCallExecutesTool | none | none (no UI test target) | clamp | Unknown keys and imported objects (silent ignore) are untested. |
| DOC-8 | none | none | none (no UI test target) | none | Test-only gap, no ticket. No test references this capability. setTransform has no test at document, tool or GUI level. |
| DOC-9 | DocumentModelTests.swift: testExtendedDocumentProperties | none | none (no UI test target) | setName and setVisibility | Empty name handling is untested. |
| DOC-10 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| DOC-11 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| DOC-12 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| DOC-13 | DocumentModelTests.swift: testExtendedDocumentProperties | none | none (no UI test target) | setLocked stores flag | Nothing reads the flag; no test pins the missing enforcement. |
| DOC-14 | DocumentModelTests.swift: testExtendedDocumentProperties | none | none (no UI test target) | setMaterial stores color | Rendering of the material color is untested. |
| UI-1 | removed | none | removed | none | Removed; no test expected. |
| UI-2 | none | none | none (no UI test target) | none | No test references this capability. Navigator selection lives in MadeApp. |
| UI-3 | DocumentModelTests.swift: testSetParamClampsWithinLimits (document clamp only) | none | none (no UI test target) | none | Slider binding and mm readout (InspectorPanelView) are untested. |
| UI-4 | none | none | none (no UI test target) | none | Slider binding and mm readout (InspectorPanelView) are untested. No test references this capability. |
| UI-5 | none | none | none (no UI test target) | none | Slider binding and mm readout (InspectorPanelView) are untested. No test references this capability. |
| UI-6 | none | none | none (no UI test target) | none | Slider binding and mm readout (InspectorPanelView) are untested. No test references this capability. |
| UI-7 | none | none | none (no UI test target) | none | Slider binding and mm readout (InspectorPanelView) are untested. No test references this capability. |
| UI-8 | none | none | none (no UI test target) | none | No test references this capability. |
| UI-9 | SolidMeshApplierTests.swift (testAppliesTransformSetAfterRequest, testReadsLiveColorAndVisibility, testZeroPositionGetsDemoOffset); KernelClientTests stale-result drop | none | none (no UI test target) | removal during recompute, double transform edit, parameter plus transform edit, failed result, sink allocation failure, zero-position demo offset | The slider binding and the WorkspaceModel call site (MadeApp) are untested. |
| UI-10 | DocumentModelTests.swift: testInitialDocumentHasTwoDefaultSolids (document only) | none | none (no UI test target) | none | Mesh generation at launch (WorkspaceModel.setUp) is untested. |
| UI-11 | removed | none | removed | none | Removed; no test expected. |
| UI-12 | removed | none | removed | none | Removed; no test expected. |
| UI-13 | removed | none | removed | none | Removed; no test expected. |
| UI-14 | none | none | none (no UI test target) | none | No test references this capability. |
| UI-15 | removed | none | removed | none | Removed; no test expected. |
| UI-16 | DocumentModelTests.swift: testAddAndRemoveObject (document only) | none | none (no UI test target) | none | Navigator Add menu and fixed 30x30x30 mm dimensions are untested. |
| UI-17 | DocumentModelTests.swift: testAddAndRemoveObject (document only) | none | none (no UI test target) | none | Navigator Add menu and fixed radius 12 and height 35 are untested. |
| UI-18 | removed | none | removed | none | Removed; no test expected. |
| UI-19 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| UI-20 | none | none | none (no UI test target) | none | No test references this capability. |
| UI-21 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| UI-22 | DocumentModelTests.swift: testAddAndRemoveObject; CADToolsTests.swift: testRemoveSolidDeletesFromDocument (document only) | none | none (no UI test target) | none | WorkspaceModel.removeObject and the Navigator button are untested. |
| UI-23 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| UI-24 | none | none | none (no UI test target) | none | No test references this capability. |
| UI-25 | none | none | none (no UI test target) | none | No test references this capability. |
| UI-26 | none | none | none (no UI test target) | none | No test references this capability. The filter predicate is inline in the view. |
| UI-27 | DocumentModelTests.swift: testExtendedDocumentProperties (setVisibility only) | none | none (no UI test target) | none | Navigator control and the viewport and snapping skip of hidden objects are untested. |
| UI-28 | DocumentModelTests.swift: testExtendedDocumentProperties (setLocked only) | none | none (no UI test target) | none | Navigator control is untested. |
| UI-29 | DocumentModelTests.swift: testExtendedDocumentProperties (setName only) | none | none (no UI test target) | none | Inspector Identity section is untested. |
| UI-30 | none | none | none (no UI test target) | none | No test references this capability. The 0.01 scale floor is untested. |
| UI-31 | none | none | none (no UI test target) | none | No test references this capability. Console log model lives in MadeApp. |
| UI-32 | none | none | none (no UI test target) | none | No test references this capability. Console log model lives in MadeApp. |
| UI-33 | none | none | none (no UI test target) | none | No test references this capability. Console log model lives in MadeApp. |
| UI-34 | none | none | none (no UI test target) | none | No test references this capability. |
| UI-35 | MCPServerTests.swift: testStartAndStopTCPServer (server only, port 19820) | none | none (no UI test target) | isRunning toggles | MCP window controls and WorkspaceModel start path are untested. |
| UI-36 | none | none | none (no UI test target) | none | No test references this capability. |
| UI-37 | MCPServerTests.swift: testToolsListReturnsAllCADTools (tool names via protocol) | none | none (no UI test target) | none | The window list view is untested. |
| AGENT-1 | none | none | none (no automated process-level stdio test; manual recipe guides/testing.md:56) | none | Test-only gap, no ticket. No test references this capability. --mcp-stdio parsing and MCPServer.runStdio are never run; guides/testing.md:56 documents a manual recipe only. |
| AGENT-2 | CADToolsTests.swift: testGetSceneReturnsDefaultSolids; ViewportStateTests.swift: testKernelRunsWithoutRenderer | none | none (no UI test target) | default solids listed | Position and parameter fields in the output are not asserted. |
| AGENT-3 | CADToolsTests.swift: testAddSolidCreatesNewBox | none | none (no UI test target) | box with dimensions | Cylinder, position arguments and dimension clamping are untested. |
| AGENT-4 | CADToolsTests.swift: testSetParamClampsAndUpdates; MCPServerTests.swift: testToolsCallExecutesTool | none | none (no UI test target) | clamp at 90 | Unknown parameter name (reports success) is untested. |
| AGENT-5 | none | none | none (no UI test target) | none | Test-only gap, no ticket. No test references this capability. cad_set_transform is never called by a test. |
| AGENT-6 | CADToolsTests.swift: testRemoveSolidDeletesFromDocument | none | none (no UI test target) | removes default box | Unknown ID and GUI syncMeshes are untested. |
| AGENT-7 | CADToolsTests.swift: testMeasureReturnsCorrectVolume | none | none (no UI test target) | box volume 24000 | Cylinder, bounds, surface area and imported solids are untested. |
| AGENT-8 | none | none | none (no UI test target) | none | Test-only gap, no ticket. No test references this capability. cad_boolean_operation is never called by a test. |
| AGENT-9 | none | AxesGeneratorTests.swift: testSnapshotViaCADToolsIncludesAxes; GridGeneratorTests.swift: testSnapshotViaCADTools (Metal 4 gated); ViewportStateTests.swift: testKernelRunsWithoutRenderer (nil provider registry built) | none (no UI test target) | PNG image content with image/png mime | The nil-provider error result is not called. Tests skip where Metal 4 is absent. |
| AGENT-10 | none | none | none (no UI test target) | none | No test references this capability. InAppAgentController has no test and no caller since #124. |
| AGENT-11 | none | none | none (no UI test target) | none | No test references this capability. InAppAgentController has no test and no caller since #124. |
| AGENT-12 | none | none | none (no UI test target) | none | No test references this capability. InAppAgentController has no test and no caller since #124. |
| AGENT-13 | none | none | none (no UI test target) | none | No test references this capability. InAppAgentController has no test and no caller since #124. |
| AGENT-14 | none | none | none (no UI test target) | none | No test references this capability. InAppAgentController has no test and no caller since #124. |
| AGENT-15 | none | none | none (no UI test target) | none | No test references this capability. InAppAgentController has no test and no caller since #124. |
| AGENT-16 | none | none | none (no UI test target) | none | No test references this capability. InAppAgentController has no test and no caller since #124. |
| AGENT-17 | MCPServerTests.swift: testUnknownMethodReturnsError | none | none (no UI test target) | -32601 only | -32700, -32602 and -32603 are never asserted. |
| AGENT-18 | MCPServerTests.swift: testInitializeReturnsServerCapabilities, testToolsListReturnsAllCADTools, testToolsCallExecutesTool, testUnknownMethodReturnsError | MCPServerTests.swift: same four tests drive server, registry, document and kernel in process | none (no UI test target) | response is non-nil | Malformed JSON input is untested. |
| AGENT-19 | MCPServerTests.swift: testInitializeReturnsServerCapabilities | in-process | none (no UI test target) | server name and protocolVersion key present | Version value 2024-11-05 and the tools capability are not asserted. |
| AGENT-20 | MCPServerTests.swift: testToolsListReturnsAllCADTools | in-process | none (no UI test target) | 5 of 8 names asserted | cad_set_transform, cad_remove_solid, cad_boolean_operation and the schemas are not asserted; the count of 8 is not asserted. |
| AGENT-21 | MCPServerTests.swift: testToolsCallExecutesTool | in-process (mutates DocumentModel) | none (no UI test target) | successful call mutates document | Missing name (-32602) and unknown tool (isError) are untested. |
| AGENT-22 | none | none | none (no UI test target) | none | No test references this capability. |
| AGENT-23 | MCPServerTests.swift: testUnknownMethodReturnsError | in-process | none (no UI test target) | -32601 | None. |
| AGENT-24 | MCPServerTests.swift: testStartAndStopTCPServer (start and stop only) | none | none (no process-level stdio test; manual recipe guides/testing.md:56) | none | No test connects to the listener or runs stdio. Newline framing and 64 KB chunking are untested. |
| AGENT-25 | none | none | none (no UI test target) | none | No test references this capability. |
| AGENT-26 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| AGENT-27 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| AGENT-28 | MCPServerTests.swift: testStartAndStopTCPServer | none | none (no UI test target) | start and stop on port 19820 | No client connection; loopback restriction is untested. |
| DSL-1 | CADDSLTests.swift: all six tests (via Box and Cylinder) | none | none (no UI test target) | none | A custom CADShape conformer is untested. |
| DSL-2 | CADDSLTests.swift: testDeclarativeSubtractionOperator, testDeclarativeUnionOperator, testDeclarativeIntersectionOperator | none | none (no UI test target) | none | None. |
| DSL-3 | CADDSLTests.swift: testDeclarativeBoxCreation | none | none (no UI test target) | none | Box(x:y:z:) form and offset are untested. |
| DSL-4 | CADDSLTests.swift: testDeclarativeCylinderCreation, testDeclarativeSubtractionOperator | none | none (no UI test target) | none | diameter form and offset are untested. |
| DSL-5 | CADDSLTests.swift: testDeclarativeUnionOperator, testDeclarativeMethodChaining | none | none (no UI test target) | none | Resulting position is not asserted. |
| DSL-6 | CADDSLTests.swift: testDeclarativeMethodChaining | none | none (no UI test target) | none | Builder-closure form is untested. |
| DSL-7 | CADDSLTests.swift: testDeclarativeUnionOperator (operator form) | none | none (no UI test target) | none | Method and builder-closure forms are untested. |
| DSL-8 | CADDSLTests.swift: testDeclarativeIntersectionOperator (operator form) | none | none (no UI test target) | none | Method form is untested. |
| DSL-9 | CADDSLTests.swift: all six tests | none | none (no UI test target) | none | None. |
| DSL-10 | CADDSLTests.swift: testDeclarativeSubtractionOperator, testDeclarativeUnionOperator, testDeclarativeIntersectionOperator | none | none (no UI test target) | none | None. |
| DSL-11 | none | none | none (no UI test target) | none | No test references this capability. @CADShapeBuilder is not used in any test. |
| DSL-12 | none | none | none (no UI test target) | none | Capability not implemented; no test expected until built. |
| WORKSPACE-1 | none | none | none (no UI test target) | none | No test references this capability. |
