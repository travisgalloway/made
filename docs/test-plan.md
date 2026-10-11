# Test plan

Date: 2026-10-10
Scope: macos/ (Swift package, test target MadeCoreTests)
Audit run: 20261010-114045

The plan covers 122 capabilities. The MadeCoreTests target holds 9 XCTest files and 43 test functions. A run of `swift test` in macos/ executes 43 tests with 0 failures. The Swift Testing run finds 0 tests.

The audit found `KernelClientTests.testRapidRequestsConflateToLatestValue` flaky and a race in `KernelClient.executePending` (DSN-efe60d18). #90 fixed both. The test now enqueues requests in a fixed order, and `testStaleDebounceDoesNotStrandNewerRequest` covers the race.

Table 1 gives the class decisions. Table 2 gives the per-capability coverage.

Table 1. Test class decisions, macos/ scope, 2026-10-10.

| Class | Decision | Evidence |
| --- | --- | --- |
| Unit | Covered for MadeCore logic and ViewportState. Unobserved for MadeApp UI rendering. | ViewportStateTests covers ViewportState, MetalDeviceProvider seams, and device lost lifecycle. No test imports MadeApp, Orientation, RenderLoop, PointerRouter, or InAppAgentController. |
| Integration | n/a | Package.swift declares one test target. MCPServerTests and CADToolsTests drive server, registry, and document in process. No stdio process test exists, although docs/guides/testing.md:47 describes a manual check. |
| UI and E2E | none (no UI test target) | No XCUITest target and no UITests directory exists. The Playwright suite in e2e/ targets the archived SvelteKit app. All 23 UI and 17 VIEW capabilities have zero tests at every level. |

Table 2. Per-capability test coverage, macos/ scope, 2026-10-10. Source: closure pass C.

