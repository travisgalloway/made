import Foundation
import SwiftUI
import os
import MadeCore

public enum ConsoleLogLevel: String, Sendable, CaseIterable {
    case info = "INFO"
    case kernel = "KERNEL"
    case snap = "SNAP"
    case agent = "AGENT"
    case error = "ERROR"
    
    var osLogType: OSLogType {
        switch self {
        case .info, .snap, .agent: return .info
        case .kernel: return .debug
        case .error: return .error
        }
    }
    
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

public struct SaveErrorInfo: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let destinationURL: URL
    public let reason: String

    public var fileName: String {
        destinationURL.lastPathComponent
    }

    public init(id: UUID = UUID(), destinationURL: URL, reason: String) {
        self.id = id
        self.destinationURL = destinationURL
        self.reason = reason
    }
}

