import Foundation
import SwiftUI
import MadeCore

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
