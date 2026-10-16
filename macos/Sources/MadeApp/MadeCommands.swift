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

            Button("Export STEP…") {
                workspace.promptExportStepFile(selectedOnly: false)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

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
            Button("Delete") {
                workspace.deleteSelectedObject()
            }
            .keyboardShortcut(WorkspaceModel.deleteShortcutKey, modifiers: WorkspaceModel.deleteShortcutModifiers)
            .disabled(!workspace.canDeleteSelectedObject)
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

            Button("Add Box Solid…") {
                workspace.startAddBoxCommand()
            }

            Button("Add Cylinder Solid") {
                workspace.addDefaultCylinder()
            }
            .keyboardShortcut(WorkspaceModel.addCylinderShortcutKey, modifiers: WorkspaceModel.addCylinderShortcutModifiers)

            Button("Add Cylinder Solid…") {
                workspace.startAddCylinderCommand()
            }

            Button("Add Sphere Solid") {
                workspace.addDefaultSphere()
            }

            Button("Add Sphere Solid…") {
                workspace.startAddSphereCommand()
            }

            Button("Add Cone Solid") {
                workspace.addDefaultCone()
            }

            Button("Add Cone Solid…") {
                workspace.startAddConeCommand()
            }

            Button("Add Torus Solid") {
                workspace.addDefaultTorus()
            }

            Button("Add Torus Solid…") {
                workspace.startAddTorusCommand()
            }

            Button("Add Wedge Solid") {
                workspace.addDefaultWedge()
            }

            Button("Add Wedge Solid…") {
                workspace.startAddWedgeCommand()
            }

            Button("Import STEP Solid…") {
                workspace.promptImportStepFile()
            }

            Button("Export STEP Solid…") {
                workspace.promptExportStepFile(selectedOnly: workspace.selectedId != nil)
            }
            .disabled(workspace.document.objects.isEmpty)

            Button("Transform Solid…") {
                workspace.startTransformCommand()
            }
            .disabled(workspace.selectedObject == nil)

            Button("Boolean Operation…") {
                workspace.startBooleanCommand()
            }
            .disabled(workspace.document.objects.count < 2)

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

            Divider()

            Button("Reload Part") {
                workspace.reloadSelectedPart()
            }
            .keyboardShortcut(WorkspaceModel.reloadPartShortcutKey, modifiers: WorkspaceModel.reloadPartShortcutModifiers)
            .disabled(workspace.selectedPartId == nil)

            Divider()

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
        }
    }
}

struct ToolsMenuCommands: Commands {
    var workspace: WorkspaceModel

    var body: some Commands {
        CommandMenu("Tools") {
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
            }
        }
    }
}
