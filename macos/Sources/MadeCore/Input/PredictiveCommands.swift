import Foundation

public enum PredictiveCommandKind: String, Sendable, CaseIterable, Equatable {
    case fillet = "fillet"
    case chamfer = "chamfer"
    case pushPull = "push-pull"
}

public struct PredictiveCommand: Sendable, Equatable, Identifiable {
    public let id: PredictiveCommandKind
    public let title: String
    public let iconName: String
    public let isEnabled: Bool
    public let disabledReason: String?

    public init(
        id: PredictiveCommandKind,
        title: String,
        iconName: String,
        isEnabled: Bool,
        disabledReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

public enum PredictiveCommandProvider {
    public static func availableCommands(
        for elementType: SubelementType,
        isPlanarFace: Bool = false
    ) -> [PredictiveCommand] {
        switch elementType {
        case .edge:
            return [
                PredictiveCommand(
                    id: .chamfer,
                    title: "Chamfer",
                    iconName: "skew",
                    isEnabled: true,
                    disabledReason: nil
                ),
                PredictiveCommand(
                    id: .fillet,
                    title: "Fillet",
                    iconName: "skew",
                    isEnabled: false,
                    disabledReason: "Fillet will be enabled when geometry engine ships (#82)"
                )
            ]
        case .face:
            guard isPlanarFace else { return [] }
            return [
                PredictiveCommand(
                    id: .pushPull,
                    title: "Push-Pull",
                    iconName: "arrow.up.and.down.square",
                    isEnabled: true,
                    disabledReason: nil
                )
            ]
        case .vertex:
            return []
        }
    }
}
