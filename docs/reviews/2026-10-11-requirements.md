# Requirements review, 2026-10-11

## Scope

Date: 2026-10-11
Repository: made (/Users/travisgalloway/github/made; the GitHub repository is still named wade)
Scope tokens: macos/ (Swift 6 package), lens requirements
Audit run: 20261011-195134

Coverage.

- R1 (acceptance criteria): 107 criteria verified over 15 macOS issues, out of 139 criteria in 21 issues in scope. 15 findings. The no-criteria count is 0. The feature matrix header said 67 Shipped rows while the table held 76.
- Prior findings REQ-993fbf1a, REQ-2d2334be, REQ-95ea66a6, REQ-9c2d0772, and REQ-bdc6a8b8 no longer fire, because the grid, axes, Orientation tests, and snapping are now built. #104 still reproduces.
- Control: the `gh` body extraction matched 139 checkbox lines, and Swift Testing tests were counted through `@Test`.

## Findings

### REQ-1634436b

- Location: macos/Sources/MadeApp/ContentView.swift:46
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: #121 scope lists a 'transform gizmo mode segmented control (Translate, Rotate, Scale, Select)'. The only mode control is the 'Viewport Tool' picker over ViewportTool (Select, Orbit, Pan, Zoom) at ContentView.swift:46-55. grep -i gizmo in macos/Sources returns nothing; no translate, rotate or scale mode exists. ViewportToolTests covers only the navigation tools.
- Closed issue: #121
- Disposition: covered by #71 and #72 (closed issue #121 stays closed)

### REQ-69d7e14d

- Location: macos/Sources/MadeApp/InspectorPanelView.swift:11
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: InspectorPanelView builds identitySection, transformSection and dimensionsSection only (lines 11-13). DocumentModel.setMaterial (DocumentModel.swift:207) has no caller in Sources (closure-A DOC-14), and no simulation property exists in SceneObject.
- Closed issue: #122
- Disposition: ticketed as #137 (merged closure DOC-14; closed issue #122 stays closed)

### REQ-38616f4b

- Location: macos/Sources/MadeCore/Viewport/MetalRenderer.swift:1
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: Selection reaches the inspector (WorkspaceModel.selectedId, InspectorPanelView) but grep -i 'selected|highlight' over macos/Sources/MadeCore/Viewport and CADMetalViewRepresentable.swift finds no selection state or highlight draw. The only 'highlighted' hit is a grid color comment (GridGenerator.swift:47).
- Closed issue: #120
- Disposition: covered by #40 (closed issue #120 stays closed)

### REQ-2e631f9f

- Location: macos/Sources/MadeApp/WorkspaceModel.swift:103
- Rule: criterion-unmet
- Severity: high
- Verdict: CONFIRMED
- Evidence: setParam logs (WorkspaceModel.swift:~124 log(.kernel, "CSG", ...)) and addObject/removeObject log, but setTransform (lines 103-111) calls no log(...). Editing Position or Scale in the Inspector writes no console entry.
- Closed issue: #123
- Disposition: ticketed as #138 (closed issue #123 stays closed)

### REQ-e7cab54e

- Location: macos/Sources/MadeCore/Scene/DocumentModel.swift:150
- Rule: criterion-unmet
- Severity: high
- Verdict: PLAUSIBLE
- Evidence: Still reproduces. DocumentModel.addObject(def:transform:) at :150 stores the def unclamped ('let obj = SceneObject(id: id, def: def, transform: transform)'); clamping lives in callers (CADTools.swift:197-209 DocumentLimits.boxWidth.clamp). No test in DocumentModelTests exercises an out-of-range addObject. Open issue #104 already tracks this.
- Closed issue: #65
- Disposition: covered by #104

### REQ-ccfe3b7a

- Location: macos/Sources/MadeCore/Viewport/MetalRenderer.swift:392
- Rule: criterion-unmet
- Severity: high
- Verdict: PLAUSIBLE
- Evidence: Inspector shows editable Scale fields (InspectorPanelView.swift:48-53) and WorkspaceModel.setTransform stores them, but MetalRenderer builds the model matrix from mesh.transform.position only (line 392; grep scale|rotation in MetalRenderer.swift returns nothing). The inspector reports a scale the viewport does not show (closure-A UI-30).
- Closed issue: #122
- Disposition: ticketed as #136 (merged closure UI-30; closed issue #122 stays closed)

### REQ-ac8f52ad

- Location: macos/Sources/MadeApp/ConsoleDrawerView.swift:1
- Rule: criterion-unmet
- Severity: high
- Verdict: PLAUSIBLE
- Evidence: #123 title promises a 'telemetry drawer'. ConsoleDrawerView renders only the log list with filter, clear and hide controls. Render count, draw calls and invalidate reason appear only in the viewport HUD (ViewportCanvasView.statusHUD); kernel getStats has no reader (closure-A KERN-14).
- Closed issue: #123
- Disposition: ticketed as #139 (closed issue #123 stays closed)

