import SwiftUI
import MadeCore
import AppKit

/// Standalone master-detail browser for inspecting standard engineering materials and physical properties.
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

    public let library: MaterialLibrary

    @State private var searchText: String = ""
    @State private var selectedCategory: CategoryFilter = .all
    @State private var selectedMaterialID: String?
    @State private var copied: Bool = false

    public init(
        library: MaterialLibrary = .standard,
        initialMaterialID: String? = nil
    ) {
        self.library = library
        let defaultID = initialMaterialID ?? library.materials.first?.id
        self._selectedMaterialID = State(initialValue: defaultID)
    }

    private var filteredMaterials: [MaterialDefinition] {
        library.filter(category: selectedCategory.category, query: searchText)
    }

    private var activeMaterial: MaterialDefinition? {
        if let id = selectedMaterialID, let mat = library.material(withId: id) {
            return mat
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
                ForEach(filteredMaterials) { material in
                    MaterialRow(material: material)
                        .tag(material.id)
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("material-list")
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
                }

                Text(material.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

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
                Text(material.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

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
