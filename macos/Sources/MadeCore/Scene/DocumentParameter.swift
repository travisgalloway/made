import Foundation

/// Canonical parameter defined at document scope (BL-PAR-01).
public struct DocumentParameter: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var value: Double
    public var unit: String
    public var comment: String

    public init(
        id: UUID = UUID(),
        name: String,
        value: Double,
        unit: String = "",
        comment: String = ""
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
        self.comment = comment
    }

    /// Reserved unit symbols that cannot be used as parameter identifiers.
    public static let reservedUnitSymbols: Set<String> = [
        "mm", "cm", "m", "in", "ft", "deg", "rad"
    ]

    /// Identifier validation regex: starts with a letter or underscore, followed by alphanumeric characters or underscores.
    private static let identifierRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "^[a-zA-Z_][a-zA-Z0-9_]*$")
    }()

    /// Returns true if the candidate string matches identifier rules `^[a-zA-Z_][a-zA-Z0-9_]*$`.
    public static func isValidIdentifier(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let range = NSRange(location: 0, length: name.utf16.count)
        return identifierRegex.firstMatch(in: name, options: [], range: range) != nil
    }

    /// Validates a parameter name against identifier rules, reserved unit symbols, and existing names.
    public static func validateName(
        _ name: String,
        existingNames: [String] = [],
        ignoringName: String? = nil
    ) throws {
        guard isValidIdentifier(name) else {
            throw DocumentParameterError.invalidIdentifier(name)
        }
        if reservedUnitSymbols.contains(name.lowercased()) {
            throw DocumentParameterError.reservedUnitSymbol(name)
        }
        for existing in existingNames {
            if let ignoringName, existing == ignoringName {
                continue
            }
            if existing == name {
                throw DocumentParameterError.duplicateName(name)
            }
        }
    }
}

/// Errors thrown during document parameter mutations and validation.
public enum DocumentParameterError: Error, Equatable, LocalizedError, Sendable {
    case duplicateName(String)
    case invalidIdentifier(String)
    case reservedUnitSymbol(String)
    case emptyValue
    case parameterNotFound(String)
    case parameterInUse(name: String, referencingFeatures: [String])

    public var errorDescription: String? {
        switch self {
        case .duplicateName(let name):
            return "A parameter named '\(name)' already exists."
        case .invalidIdentifier(let name):
            return "Parameter name '\(name)' is not a valid identifier. Parameter names must start with a letter or underscore and contain only alphanumeric characters and underscores."
        case .reservedUnitSymbol(let name):
            return "Parameter name '\(name)' cannot equal a unit symbol."
        case .emptyValue:
            return "Parameter value cannot be empty."
        case .parameterNotFound(let name):
            return "Parameter '\(name)' not found."
        case .parameterInUse(let name, let referencingFeatures):
            return "Cannot delete parameter '\(name)' because it is referenced by: \(referencingFeatures.joined(separator: ", "))."
        }
    }
}