### REQ-0d580633

- Location: macos/Sources/MadeApp/ContentView.swift:92
- Rule: criterion-unmet
- Severity: high
- Verdict: PLAUSIBLE
- Evidence: Navigator and Inspector get shortcuts from SidebarCommands and InspectorCommands (MadeApp.swift commands block). The Console toggle (ContentView.swift:92-95) has only .help; grep keyboardShortcut over macos/Sources returns nothing, so the console pane has no shortcut.
- Closed issue: #118
- Disposition: ticketed as #140 (closed issue #118 stays closed)

### REQ-14373dc4

- Location: docs/feature-matrix.md:92
- Rule: matrix-overclaims
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Row UI-1 is Shipped. After #124-#126 the window is NavigationSplitView + inspector (ContentView.swift); grep -i 'copilot' over macos/Sources/MadeApp returns nothing.
- Disposition: reported. Fixed in docs/feature-matrix.md (UI-1 is Deprecated)

### REQ-84b32cac

- Location: docs/feature-matrix.md:93
- Rule: matrix-overclaims
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Row UI-2 is Shipped citing #34. The picker was replaced by NavigatorSidebarView (List with selection); no menu picker of objects remains.
- Disposition: reported. Fixed in docs/feature-matrix.md (UI-2 reworded to the Navigator list)

### REQ-c7b87ca6

- Location: docs/feature-matrix.md:102
- Rule: matrix-overclaims
- Severity: medium
- Verdict: CONFIRMED
- Evidence: Rows are Shipped with UI done. InAppAgentController has no reference in macos/Sources/MadeApp and no Copilot field or transcript view exists (closure-A AGENT-10 CONFIRMED).
- Disposition: reported. Fixed in docs/feature-matrix.md (UI-11 to UI-13 Deprecated, AGENT-10, AGENT-11, AGENT-14 to AGENT-16 In progress with UI none)

### REQ-37b53d76

- Location: docs/feature-matrix.md:20
- Rule: matrix-overclaims
- Severity: medium
- Verdict: CONFIRMED
- Evidence: The note claims a 'multi-tab inspector'. InspectorPanelView is a single Form with three sections and no tabs. WORKSPACE-1 has no row in Table 1, and the header reads 67 Shipped while the table has 76 '| Shipped |' rows. Rows UI-20 and UI-22 still read Planned although the inspector edits position and the navigator deletes solids.
- Disposition: reported. Fixed in docs/feature-matrix.md (WORKSPACE-1 row added as In progress, counts recomputed, UI-20 and UI-22 Shipped)

### REQ-2011a068

- Location: macos/Tests/MadeCoreTests/KernelClientTests.swift:1
- Rule: criterion-untested
- Severity: medium
- Verdict: PLAUSIBLE
- Evidence: #90 requires 'a test shows that a box slider burst does not re-tessellate the cylinder'. KernelClientTests holds five tests (box, cylinder, conflation, stale debounce, invalid dims); none requests two solids and asserts the second is not recomputed.
- Closed issue: #90
- Disposition: parked

### REQ-2574b26a

- Location: macos/Sources/MadeApp/WorkspaceModel.swift:1
- Rule: criterion-untested
- Severity: medium
- Verdict: PLAUSIBLE
- Evidence: WorkspaceModel.toggleVisibility and selectedId drive hiddenSolidIds and the inspector, but no test target imports MadeApp (Package.swift declares MadeCoreTests only; closure-C-testplan.md). #120 and #122 criteria on selection, visibility and numeric edit have no automated check.
- Closed issue: #120
- Disposition: parked

### REQ-6c94a83c

- Location: docs/feature-matrix.md:105
- Rule: matrix-overclaims
- Severity: low
- Verdict: CONFIRMED
- Evidence: Row UI-14 is Shipped. grep 'made - Native' over macos/Sources returns nothing; ContentView shows 'Untitled Project' and the window uses .unified(showsTitle: false).
- Disposition: reported. Fixed in docs/feature-matrix.md (UI-14 reworded)


## Decisions needed

Five closed issues carry unmet criteria. Each stays closed, and the disposition of each is the maintainer's call.

Table 1. Closed issues with an unmet criterion, macos/ scope, 2026-10-11.

| Issue | Unmet criterion | Follow-up |
| --- | --- | --- |
| #118 | Panes can be toggled by keyboard shortcut | #140 |
| #120 | Selection highlights in the viewport | #40 |
| #121 | Gizmo mode selector | #71 and #72 |
| #122 | Scale rendering and material persistence | #136 and #137 |
| #123 | Transform events in the console and a telemetry pane | #138 and #139 |

## Not audited

- 32 criteria in six removed web-prototype issues (#77, #75, #74, #68, #47, and #5) were not verified. Their code lives in the git history only, and CLAUDE.md forbids citing it.
