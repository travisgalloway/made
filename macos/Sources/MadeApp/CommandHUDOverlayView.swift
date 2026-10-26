import SwiftUI
import MadeCore
import simd

private struct HUDSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = CGSize(width: 280, height: 280)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0 && next.height > 0 {
            value = next
        }
    }
}

struct CommandHUDOverlayView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Bindable var session: CommandSession
    @State private var hudSize: CGSize = CGSize(width: 280, height: 280)
    @State private var dragOffset: CGSize = .zero
    @GestureState private var activeDragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let viewportSize = geo.size
            let geomRect = computeGeometryScreenRect(viewportSize: viewportSize)
            let basePos = CommandHUDPlacement.computePosition(
                geometryScreenRect: geomRect,
                viewportSize: viewportSize,
                hudSize: hudSize
            )
            let clampedPos = Self.clampedPosition(
                basePosition: basePos,
                dragOffset: dragOffset,
                activeTranslation: activeDragTranslation,
                viewportSize: viewportSize,
                hudSize: hudSize
            )

            CommandPanelView(session: session)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.separator, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                .frame(width: 280)
                .fixedSize(horizontal: true, vertical: true)
                .background(
                    GeometryReader { cardGeo in
                        Color.clear
                            .preference(key: HUDSizePreferenceKey.self, value: cardGeo.size)
                    }
                )
                .onPreferenceChange(HUDSizePreferenceKey.self) { newSize in
                    if newSize.width > 0 && newSize.height > 0 {
                        hudSize = newSize
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($activeDragTranslation) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            dragOffset = CGSize(
                                width: dragOffset.width + value.translation.width,
                                height: dragOffset.height + value.translation.height
                            )
                        }
                )
                .offset(x: clampedPos.x, y: clampedPos.y)
                .onChange(of: session.id) { _, _ in
                    dragOffset = .zero
                }
        }
    }

    static func clampedPosition(
        basePosition: CGPoint,
        dragOffset: CGSize,
        activeTranslation: CGSize = .zero,
        viewportSize: CGSize,
        hudSize: CGSize,
        margin: CGFloat = 12
    ) -> CGPoint {
        let rawX = basePosition.x + dragOffset.width + activeTranslation.width
        let rawY = basePosition.y + dragOffset.height + activeTranslation.height
        guard viewportSize.width > 0 && viewportSize.height > 0 else {
            return CGPoint(x: rawX, y: rawY)
        }
        let maxX = max(margin, viewportSize.width - hudSize.width - margin)
        let maxY = max(margin, viewportSize.height - hudSize.height - margin)
        return CGPoint(
            x: min(max(margin, rawX), maxX),
            y: min(max(margin, rawY), maxY)
        )
    }

    private func computeGeometryScreenRect(viewportSize: CGSize) -> CGRect? {
        guard let renderer = workspace.viewportManager.renderer else { return nil }
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return nil }

        var targetCandidate: CandidateMesh? = nil
        let meshes = renderer.candidateMeshes()

        if let previewMesh = renderer.meshes[CommandSession.previewSolidId] {
            var cand = previewMesh.candidateMesh
            cand.transform = previewMesh.transform
            targetCandidate = cand
        } else if let slotObjId = session.selectionSlots.first(where: { $0.selectedObjectId != nil })?.selectedObjectId,
                  let match = meshes.first(where: { $0.id == slotObjId }) {
            targetCandidate = match
        } else if let selId = workspace.selectedId,
                  let match = meshes.first(where: { $0.id == selId }) {
            targetCandidate = match
        }

        guard let target = targetCandidate,
              let bounds = SceneBounds.of([target]) else {
            return nil
        }

        let aspect = Float(max(1.0, viewportSize.width) / max(1.0, viewportSize.height))
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = simd_mul(matrices.projection, matrices.view)

        return ScreenBoundsCalculator.screenBoundingBox(
            for: bounds,
            viewProjectionMatrix: vp,
            viewportSize: viewportSize
        )
    }
}
