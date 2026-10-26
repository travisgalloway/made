import SwiftUI
import MadeCore

struct FileMenuCommands: Commands {
    var workspace: WorkspaceModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") {
                workspace.newDocument()
            }
            .keyboardShortcut(WorkspaceModel.newDocumentShortcutKey, modifiers: WorkspaceModel.newDocumentShortcutModifiers)

            Button("New Assembly") {
                workspace.newAssemblyDocument()
            }
            .keyboardShortcut(WorkspaceModel.newAssemblyShortcutKey, modifiers: WorkspaceModel.newAssemblyShortcutModifiers)

            Button("New Drawing") {
                workspace.newDrawingDocument()
            }
            .keyboardShortcut(WorkspaceModel.newDrawingShortcutKey, modifiers: WorkspaceModel.newDrawingShortcutModifiers)

            Button("Open Document…") {
                workspace.promptOpenDocument()
            }
            .keyboardShortcut(WorkspaceModel.openDocumentShortcutKey, modifiers: WorkspaceModel.openDocumentShortcutModifiers)

            Button("Open Part Script…") {
                workspace.promptOpenPartFile()
            }
            .keyboardShortcut(WorkspaceModel.openPartShortcutKey, modifiers: WorkspaceModel.openPartShortcutModifiers)

            Divider()

            Button("Save") {
                workspace.promptSaveDocument()
            }
            .keyboardShortcut(WorkspaceModel.saveDocumentShortcutKey, modifiers: WorkspaceModel.saveDocumentShortcutModifiers)

            Button("Save As…") {
                workspace.saveDocumentAs()
            }
            .keyboardShortcut(WorkspaceModel.saveAsDocumentShortcutKey, modifiers: WorkspaceModel.saveAsDocumentShortcutModifiers)

            Button("Document Settings…") {
                workspace.isInspectorPresented = true
                workspace.inspectorTab = .document
            }

            Divider()

            Button("Import STEP…") {
                workspace.promptImportStepFile()
            }

            Button("Link External File…") {
                workspace.promptLinkExternalFile()
            }

            Menu("Export") {
                Button("3MF…") {
                    workspace.promptExportThreeMFFile()
                }
                .disabled(workspace.document.objects.isEmpty)

                Button("STL…") {
                    workspace.promptExportSTLFile()
                }
                .disabled(workspace.document.objects.isEmpty)

                Button("STEP…") {
                    workspace.promptExportStepFile(selectedOnly: false)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Menu("Bill of Materials (CSV)") {
                    Button("Flat BOM…") {
                        workspace.promptExportBillOfMaterials(structure: .flat)
                    }
                    Button("Hierarchical BOM…") {
                        workspace.promptExportBillOfMaterials(structure: .hierarchical)
                    }
                }
                .disabled(!workspace.canExportBillOfMaterials)

                Divider()

                Menu("Drawing") {
                    Button("PDF…") {
                        workspace.promptExportDrawingPDF()
                    }
                    Button("DXF…") {
                        workspace.promptExportDrawingDXF()
                    }
                }
                .disabled(!workspace.canExportDrawing)

                Divider()

                Menu("Simulation") {
                    Button("VTU (ParaView)…") {
                        if let study = workspace.activeSimulationStudy {
                            workspace.promptExportSimulationVTU(studyId: study.id)
                        }
                    }
                    .disabled(workspace.activeSimulationStudy?.results.status != .completed)
                }
                .disabled(workspace.activeSimulationStudy?.results.status != .completed)
            }
            .disabled(workspace.document.objects.isEmpty && !workspace.canExportBillOfMaterials && !workspace.canExportDrawing && workspace.activeSimulationStudy?.results.status != .completed)

            Button("Reload Part Scripts") {
                workspace.reloadAllParts()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

struct EditMenuCommands: Commands {
    var workspace: WorkspaceModel

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(workspace.undoTitle) {
                workspace.undo()
            }
            .keyboardShortcut(WorkspaceModel.undoShortcutKey, modifiers: WorkspaceModel.undoShortcutModifiers)
            .disabled(!workspace.canUndo)

            Button(workspace.redoTitle) {
                workspace.redo()
            }
            .keyboardShortcut(WorkspaceModel.redoShortcutKey, modifiers: WorkspaceModel.redoShortcutModifiers)
            .disabled(!workspace.canRedo)
        }
        CommandGroup(after: .pasteboard) {
            Button("Duplicate") {
                workspace.duplicateSelectedObject()
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(workspace.selectedObject == nil)

            Button("Delete") {
                workspace.deleteSelectedObject()
            }
            .keyboardShortcut(WorkspaceModel.deleteShortcutKey, modifiers: WorkspaceModel.deleteShortcutModifiers)
            .disabled(!workspace.canDeleteSelectedObject)

            Divider()

            Menu("Selection Filters") {
                Toggle("Faces", isOn: Binding(
                    get: { workspace.selectionFilter.contains(.faces) },
                    set: { workspace.toggleSelectionFilter(.faces, enabled: $0) }
                ))
                .keyboardShortcut(WorkspaceModel.filterFaceShortcutKey, modifiers: WorkspaceModel.filterShortcutModifiers)

                Toggle("Edges", isOn: Binding(
                    get: { workspace.selectionFilter.contains(.edges) },
                    set: { workspace.toggleSelectionFilter(.edges, enabled: $0) }
                ))
                .keyboardShortcut(WorkspaceModel.filterEdgeShortcutKey, modifiers: WorkspaceModel.filterShortcutModifiers)

                Toggle("Vertices", isOn: Binding(
                    get: { workspace.selectionFilter.contains(.vertices) },
                    set: { workspace.toggleSelectionFilter(.vertices, enabled: $0) }
                ))
                .keyboardShortcut(WorkspaceModel.filterVertexShortcutKey, modifiers: WorkspaceModel.filterShortcutModifiers)

                Toggle("Bodies", isOn: Binding(
                    get: { workspace.selectionFilter.contains(.bodies) },
                    set: { workspace.toggleSelectionFilter(.bodies, enabled: $0) }
                ))
                .keyboardShortcut(WorkspaceModel.filterBodyShortcutKey, modifiers: WorkspaceModel.filterShortcutModifiers)

                Toggle("Sketch Entities", isOn: Binding(
                    get: { workspace.selectionFilter.contains(.sketchEntities) },
                    set: { workspace.toggleSelectionFilter(.sketchEntities, enabled: $0) }
                ))
                .keyboardShortcut(WorkspaceModel.filterSketchShortcutKey, modifiers: WorkspaceModel.filterShortcutModifiers)

                Divider()

                Button("All Filters") {
                    workspace.resetSelectionFilters()
                }
                .keyboardShortcut(WorkspaceModel.filterAllShortcutKey, modifiers: WorkspaceModel.filterShortcutModifiers)
            }
        }
    }
}

struct SolidMenuCommands: Commands {
    var workspace: WorkspaceModel

    var body: some Commands {
        CommandMenu("Solid") {
            Button("Add Box Solid") {
                workspace.addDefaultBox()
            }
            .keyboardShortcut(WorkspaceModel.addBoxShortcutKey, modifiers: WorkspaceModel.addBoxShortcutModifiers)

            Button("Add Cylinder Solid") {
                workspace.addDefaultCylinder()
            }
            .keyboardShortcut(WorkspaceModel.addCylinderShortcutKey, modifiers: WorkspaceModel.addCylinderShortcutModifiers)

            Menu("More Primitives") {
                Button("Add Sphere Solid") {
                    workspace.addDefaultSphere()
                }
                Button("Add Cone Solid") {
                    workspace.addDefaultCone()
                }
                Button("Add Torus Solid") {
                    workspace.addDefaultTorus()
                }
                Button("Add Wedge Solid") {
                    workspace.addDefaultWedge()
                }
            }

            Menu("Add Primitive with Dialog") {
                Button("Add Box Solid…") {
                    workspace.startAddBoxCommand()
                }
                Button("Add Cylinder Solid…") {
                    workspace.startAddCylinderCommand()
                }
                Button("Add Sphere Solid…") {
                    workspace.startAddSphereCommand()
                }
                Button("Add Cone Solid…") {
                    workspace.startAddConeCommand()
                }
                Button("Add Torus Solid…") {
                    workspace.startAddTorusCommand()
                }
                Button("Add Wedge Solid…") {
                    workspace.startAddWedgeCommand()
                }
            }

            Divider()

            Button("New Ground Sketch…") {
                workspace.startNewSketchCommand()
            }

            Button("Extrude Sketch…") {
                workspace.startExtrudeCommand()
            }

            Button("Revolve Sketch…") {
                workspace.startRevolveCommand()
            }

            Menu("Modify & Pattern") {
                Button("Transform Solid…") {
                    workspace.startTransformCommand()
                }
                .disabled(workspace.selectedObject == nil)

                Button("Boolean Operation…") {
                    workspace.startBooleanCommand()
                }
                .disabled(workspace.document.objects.count < 2)

                Divider()

                Button("Chamfer…") {
                    workspace.startChamferCommand()
                }
                .disabled(workspace.document.objects.isEmpty)

                Button("Shell…") {
                    workspace.startShellCommand()
                }
                .disabled(workspace.document.objects.isEmpty)

                Button("Hole…") {
                    workspace.startHoleCommand()
                }
                .disabled(workspace.document.objects.isEmpty)

                Divider()

                Button("Linear Pattern…") {
                    workspace.startLinearPatternCommand()
                }
                .disabled(workspace.document.objects.isEmpty)

                Button("Circular Pattern…") {
                    workspace.startCircularPatternCommand()
                }
                .disabled(workspace.document.objects.isEmpty)

                Button("Mirror…") {
                    workspace.startMirrorCommand()
                }
                .disabled(workspace.document.objects.isEmpty)
            }

            Menu("Reference Geometry") {
                Button("New Datum Plane…") {
                    workspace.startDatumPlaneCommand()
                }

                Button("New Datum Axis…") {
                    workspace.startDatumAxisCommand()
                }

                Button("New Datum Point…") {
                    workspace.startDatumPointCommand()
                }

                Button("New Coordinate System…") {
                    workspace.startDatumCoordinateSystemCommand()
                }
            }

            Divider()

            Button(workspace.hideToggleTitle) {
                workspace.toggleSelectedObjectVisibility()
            }
            .keyboardShortcut(WorkspaceModel.hideSolidShortcutKey, modifiers: WorkspaceModel.hideSolidShortcutModifiers)
            .disabled(workspace.selectedObject == nil)

            Button(workspace.lockToggleTitle) {
                workspace.toggleSelectedObjectLock()
            }
            .keyboardShortcut(WorkspaceModel.lockSolidShortcutKey, modifiers: WorkspaceModel.lockSolidShortcutModifiers)
            .disabled(workspace.selectedObject == nil)

            Button(workspace.suppressToggleTitle) {
                workspace.toggleSelectedFeatureSuppression()
            }
            .keyboardShortcut(WorkspaceModel.suppressFeatureShortcutKey, modifiers: WorkspaceModel.suppressFeatureShortcutModifiers)
            .disabled(workspace.selectedFeature == nil || (workspace.selectedFeature?.isLocked ?? false))

            Divider()

            Button("Reload Part") {
                workspace.reloadSelectedPart()
            }
            .keyboardShortcut(WorkspaceModel.reloadPartShortcutKey, modifiers: WorkspaceModel.reloadPartShortcutModifiers)
            .disabled(workspace.selectedPartId == nil)

            Button("Roll Back to Selected") {
                if let sel = workspace.selectedId {
                    workspace.rollBack(to: sel)
                }
            }
            .keyboardShortcut(WorkspaceModel.rollBackToSelectedShortcutKey, modifiers: WorkspaceModel.rollBackToSelectedShortcutModifiers)
            .disabled(workspace.selectedObject == nil)

            Button("Roll Forward to End") {
                workspace.rollForwardToEnd()
            }
            .keyboardShortcut(WorkspaceModel.rollForwardToEndShortcutKey, modifiers: WorkspaceModel.rollForwardToEndShortcutModifiers)
            .disabled(!workspace.document.isRolledBack)

            Divider()

            Button("Delete Solid") {
                workspace.deleteSelectedObject()
            }
            .keyboardShortcut(WorkspaceModel.deleteShortcutKey, modifiers: WorkspaceModel.deleteShortcutModifiers)
            .disabled(!workspace.canDeleteSelectedObject)
        }
    }
}

struct ViewNavigationCommands: Commands {
    var workspace: WorkspaceModel

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Menu("Navigators") {
                ForEach(NavigatorTab.allCases) { tab in
                    Button(tab.title) {
                        workspace.navigatorTab = tab
                    }
                }
            }

            Menu("Inspectors") {
                ForEach(InspectorTab.allCases) { tab in
                    Button(tab.title) {
                        workspace.isInspectorPresented = true
                        workspace.inspectorTab = tab
                    }
                }
            }

            Button(workspace.consoleToggleTitle) {
                workspace.toggleConsole()
            }
            .keyboardShortcut(WorkspaceModel.consoleShortcutKey, modifiers: WorkspaceModel.consoleShortcutModifiers)

            Divider()

            Button("Zoom In") {
                workspace.zoomStep(zoomIn: true)
            }
            .keyboardShortcut(WorkspaceModel.zoomInShortcutKey, modifiers: WorkspaceModel.zoomInShortcutModifiers)
            .disabled(workspace.coordinator == nil)

            Button("Zoom Out") {
                workspace.zoomStep(zoomIn: false)
            }
            .keyboardShortcut(WorkspaceModel.zoomOutShortcutKey, modifiers: WorkspaceModel.zoomOutShortcutModifiers)
            .disabled(workspace.coordinator == nil)

            Button("Zoom to Fit") {
                workspace.fitToScene()
            }
            .keyboardShortcut(WorkspaceModel.zoomToFitShortcutKey, modifiers: WorkspaceModel.zoomToFitShortcutModifiers)
            .disabled(workspace.coordinator == nil)

            Button("Reset View") {
                workspace.resetView()
            }
            .keyboardShortcut(WorkspaceModel.resetViewShortcutKey, modifiers: WorkspaceModel.resetViewShortcutModifiers)
            .disabled(workspace.coordinator == nil)

            Button("Contextual Radial Menu") {
                workspace.openRadialMenuAtCenter()
            }

            Divider()

            Menu("View Angle") {
                Button("Front") {
                    workspace.applyPerspective(.front)
                }
                .keyboardShortcut(WorkspaceModel.viewFrontShortcutKey, modifiers: WorkspaceModel.viewShortcutModifiers)

                Button("Top") {
                    workspace.applyPerspective(.top)
                }
                .keyboardShortcut(WorkspaceModel.viewTopShortcutKey, modifiers: WorkspaceModel.viewShortcutModifiers)

                Button("Right") {
                    workspace.applyPerspective(.right)
                }
                .keyboardShortcut(WorkspaceModel.viewRightShortcutKey, modifiers: WorkspaceModel.viewShortcutModifiers)

                Button("Isometric") {
                    workspace.applyPerspective(.isometric)
                }
                .keyboardShortcut(WorkspaceModel.viewIsometricShortcutKey, modifiers: WorkspaceModel.viewShortcutModifiers)

                Divider()

                Button("Normal To") {
                    workspace.alignNormalTo()
                }
                .keyboardShortcut(WorkspaceModel.viewNormalToShortcutKey, modifiers: WorkspaceModel.viewShortcutModifiers)

                Divider()

                Button("Back") {
                    workspace.applyPerspective(.back)
                }

                Button("Left") {
                    workspace.applyPerspective(.left)
                }

                Button("Bottom") {
                    workspace.applyPerspective(.bottom)
                }

                Button("Perspective") {
                    workspace.applyPerspective(.perspective)
                }
            }

            Menu("Camera Projection") {
                Button("Perspective") {
                    workspace.setProjectionMode(.perspective)
                }
                Button("Orthographic") {
                    workspace.setProjectionMode(.orthographic)
                }
            }

            Menu("Display Mode") {
                ForEach(DisplayMode.allCases) { mode in
                    Button(mode.rawValue) {
                        workspace.setDisplayMode(mode)
                    }
                }
            }
        }
    }
}

