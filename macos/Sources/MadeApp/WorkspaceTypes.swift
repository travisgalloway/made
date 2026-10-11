import Foundation
import SwiftUI
import MadeCore

public enum GizmoMode: String, CaseIterable, Identifiable, Sendable {
    case select = "Select"
    case translate = "Translate"
    case rotate = "Rotate"
    case scale = "Scale"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .select: return "cursorarrow"
        case .translate: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: return "arrow.triangle.2.circlepath"
        case .scale: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        }
    }
}

public enum ConsoleLogLevel: String, Sendable, CaseIterable {
    case info = "INFO"
    case kernel = "KERNEL"
    case snap = "SNAP"
    case agent = "AGENT"
    case error = "ERROR"
    
    public var color: Color {
        switch self {
        case .info: return .blue
        case .kernel: return .purple
        case .snap: return .orange
        case .agent: return .green
        case .error: return .red
        }
    }
}

public struct ConsoleLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let level: ConsoleLogLevel
    public let subsystem: String
    public let message: String
    
    public init(level: ConsoleLogLevel, subsystem: String, message: String) {
        self.timestamp = Date()
        self.level = level
        self.subsystem = subsystem
        self.message = message
    }
}

public enum NavigatorSection: String, CaseIterable, Identifiable {
    case outline = "Outline"
    case layers = "Layers"
    case constraints = "Constraints"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .outline: return "folder.fill"
        case .layers: return "square.3.layers.3d"
        case .constraints: return "link"
        }
    }
}

public enum InspectorTab: String, CaseIterable, Identifiable {
    case properties = "Inspector"
    case simulation = "Physics"
    case copilot = "AI Copilot"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .properties: return "slider.horizontal.3"
        case .simulation: return "atom"
        case .copilot: return "sparkles"
        }
    }
}

public enum ConsoleTab: String, CaseIterable, Identifiable {
    case logs = "Console Logs"
    case engine = "CLI & Engine"
    case telemetry = "Telemetry"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .logs: return "terminal"
        case .engine: return "cpu"
        case .telemetry: return "chart.bar.xaxis"
        }
    }
}
