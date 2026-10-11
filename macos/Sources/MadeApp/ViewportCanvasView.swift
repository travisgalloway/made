import SwiftUI
import MetalKit
import MadeCore

public struct ViewportCanvasView: View {
    @Bindable var document: DocumentModel
    var renderer: MetalRenderer?
    var viewportState: ViewportState
    @Binding var selectedId: ObjectId
    @Binding var gizmoMode: GizmoMode
    @Binding var projectionMode: CameraProjection
    @Binding var currentPerspective: ViewportPerspective
    @Binding var coordinator: CADMetalViewRepresentable.Coordinator?
    var activeSnapKind: SnapKind?
    var onInvalidate: () -> Void
    var onSnapChanged: (SnapResult?) -> Void
    var onPerspectiveChanged: (ViewportPerspective) -> Void
    var onProjectionChanged: (CameraProjection) -> Void
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer?,
        viewportState: ViewportState,
        selectedId: Binding<ObjectId>,
        gizmoMode: Binding<GizmoMode>,
        projectionMode: Binding<CameraProjection>,
        currentPerspective: Binding<ViewportPerspective>,
        coordinator: Binding<CADMetalViewRepresentable.Coordinator?>,
        activeSnapKind: SnapKind?,
        onInvalidate: @escaping () -> Void,
        onSnapChanged: @escaping (SnapResult?) -> Void,
        onPerspectiveChanged: @escaping (ViewportPerspective) -> Void,
        onProjectionChanged: @escaping (CameraProjection) -> Void
    ) {
        self.document = document
        self.renderer = renderer
        self.viewportState = viewportState
        self._selectedId = selectedId
        self._gizmoMode = gizmoMode
        self._projectionMode = projectionMode
        self._currentPerspective = currentPerspective
        self._coordinator = coordinator
        self.activeSnapKind = activeSnapKind
        self.onInvalidate = onInvalidate
        self.onSnapChanged = onSnapChanged
        self.onPerspectiveChanged = onPerspectiveChanged
        self.onProjectionChanged = onProjectionChanged
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Xcode-Style Editor Jump Bar
            HStack(spacing: 8) {
                // Breadcrumbs
                HStack(spacing: 4) {
                    Image(systemName: "cube")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("made")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("Scene")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    // Selected entity jump menu
                    Menu {
                        ForEach(document.objects) { obj in
                            Button {
                                selectedId = obj.id
                            } label: {
                                HStack {
                                    Text(obj.name)
                                    if obj.id == selectedId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(selectedEntityName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
                
                Spacer()
                
                // Gizmo Mode Segmented Control
                HStack(spacing: 2) {
                    ForEach(GizmoMode.allCases) { mode in
                        Button {
                            gizmoMode = mode
                        } label: {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 11, weight: gizmoMode == mode ? .semibold : .regular))
                                .foregroundColor(gizmoMode == mode ? .accentColor : .secondary)
                                .frame(width: 24, height: 20)
                                .background(gizmoMode == mode ? Color.accentColor.opacity(0.15) : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("\(mode.rawValue) Gizmo Mode")
                    }
                }
                .padding(2)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                
                Divider().frame(height: 14)
                
                // Projection Picker (Persp / Ortho)
                Picker("Projection", selection: $projectionMode) {
                    Text("Persp").tag(CameraProjection.perspective)
                    Text("Ortho").tag(CameraProjection.orthographic)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .onChange(of: projectionMode) { _, newProj in
                    onProjectionChanged(newProj)
                }
                
                // Camera View Presets Menu
                Menu {
                    ForEach(ViewportPerspective.allCases) { persp in
                        Button(persp.rawValue) {
                            currentPerspective = persp
                            onPerspectiveChanged(persp)
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11))
                        Text(currentPerspective.rawValue)
                            .font(.system(size: 11))
                    }
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 3D Canvas Area
            ZStack(alignment: .bottomLeading) {
                switch viewportState {
                case .ready:
                    if let rend = renderer {
                        CADMetalViewRepresentable(
                            document: document,
                            renderer: rend,
                            coordinator: $coordinator,
                            onInvalidate: onInvalidate,
                            onSnapChanged: onSnapChanged
                        )
                        .frame(minWidth: 350, minHeight: 250)
                    }
                case .initializing:
                    Color.black
                        .overlay(
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Initializing Metal 3 Pipeline...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        )
                case .unavailable(let reason):
                    Color.black
                        .overlay(
                            VStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("Metal unavailable")
                                    .font(.headline)
                                Text(reason.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        )
                }
                
                // Viewport Overlay Badges
                HStack(spacing: 8) {
                    if let snap = activeSnapKind {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(snapColor(for: snap))
                                .frame(width: 6, height: 6)
                            Text("Snap: \(snap.rawValue)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    
                    if gizmoMode != .select {
                        HStack(spacing: 4) {
                            Image(systemName: gizmoMode.iconName)
                                .font(.system(size: 10))
                            Text(gizmoMode.rawValue)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(10)
            }
        }
    }
    
    private var selectedEntityName: String {
        document.objects.first(where: { $0.id == selectedId })?.name ?? "No Selection"
    }
    
    private func snapColor(for kind: SnapKind) -> Color {
        switch kind {
        case .vertex: return .orange
        case .edge: return .cyan
        case .grid: return .green
        }
    }
}