struct ToolsMenuCommands: Commands {
    var workspace: WorkspaceModel

    var body: some Commands {
        CommandMenu("Tools") {
            Button("Measure") {
                workspace.startMeasureCommand()
            }

            MaterialLibraryMenuButton()

            Divider()

            Button(workspace.mcpServerToggleTitle) {
                workspace.toggleMCPServer()
            }
            .keyboardShortcut(WorkspaceModel.mcpServerShortcutKey, modifiers: WorkspaceModel.mcpServerShortcutModifiers)

            Divider()

            Menu("Viewport Tool") {
                Button("Select") { workspace.tool = .select }
                    .keyboardShortcut(WorkspaceModel.toolSelectShortcutKey, modifiers: WorkspaceModel.toolShortcutModifiers)
                Button("Orbit") { workspace.tool = .orbit }
                    .keyboardShortcut(WorkspaceModel.toolOrbitShortcutKey, modifiers: WorkspaceModel.toolShortcutModifiers)
                Button("Pan") { workspace.tool = .pan }
                    .keyboardShortcut(WorkspaceModel.toolPanShortcutKey, modifiers: WorkspaceModel.toolShortcutModifiers)
                Button("Zoom") { workspace.tool = .zoom }
                    .keyboardShortcut(WorkspaceModel.toolZoomShortcutKey, modifiers: WorkspaceModel.toolShortcutModifiers)
                Button("Trim") { workspace.tool = .trim }
                    .keyboardShortcut(WorkspaceModel.toolTrimShortcutKey, modifiers: WorkspaceModel.toolShortcutModifiers)
                Button("Rectangle") { workspace.tool = .rectangle }
                    .keyboardShortcut(WorkspaceModel.toolRectangleShortcutKey, modifiers: WorkspaceModel.toolShortcutModifiers)
            }

            Divider()

            Button("Predictive Commands") {
                workspace.togglePredictiveCommandSurface()
            }
            .disabled(workspace.document.selectedSubElement == nil)

            Divider()

            Menu("Sketch Operations") {
                Button("Project Selected Geometry") {
                    _ = workspace.projectSelectedGeometry()
                }
                .keyboardShortcut(WorkspaceModel.projectGeometryShortcutKey, modifiers: WorkspaceModel.projectGeometryShortcutModifiers)

                Divider()

                Menu("Rectangle") {
                    Button("Corner Rectangle") {
                        workspace.activeRectangleKind = .corner
                        _ = try? workspace.addCornerRectangle()
                    }
                    Button("Center Rectangle") {
                        workspace.activeRectangleKind = .center
                        _ = try? workspace.addCenterRectangle()
                    }
                    Button("Three-Point Rectangle") {
                        workspace.activeRectangleKind = .threePoint
                        _ = try? workspace.addThreePointRectangle()
                    }
                }
                .disabled(workspace.selectedSketchFeature == nil)

                Divider()

                Button("Trim Entity") {
                    workspace.tool = .trim
                }
                .keyboardShortcut(WorkspaceModel.toolTrimShortcutKey, modifiers: WorkspaceModel.toolShortcutModifiers)

                Divider()

                Button("Extend Selected Start") {
                    workspace.extendSelectedSketchEntity(targetEnd: .start)
                }
                .disabled(workspace.selectedSketchEntity == nil || (workspace.selectedSketchEntity?.entity.kind != "line" && workspace.selectedSketchEntity?.entity.kind != "arc"))

                Button("Extend Selected End") {
                    workspace.extendSelectedSketchEntity(targetEnd: .end)
                }
                .disabled(workspace.selectedSketchEntity == nil || (workspace.selectedSketchEntity?.entity.kind != "line" && workspace.selectedSketchEntity?.entity.kind != "arc"))

                Button("Split Selected Entity") {
                    workspace.splitSelectedSketchEntityAtMidpoint()
                }
                .disabled(workspace.selectedSketchEntity == nil)
            }
            .disabled(workspace.selectedSketchFeature == nil)

            Menu("Sketch Constraints") {
                Button("Dimension Line…") {
                    workspace.startDimensionCommand()
                }
                .keyboardShortcut(WorkspaceModel.dimensionLineShortcutKey, modifiers: WorkspaceModel.dimensionLineShortcutModifiers)
                .disabled(!workspace.hasAvailableSketchLine)

                Button(workspace.selectedSketchEntity?.entity.isConstruction == true ? "Unmark Construction Geometry" : "Toggle Construction Geometry") {
                    workspace.toggleSelectedSketchEntityConstruction()
                }
                .keyboardShortcut(WorkspaceModel.toggleConstructionShortcutKey, modifiers: WorkspaceModel.toggleConstructionShortcutModifiers)
                .disabled(workspace.selectedSketchEntity == nil)

                Divider()

                Button("Apply Parallel Constraint") {
                    workspace.applyConstraintToSelectedSketch(.parallel)
                }
                Button("Apply Perpendicular Constraint") {
                    workspace.applyConstraintToSelectedSketch(.perpendicular)
                }
                Button("Apply Tangent Constraint") {
                    workspace.applyConstraintToSelectedSketch(.tangent)
                }
                Button("Apply Concentric Constraint") {
                    workspace.applyConstraintToSelectedSketch(.concentric)
                }
                Button("Apply Symmetric Constraint") {
                    workspace.applyConstraintToSelectedSketch(.symmetric)
                }
                Divider()
                Button("Solve Sketch Constraints") {
                    workspace.solveActiveSketchConstraints()
                }
                Button("Toggle Live Constraint Inference") {
                    workspace.toggleLiveInference()
                }
            }
            .disabled(workspace.selectedSketchFeature == nil)
        }
    }
}

