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
            if workspace.document.objects.isEmpty {
                ContentUnavailableView {
                    Label("No Objects", systemImage: "cube.transparent")
                } description: {
                    Text("Add a 3D solid primitive or open a part script to begin modeling.")
                } actions: {
                    VStack(spacing: 8) {
                        Button("Add Box", systemImage: "shippingbox") {
                            workspace.addDefaultBox()
                        }
                        Button("Add Cylinder", systemImage: "cylinder") {
                            workspace.addDefaultCylinder()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if filteredObjects.isEmpty {
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
                Button("Delete", role: .destructive) { workspace.requestDeleteObject(id) }
                    .disabled(obj.isLocked)
            }
        }
        .confirmationDialog(
            "Delete “\(workspace.objectPendingDeletion?.name ?? "Solid")”?",
            isPresented: Binding(
                get: { workspace.pendingDeleteId != nil },
                set: { if !$0 { workspace.cancelDeleteObject() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                workspace.confirmDeleteObject()
            }
            Button("Cancel", role: .cancel) {
                workspace.cancelDeleteObject()
            }
        } message: {
            Text("Are you sure you want to delete “\(workspace.objectPendingDeletion?.name ?? "this solid")”? This action cannot be undone.")
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
                    workspace.addDefaultBox()
                }
                Button("Cylinder Solid", systemImage: "cylinder") {
                    workspace.addDefaultCylinder()
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

    static func filter(objects: [SceneObject], query: String) -> [SceneObject] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return objects }
        return objects.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.id.rawValue.localizedCaseInsensitiveContains(trimmed)
                || $0.def.kind.localizedCaseInsensitiveContains(trimmed)
                || $0.parameterSummary.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var filteredObjects: [SceneObject] {
        Self.filter(objects: workspace.document.objects, query: filterText)
    }
}

/// One outline row. Visibility and lock buttons show on hover, and stay visible while the object is hidden or locked.
private struct NavigatorRow: View {
    @Environment(WorkspaceModel.self) private var workspace
    let object: SceneObject
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(object.name)
                        .font(.body)
                        .lineLimit(1)

                    Text(object.def.kind.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                        )
                }

                HStack(spacing: 6) {
                    Text(object.id.rawValue)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(object.parameterSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

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
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(object.name), \(object.def.kind), ID \(object.id.rawValue), \(object.parameterSummary)")
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
