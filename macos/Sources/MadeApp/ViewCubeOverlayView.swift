import SwiftUI
import MadeCore

/// Interactive on-canvas 3D View Cube overlay tracking camera orientation in real time.
/// Supports clicking faces, edges, corners, and a home reset button.
/// Complies with Invariant 2 (on-demand redraws) and Invariant 3 (imperative viewport).
struct ViewCubeOverlayView: View {
    @Environment(WorkspaceModel.self) private var workspace

    @State private var hoveredRegion: ViewCube.Region? = nil

    private let cubeSize = CGSize(width: 110, height: 110)

    var body: some View {
        let projectedFaces = ViewCube.projectedFaces(camera: workspace.camera, size: cubeSize)

        ZStack(alignment: .topLeading) {
            // 3D-oriented Cube Faces
            ZStack {
                ForEach(projectedFaces) { pf in
                    facePolygon(pf)
                }

                ForEach(projectedFaces) { pf in
                    faceLabel(pf)
                }
            }
            .frame(width: cubeSize.width, height: cubeSize.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredRegion = ViewCube.hitTest(
                        point: location,
                        in: cubeSize,
                        camera: workspace.camera
                    )
                case .ended:
                    hoveredRegion = nil
                }
            }
            .onTapGesture { location in
                if let region = ViewCube.hitTest(
                    point: location,
                    in: cubeSize,
                    camera: workspace.camera
                ) {
                    workspace.applyViewCubeRegion(region)
                }
            }

            // Home reset button at top-left
            homeButton

            // Region badge feedback at bottom
            if let region = hoveredRegion {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(region.displayName)
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                                    .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                            )
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, 2)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: cubeSize.width, height: cubeSize.height)
    }

    // MARK: - Face Polygon

    @ViewBuilder
    private func facePolygon(_ pf: ViewCube.ProjectedFace) -> some View {
        let isHighlighted = hoveredRegion?.contains(face: pf.face) ?? false

        Path { path in
            guard let first = pf.vertices.first else { return }
            path.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
            for v in pf.vertices.dropFirst() {
                path.addLine(to: CGPoint(x: CGFloat(v.x), y: CGFloat(v.y)))
            }
            path.closeSubpath()
        }
        .fill(
            isHighlighted
                ? Color.accentColor.opacity(0.3)
                : Color(nsColor: .windowBackgroundColor).opacity(0.85)
        )
        .overlay(
            Path { path in
                guard let first = pf.vertices.first else { return }
                path.move(to: CGPoint(x: CGFloat(first.x), y: CGFloat(first.y)))
                for v in pf.vertices.dropFirst() {
                    path.addLine(to: CGPoint(x: CGFloat(v.x), y: CGFloat(v.y)))
                }
                path.closeSubpath()
            }
            .stroke(Color.primary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Face Label

    private func faceLabel(_ pf: ViewCube.ProjectedFace) -> some View {
        Text(pf.face.rawValue)
            .font(.callout.bold())
            .foregroundColor(.primary.opacity(0.85))
            .position(x: CGFloat(pf.center.x), y: CGFloat(pf.center.y))
            .allowsHitTesting(false)
    }

    // MARK: - Home Button

    private var homeButton: some View {
        Button {
            workspace.resetView()
        } label: {
            Image(systemName: "house")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Reset View (Isometric)")
        .padding(4)
    }
}
