import SwiftUI
import MadeCore
import simd

private struct PopoverSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = CGSize(width: 180, height: 110)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0 && next.height > 0 {
            value = next
        }
    }
}

struct PredictiveCommandPopoverView: View {
    @Environment(WorkspaceModel.self) private var envWorkspace
    private let explicitWorkspace: WorkspaceModel?
    let selectedSubElement: SelectedSubElement
    @State private var popoverSize: CGSize = CGSize(width: 180, height: 110)

    init(workspace: WorkspaceModel? = nil, selectedSubElement: SelectedSubElement) {
        self.explicitWorkspace = workspace
        self.selectedSubElement = selectedSubElement
    }

    var workspace: WorkspaceModel {
        if let explicitWorkspace {
            return explicitWorkspace
        }
        return envWorkspace
    }

    var availableCommands: [PredictiveCommand] {
        let isPlanar: Bool
        if selectedSubElement.elementType == .face {
            isPlanar = workspace.isFacePlanar(solidId: selectedSubElement.solidId, faceId: selectedSubElement.elementId)
        } else {
            isPlanar = false
        }
        return PredictiveCommandProvider.availableCommands(
            for: selectedSubElement.elementType,
            isPlanarFace: isPlanar
        )
    }

    var badgeTitle: String {
        switch selectedSubElement.elementType {
        case .edge:
            return "Edge #\(selectedSubElement.elementId)"
        case .face:
            return "Face #\(selectedSubElement.elementId)"
        case .vertex:
            return "Vertex #\(selectedSubElement.elementId)"
        }
    }

    var body: some View {
        let commands = availableCommands
        if commands.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geo in
                let viewportSize = geo.size
                let anchorScreen = workspace.subElementScreenPosition(for: selectedSubElement, viewportSize: viewportSize)
                let anchorRect: CGRect? = anchorScreen.map { pt in
                    CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16)
                }
                let pos = CommandHUDPlacement.computePosition(
                    geometryScreenRect: anchorRect,
                    viewportSize: viewportSize,
                    hudSize: popoverSize,
                    margin: 12,
                    padding: 16
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(badgeTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())

                        Spacer()

                        Button {
                            workspace.document.selectedSubElement = nil
                            workspace.syncViewportSelection()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss predictive commands")
                    }

                    Divider()

                    ForEach(commands) { cmd in
                        Button {
                            executeCommand(cmd)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: cmd.iconName)
                                    .font(.system(size: 13))
                                    .frame(width: 16, height: 16)
                                Text(cmd.title)
                                    .font(.callout)
                                Spacer()
                                if !cmd.isEnabled, let reason = cmd.disabledReason {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .help(reason)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(cmd.isEnabled ? Color.accentColor : Color.secondary.opacity(0.3))
                        .disabled(!cmd.isEnabled)
                        .help(cmd.disabledReason ?? cmd.title)
                    }
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.separator, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 3)
                .frame(width: 180)
                .fixedSize(horizontal: true, vertical: true)
                .background(
                    GeometryReader { cardGeo in
                        Color.clear
                            .preference(key: PopoverSizePreferenceKey.self, value: cardGeo.size)
                    }
                )
                .onPreferenceChange(PopoverSizePreferenceKey.self) { newSize in
                    if newSize.width > 0 && newSize.height > 0 {
                        popoverSize = newSize
                    }
                }
                .offset(x: pos.x, y: pos.y)
            }
        }
    }

    func executeCommand(_ command: PredictiveCommand) {
        guard command.isEnabled else { return }
        switch command.id {
        case .pushPull:
            workspace.startPushPullCommand(solidId: selectedSubElement.solidId, faceId: selectedSubElement.elementId)
        case .fillet:
            break
        }
    }
}
