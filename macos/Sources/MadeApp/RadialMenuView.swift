import SwiftUI
import MadeCore

struct RadialMenuView: View {
    let state: RadialMenuState
    @Environment(WorkspaceModel.self) private var workspace

    private let layout = RadialMenuLayout()

    init(state: RadialMenuState) {
        self.state = state
    }

    var body: some View {
        GeometryReader { geometry in
            let center = layout.clampedCenter(
                pointer: state.position,
                viewportSize: geometry.size
            )
            let targetSolid = state.targetSolidId.flatMap { id in
                workspace.document.objects.first(where: { $0.id == id })
            }
            let items = Self.items(targetSolid: targetSolid)

            ZStack {
                // Center anchor dot
                Circle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 6, height: 6)
                    .position(center)

                // Radial action buttons
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let pos = layout.itemPosition(
                        center: center,
                        index: index,
                        count: items.count
                    )
                    RadialButton(item: item) {
                        Self.execute(
                            command: item.id,
                            targetSolidId: state.targetSolidId,
                            workspace: workspace
                        )
                    }
                    .position(pos)
                }
            }
        }
    }

    static func items(targetSolid: SceneObject?) -> [RadialMenuItem] {
        if let targetSolid {
            return [
                RadialMenuItem(
                    id: .delete,
                    title: "Delete",
                    iconName: "trash",
                    isDestructive: true
                ),
                RadialMenuItem(
                    id: .duplicate,
                    title: "Duplicate",
                    iconName: "plus.square.on.square",
                    isDestructive: false
                ),
                RadialMenuItem(
                    id: .lock,
                    title: targetSolid.isLocked ? "Unlock" : "Lock",
                    iconName: targetSolid.isLocked ? "lock.open" : "lock",
                    isDestructive: false
                ),
                RadialMenuItem(
                    id: .hide,
                    title: targetSolid.isVisible ? "Hide" : "Show",
                    iconName: targetSolid.isVisible ? "eye.slash" : "eye",
                    isDestructive: false
                )
            ]
        } else {
            return [
                RadialMenuItem(
                    id: .addBox,
                    title: "Add Box",
                    iconName: "cube",
                    isDestructive: false
                ),
                RadialMenuItem(
                    id: .addCylinder,
                    title: "Add Cylinder",
                    iconName: "cylinder",
                    isDestructive: false
                )
            ]
        }
    }

    static func execute(
        command: RadialCommandKind,
        targetSolidId: ObjectId?,
        workspace: WorkspaceModel
    ) {
        switch command {
        case .delete:
            if let targetSolidId {
                workspace.removeObject(targetSolidId)
            }
        case .duplicate:
            if let targetSolidId {
                workspace.duplicateObject(targetSolidId)
            }
        case .lock:
            if let targetSolidId {
                workspace.toggleLock(targetSolidId)
            }
        case .hide:
            if let targetSolidId {
                workspace.toggleVisibility(targetSolidId)
            }
        case .addBox:
            workspace.addDefaultBox()
        case .addCylinder:
            workspace.addDefaultCylinder()
        }
        workspace.dismissRadialMenu()
    }
}

private struct RadialButton: View {
    let item: RadialMenuItem
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                item.isDestructive
                                    ? Color.red.opacity(isHovered ? 0.8 : 0.4)
                                    : (isHovered ? Color.accentColor : Color.primary.opacity(0.15)),
                                lineWidth: isHovered ? 2 : 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)

                Image(systemName: item.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(item.isDestructive ? Color.red : (isHovered ? Color.accentColor : Color.primary))
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(item.title)
        .accessibilityLabel(item.title)
    }
}
