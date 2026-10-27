import Foundation

/// Canonical model representing a named design variant (BL-PAR-04, #177).
public struct DocumentConfiguration: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var comment: String
    public var parameterOverrides: [String: Double]
    public var suppressionOverrides: [UUID: Bool]
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        comment: String = "",
        parameterOverrides: [String: Double] = [:],
        suppressionOverrides: [UUID: Bool] = [:],
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.comment = comment
        self.parameterOverrides = parameterOverrides
        self.suppressionOverrides = suppressionOverrides
        self.isDefault = isDefault
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case comment
        case parameterOverrides
        case suppressionOverrides
        case isDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        self.parameterOverrides = try container.decodeIfPresent([String: Double].self, forKey: .parameterOverrides) ?? [:]
        self.suppressionOverrides = try container.decodeIfPresent([UUID: Bool].self, forKey: .suppressionOverrides) ?? [:]
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        if !comment.isEmpty {
            try container.encode(comment, forKey: .comment)
        }
        if !parameterOverrides.isEmpty {
            try container.encode(parameterOverrides, forKey: .parameterOverrides)
        }
        if !suppressionOverrides.isEmpty {
            try container.encode(suppressionOverrides, forKey: .suppressionOverrides)
        }
        if isDefault {
            try container.encode(isDefault, forKey: .isDefault)
        }
    }

    public static func validateName(_ name: String, existingNames: [String] = [], ignoringId: UUID? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DocumentConfigurationError.emptyName
        }
        if existingNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            throw DocumentConfigurationError.duplicateName(trimmed)
        }
    }
}

public enum DocumentConfigurationError: LocalizedError, Sendable, Equatable {
    case emptyName
    case duplicateName(String)
    case configurationNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Configuration name cannot be empty."
        case .duplicateName(let name):
            return "A configuration named '\(name)' already exists."
        case .configurationNotFound(let id):
            return "Configuration '\(id.uuidString)' was not found."
        }
    }
}
