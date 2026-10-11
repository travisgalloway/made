import SwiftUI
import MetalKit
import MadeCore

public struct ViewportCanvasView: View {
    @Bindable var document: DocumentModel
    var renderer: MetalRenderer?
    var viewportState: ViewportState
    @Binding var selectedId: ObjectId
    @Binding var coordinator: CADMetalViewRepresentable.Coordinator?
    var activeSnapKind: SnapKind?
    var currentPerspective: ViewportPerspective
    var renderCount: Int
    var drawCalls: Int
    var lastReason: String
    var onInvalidate: () -> Void
    var onSnapChanged: (SnapResult?) -> Void
    var onPerspectiveChanged: (ViewportPerspective) -> Void
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer?,
        viewportState: ViewportState,
        selectedId: Binding<ObjectId>,
        coordinator: Binding<CADMetalViewRepresentable.Coordinator?>,
        activeSnapKind: SnapKind?,
        currentPerspective: ViewportPerspective,
        renderCount: Int,
        drawCalls: Int,
        lastReason: String,
        onInvalidate: @escaping () -> Void,
        onSnapChanged: @escaping (SnapResult?) -> Void,
        onPerspectiveChanged: @escaping (ViewportPerspective) -> Void
    ) {
        self.document = document
        self.renderer = renderer
        self.viewportState = viewportState
        self._selectedId = selectedId
        self._coordinator = coordinator
        self.activeSnapKind = activeSnapKind
        self.currentPerspective = currentPerspective
        self.renderCount = renderCount
        self.drawCalls = drawCalls
        self.lastReason = lastReason
        self.onInvalidate = onInvalidate
        self.onSnapChanged = onSnapChanged
        self.onPerspectiveChanged = onPerspectiveChanged
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Scene View Header Frame
            HStack(spacing: 6) {
                // Left: Breadcrumbs
                Image(systemName: "cube")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Scene")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(selectedEntityName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Right: View Toggle (Camera Perspective Presets)
                Menu {
                    ForEach(ViewportPerspective.allCases) { persp in
                        Button(persp.rawValue) {
                            onPerspectiveChanged(persp)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11))
                        Text(currentPerspective.rawValue)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .help("Camera View Perspective")
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
                                Text("Initializing Metal 3...")
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
                
                // Observability Status HUD
                HStack(spacing: 14) {
                    if viewportState.isUnavailable {
                        Label("Metal unavailable", systemImage: "bolt.slash.fill")
                            .foregroundColor(.red)
                    } else {
                        Label("Metal 3", systemImage: "bolt.fill")
                            .foregroundColor(viewportState == .ready ? .green : .yellow)
                    }
                    
                    Divider().frame(height: 12)
                    
                    Text("Render: \(renderCount)")
                        .monospacedDigit()
                    
                    Divider().frame(height: 12)
                    
                    Text("Draw Calls: \(drawCalls)")
                        .monospacedDigit()
                    
                    Divider().frame(height: 12)
                    
                    Text("Invalidate: \(lastReason)")
                        .foregroundColor(.secondary)
                    
                    Divider().frame(height: 12)
                    
                    if let snap = activeSnapKind {
                        Text("Snap: \(snap.rawValue)")
                            .foregroundColor(snapColor(for: snap))
                            .monospacedDigit()
                    } else {
                        Text("Snap: none")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
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
