import SwiftUI
import MadeCore

/// Target storage scope for creating or updating custom materials.
public enum MaterialTargetScope: String, CaseIterable, Identifiable, Sendable {
    case document = "Current Document"
    case userLibrary = "User Library"

    public var id: String { rawValue }
}

/// Modal editor sheet for creating or editing engineering materials in Made.
public struct CustomMaterialEditorView: View {
    @Environment(WorkspaceModel.self) private var workspace: WorkspaceModel?
    @Environment(\.dismiss) private var dismiss

    public let materialToEdit: MaterialDefinition?
    public let initialScope: MaterialTargetScope
    public var onSave: ((MaterialDefinition, MaterialTargetScope) -> Void)?

    @State private var targetScope: MaterialTargetScope
    @State private var name: String
    @State private var category: MaterialCategory
    @State private var descriptionText: String
    @State private var color: Color

    // Mechanical properties
    @State private var density: Double
    @State private var youngsModulus: Double
    @State private var poissonsRatio: Double
    @State private var yieldStrength: Double
    @State private var ultimateStrength: Double

    // Thermal properties
    @State private var thermalConductivity: Double
    @State private var thermalExpansion: Double
    @State private var specificHeat: Double

    // Citation
    @State private var citationSourceName: String
    @State private var citationSpecification: String
    @State private var citationNotes: String
    @State private var citationURLString: String

    @State private var errorMessage: String?

    public init(
        materialToEdit: MaterialDefinition? = nil,
        initialScope: MaterialTargetScope = .document,
        onSave: ((MaterialDefinition, MaterialTargetScope) -> Void)? = nil
    ) {
        self.materialToEdit = materialToEdit
        self.initialScope = initialScope
        self.onSave = onSave

        self._targetScope = State(initialValue: initialScope)
        if let mat = materialToEdit {
            self._name = State(initialValue: mat.name)
            self._category = State(initialValue: mat.category)
            self._descriptionText = State(initialValue: mat.description)
            self._color = State(initialValue: Color(
                red: Double(mat.color.x),
                green: Double(mat.color.y),
                blue: Double(mat.color.z),
                opacity: Double(mat.color.w)
            ))
            self._density = State(initialValue: mat.densityKgPerM3)
            self._youngsModulus = State(initialValue: mat.youngsModulusGPa)
            self._poissonsRatio = State(initialValue: mat.poissonsRatioValue)
            self._yieldStrength = State(initialValue: mat.yieldStrengthMPa)
            self._ultimateStrength = State(initialValue: mat.ultimateStrengthMPa)
            self._thermalConductivity = State(initialValue: mat.thermalConductivityWPerMK)
            self._thermalExpansion = State(initialValue: mat.thermalExpansion.value)
            self._specificHeat = State(initialValue: mat.specificHeatJPerKgK)

            if let cite = mat.citations.first {
                self._citationSourceName = State(initialValue: cite.sourceName)
                self._citationSpecification = State(initialValue: cite.specification)
                self._citationNotes = State(initialValue: cite.notes)
                self._citationURLString = State(initialValue: cite.urlString ?? "")
            } else {
                self._citationSourceName = State(initialValue: "")
                self._citationSpecification = State(initialValue: "")
                self._citationNotes = State(initialValue: "")
                self._citationURLString = State(initialValue: "")
            }
        } else {
            self._name = State(initialValue: "")
            self._category = State(initialValue: .metal)
            self._descriptionText = State(initialValue: "")
            self._color = State(initialValue: Color(red: 0.6, green: 0.6, blue: 0.65))
            self._density = State(initialValue: 7850.0)
            self._youngsModulus = State(initialValue: 200.0)
            self._poissonsRatio = State(initialValue: 0.30)
            self._yieldStrength = State(initialValue: 250.0)
            self._ultimateStrength = State(initialValue: 400.0)
            self._thermalConductivity = State(initialValue: 50.0)
            self._thermalExpansion = State(initialValue: 12.0)
            self._specificHeat = State(initialValue: 500.0)
            self._citationSourceName = State(initialValue: "")
            self._citationSpecification = State(initialValue: "")
            self._citationNotes = State(initialValue: "")
            self._citationURLString = State(initialValue: "")
        }
    }