| ID | Unit | Integration | E2E | Edge cases covered | Gaps |
| --- | --- | --- | --- | --- | --- |
| VIEW-1 | ViewportStateTests.swift: testInitialStateIsInitializing, testStateResolverLogic, testNoDevicePathProducesUnavailableNoDevice, testForceNoGPUSeam, testPipelineCreationFailedProducesUnavailable, testDeviceLostAfterLaunchTransition, testDeviceLostViaNotification, testKernelRunsWithoutRenderer, testViewportStateDescriptions | n/a (no integration target) | none (no UI test target) | no device path (seam); pipeline creation failure; device lost after launch; device lost via notification; kernel runs without renderer | MTKView window rendering unobserved by unit test (no UI test target); verified manually and via test seam. |
| VIEW-2 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-3 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-4 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-5 | ViewportCoordinatorTests.swift: testMeshSwapTriggersRedrawThroughCoordinator, testRenderCountStaysFlatAtIdle, testFailedKernelResultDoesNotRedraw, testWindowMinimizedSuppressesRedrawDuringUpdate, testRemovingSolidRedrawsOnce, testTwoMeshesSettleInSameFrame | n/a (no integration target) | none (no UI test target) | window minimized; failed kernel result; idle flat count; two meshes in same frame; solid removal | MTKView window rendering unobserved by unit test (no UI test target); verified manually and via stub test seam. |
| VIEW-6 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-7 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-8 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-9 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-10 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-11 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-12 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-13 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-14 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-15 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| VIEW-16 | ViewportCoordinatorTests.swift: testInvalidateReasonClassification | n/a (no integration target) | none (no UI test target) | camera, resize, model, interaction classification | Automated unit test coverage; UI event hooks for camera/interaction wired in separate issues (#87). |
| VIEW-17 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| INPUT-1 | GestureArbiterTests.swift: testSinglePointerDragLocksManipulateOnMove, testTwoPointersLockNavigateOnMove | n/a (no integration target) | none (no UI test target) | lock on first move; reset after release | No test of a mode that stays locked when a second pointer joins mid-gesture or when a locked navigate drops to one pointer. |
| INPUT-2 | GestureArbiterTests.swift: testPureTapDecidesAtReleaseUsingPeakCount | n/a (no integration target) | none (no UI test target) | peak count 2 tap | Single-pointer tap (peak 1) not tested. |
| INPUT-3 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| INPUT-4 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| INPUT-5 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| INPUT-6 | SnappingTests.swift: testGridSnapRoundsXYAndPreservesZ | n/a (no integration target) | none (no UI test target) | XY round, Z kept | Negative coordinates and half-pitch ties not tested. |
| INPUT-7 | SnappingTests.swift: testPriorityVertexBeatsCloserEdgeAndGrid, testEdgeBeatsCloserGrid, testCandidateBeyondToleranceIsIgnored | n/a (no integration target) | none (no UI test target) | priority order; tolerance cutoff | Empty candidate list, equal-priority tie and exact-tolerance boundary not tested. |
| INPUT-8 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| INPUT-9 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| INPUT-10 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| INPUT-11 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| KERN-1 | EuclidEngineTests.swift: testMakeBoxGeneratesValidEuclidMesh, testMakeCylinderGeneratesValidEuclidMesh | n/a (no integration target) | none (no UI test target) | index count = 3 x triangles; positions = normals | No assertion on Z-up axis orientation or vertex positions. |
| KERN-2 | EuclidEngineTests.swift: testMakeBoxGeneratesValidEuclidMesh; KernelClientTests.swift: testMakeBoxGeneratesIndexedTriangles; CADDSLTests.swift: testDeclarativeBoxCreation | n/a (no integration target) | none (no UI test target) | valid indexed mesh | Dimensions are not checked against bounds (width X, depth Y, height Z mapping unverified). |
| KERN-3 | EuclidEngineTests.swift: testMakeCylinderGeneratesValidEuclidMesh; KernelClientTests.swift: testMakeCylinderGeneratesValidNormals; CADDSLTests.swift: testDeclarativeCylinderCreation | n/a (no integration target) | none (no UI test target) | valid indexed mesh, normals | Axis along +Z and 32 slices not asserted. |
| KERN-4 | EuclidEngineTests.swift: testBooleanDifferenceProducesWatertightMesh; CADDSLTests.swift: testDeclarativeSubtractionOperator | n/a (no integration target) | none (no UI test target) | non-empty result | Test name claims watertight but asserts only triangle count > 0; disjoint operands and empty result not tested. |
| KERN-5 | EuclidEngineTests.swift: testBooleanUnionCombinesMeshes; CADDSLTests.swift: testDeclarativeUnionOperator | n/a (no integration target) | none (no UI test target) | overlapping boxes | Disjoint union not tested. |
| KERN-6 | CADDSLTests.swift: testDeclarativeIntersectionOperator (via DSL only) | n/a (no integration target) | none (no UI test target) | box and cylinder overlap | EuclidEngine.intersect has no direct test; empty-intersection case not tested. |
| KERN-7 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| KERN-8 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| KERN-9 | KernelClientTests.swift: testRapidRequestsConflateToLatestValue | n/a (no integration target) | none (no UI test target) | three ordered requests: first two cancelled, third builds a 30-mm box, conflated == 2, dispatched == 1; KernelClientTests.swift: testStaleDebounceDoesNotStrandNewerRequest covers the stale-debounce race (#90) | Per-solid isolation (cylinder untouched by box slider) not tested. |
| KERN-10 | KernelClientTests.swift: testInvalidDimensionsFailWithErrorCode | n/a (no integration target) | none (no UI test target) | negative box width -> invalidParams | Zero values, cylinder radius/height and NaN not tested. |
| KERN-11 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| KERN-12 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| KERN-13 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| KERN-14 | KernelClientTests.swift: testRapidRequestsConflateToLatestValue (asserts conflated and dispatched) | n/a (no integration target) | none (no UI test target) | conflated and dispatched counters | dropped and completed counters not asserted. |
| KERN-15 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| KERN-16 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| KERN-17 | KernelClientTests.swift: testInvalidDimensionsFailWithErrorCode | n/a (no integration target) | none (no UI test target) | invalidParams code only | Other five error codes have no test. |
| KERN-18 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| KERN-19 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| DOC-1 | DocumentModelTests.swift: testInitialDocumentHasTwoDefaultSolids; CADToolsTests.swift: testGetSceneReturnsDefaultSolids | n/a (no integration target) | none (no UI test target) | box and cylinder kinds | Imported kind not tested. |
| DOC-2 | DocumentModelTests.swift: testSetParamClampsWithinLimits; CADToolsTests.swift: testSetParamClampsAndUpdates | n/a (no integration target) | none (no UI test target) | box width low/high clamp | Box depth/height, cylinder radius/height and NaN not tested. |
| DOC-3 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| DOC-4 | DocumentModelTests.swift: testInitialDocumentHasTwoDefaultSolids | n/a (no integration target) | none (no UI test target) | 2 objects, IDs | Default parameter values (40x30x20, r15 h40) not asserted. |
| DOC-5 | DocumentModelTests.swift: testAddAndRemoveObject; CADToolsTests.swift: testAddSolidCreatesNewBox | n/a (no integration target) | none (no UI test target) | box- prefix; count 3 | Exact ID (box-2) not asserted; cylinder/imported add not tested. |
| DOC-6 | DocumentModelTests.swift: testAddAndRemoveObject; CADToolsTests.swift: testRemoveSolidDeletesFromDocument | n/a (no integration target) | none (no UI test target) | remove existing ID | Removing an unknown ID not tested. |
| DOC-7 | DocumentModelTests.swift: testSetParamClampsWithinLimits; CADToolsTests.swift: testSetParamClampsAndUpdates; MCPServerTests.swift: testToolsCallExecutesTool | n/a (no integration target) | none (no UI test target) | box width/height | Unknown key and imported-object silent-ignore not tested. |
| DOC-8 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| DOC-9 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| DOC-10 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| DOC-11 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| DOC-12 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| UI-1 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-2 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-3 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-4 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-5 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-6 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-7 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-8 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-9 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-10 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-11 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-12 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-13 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-14 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-15 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-16 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-17 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-18 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| UI-19 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| UI-20 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| UI-21 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| UI-22 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| UI-23 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| AGENT-1 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-2 | CADToolsTests.swift: testGetSceneReturnsDefaultSolids | n/a (no integration target) | none (no UI test target) | IDs present in text | Position and parameter fields not asserted. Only in-process server tests exist; no stdio process test. |
| AGENT-3 | CADToolsTests.swift: testAddSolidCreatesNewBox | n/a (no integration target) | none (no UI test target) | box dims and count | Cylinder, clamping and position args not tested. Only in-process server tests exist; no stdio process test. |
| AGENT-4 | CADToolsTests.swift: testSetParamClampsAndUpdates; MCPServerTests.swift: testToolsCallExecutesTool | n/a (no integration target) | none (no UI test target) | clamp to 90; height 75 | Unknown param name (silent success) and unknown id not tested. Only in-process server tests exist; no stdio process test. |
| AGENT-5 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-6 | CADToolsTests.swift: testRemoveSolidDeletesFromDocument | n/a (no integration target) | none (no UI test target) | remove box-1 | Unknown id error path not tested. Only in-process server tests exist; no stdio process test. |
| AGENT-7 | CADToolsTests.swift: testMeasureReturnsCorrectVolume | n/a (no integration target) | none (no UI test target) | box volume 24000 | Cylinder, bounds, surface area and imported-name case not tested. Only in-process server tests exist; no stdio process test. |
| AGENT-8 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-9 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-10 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-11 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-12 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-13 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-14 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-15 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-16 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-17 | MCPServerTests.swift: testUnknownMethodReturnsError | n/a (no integration target) | none (no UI test target) | -32601 only | -32700, -32600, -32602, -32603 not tested (no malformed-JSON test). Only in-process server tests exist; no stdio process test. |
| AGENT-18 | MCPServerTests.swift: all four tests | n/a (no integration target) | none (no UI test target) | valid requests | Malformed JSON, empty string and notification (no id) not tested. Only in-process server tests exist; no stdio process test. |
| AGENT-19 | MCPServerTests.swift: testInitializeReturnsServerCapabilities | n/a (no integration target) | none (no UI test target) | name and protocolVersion keys | Version string 2024-11-05 and 0.1.0 not asserted. Only in-process server tests exist; no stdio process test. |
| AGENT-20 | MCPServerTests.swift: testToolsListReturnsAllCADTools | n/a (no integration target) | none (no UI test target) | 5 of 8 tool names | cad_set_transform, cad_remove_solid, cad_boolean_operation not asserted; tool count 8 and input schemas not checked. Only in-process server tests exist; no stdio process test. |
| AGENT-21 | MCPServerTests.swift: testToolsCallExecutesTool | n/a (no integration target) | none (no UI test target) | cad_set_param happy path | Missing name (-32602) and unknown tool (isError) not tested. Only in-process server tests exist; no stdio process test. |
| AGENT-22 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-23 | MCPServerTests.swift: testUnknownMethodReturnsError | n/a (no integration target) | none (no UI test target) | -32601 | No gap material to the capability. Only in-process server tests exist; no stdio process test. |
| AGENT-24 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| AGENT-25 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| AGENT-26 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| AGENT-27 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| AGENT-28 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
| DSL-1 | CADDSLTests.swift: all six tests (via Box/Cylinder conformers) | n/a (no integration target) | none (no UI test target) | valid mesh from Box and Cylinder conformers | Custom CADShape conformer not tested. |
| DSL-2 | CADDSLTests.swift: testDeclarativeSubtractionOperator, testDeclarativeUnionOperator, testDeclarativeIntersectionOperator | n/a (no integration target) | none (no UI test target) | non-empty mesh | No gap material to the capability. |
| DSL-3 | CADDSLTests.swift: testDeclarativeBoxCreation | n/a (no integration target) | none (no UI test target) | width/depth/height init | Box(x:y:z:) init and offset not tested. |
| DSL-4 | CADDSLTests.swift: testDeclarativeCylinderCreation | n/a (no integration target) | none (no UI test target) | radius/height init | diameter init, slices and offset not tested. |
| DSL-5 | CADDSLTests.swift: testDeclarativeMethodChaining, testDeclarativeUnionOperator | n/a (no integration target) | none (no UI test target) | translated(z:), translated(x:) | Result position not asserted; only triangle count. |
| DSL-6 | CADDSLTests.swift: testDeclarativeMethodChaining (.subtracting) | n/a (no integration target) | none (no UI test target) | method form | Builder-closure form not tested. |
| DSL-7 | CADDSLTests.swift: testDeclarativeUnionOperator (operator form) | n/a (no integration target) | none (no UI test target) | operator or protocol form only | .union(_:) method and builder-closure form not tested. |
| DSL-8 | CADDSLTests.swift: testDeclarativeIntersectionOperator (operator form) | n/a (no integration target) | none (no UI test target) | operator or protocol form only | .intersecting(_:) method not tested. |
| DSL-9 | CADDSLTests.swift: all six tests | n/a (no integration target) | none (no UI test target) | index count = 3 x triangles | No gap material to the capability. |
| DSL-10 | CADDSLTests.swift: testDeclarativeSubtractionOperator, testDeclarativeUnionOperator, testDeclarativeIntersectionOperator | n/a (no integration target) | none (no UI test target) | - + & | No gap material to the capability. |
| DSL-11 | none | n/a (no integration target) | none (no UI test target) | none | No test references this capability. |
| DSL-12 | none | n/a (no integration target) | none (no UI test target) | none | Capability not implemented; no test expected until built. Add a failing-spec ticket only with the feature. |
