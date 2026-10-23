import SwiftUI
import MadeCore
import AppKit

/// Standalone master-detail browser for inspecting standard and custom engineering materials and physical properties.
public struct MaterialLibraryView: View {
    public static let windowID = "material-library"

    public enum CategoryFilter: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case metals = "Metals"
        case plastics = "Plastics"

        public var id: String { rawValue }

        public var category: MaterialCategory? {
            switch self {
            case .all:
                return nil
            case .metals:
                return .metal
            case .plastics:
                return .plastic
            }
        }
    }

    public enum MaterialScope: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case standard = "Standard"
        case document = "Document"
        case userLibrary = "User Library"

        public var id: String { rawValue }
    }

    public let library: MaterialLibrary

    @Environment(WorkspaceModel.self) private var workspace: WorkspaceModel?

    @State private var searchText: String = ""
    @State private var selectedScope: MaterialScope = .all
    @State private var selectedCategory: CategoryFilter = .all
    @State private var selectedMaterialID: String?
    @State private var copied: Bool = false
    @State private var showingEditorSheet: Bool = false
    @State private var materialToEdit: MaterialDefinition? = nil

    public init(
        library: MaterialLibrary = .standard,
        initialMaterialID: String? = nil
    ) {
        self.library = library
        let defaultID = initialMaterialID ?? library.materials.first?.id
        self._selectedMaterialID = State(initialValue: defaultID)
    }

    private var allAvailableMaterials: [(material: MaterialDefinition, scope: MaterialScope)] {
        var result: [(material: MaterialDefinition, scope: MaterialScope)] = []
        var seenIDs: Set<String> = []

        // Document materials
        let docMaterials = workspace?.document.customMaterials ?? []
        for mat in docMaterials {
            if !seenIDs.contains(mat.id) {
                seenIDs.insert(mat.id)
                result.append((mat, .document))
            }
        }

        // User library materials
        let userMaterials = workspace?.userMaterials ?? []
        for mat in userMaterials {
            if !seenIDs.contains(mat.id) {
                seenIDs.insert(mat.id)
                result.append((mat, .userLibrary))
            }
        }

        // Standard materials
        for mat in library.materials {
            if !seenIDs.contains(mat.id) {
                seenIDs.insert(mat.id)
                result.append((mat, .standard))
            }
        }

        return result
    }

    private var filteredMaterialItems: [(material: MaterialDefinition, scope: MaterialScope)] {
        allAvailableMaterials.filter { item in
            if selectedScope != .all && item.scope != selectedScope {
                return false
            }
            if let cat = selectedCategory.category, item.material.category != cat {
                return false
            }
            if !searchText.isEmpty {
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let nameMatch = item.material.name.lowercased().contains(q)
                let descMatch = item.material.description.lowercased().contains(q)
                let specMatch = item.material.citations.contains(where: {
                    $0.specification.lowercased().contains(q) || $0.sourceName.lowercased().contains(q)
                })
                return nameMatch || descMatch || specMatch
            }
            return true
        }
    }

    private var filteredMaterials: [MaterialDefinition] {
        filteredMaterialItems.map(\.material)
    }

    private func scope(for material: MaterialDefinition) -> MaterialScope {
        if let item = allAvailableMaterials.first(where: { $0.material.id == material.id }) {
            return item.scope
        }
        return .standard
    }

    private var activeMaterial: MaterialDefinition? {
        if let id = selectedMaterialID {
            if let mat = allAvailableMaterials.first(where: { $0.material.id == id })?.material {
                return mat
            }
            if let mat = library.material(withId: id) {
                return mat
            }
        }
        return filteredMaterials.first
    }

    public var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 520)
        .sheet(isPresented: $showingEditorSheet) {
            CustomMaterialEditorView(
                materialToEdit: materialToEdit,
                initialScope: selectedScope == .userLibrary ? .userLibrary : .document
            )
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        VStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search materials…", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("material-library-search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 10)
            .padding(.top, 10)

            // Scope filter
            Picker("Scope", selection: $selectedScope) {
                ForEach(MaterialScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("material-scope-picker")
            .padding(.horizontal, 10)

            // Category filter
            Picker("Category", selection: $selectedCategory) {
                ForEach(CategoryFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("material-category-picker")
            .padding(.horizontal, 10)

            // Material List
            List(selection: $selectedMaterialID) {
                ForEach(filteredMaterialItems, id: \.material.id) { item in
                    MaterialRow(material: item.material, scope: item.scope)
                        .tag(item.material.id)
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("material-list")

            // Add Material button
            Button {
                materialToEdit = nil
                showingEditorSheet = true
            } label: {
                Label("Add Material…", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .accessibilityIdentifier("add-material-button")
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let material = activeMaterial {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    materialHeader(material)

                    Divider()

                    // Mechanical Properties Card
                    mechanicalPropertiesCard(material)

                    // Thermal Properties Card
                    thermalPropertiesCard(material)

                    // Citations & Standards Card
                    citationsCard(material)
                }
                .padding(20)
            }
            .accessibilityIdentifier("material-detail-panel")
        } else {
            ContentUnavailableView(
                "No Material Selected",
                systemImage: "cube.transparent",
                description: Text("Select a material from the list to view its mechanical and thermal properties.")
            )
            .accessibilityIdentifier("material-detail-panel")
        }
    }

    private func materialHeader(_ material: MaterialDefinition) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(
                    red: Double(material.color.x),
                    green: Double(material.color.y),
                    blue: Double(material.color.z),
                    opacity: Double(material.color.w)
                ))
                .frame(width: 54, height: 54)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(material.name)
                        .font(.title2)
                        .bold()

                    categoryBadge(material.category)
                    scopeBadge(scope(for: material))
                }

                Text(material.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    if let selectedSolidId = workspace?.selectedId {
                        Button {
                            workspace?.applyMaterialDefinition(material, to: selectedSolidId)
                        } label: {
                            Label("Apply to Body", systemImage: "paintbrush")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("apply-to-body-button")
                    }

                    Button {
                        let attributes = MaterialAttributes(
                            color: material.color,
                            materialDefinitionId: material.id,
                            materialName: material.name
                        )
                        workspace?.setDocumentDefaultMaterial(attributes)
                    } label: {
                        Label("Set as Default", systemImage: "star")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("set-as-default-material-button")

                    Button {
                        copyProperties(material)
                    } label: {
                        Label(copied ? "Copied" : "Copy Properties", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("copy-properties-button")
                    .task(id: copied) {
                        guard copied else { return }
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }

                if scope(for: material) != .standard {
                    HStack(spacing: 8) {
                        Button {
                            materialToEdit = material
                            showingEditorSheet = true
                        } label: {
                            Label("Edit Material", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("edit-material-button")

                        Button(role: .destructive) {
                            deleteMaterial(material)
                        } label: {
                            Label("Delete Material", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("delete-material-button")
                    }
                }
            }
        }
    }

    private func deleteMaterial(_ material: MaterialDefinition) {
        let sc = scope(for: material)
        if sc == .document {
            _ = workspace?.removeDocumentCustomMaterial(id: material.id)
        } else if sc == .userLibrary {
            try? workspace?.removeUserMaterial(id: material.id)
        }
        if selectedMaterialID == material.id {
            selectedMaterialID = filteredMaterials.first(where: { $0.id != material.id })?.id
        }
    }

    private func mechanicalPropertiesCard(_ material: MaterialDefinition) -> some View {
        GroupBox {
            VStack(spacing: 10) {
                PropertyRow(label: "Density (ρ)", value: material.density.formattedValue)
                Divider()
                PropertyRow(label: "Young's Modulus (E)", value: material.youngsModulus.formattedValue)
                Divider()
                PropertyRow(label: "Poisson's Ratio (ν)", value: material.poissonsRatio.formattedValue)
                Divider()
                PropertyRow(label: "Yield Strength (σy)", value: material.yieldStrength.formattedValue)
                Divider()
                PropertyRow(label: "Ultimate Tensile Strength (σuts)", value: material.ultimateStrength.formattedValue)
            }
            .padding(.vertical, 4)
        } label: {
            Label("Mechanical Properties", systemImage: "wrench.and.screwdriver")
                .font(.headline)
        }
    }

    private func thermalPropertiesCard(_ material: MaterialDefinition) -> some View {
        GroupBox {
            VStack(spacing: 10) {
                PropertyRow(label: "Thermal Conductivity (k)", value: material.thermalConductivity.formattedValue)
                Divider()
                PropertyRow(label: "Thermal Expansion (α)", value: material.thermalExpansion.formattedValue)
                Divider()
                PropertyRow(label: "Specific Heat Capacity (cp)", value: material.specificHeat.formattedValue)
            }
            .padding(.vertical, 4)
        } label: {
            Label("Thermal Properties", systemImage: "flame")
                .font(.headline)
        }
    }

    private func citationsCard(_ material: MaterialDefinition) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(material.citations) { citation in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(citation.sourceName)
                                .font(.subheadline)
                                .bold()

                            Spacer()

                            Text(citation.specification)
                                .font(.caption)
                                .monospaced()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }

                        Text(citation.notes)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let urlString = citation.urlString, let url = URL(string: urlString) {
                            Link(destination: url) {
                                Label(urlString, systemImage: "arrow.up.right.square")
                                    .font(.caption2)
                            }
                            .padding(.top, 2)
                        }
                    }
                    if citation.id != material.citations.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Citations & Standards", systemImage: "bookmark")
                .font(.headline)
        }
    }

    private func categoryBadge(_ category: MaterialCategory) -> some View {
        Text(category.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(category == .metal ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
            .foregroundColor(category == .metal ? .blue : .green)
            .cornerRadius(6)
    }

    @ViewBuilder
    private func scopeBadge(_ scope: MaterialScope) -> some View {
        switch scope {
        case .standard:
            Text("Standard")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .foregroundColor(.secondary)
                .cornerRadius(6)
        case .document:
            Text("Document")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .cornerRadius(6)
        case .userLibrary:
            Text("User Library")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.15))
                .foregroundColor(.purple)
                .cornerRadius(6)
        case .all:
            EmptyView()
        }
    }

    private func copyProperties(_ material: MaterialDefinition) {
        let summary = material.formattedSummary()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        copied = true
    }
}

// MARK: - Subviews

private struct MaterialRow: View {
    let material: MaterialDefinition
    let scope: MaterialLibraryView.MaterialScope

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(
                    red: Double(material.color.x),
                    green: Double(material.color.y),
                    blue: Double(material.color.z),
                    opacity: Double(material.color.w)
                ))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(material.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    rowScopeBadge(scope)
                }

                HStack(spacing: 6) {
                    Text(material.category.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(material.density.formattedValue)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rowScopeBadge(_ scope: MaterialLibraryView.MaterialScope) -> some View {
        switch scope {
        case .standard:
            Text("Standard")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15))
                .foregroundColor(.secondary)
                .cornerRadius(3)
        case .document:
            Text("Doc")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.18))
                .foregroundColor(.blue)
                .cornerRadius(3)
        case .userLibrary:
            Text("User")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.purple.opacity(0.18))
                .foregroundColor(.purple)
                .cornerRadius(3)
        case .all:
            EmptyView()
        }
    }
}

private struct PropertyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
                .monospacedDigit()
        }
        .font(.callout)
    }
}
