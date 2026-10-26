import Foundation

/// The active viewport tool, which decides what a plain primary-button drag does.
public enum ViewportTool: String, CaseIterable, Identifiable, Sendable {
    case select
    case orbit
    case pan
    case zoom
    case trim
    case rectangle
    case slot
    case polygon
    case ellipse

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .select: return "Select"
        case .orbit: return "Orbit"
        case .pan: return "Pan"
        case .zoom: return "Zoom"
        case .trim: return "Trim"
        case .rectangle: return "Rectangle"
        case .slot: return "Slot"
        case .polygon: return "Polygon"
        case .ellipse: return "Ellipse"
        }
    }

    public var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .orbit: return "rotate.3d"
        case .pan: return "hand.raised"
        case .zoom: return "magnifyingglass"
        case .trim: return "scissors"
        case .rectangle: return "rectangle"
        case .slot: return "capsule"
        case .polygon: return "hexagon"
        case .ellipse: return "oval"
        }
    }

    /// Single-key shortcut, active while the viewport has keyboard focus.
    public var shortcutKey: Character {
        switch self {
        case .select: return "v"
        case .orbit: return "o"
        case .pan: return "p"
        case .zoom: return "z"
        case .trim: return "t"
        case .rectangle: return "r"
        case .slot: return "s"
        case .polygon: return "g"
        case .ellipse: return "e"
        }
    }

    public static func forShortcutKey(_ key: Character) -> ViewportTool? {
        allCases.first { $0.shortcutKey == Character(key.lowercased()) }
    }
}

public enum ViewportPointerButton: Sendable, Equatable {
    case primary
    case secondary
    case middle
}

/// What one drag does to the scene. Chosen on mouse-down and held until release (invariant 8).
public enum ViewportDragAction: Sendable, Equatable {
    case manipulate
    case orbit
    case pan
    case zoom

    public var isNavigation: Bool { self != .manipulate }
}

public enum NavigationPreset: String, CaseIterable, Identifiable, Sendable, Codable, Equatable {
    case defaultPreset = "Default (Made)"
    case solidWorks = "SolidWorks"
    case fusion360 = "Fusion 360"
    case blender = "Blender"
    case onshape = "Onshape"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var description: String {
        switch self {
        case .defaultPreset:
            return "Middle drag pans. Secondary drag orbits (Shift+drag pans). Option+Primary drag navigates."
        case .solidWorks:
            return "Middle drag orbits (Control+drag pans, Shift+drag zooms). Secondary drag orbits."
        case .fusion360:
            return "Middle drag pans (Shift+drag orbits, Control+drag zooms). Secondary drag orbits."
        case .blender:
            return "Middle drag orbits (Shift+drag pans, Control+drag zooms). Secondary drag orbits."
        case .onshape:
            return "Secondary drag orbits (Shift+drag pans). Middle drag pans."
        }
    }
}

extension ViewportTool {
    /// Modifier and button navigation keep working under every tool, so the tool only changes a plain primary drag.
    public static func dragAction(
        tool: ViewportTool,
        button: ViewportPointerButton,
        option: Bool,
        shift: Bool,
        control: Bool = false,
        command: Bool = false,
        preset: NavigationPreset = .defaultPreset
    ) -> ViewportDragAction {
        switch button {
        case .primary:
            if preset == .defaultPreset && option {
                return shift ? .pan : .orbit
            }
            return toolAction(tool)

        case .secondary:
            return shift ? .pan : .orbit

        case .middle:
            switch preset {
            case .defaultPreset:
                return .pan
            case .solidWorks:
                if shift { return .zoom }
                if control { return .pan }
                return .orbit
            case .fusion360:
                if shift { return .orbit }
                if control { return .zoom }
                return .pan
            case .blender:
                if shift { return .pan }
                if control { return .zoom }
                return .orbit
            case .onshape:
                return .pan
            }
        }
    }

    private static func toolAction(_ tool: ViewportTool) -> ViewportDragAction {
        switch tool {
        case .select: return .manipulate
        case .orbit: return .orbit
        case .pan: return .pan
        case .zoom: return .zoom
        case .trim: return .manipulate
        case .rectangle: return .manipulate
        case .slot: return .manipulate
        case .polygon: return .manipulate
        case .ellipse: return .manipulate
        }
    }

    /// Zoom-drag factor for a vertical pointer delta in points. Dragging up (positive y in AppKit) moves closer.
    public static func zoomFactor(forDragDeltaY deltaY: Float) -> Float {
        exp(-deltaY * 0.01)
    }
}
