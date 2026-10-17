# Requirements review, 2026-10-17

## Scope

Date: 2026-10-17
Repository: made (/Users/travisgalloway/github/made; GitHub repository travisgalloway/made)
Scope tokens: macos/ (Swift 6 package), lens requirements
Audit run: 20261017-112015

Coverage.

- R1: 1,208 checkbox criteria over 132 issues closed as completed since 2026-07-19. About 174 of 1,208 criteria were verified against code. The other 1,034 are UNAUDITED.
- R1 first pass: Denominator: 1208 checkbox criteria over 132 COMPLETED issues closed since 2026-07-19 (extraction matched checkbox lines; 797 sit unchecked in closed issues, so checkbox state carries no signal). Deep verification covered the sketch and constraint cluster (#196 #197 #198 #200 #354 #356 #357 #360 #365 #366 #310, roughly 125 criteria plus #197 numbered ACs); the other issues' criteria were not individually verified. DOC-21 to DOC-26 matrix rows checked for the same cluster.
- R1 second pass: 49 criteria over 18 issues (#201, #398, #238, #338, #336, #342, #239, #240, #150, #170, #235, #301, #309, #383, #382, #384, #425, #250). Counts are criteria read against code, including 3 non-checkbox scope or capability lines. Sampled and REFUTED (no row): #383 display mode (canvas picker, View menu, Settings, persistence tests), #382 showsEdges toggle, #384 view menu shortcuts and alignNormalTo flip test (WorkspaceModelTests:818), #425 license catalog tests (LicenseCatalogTests:88-93), #250 Delete/Hide/Lock/Reload Part menu items and enablement, #235 rollback Navigator and menu, #201 density, fallback and wire tests. WORKSPACE-3 conversion is carried by the #238 row, since #398 promises only selectable units. KERN-15 re-fetch itself is met (matrix row accurate).

## Findings

### REQ-f0dd0a1a

- Summary: Sketch entities draw in the viewport, and construction entities draw dashed
- Location: macos/Sources/MadeCore/Viewport/MetalRenderer.swift:358
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: Exclusion from profiles is met (SketchRegionTests.testConstructionEntitiesExcludedFromRegionDetection). The dashed half is absent: grep -i sketch over Sources/MadeCore/Viewport/*.swift and *.metal finds only SketchPlane grid code (MetalRenderer.swift:358 'activeSketchPlane'), so no sketch entity is drawn in the viewport at all. 'dash' appears only in InspectorPanelView.swift:652 and :847 (a dashed badge border and a dashed row divider). CADMetalViewRepresentable passes sketchEntities (:174) only for hit-testing. No test references dashed rendering.
- Disposition: ticketed as #558

### REQ-bf8d4783

- Summary: Report remaining DOF per entity and color entities by status.
- Location: macos/Sources/MadeApp/InspectorPanelView.swift:636
- Rule: criterion-unmet
- Severity: high
- Verdict: PLAUSIBLE
- Evidence: Per-entity DOF is reported: WorkspaceModel.entityDOFStatus (:58), ConstraintSolver.computeEntityDOF, InspectorPanelView 'let statusColor = ViewportStatusBar.dofColor(for: status)' (:636) and entityDOFBadge (:869); tests testWorkspaceEntityDOFTrackingAndAccessor and testViewportStatusBarSemanticColorMapping. Coloring exists only on Inspector rows. The viewport draws no sketch entities, so entities themselves are never colored by status.
- Disposition: reported here

### REQ-a45ddc8e

- Summary: DOC-22 Shipped: construction entities draw dashed
- Location: docs/feature-matrix.md:140
- Rule: matrix-overclaims
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Row DOC-22 (and line 33) claims 'construction entities draw dashed' with status Shipped. No viewport draw path for sketch entities exists (see the #356 finding). Only the Inspector shows a dashed badge.
- Disposition: reported here

### REQ-4fde014f

- Summary: Hover highlights a region for extrude selection.
- Location: macos/Sources/MadeApp/CADMetalViewRepresentable.swift:1170
- Rule: criterion-untested
- Severity: medium
- Verdict: PLAUSIBLE
- Evidence: Code: 'parent.onHoverSketchRegion?(hitRegion?.id)' (:1170) feeds WorkspaceModel.setHoveredSketchRegion, which installs a highlight mesh via updateRegionHighlightMesh (:180). SketchRegionAppTests covers region detection, but no test in MadeAppTests was found that drives the hover path or asserts the highlight mesh color (0.2,0.7,1.0,0.45). Viewport hover needs an MTKView, so the path is not unit-reachable.
- Disposition: parked (docs/parked-findings.md)

### REQ-a4b42305

- Summary: A person who changes the chordal or angular tolerance sees every solid re-tessellate at that tolerance
- Location: macos/Sources/MadeCore/Kernel/LocalKernelEngine.swift:148
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: The engine API is met and tested: `case .tessellate(_, let sId, let tolerances): ... OCCTEngine.toMeshPayload(shape, tolerances: tolerances.clamped())` (:195-199), tested by BRepTessellationTests.testLocalKernelEngineRetessellate (:134) and testCylinderToleranceScalingChordal/Angular. The settings never reach it: every display path calls `OCCTEngine.toMeshPayload(shape)` with the hardcoded defaults deflection 0.1, angle 0.5 (LocalKernelEngine.swift:148, :220, :249; OCCTEngine.swift:178), and no code outside Types.swift constructs `.tessellate` (grep '\.tessellate(' in Sources returns only Types.swift:358 and the handler at LocalKernelEngine.swift:195). WorkspaceModel.kernelTolerances (:389) and DocumentModel.setTolerances only persist values; MadeAppTests has no test that a tolerance edit changes a mesh. Satisfies #398 'Kernel tolerances configure linear, angular, and chordal tolerances' only at the storage level.
- Disposition: ticketed as #555

### REQ-5633752e

- Summary: A person who selects inches sees and enters Inspector dimensions in inches
- Location: macos/Sources/MadeApp/InspectorPanelView.swift:169
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: The caption changes: `LabeledContent("Position (\(workspace.document.settings.units.lengthUnit.symbol))")` (:169) and paramField's `let symbol = workspace.document.settings.units.lengthUnit.symbol; let spoken = "\(value...) \(symbol)"` (:1263). The value shown and committed is the raw millimeter float (doc comment at :1251 'A typed millimeter value'). `LengthUnit.toMillimeters` and `toDegrees` (UnitSettings.swift:28, :69) have no caller in Sources, only UnitsAndTolerancesTests. Choosing inches therefore labels 25.4 mm as '25.4 in'. The Settings Units tab (#398 'selectable length units') and the Document tab store the choice and nothing converts. Matrix row WORKSPACE-3 lists Units as shipped.
- Disposition: ticketed as #556

### REQ-a657861d

- Summary: A person who disables the Sketch Entities filter cannot pick or drag sketch entities in the viewport
- Location: macos/Sources/MadeApp/CADMetalViewRepresentable.swift:572
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: Checkboxes 1, 5, 6 are met (SelectionFilter OptionSet; ContentView.swift:107 and MadeCommands.swift:112 toggle `.sketchEntities`/`.components`). Checkboxes 2-4 name only faces, edges, vertices and bodies, so no checkbox covers the other two. `allowsSketchEntities` (SelectionFilter.swift:50) and `allowsComponents` (:55) have no reader: sketch hit-testing at CADMetalViewRepresentable.swift:565-575 tests `SketchOperations.hitTestSketchDragTarget` without consulting `workspace.selectionFilter`, and no component pick path exists. Toggling the two menu items changes state and nothing else. No test exercises either flag outside SelectionFilter unit tests.
- Disposition: ticketed as #557

### REQ-aab459b0

- Summary: Matrix INPUT-9 (Shipped): '...restrict picking/hover preselection to faces, edges, vertices, bodies, sketch entities, or components via toolbar controls and keyboard shortcuts (selection filters, BL-SEL-06)'
- Location: docs/feature-matrix.md:94
- Rule: matrix-overclaims
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Row cites #338. Sketch entities and components have no effect (see the criterion-unmet row for #338). The row's Tests column reads done and no test covers either flag's effect.
- Disposition: reported here

### REQ-c025717f

- Summary: A person extends the selection to several objects with Shift or Command click
- Location: macos/Sources/MadeCore/Scene/DocumentModel.swift:694
- Rule: no-prior-criterion
- Severity: high
- Verdict: CONFIRMED
- Evidence: The #336 checkboxes are met and tested (testMultiReferenceSelectionHelpers). #336 scopes out 'Viewport multi-selection ... (future viewport tickets)', #342 specifies 'single click', and #338 scopes out marquee (BL-SEL-07, open #339). No closed issue promised a Shift or Command click or a Navigator extend gesture. Production code only assigns single references (`document.selection = [Reference...]`, WorkspaceModel.swift:628, :682, :1248); `isShiftDown` (CADMetalViewRepresentable.swift:403) feeds ViewportTool.dragAction only; Navigator `List(selection: $workspace.selectedId)` (NavigatorSidebarView.swift:19) is single-valued. Matrix DOC-10 says 'multi-object ... selection' Shipped.
- Disposition: merged into the DOC-10 closure ticket

### REQ-f5131c79

- Summary: A person renames, hides, locks and recolors a body inside a multi-body part
- Location: macos/Sources/MadeCore/Scene/DocumentModel.swift:3063
- Rule: no-prior-criterion
- Severity: medium
- Verdict: CONFIRMED
- Evidence: The mutators and their undo, lock and empty-name rules are met and tested (BodyTests.swift:96-219, WorkspaceModelTests.swift:1732-1754). #240 UI exposure is met for SceneObject rows: Navigator context menu has Rename, Hide/Show, Lock/Unlock (NavigatorSidebarView.swift:100-106) and Inspector has a ColorPicker bound to setMaterial (InspectorPanelView.swift:260-268). The Body-level API has no UI caller: setBodyColor, setBodyMaterial, setBodyLocked and toggleBodyVisibility have 0 callers outside tests, and setBodyName/setBodyVisibility on WorkspaceModel are called only from tests. No view reads `document.bodies` (MadeApp references only `selectedBody`, WorkspaceModel.swift:551). No closed issue required a body-level control inside a multi-body part, and BL-PRT-18 (open #307) covers body tools.
- Disposition: merged into the DOC-33 closure ticket

### REQ-27cb650f

- Summary: A person deletes, suppresses and locks a sketch or datum feature from the Navigator
- Location: macos/Sources/MadeCore/Scene/DocumentModel.swift:1255
- Rule: no-prior-criterion
- Severity: high
- Verdict: CONFIRMED
- Evidence: #150 requires the model to hold a suppression flag (met: Feature.isSuppressed; FeatureTests.swift:442 tests setFeatureSuppressed). #235 rollback UI is met (Navigator 'Roll to End' banner, 'Roll Back to Here', MadeCommands.swift:263-269). #301 and #309 list creation, Navigator rows, Inspector and Solid menu items, and no deletion. `removeFeature` has no caller outside tests and its own undo closure; WorkspaceModel.canDeleteSelectedObject (:2082) and removeObject (:2108) take a SceneObject, so sketch, datum plane, axis, point and coordinate-system rows cannot be deleted from the Navigator (rows at NavigatorSidebarView.swift:28-67, no Delete button; context menu :91-108 is solid-only). `grep -i suppress macos/Sources/MadeApp` returns 0.
- Disposition: merged into the DOC-1 closure ticket; suppress covered by #176
