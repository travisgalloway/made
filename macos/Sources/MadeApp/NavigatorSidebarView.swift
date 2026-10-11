import SwiftUI
import MadeCore

public struct NavigatorSidebarView: View {
    @Bindable var document: DocumentModel
    @Binding var selectedId: ObjectId
    var onAddObject: (ObjectDef) -> Void
    var onToggleVisibility: (ObjectId) -> Void
    var onToggleLock: (ObjectId) -> Void
    var onDeleteObject: (ObjectId) -> Void
    
    @State private var filterText: String = ""
    
    public init(
        document: DocumentModel,
        selectedId: Binding<ObjectId>,
        onAddObject: @escaping (ObjectDef) -> Void,
        onToggleVisibility: @escaping (ObjectId) -> Void,
        onToggleLock: @escaping (ObjectId) -> Void,
        onDeleteObject: @escaping (ObjectId) -> Void
    ) {
        self.document = document
        self._selectedId = selectedId
        self.onAddObject = onAddObject
        self.onToggleVisibility = onToggleVisibility
        self.onToggleLock = onToggleLock
        self.onDeleteObject = onDeleteObject
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 6) {
                Image(systemName: "cube.transparent")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13))
                Text("Scene Outline")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(filteredObjects.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Objects List
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if filteredObjects.isEmpty {
                        Text("No matching objects")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 16)
                            .padding(.horizontal, 12)
                    } else {
                        ForEach(filteredObjects) { obj in
                            objectRow(for: obj)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            
            Divider()
            
            // Bottom Filter & Add Bar
            HStack(spacing: 6) {
                Menu {
                    Button("Add Box Solid") {
                        onAddObject(.box(BoxParams(width: 30, depth: 30, height: 30)))
                    }
                    Button("Add Cylinder Solid") {
                        onAddObject(.cylinder(CylinderParams(radius: 12, height: 35)))
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Filter", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 200, maxWidth: 300)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Row View
    
    private func objectRow(for obj: SceneObject) -> some View {
        let isSelected = (obj.id == selectedId)
        
        return HStack(spacing: 6) {
            // Primitive Type Icon
            Image(systemName: iconFor(def: obj.def))
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .white : colorFor(def: obj.def))
                .frame(width: 16)
            
            // Entity Name and ID
            VStack(alignment: .leading, spacing: 1) {
                Text(obj.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                Text(obj.id.rawValue)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            
            Spacer()
            
            // Visibility Toggle
            Button {
                onToggleVisibility(obj.id)
            } label: {
                Image(systemName: obj.isVisible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white : (obj.isVisible ? .secondary : .red))
            }
            .buttonStyle(.plain)
            .help(obj.isVisible ? "Hide object" : "Show object")
            
            // Lock Toggle
            Button {
                onToggleLock(obj.id)
            } label: {
                Image(systemName: obj.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white : (obj.isLocked ? .orange : .secondary.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .help(obj.isLocked ? "Unlock object" : "Lock object")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor : Color.clear
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedId = obj.id
        }
        .contextMenu {
            Button("Focus in Viewport") {
                selectedId = obj.id
            }
            Button(obj.isVisible ? "Hide" : "Show") {
                onToggleVisibility(obj.id)
            }
            Button(obj.isLocked ? "Unlock" : "Lock") {
                onToggleLock(obj.id)
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDeleteObject(obj.id)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var filteredObjects: [SceneObject] {
        if filterText.trimmingCharacters(in: .whitespaces).isEmpty {
            return document.objects
        }
        return document.objects.filter {
            $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.id.rawValue.localizedCaseInsensitiveContains(filterText)
        }
    }
    
    private func iconFor(def: ObjectDef) -> String {
        switch def {
        case .box: return "shippingbox.fill"
        case .cylinder: return "cylinder.fill"
        case .imported: return "cube.transparent"
        }
    }
    
    private func colorFor(def: ObjectDef) -> Color {
        switch def {
        case .box: return .blue
        case .cylinder: return .orange
        case .imported: return .purple
        }
    }
}
