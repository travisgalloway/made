import SwiftUI
import MadeCore

public struct NavigatorSidebarView: View {
    @Bindable var document: DocumentModel
    @Binding var selectedId: ObjectId
    var onAddObject: (ObjectDef) -> Void
    var onToggleVisibility: (ObjectId) -> Void
    var onToggleLock: (ObjectId) -> Void
    var onDeleteObject: (ObjectId) -> Void
    
    @State private var activeSection: NavigatorSection = .outline
    @State private var filterText: String = ""
    @State private var defaultLayerVisible: Bool = true
    @State private var defaultLayerLocked: Bool = false
    @State private var constructionLayerVisible: Bool = true
    @State private var constructionLayerLocked: Bool = false
    
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
            // Navigator Tab Bar (Xcode-like tabs)
            HStack(spacing: 8) {
                ForEach(NavigatorSection.allCases) { section in
                    Button {
                        activeSection = section
                    } label: {
                        Image(systemName: section.iconName)
                            .font(.system(size: 13, weight: activeSection == section ? .semibold : .regular))
                            .foregroundColor(activeSection == section ? .accentColor : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(
                                activeSection == section ?
                                Color.accentColor.opacity(0.12) : Color.clear
                            )
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help(section.rawValue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content List based on active section
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch activeSection {
                    case .outline:
                        sceneOutlineSection
                    case .layers:
                        cadLayersSection
                    case .constraints:
                        physicsConstraintsSection
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
        .frame(minWidth: 220, maxWidth: 320)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Scene Outline Section
    
    private var sceneOutlineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Scene Root Header
            HStack(spacing: 6) {
                Image(systemName: "cube.transparent")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
                Text("Scene (3D)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(filteredObjects.count) items")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
            
            // Geometric Primitives Group
            VStack(alignment: .leading, spacing: 2) {
                Text("GEOMETRIC PRIMITIVES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
                    .padding(.bottom, 2)
                
                if filteredObjects.isEmpty {
                    Text("No matching objects")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                } else {
                    ForEach(filteredObjects) { obj in
                        objectRow(for: obj)
                    }
                }
            }
            
            Divider()
            
            // CAD Layers Overview
            cadLayersSummary
            
            Divider()
            
            // Physics Constraints Overview
            physicsConstraintsSummary
        }
    }
    
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
    
    // MARK: - CAD Layers Section
    
    private var cadLayersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAD LAYERS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            
            layerRow(name: "Default Layer", color: .blue, isVisible: $defaultLayerVisible, isLocked: $defaultLayerLocked)
            layerRow(name: "Construction", color: .purple, isVisible: $constructionLayerVisible, isLocked: $constructionLayerLocked)
            layerRow(name: "Annotations", color: .orange, isVisible: .constant(true), isLocked: .constant(false))
        }
    }
    
    private var cadLayersSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACTIVE LAYERS")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            
            HStack(spacing: 8) {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("Default Layer")
                    .font(.system(size: 11))
                Spacer()
                Text("2 solids")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }
    
    private func layerRow(name: String, color: Color, isVisible: Binding<Bool>, isLocked: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12))
            Spacer()
            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundColor(isVisible.wrappedValue ? .secondary : .red)
            }
            .buttonStyle(.plain)
            
            Button {
                isLocked.wrappedValue.toggle()
            } label: {
                Image(systemName: isLocked.wrappedValue ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .foregroundColor(isLocked.wrappedValue ? .orange : .secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        .cornerRadius(5)
    }
    
    // MARK: - Physics Constraints Section
    
    private var physicsConstraintsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PHYSICS CONSTRAINTS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            
            constraintRow(name: "Ground Contact Plane", type: "Plane (Z = 0)", active: true)
            constraintRow(name: "Rigid Collision Bounds", type: "Continuous", active: true)
            constraintRow(name: "Box-Cylinder Coaxial", type: "Distance (50mm)", active: false)
        }
    }
    
    private var physicsConstraintsSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PHYSICS CONSTRAINTS")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                Text("Ground Plane (Z = 0)")
                    .font(.system(size: 11))
                Spacer()
                Text("Rigid")
                    .font(.system(size: 9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(3)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }
    
    private func constraintRow(name: String, type: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: active ? "link" : "link.badge.plus")
                .foregroundColor(active ? .green : .secondary)
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12))
                Text(type)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Circle()
                .fill(active ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        .cornerRadius(5)
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
