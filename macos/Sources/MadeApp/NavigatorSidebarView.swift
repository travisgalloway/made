import SwiftUI
import MadeCore

struct NavigatorSidebarView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var filterText = ""

    var body: some View {
        @Bindable var workspace = workspace

        List(selection: $workspace.selectedId) {
            Section("Scene") {
                ForEach(filteredObjects) { obj in
                    NavigatorRow(object: obj).tag(obj.id)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if filteredObjects.isEmpty {
                ContentUnavailableView.search(text: filterText)
            }
        }
        .contextMenu(forSelectionType: ObjectId.self) { ids in
            if let id = ids.first, let obj = workspace.document.objects.first(where: { $0.id == id }) {
                if case .part = obj.def {
                    Button("Reload Part") { workspace.reloadPart(id) }
                    Divider()
                }
                Button(obj.isVisible ? "Hide" : "Show") { workspace.toggleVisibility(id) }
                Button(obj.isLocked ? "Unlock" : "Lock") { workspace.toggleLock(id) }
                Divider()
                Button("Delete", role: .destructive) { workspace.removeObject(id) }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PaneTabBar(label: "Navigator", selection: $workspace.navigatorTab)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Menu("Add Solid", systemImage: "plus") {
                Button("Box Solid", systemImage: "shippingbox") {
                    workspace.addObject(.box(BoxParams(width: 30, depth: 30, height: 30)))
                }
                Button("Cylinder Solid", systemImage: "cylinder") {
                    workspace.addObject(.cylinder(CylinderParams(radius: 12, height: 35)))
                }
                Divider()
                Button("Part Script File…", systemImage: "curlybraces") {
                    workspace.promptOpenPartFile()
                }
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add Solid")
            BarFilterField(text: $filterText)
        }
        .barControl()
        .padding(.horizontal, 10)
        .frame(height: BarMetrics.height)
    }

    private var filteredObjects: [SceneObject] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return workspace.document.objects }
        return workspace.document.objects.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
}

/// One outline row. Visibility and lock buttons show on hover, and stay visible while the object is hidden or locked.
private struct NavigatorRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let object: SceneObject
    @State private var isHovered = false

    var body: some View {
        HStack {
            Label {
                Text(object.name)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            Spacer()
            Group {
                if isHovered || !object.isVisible {
                    Button(object.isVisible ? "Hide Object" : "Show Object",
                           systemImage: object.isVisible ? "eye" : "eye.slash") {
                        workspace.toggleVisibility(object.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(object.isVisible ? "Hide Object" : "Show Object")
                }
                if isHovered || object.isLocked {
                    Button(object.isLocked ? "Unlock Object" : "Lock Object",
                           systemImage: object.isLocked ? "lock.fill" : "lock.open") {
                        workspace.toggleLock(object.id)
                    }
                    .foregroundStyle(.secondary)
                    .help(object.isLocked ? "Unlock Object" : "Lock Object")
                }
            }
            .barControl()
        }
        .onHover { isHovered = $0 }
        // The row buttons appear only on hover, so VoiceOver gets the same commands as row actions.
        .accessibilityAction(named: object.isVisible ? "Hide Object" : "Show Object") {
            workspace.toggleVisibility(object.id)
        }
        .accessibilityAction(named: object.isLocked ? "Unlock Object" : "Lock Object") {
            workspace.toggleLock(object.id)
        }
    }

    private var icon: String {
        switch object.def {
        case .box: return "shippingbox.fill"
        case .cylinder: return "cylinder.fill"
        case .imported: return "cube.transparent"
        case .boolean: return "square.on.circle"
        case .part: return "curlybraces.square.fill"
        }
    }

    private var tint: Color {
        switch object.def {
        case .box: return .blue
        case .cylinder: return .orange
        case .imported: return .purple
        case .boolean: return .green
        case .part: return .teal
        }
    }
}
