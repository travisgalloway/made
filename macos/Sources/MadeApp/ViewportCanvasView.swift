import SwiftUI
import MadeCore

struct ViewportCanvasView: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            canvas
        }
    }

    private var header: some View {
        HStack {
            if workspace.document.documentType == .drawing {
                HStack(spacing: 4) {
                    Label("Drawing", systemImage: "doc.richtext")
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text(workspace.document.activeSheet?.name ?? "No Sheet")
                }
                .font(.callout)
                Spacer()
                if let sheet = workspace.document.activeSheet {
                    HStack(spacing: 8) {
                        Text("\(sheet.size.displayName) · \(sheet.orientation.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Scale: \(sheet.scale)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Label("Scene", systemImage: "cube")
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text(workspace.document.objects.isEmpty ? "Empty Scene" : (workspace.selectedObject?.name ?? "No Selection"))
                }
                .font(.callout)
                Spacer()
                if workspace.viewportManager.state == .ready {
                    Picker("Display Mode", selection: Binding(
                        get: { workspace.displayMode },
                        set: { workspace.setDisplayMode($0) }
                    )) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)

                    Picker("Projection", selection: Binding(
                        get: { workspace.projectionMode },
                        set: { workspace.setProjectionMode($0) }
                    )) {
                        ForEach(CameraProjection.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 170)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: BarMetrics.height)
        .background(.bar)
    }

    @ViewBuilder
    private var canvas: some View {
        @Bindable var workspace = workspace

        if workspace.document.documentType == .drawing {
            DrawingCanvasView()
        } else {
            switch workspace.viewportManager.state {
            case .ready:
            if let renderer = workspace.viewportManager.renderer {
                ZStack(alignment: .topTrailing) {
                    ZStack(alignment: .topLeading) {
                        let activePlane = workspace.selectedSketchFeature.flatMap {
                            if case .sketch(let data) = $0.operation { return workspace.document.resolveSketchPlane(for: data) }
                            return nil
                        }
                        let sketchEntities: [SketchEntity] = workspace.selectedSketchFeature.flatMap {
                            if case .sketch(let data) = $0.operation { return data.entities }
                            return []
                        } ?? []

                        CADMetalViewRepresentable(
                            document: workspace.document,
                            renderer: renderer,
                            selectedId: workspace.selectedId,
                            selectedSubElement: workspace.document.selectedSubElement,
                            tool: workspace.tool,
                            selectionFilter: workspace.selectionFilter,
                            showsGrid: workspace.showsGrid,
                            showsAxes: workspace.showsAxes,
                            showsGizmo: workspace.showsGizmo,
                            showsEdges: workspace.showsEdges,
                            displayMode: workspace.displayMode,
                            navigationPreset: workspace.navigationPreset,
                            coordinator: $workspace.coordinator,
                            isCommandActive: workspace.activeCommand != nil,
                            onCancelCommand: { workspace.cancelActiveCommand() },
                            onCommitCommand: { workspace.commitActiveCommand() },
                            onSelectObjectForCommand: { id in workspace.selectObjectForActiveCommand(id) },
                            onSelectElementForCommand: { id, sub in workspace.selectElementForActiveCommand(id, subElement: sub) },
                            onInvalidate: { workspace.updateStats() },
                            onSnapChanged: { workspace.handleSnapChanged($0) },
                            onToolShortcut: { workspace.tool = $0 },
                            onResetView: { workspace.resetView() },
                            onCommitParam: { id, key, value in workspace.setParam(id, key, value) },
                            onDoubleTapFace: { solidId, faceId in workspace.snapCameraToFace(solidId: solidId, faceId: faceId) },
                            onCancelAnimation: { workspace.cancelCameraAnimation() },
                            activeSketchPlane: activePlane,
                            sketchEntities: sketchEntities,
                            sketchRegions: workspace.detectedSketchRegions,
                            onHoverSketchRegion: { regionId in workspace.setHoveredSketchRegion(regionId) },
                            onSelectSketchRegion: { regionId in
                                if let sketchId = workspace.selectedSketchFeature?.id {
                                    workspace.selectSketchRegion(featureId: sketchId, regionId: regionId)
                                }
                            },
                            onTrimClick: { uv in
                                if let feat = workspace.selectedSketchFeature, case .sketch(let sketchData) = feat.operation {
                                    if let hitEntity = SketchOperations.hitTestEntity(at: uv, in: sketchData.entities) {
                                        _ = workspace.trimSketchEntity(in: feat.id, entityId: hitEntity.id, clickPoint: uv)
                                    }
                                }
                            },
                            onTrimDrag: { path in
                                if let feat = workspace.selectedSketchFeature {
                                    _ = workspace.trimSketchEntitiesAlongPath(in: feat.id, path: path)
                                }
                            },
                            activeSketchFeatureId: workspace.selectedSketchFeature?.id,
                            onSketchDragStart: { featId, entityId in
                                workspace.beginInteractiveSketchDrag(featureId: featId, entityId: entityId)
                            },
                            onSketchDragUpdate: { featId, dragTarget in
                                workspace.solveSketchDrag(featureId: featId, dragTarget: dragTarget)
                            },
                            onSketchDragEnd: { featId in
                                workspace.endInteractiveSketchDrag(featureId: featId)
                            },
                            onAssemblyDragStart: { instanceId in
                                workspace.beginInteractiveAssemblyDrag(instanceId: instanceId)
                            },
                            onAssemblyDragUpdate: { dragTarget in
                                workspace.solveAssemblyDrag(dragTarget: dragTarget)
                            },
                            onAssemblyDragEnd: { instanceId in
                                workspace.endInteractiveAssemblyDrag(instanceId: instanceId)
                            },
                            onAssemblyDragCancel: { _ in
                                workspace.cancelInteractiveAssemblyDrag()
                            },
                            activeRectangleKind: workspace.activeRectangleKind,
                            onRectangleCompleted: { start, end in
                                guard let feat = workspace.selectedSketchFeature else { return }
                                switch workspace.activeRectangleKind {
                                case .corner:
                                    _ = try? workspace.addCornerRectangle(to: feat.id, corner1: start, corner2: end)
                                case .center:
                                    _ = try? workspace.addCenterRectangle(to: feat.id, center: start, corner: end)
                                case .threePoint:
                                    let baseVec = end - start
                                    let normal = SIMD2<Double>(-baseVec.y, baseVec.x)
                                    let p3 = start + normal * 0.5
                                    _ = try? workspace.addThreePointRectangle(to: feat.id, point1: start, point2: end, point3: p3)
                                }
                            },
                            isRadialMenuOpen: workspace.radialMenuState != nil,
                            onOpenRadialMenu: { loc, hitId in
                                workspace.openRadialMenu(at: loc, targetSolidId: hitId)
                            },
                            onDismissRadialMenu: {
                                workspace.dismissRadialMenu()
                            },
                            pendingPlacement: workspace.pendingComponentPlacement,
                            onPlacePendingComponent: { targetPoint in
                                _ = workspace.placePendingComponent(at: targetPoint)
                            },
                            onCancelPendingPlacement: {
                                workspace.cancelPendingPlacement()
                            },
                            isProbeModeActive: workspace.isProbeModeActive,
                            onProbeClick: { loc, view in
                                if let studyId = workspace.selectedSimulationStudyId ?? workspace.document.activeStudyId {
                                    workspace.probeAtScreenPoint(loc: loc, in: view, studyId: studyId)
                                }
                            }
                        )

                        if let pending = workspace.pendingComponentPlacement {
                            ComponentPlacementHUDOverlayView(pending: pending) {
                                workspace.cancelPendingPlacement()
                            }
                        }

                        if let snap = workspace.activeSnapResult, snap.screenPoint != nil {
                            SnapOverlayView(snap: snap)
                        }

                        if workspace.document.objects.isEmpty {
                            EmptySceneGuidanceOverlayView()
                        }

                        if workspace.commandPanelPlacement == .floatingHUD, let session = workspace.activeCommand {
                            CommandHUDOverlayView(session: session)
                        }

                        if let session = workspace.activeCommand {
                            DimensionLabelsOverlayView(session: session)
                        }

                        if workspace.isPredictiveCommandsVisible,
                           workspace.activeCommand == nil,
                           let sub = workspace.document.selectedSubElement {
                            PredictiveCommandPopoverView(selectedSubElement: sub)
                        }

                        if let radialState = workspace.radialMenuState {
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .onTapGesture {
                                    workspace.dismissRadialMenu()
                                }
                            RadialMenuView(state: radialState)
                        }
                    }

                    if let studyId = workspace.selectedSimulationStudyId,
                       let study = workspace.document.study(id: studyId),
                       study.contourSettings.isVisible,
                       let extrema = workspace.activeContourExtrema[studyId] {
                        SimulationContourLegendOverlayView(
                            studyId: studyId,
                            settings: study.contourSettings,
                            extrema: extrema
                        )
                    }

                    ViewCubeOverlayView()
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                }
                .sheet(isPresented: $workspace.isShowingBodyPickerForInsertion) {
                    ComponentBodyPickerSheet()
                }
            }
        case .initializing:
            ProgressView("Initializing Metal 4…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let reason):
            ContentUnavailableView("Metal Unavailable", systemImage: "exclamationmark.triangle", description: Text(reason.description))
        }
    }
}
}

private struct ComponentPlacementHUDOverlayView: View {
    let pending: PendingComponentPlacement
    let onCancel: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "square.3.layers.3d.down.right")
                    .foregroundStyle(.blue)
                    .imageScale(.medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Placing: \(pending.name)")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Click in viewport to place • Esc to cancel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
            .padding(.top, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ComponentBodyPickerSheet: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insert Component from Document")
                .font(.headline)
            Text("Select a body to insert as a component instance:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(workspace.document.bodies) { body in
                HStack {
                    Image(systemName: "cube")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(body.name)
                            .font(.body)
                        Text(body.id.rawValue)
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Insert") {
                        workspace.insertComponentFromInternalBody(body)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 180, maxHeight: 300)

            HStack {
                Spacer()
                Button("Cancel") {
                    workspace.isShowingBodyPickerForInsertion = false
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
    }
}
