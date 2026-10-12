import SwiftUI
import MadeCore

struct NavigatorSidebarView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var filterText = ""

    var body: some View {
        @Bindable var workspace = workspace

        List(selection: $workspace.selectedId) {
            Section {
                ForEach(filteredObjects) { obj in
                    row(for: obj).tag(obj.id)
                }
            } header: {
                Text("Scene Outline")
                    .badge(filteredObjects.count)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $filterText, placement: .sidebar, prompt: "Filter")
        .overlay {
            if filteredObjects.isEmpty {
                ContentUnavailableView.search(text: filterText)
            }
        }
        .contextMenu(forSelectionType: ObjectId.self) { ids in
            if let id = ids.first, let obj = workspace.document.objects.first(where: { $0.id == id }) {
                Button(obj.isVisible ? "Hide" : "Show") { workspace.toggleVisibility(id) }
                Button(obj.isLocked ? "Unlock" : "Lock") { workspace.toggleLock(id) }
                Divider()
                Button("Delete", role: .destructive) { workspace.removeObject(id) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Menu("Add", systemImage: "plus") {
                    Button("Box Solid", systemImage: "shippingbox") {
                        workspace.addObject(.box(BoxParams(width: 30, depth: 30, height: 30)))
                    }
                    Button("Cylinder Solid", systemImage: "cylinder") {
                        workspace.addObject(.cylinder(CylinderParams(radius: 12, height: 35)))
                    }
                }
                .labelStyle(.iconOnly)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
            }
            .padding(8)
        }
    }

    private func row(for obj: SceneObject) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(obj.name)
                    Text(obj.id.rawValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon(for: obj.def))
                    .foregroundStyle(tint(for: obj.def))
            }
            Spacer()
            Button(obj.isVisible ? "Hide object" : "Show object",
                   systemImage: obj.isVisible ? "eye.fill" : "eye.slash") {
                workspace.toggleVisibility(obj.id)
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(obj.isVisible ? Color.secondary : Color.red)
            .help(obj.isVisible ? "Hide object" : "Show object")
            Button(obj.isLocked ? "Unlock object" : "Lock object",
                   systemImage: obj.isLocked ? "lock.fill" : "lock.open") {
                workspace.toggleLock(obj.id)
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(obj.isLocked ? Color.orange : Color.secondary)
            .help(obj.isLocked ? "Unlock object" : "Lock object")
        }
        .buttonStyle(.borderless)
    }

    private var filteredObjects: [SceneObject] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return workspace.document.objects }
        return workspace.document.objects.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private func icon(for def: ObjectDef) -> String {
        switch def {
        case .box: return "shippingbox.fill"
        case .cylinder: return "cylinder.fill"
        case .imported: return "cube.transparent"
        }
    }

    private func tint(for def: ObjectDef) -> Color {
        switch def {
        case .box: return .blue
        case .cylinder: return .orange
        case .imported: return .purple
        }
    }
}
