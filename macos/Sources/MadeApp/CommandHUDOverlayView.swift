import SwiftUI
import MadeCore
import simd

private struct HUDSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = CGSize(width: 260, height: 280)
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
    @State private var hudSize: CGSize = CGSize(width: 260, height: 280)

    var body: some View {
        GeometryReader { geo in
            let viewportSize = geo.size
            let geomRect = computeGeometryScreenRect(viewportSize: viewportSize)
            let pos = CommandHUDPlacement.computePosition(
                geometryScreenRect: geomRect,
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
                .frame(width: 260)
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
                .offset(x: pos.x, y: pos.y)
        }
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
