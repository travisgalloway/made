import SwiftUI
import MadeCore

public struct SettingsView: View {
    @Environment(WorkspaceModel.self) private var workspace

    public enum Tab: String, CaseIterable, Identifiable, Hashable {
        case general = "General"
        case units = "Units"
        case navigation = "Navigation"
        case display = "Display"
        case tolerances = "Tolerances"
        case shortcuts = "Shortcuts"

        public var id: String { rawValue }
    }

    @State private var selectedTab: Tab = .general

    public init(initialTab: Tab = .general) {
        self._selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(Tab.general)

            UnitsSettingsTab()
                .tabItem {
                    Label("Units", systemImage: "ruler")
                }
                .tag(Tab.units)

            NavigationSettingsTab()
                .tabItem {
                    Label("Navigation", systemImage: "hand.draw")
                }
                .tag(Tab.navigation)

            DisplaySettingsTab()
                .tabItem {
                    Label("Display", systemImage: "display")
                }
                .tag(Tab.display)

            TolerancesSettingsTab()
                .tabItem {
                    Label("Tolerances", systemImage: "slider.horizontal.3")
                }
                .tag(Tab.tolerances)

            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(Tab.shortcuts)
        }
        .frame(minWidth: 540, minHeight: 400)
    }
}

// MARK: - Tab Views