private struct MaterialLibraryMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Material Library…") {
            openWindow(id: MaterialLibraryView.windowID)
        }
    }
}

struct AssemblyMenuCommands: Commands {
    var workspace: WorkspaceModel

    var body: some Commands {
        CommandMenu("Assembly") {
            Button("Insert Component from File…") {
                workspace.promptInsertComponentFromFile()
            }
            .keyboardShortcut("i", modifiers: [.option, .command])

            Button("Insert Component from Document…") {
                workspace.promptInsertComponentFromDocument()
            }

            Divider()

            Button("Solve Assembly") {
                _ = workspace.solveAssemblyConstraints()
            }
            .keyboardShortcut(WorkspaceModel.solveAssemblyShortcutKey, modifiers: WorkspaceModel.solveAssemblyShortcutModifiers)
            .disabled(workspace.document.documentType != .assembly && workspace.document.assemblyConstraints.isEmpty)

            Menu("Add Joint") {
                Button("Fastened Joint") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .fastened)
                }
                Button("Revolute Joint") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .revolute)
                }
                Button("Slider Joint") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .slider)
                }
                Button("Cylindrical Joint") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .cylindrical)
                }
                Button("Pin-Slot Joint") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .pinSlot)
                }
                Button("Planar Joint") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .planar)
                }
                Button("Ball Joint") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .ball)
                }
            }
            .disabled(workspace.document.componentInstances.isEmpty)

            Menu("Add Mate") {
                Button("Coincident Mate") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .coincident)
                }
                Button("Concentric Mate") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .concentric)
                }
                Button("Distance Mate") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .distance)
                }
                Button("Parallel Mate") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .parallel)
                }
                Button("Perpendicular Mate") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .perpendicular)
                }
                Button("Angle Mate") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .angle)
                }
                Button("Tangent Mate") {
                    _ = workspace.addDefaultAssemblyConstraint(kind: .tangent)
                }
            }
            .disabled(workspace.document.componentInstances.isEmpty)

            Divider()

            let selected = workspace.selectedComponentInstance
            Button(selected?.isGrounded == true ? "Float Component" : "Ground Component") {
                if let selected {
                    workspace.toggleComponentInstanceGrounded(id: selected.id)
                }
            }
            .disabled(selected == nil)

            Divider()

            Button("Group as Subassembly") {
                _ = workspace.groupSelectedAsSubassembly()
            }
            .disabled(!workspace.canGroupSelectedAsSubassembly)

            Button("Dissolve Subassembly") {
                _ = workspace.dissolveSelectedSubassembly()
            }
            .disabled(selected?.isSubassembly != true)

            Button(selected?.subassemblyBehavior == .flexible ? "Make Subassembly Rigid" : "Make Subassembly Flexible") {
                if let selected, selected.isSubassembly {
                    _ = workspace.toggleSubassemblyBehavior(id: selected.id)
                }
            }
            .disabled(selected?.isSubassembly != true)

            Divider()

            Menu("Pattern Component") {
                Button("Linear Pattern…") {
                    _ = workspace.patternSelectedComponentLinear()
                }
                Button("Circular Pattern…") {
                    _ = workspace.patternSelectedComponentCircular()
                }
                Button("Pattern by Part Feature…") {
                    _ = workspace.patternSelectedComponentByFeaturePattern()
                }
            }
            .disabled(selected == nil)

            Button("Mirror Component…") {
                _ = workspace.mirrorSelectedComponent()
            }
            .disabled(selected == nil)

            Divider()

            Menu("Export Bill of Materials") {
                Button("Flat BOM (CSV)…") {
                    workspace.promptExportBillOfMaterials(structure: .flat)
                }
                Button("Hierarchical BOM (CSV)…") {
                    workspace.promptExportBillOfMaterials(structure: .hierarchical)
                }
            }
            .disabled(!workspace.canExportBillOfMaterials)

            Divider()

            Menu("Exploded Views") {
                Button("New Exploded View") {
                    _ = workspace.createExplodedView()
                }
                if !workspace.document.explodedViews.isEmpty {
                    Divider()
                    ForEach(workspace.document.explodedViews) { view in
                        let isActive = workspace.activeExplodedViewId == view.id && !view.isCollapsed
                        Button(isActive ? "Collapse \(view.name)" : "Explode \(view.name)") {
                            workspace.toggleExplodedView(id: view.id)
                        }
                    }
                }
            }
            .disabled(workspace.document.documentType != .assembly && workspace.document.componentInstances.isEmpty)
        }
    }
}