    public var validationError: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "Material name is required."
        }
        if density <= 0 {
            return "Density must be greater than zero."
        }
        if youngsModulus <= 0 {
            return "Young's Modulus must be greater than zero."
        }
        if poissonsRatio <= -1.0 || poissonsRatio >= 0.5 {
            return "Poisson's Ratio must be between -1.0 and 0.5."
        }
        if yieldStrength <= 0 {
            return "Yield Strength must be greater than zero."
        }
        if ultimateStrength <= 0 {
            return "Ultimate Tensile Strength must be greater than zero."
        }
        if thermalConductivity <= 0 {
            return "Thermal Conductivity must be greater than zero."
        }
        if thermalExpansion <= 0 {
            return "Thermal Expansion must be greater than zero."
        }
        if specificHeat <= 0 {
            return "Specific Heat Capacity must be greater than zero."
        }
        return nil
    }

    public var isValid: Bool {
        validationError == nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(materialToEdit == nil ? "New Custom Material" : "Edit Custom Material")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("material-editor-cancel")

                Button("Save") {
                    saveMaterial()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .accessibilityIdentifier("material-editor-save")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let err = errorMessage ?? validationError, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    // Scope Target (only changeable when creating new material)
                    if materialToEdit == nil {
                        GroupBox("Target Scope") {
                            Picker("Scope", selection: $targetScope) {
                                ForEach(MaterialTargetScope.allCases) { scope in
                                    Text(scope.rawValue).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("material-editor-scope-picker")
                        }
                    }

                    // Identity & Appearance
                    GroupBox("Identity & Appearance") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Name:")
                                    .frame(width: 140, alignment: .trailing)
                                TextField("e.g. Inconel 718", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("material-editor-name")
                            }

                            HStack {
                                Text("Category:")
                                    .frame(width: 140, alignment: .trailing)
                                Picker("Category", selection: $category) {
                                    ForEach(MaterialCategory.allCases) { cat in
                                        Text(cat.displayName).tag(cat)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("material-editor-category")
                            }

                            HStack {
                                Text("Description:")
                                    .frame(width: 140, alignment: .trailing)
                                TextField("Brief summary of application or composition", text: $descriptionText)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("material-editor-description")
                            }

                            HStack {
                                Text("Appearance Color:")
                                    .frame(width: 140, alignment: .trailing)
                                ColorPicker("", selection: $color, supportsOpacity: false)
                                    .accessibilityIdentifier("material-editor-color")
                                Spacer()
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Mechanical Properties
                    GroupBox("Mechanical Properties") {
                        VStack(spacing: 10) {
                            numericPropertyRow(label: "Density (kg/m³):", value: $density, identifier: "material-editor-density")
                            numericPropertyRow(label: "Young's Modulus (GPa):", value: $youngsModulus, identifier: "material-editor-youngs-modulus")
                            numericPropertyRow(label: "Poisson's Ratio (ν):", value: $poissonsRatio, identifier: "material-editor-poissons-ratio")
                            numericPropertyRow(label: "Yield Strength (MPa):", value: $yieldStrength, identifier: "material-editor-yield-strength")
                            numericPropertyRow(label: "Ultimate Strength (MPa):", value: $ultimateStrength, identifier: "material-editor-ultimate-strength")
                        }
                        .padding(.vertical, 4)
                    }

                    // Thermal Properties
                    GroupBox("Thermal Properties") {
                        VStack(spacing: 10) {
                            numericPropertyRow(label: "Conductivity (W/(m·K)):", value: $thermalConductivity, identifier: "material-editor-thermal-conductivity")
                            numericPropertyRow(label: "Expansion (10⁻⁶/K):", value: $thermalExpansion, identifier: "material-editor-thermal-expansion")
                            numericPropertyRow(label: "Specific Heat (J/(kg·K)):", value: $specificHeat, identifier: "material-editor-specific-heat")
                        }
                        .padding(.vertical, 4)
                    }

                    // Citation & Standards
                    GroupBox("Citation & Standard Reference (Optional)") {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Source / Authority:")
                                    .frame(width: 140, alignment: .trailing)
                                TextField("e.g. ASTM, MMPDS, Manufacturer", text: $citationSourceName)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("material-editor-citation-source")
                            }

                            HStack {
                                Text("Specification:")
                                    .frame(width: 140, alignment: .trailing)
                                TextField("e.g. ASTM B637, AMS 5662", text: $citationSpecification)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("material-editor-citation-spec")
                            }

                            HStack {
                                Text("Notes:")
                                    .frame(width: 140, alignment: .trailing)
                                TextField("e.g. Solution treated and aged condition", text: $citationNotes)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("material-editor-citation-notes")
                            }

                            HStack {
                                Text("Reference URL:")
                                    .frame(width: 140, alignment: .trailing)
                                TextField("https://...", text: $citationURLString)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("material-editor-citation-url")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 640)
    }

    private func numericPropertyRow(label: String, value: Binding<Double>, identifier: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 200, alignment: .trailing)
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier)
        }
    }

    private func saveMaterial() {
        guard isValid else { return }

        let resolved = color.resolve(in: EnvironmentValues())
        let simdColor = SIMD4<Float>(resolved.red, resolved.green, resolved.blue, 1.0)

        var citations: [MaterialCitation] = []
        let trimmedSource = citationSourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSpec = citationSpecification.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSource.isEmpty || !trimmedSpec.isEmpty {
            let url = citationURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            citations.append(MaterialCitation(
                sourceName: trimmedSource.isEmpty ? "Standard Reference" : trimmedSource,
                specification: trimmedSpec.isEmpty ? "Unspecified" : trimmedSpec,
                notes: citationNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                urlString: url.isEmpty ? nil : url
            ))
        } else if let existing = materialToEdit?.citations, !existing.isEmpty {
            citations = existing
        }

        let materialId = materialToEdit?.id ?? "custom-\(UUID().uuidString.lowercased())"
        let material = MaterialDefinition(
            id: materialId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            color: simdColor,
            citations: citations,
            density: DensityQuantity(value: density, unit: .kgPerCubicMeter),
            youngsModulus: StressQuantity(value: youngsModulus, unit: .gigapascals),
            poissonsRatio: DimensionlessQuantity(value: poissonsRatio, unit: .ratio),
            yieldStrength: StressQuantity(value: yieldStrength, unit: .megapascals),
            ultimateStrength: StressQuantity(value: ultimateStrength, unit: .megapascals),
            thermalConductivity: ThermalConductivityQuantity(value: thermalConductivity, unit: .wattsPerMeterKelvin),
            thermalExpansion: ThermalExpansionQuantity(value: thermalExpansion, unit: .microstrainPerKelvin),
            specificHeat: SpecificHeatQuantity(value: specificHeat, unit: .joulesPerKilogramKelvin)
        )

        if let onSave {
            onSave(material, targetScope)
            dismiss()
            return
        }

        guard let workspace else {
            dismiss()
            return
        }

        do {
            if materialToEdit != nil {
                switch targetScope {
                case .document:
                    let res = workspace.updateDocumentCustomMaterial(material)
                    if case .failure(let err) = res {
                        errorMessage = err.localizedDescription
                        return
                    }
                case .userLibrary:
                    try workspace.updateUserMaterial(material)
                }
            } else {
                switch targetScope {
                case .document:
                    let res = workspace.addDocumentCustomMaterial(material)
                    if case .failure(let err) = res {
                        errorMessage = err.localizedDescription
                        return
                    }
                case .userLibrary:
                    try workspace.addUserMaterial(material)
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
