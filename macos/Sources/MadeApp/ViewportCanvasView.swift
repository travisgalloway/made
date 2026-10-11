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
    var renderCount: Int
    var drawCalls: Int
    var lastReason: String
    var onInvalidate: () -> Void
    var onSnapChanged: (SnapResult?) -> Void
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer?,
        viewportState: ViewportState,
        selectedId: Binding<ObjectId>,
        coordinator: Binding<CADMetalViewRepresentable.Coordinator?>,
        activeSnapKind: SnapKind?,
        renderCount: Int,
        drawCalls: Int,
        lastReason: String,
        onInvalidate: @escaping () -> Void,
        onSnapChanged: @escaping (SnapResult?) -> Void
    ) {
        self.document = document
        self.renderer = renderer
        self.viewportState = viewportState
        self._selectedId = selectedId
        self._coordinator = coordinator
        self.activeSnapKind = activeSnapKind
        self.renderCount = renderCount
        self.drawCalls = drawCalls
        self.lastReason = lastReason
        self.onInvalidate = onInvalidate
        self.onSnapChanged = onSnapChanged
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Editor Jump Bar
            HStack(spacing: 6) {
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
                Text(selectedEntityName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
