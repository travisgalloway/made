import SwiftUI

struct SettingsView: View {
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
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 180)
    }
}