/// Menu bar commands for Computer-Aided Engineering simulation studies (ADR-D5, #157).
struct SimulationMenuCommands: Commands {
    var workspace: WorkspaceModel

    var body: some Commands {
        CommandMenu("Simulation") {
            Menu("New Study") {
                Button("Linear Static Study") {
                    _ = workspace.createSimulationStudy(type: .linearStatic)
                }
                Button("Thermal Conduction Study") {
                    _ = workspace.createSimulationStudy(type: .thermalConduction)
                }
                Button("Modal Frequency Study") {
                    _ = workspace.createSimulationStudy(type: .modalFrequency)
                }
                Button("Linear Buckling Study") {
                    _ = workspace.createSimulationStudy(type: .linearBuckling)
                }
            }

            if !workspace.document.studies.isEmpty {
                Divider()
                Menu("Active Study") {
                    ForEach(workspace.document.studies) { study in
                        let isActive = workspace.document.activeStudyId == study.id
                        Button(isActive ? "✓ \(study.name)" : study.name) {
                            workspace.setActiveSimulationStudy(id: study.id)
                        }
                    }
                }
            }

            Divider()

            Button("Add Fixture…") {
                if let activeStudy = workspace.document.activeStudy {
                    _ = workspace.addSimulationFixture(studyId: activeStudy.id)
                }
            }
            .disabled(workspace.document.activeStudy == nil)

            Button("Add Load…") {
                if let activeStudy = workspace.document.activeStudy {
                    _ = workspace.addSimulationLoad(studyId: activeStudy.id)
                }
            }
            .disabled(workspace.document.activeStudy == nil)

            Divider()

            let activeStudy = workspace.document.activeStudy
            let isRunning = activeStudy.map { workspace.isStudyRunning($0.id) } ?? false
            let isMeshing = activeStudy.map { workspace.isStudyMeshing($0.id) } ?? false

            if isMeshing {
                Button("Cancel Simulation Mesh") {
                    if let activeStudy {
                        workspace.cancelSimulationMesh(studyId: activeStudy.id)
                    }
                }
            } else {
                Button("Generate Simulation Mesh") {
                    if let activeStudy {
                        workspace.generateSimulationMesh(studyId: activeStudy.id)
                    }
                }
                .disabled(activeStudy == nil || isRunning)
            }

            if isRunning {
                Button("Cancel Active Study") {
                    if let activeStudy {
                        workspace.cancelSimulationStudy(id: activeStudy.id)
                    }
                }
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button("Run Active Study") {
                    if let activeStudy {
                        workspace.runSimulationStudy(id: activeStudy.id)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(activeStudy == nil || isMeshing)
            }
        }
    }
}
