import Foundation
import SwiftUI
import os
import MadeCore

public typealias DocumentConfiguration = MadeCore.DocumentConfiguration

public enum ConsoleLogLevel: String, Sendable, CaseIterable {
    case info = "INFO"
    case warning = "WARNING"
    case kernel = "KERNEL"
    case snap = "SNAP"
    case agent = "AGENT"
    case error = "ERROR"
    
    var osLogType: OSLogType {
        switch self {
        case .info, .snap, .agent: return .info
        case .warning: return .default
        case .kernel: return .debug
        case .error: return .error
        }
    }
    
    public var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .yellow
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

public struct OpenErrorInfo: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let documentURL: URL
    public let reason: String

    public var fileName: String {
        documentURL.lastPathComponent
    }

    public init(id: UUID = UUID(), documentURL: URL, reason: String) {
        self.id = id
        self.documentURL = documentURL
        self.reason = reason
    }
}

public struct ExportErrorInfo: Identifiable, Sendable, Equatable {
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

public struct ImportErrorInfo: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let fileURL: URL
    public let errorCode: String
    public let reason: String

    public var fileName: String {
        fileURL.lastPathComponent
    }

    public init(id: UUID = UUID(), fileURL: URL, errorCode: String, reason: String) {
        self.id = id
        self.fileURL = fileURL
        self.errorCode = errorCode
        self.reason = reason
    }
}

public struct ReorderErrorInfo: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let featureId: UUID
    public let message: String

    public init(id: UUID = UUID(), featureId: UUID, message: String) {
        self.id = id
        self.featureId = featureId
        self.message = message
    }
}

