import SwiftUI
import MadeCore

struct EmptySceneGuidanceOverlayView: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Empty Scene", systemImage: "cube.transparent")
            } description: {
                Text("Add a 3D solid primitive or open a part script to begin modeling.")
            } actions: {
                HStack(spacing: 10) {
                    Button("Add Box", systemImage: "shippingbox") {
                        workspace.addDefaultBox()
                    }
                    Button("Add Cylinder", systemImage: "cylinder") {
                        workspace.addDefaultCylinder()
                    }
                    Button("Open Part…", systemImage: "curlybraces") {
                        workspace.promptOpenPartFile()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