struct GeneralSettingsTab: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        Form {
            Section("Command Panel") {
                Picker("Placement", selection: $workspace.commandPanelPlacement) {
                    ForEach(CommandPanelPlacement.allCases) { placement in
                        Text(placement.rawValue).tag(placement)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("Choose whether active command parameters appear in the trailing Inspector pane or in a floating HUD anchored near the active geometry in the 3D viewport.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reset to Defaults") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Restore all application preferences, units, navigation conventions, display flags, and kernel tolerances to their default states.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Reset All Settings to Defaults", role: .destructive) {
                        workspace.resetSettingsToDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct UnitsSettingsTab: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        Form {
            Section("Length Units") {
                Picker("Default Length Unit", selection: $workspace.lengthUnit) {
                    ForEach(LengthUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }

                Text("Internal CAD geometry coordinates are always in millimeters. Non-metric and non-millimeter inputs are converted upon input and formatted on display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Angular Units") {
                Picker("Default Angular Unit", selection: $workspace.angleUnit) {
                    ForEach(AngleUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            }

            Section("Decimal Precision") {
                Stepper("Decimal Places: \(workspace.decimalPrecision)", value: $workspace.decimalPrecision, in: UnitSettings.minDecimalPrecision...UnitSettings.maxDecimalPrecision)

                Text("Controls the number of fractional digits shown across numeric sliders, fields, and measurements (0 to 6).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Format Preview") {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Length Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(UnitSettings.format(value: workspace.lengthUnit.fromMillimeters(100.0), precision: workspace.decimalPrecision, symbol: workspace.lengthUnit.symbol))
                            .fontWeight(.medium)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Angle Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(UnitSettings.format(value: workspace.angleUnit.fromDegrees(45.0), precision: workspace.decimalPrecision, symbol: workspace.angleUnit.symbol))
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct NavigationSettingsTab: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        Form {
            Section("CAD Navigation Preset") {
                Picker("Preset", selection: $workspace.navigationPreset) {
                    ForEach(NavigationPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                Text(workspace.navigationPreset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quick Reference") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Action").fontWeight(.semibold)
                        Text("Default (Made)").fontWeight(.semibold)
                        Text("SolidWorks").fontWeight(.semibold)
                        Text("Fusion 360").fontWeight(.semibold)
                    }
                    Divider()
                    GridRow {
                        Text("Orbit")
                        Text("Right drag / Opt+Left")
                        Text("Middle drag")
                        Text("Shift + Middle drag")
                    }
                    GridRow {
                        Text("Pan")
                        Text("Middle / Shift+Right")
                        Text("Ctrl + Middle drag")
                        Text("Middle drag")
                    }
                    GridRow {
                        Text("Zoom")
                        Text("Wheel / Z drag")
                        Text("Shift + Middle drag")
                        Text("Ctrl + Middle drag")
                    }
                    GridRow {
                        Text("Select")
                        Text("Left click & drag")
                        Text("Left click & drag")
                        Text("Left click & drag")
                    }
                }
                .font(.caption)
            }

            Section {
                Text("Invariant 8 Note: Primary button drag under the Select tool always manipulates geometry or gizmo handles across all presets.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct DisplaySettingsTab: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        Form {
            Section("Default Camera Options") {
                Picker("Default Projection", selection: $workspace.defaultProjection) {
                    ForEach(CameraProjection.allCases) { proj in
                        Text(proj.rawValue).tag(proj)
                    }
                }

                Picker("Default Perspective Preset", selection: $workspace.defaultPerspective) {
                    ForEach(ViewportPerspective.allCases) { persp in
                        Text(persp.rawValue).tag(persp)
                    }
                }
            }

            Section("Viewport Overlays") {
                Toggle("Show Ground Grid (Z = 0)", isOn: $workspace.showsGrid)
                Toggle("Show Origin Axes (XYZ)", isOn: $workspace.showsAxes)
                Toggle("Show Transform Gizmo", isOn: $workspace.showsGizmo)

                Text("Toggling viewport overlays immediately updates the live Metal 4 scene.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct TolerancesSettingsTab: View {
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        Form {
            Section("Kernel Modeling Tolerances") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Linear Tolerance (mm):")
                        Spacer()
                        TextField("Linear", value: $workspace.kernelTolerances.linearTolerance, format: .number)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("Valid range: \(KernelTolerances.minLinearTolerance, specifier: "%.4f")...\(KernelTolerances.maxLinearTolerance, specifier: "%.1f") mm (Default: \(KernelTolerances.defaultLinearTolerance, specifier: "%.3f") mm)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Angular Tolerance (deg):")
                        Spacer()
                        TextField("Angular", value: $workspace.kernelTolerances.angularTolerance, format: .number)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("Valid range: \(KernelTolerances.minAngularTolerance, specifier: "%.3f")...\(KernelTolerances.maxAngularTolerance, specifier: "%.1f")° (Default: \(KernelTolerances.defaultAngularTolerance, specifier: "%.1f")°)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Chordal Deflection (mm):")
                        Spacer()
                        TextField("Chordal", value: $workspace.kernelTolerances.chordalTolerance, format: .number)
                            .frame(width: 120)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("Tessellation deflection limit: \(KernelTolerances.minChordalTolerance, specifier: "%.4f")...\(KernelTolerances.maxChordalTolerance, specifier: "%.1f") mm (Default: \(KernelTolerances.defaultChordalTolerance, specifier: "%.2f") mm)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Reset Tolerances to Defaults") {
                    workspace.resetTolerancesToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ShortcutsSettingsTab: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var searchQuery: String = ""
    @State private var selectedCategory: ShortcutCategory = .all

    var filteredShortcuts: [ShortcutCheatsheetEntry] {
        let entries = workspace.shortcuts
        return entries.filter { entry in
            let matchesCategory = (selectedCategory == .all || entry.category == selectedCategory)
            if !matchesCategory { return false }
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if query.isEmpty { return true }
            return entry.title.lowercased().contains(query) ||
                   entry.shortcut.lowercased().contains(query) ||
                   entry.description.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search shortcuts…", text: $searchQuery)
                    .textFieldStyle(.plain)

                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Picker("Category", selection: $selectedCategory) {
                    ForEach(ShortcutCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .frame(width: 140)
            }
            .padding(10)
            .background(.bar)

            Divider()

            List(filteredShortcuts) { entry in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.title)
                                .fontWeight(.medium)
                            Text(entry.category.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.quaternary))
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.shortcut)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.tertiary))
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .overlay {
                if filteredShortcuts.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                }
            }
        }
    }
}
