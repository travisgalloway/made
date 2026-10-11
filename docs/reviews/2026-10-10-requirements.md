# Requirements review, 2026-10-10

## Scope

Date: 2026-10-10
Repository: wade (/Users/travisgalloway/github/wade)
Scope tokens: macos/ (Swift 6 package), lens requirements
Audit run: 20261010-114045

Coverage.

- R1 (closed-issue criteria): 9 of 9 in-scope issues verified against macos/. The window holds 44 issues closed as COMPLETED since 2026-07-12. 35 of them are out of scope web issues, and 0 lack criteria. The 9 verified are #61, #65, #27, #26, #24, #23, #18, #17, and #25.
- Criteria extracted: 27. Shipped claims checked: 18.
- Criteria for #24, #23, and #25 were checked and produced no finding. They hold in the Swift `KernelClient` actor, which has no brepjs, and in the `MeshPayload` fields and the `KernelClient` tests.
- Shipped-row source: n/a for docs/feature-matrix.md, which did not exist before this run. The claims came from phases.md (Phases 0 to 3) and the Delivered rows of backlog-migration.md.

## Findings

### REQ-993fbf1a

- Location: macos/Sources/MadeCore/Viewport/MetalRenderer.swift:1
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: Issue #61 requires a ground grid. MetalRenderer.swift, MetalShaders.swift, and the rest of macos/Sources contain no grid geometry. A search for grid, axes, and axis matches only comments in Orientation.swift, Snapping.swift, and EuclidEngine.swift. Grid snap math exists, and nothing draws or feeds it.
- Disposition: ticketed as #102

### REQ-2d2334be

- Location: macos/Sources/MadeCore/Viewport/MetalRenderer.swift:1
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: Issue #61 requires a labelled XYZ triad at the origin. MetalRenderer.swift, MetalShaders.swift, and MadeApp/*.swift contain no axes or triad geometry or labels.
- Disposition: ticketed as #103

### REQ-9c2d0772

- Location: macos/Sources/MadeCore/Input/Snapping.swift:1
- Rule: criterion-unmet
- Severity: high
- Verdict: PLAUSIBLE
- Evidence: Issue #27 requires snapping to a vertex, an edge, and the grid in a manual test. Snapping.swift has 4 unit tests. No file in MadeApp or Viewport references Snapping, and no grid is drawn. A manual snap in the running app cannot occur.
- Disposition: ticketed as #88 (INPUT-7)

### REQ-e7cab54e

- Location: macos/Sources/MadeCore/Scene/DocumentModel.swift:1
- Rule: criterion-unmet
- Severity: high
- Verdict: PLAUSIBLE
- Evidence: Issue #65 requires that no out-of-range value reaches the kernel. `addObject(def:transform:)` stores the definition unclamped, and clamping happens in callers (CADTools.swift:197-209). Another caller can place width 500 in the document. `KernelClient` rejects only values at or below zero.
- Disposition: ticketed as #104

### REQ-95ea66a6

- Location: macos/Tests/MadeCoreTests:1
- Rule: criterion-untested
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Issue #61 requires a Z-up regression test. No file under macos/Tests references `Orientation`. `Orientation.worldUp` is used at MetalRenderer.swift:153 with no test.
- Disposition: parked

### REQ-e73808df

- Location: macos/Tests/MadeCoreTests:1
- Rule: criterion-untested
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Issue #17 requires distinct handling for touch, pen, and mouse. `PointerRouter` branches on pointer type, with a 6 px mouse threshold. No test references `PointerRouter` or `RouterEvent`.
- Disposition: parked

### REQ-e2c98d76

- Location: docs/roadmap/phases.md:1
- Rule: matrix-overclaims
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Phase 2 is marked Done and claims 60 ms debounce conflation. `swift test` fails `KernelClientTests.testRapidRequestsConflateToLatestValue`. The Rules of Engagement for the phase require zero failures.
- Disposition: reported

### REQ-ae1cd1ec

- Location: macos/Tests/MadeCoreTests/GestureArbiterTests.swift:1
- Rule: criterion-untested
- Severity: medium
- Verdict: PLAUSIBLE
- Evidence: Issue #18 requires that a gesture stays in its mode until release. `GestureArbiter` locks on the first move and holds. The 3 tests add no second pointer after the lock and assert no mode stability.
- Disposition: parked

### REQ-2011a068

- Location: macos/Tests/MadeCoreTests/KernelClientTests.swift:1
- Rule: criterion-untested
- Severity: medium
- Verdict: PLAUSIBLE
- Evidence: Issue #26 requires that only the changed solid re-tessellates. `KernelClient` keys jobs per solid, but no test requests two solids and asserts the second is untouched. The only conflation test fails.
- Disposition: parked

### REQ-bdc6a8b8

- Location: docs/roadmap/phases.md:1
- Rule: matrix-overclaims
- Severity: medium
- Verdict: PLAUSIBLE
- Evidence: Phase 1 is marked Done and lists the snapping engine as delivered. The engine is a tested module with no caller in MadeApp or Viewport. The viewport has no grid and no vertex or edge candidates.
- Disposition: reported

### REQ-44825640

- Location: docs/roadmap/backlog-migration.md:1
- Rule: matrix-overclaims
- Severity: low
- Verdict: PLAUSIBLE
- Evidence: The document lists #73 as Delivered through `document.addObject` and `document.removeObject`. ContentView.swift has a solid picker and sliders and no call to either method. Only the agent tools call them (CADTools.swift:201,209,341).
- Disposition: reported

## Decisions needed

None. No finding in this lens carries the disposition decision.

## Not audited

None. Pass R1 ran with nonzero denominators.
