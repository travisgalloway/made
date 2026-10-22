import Foundation

/// Standard property keys for parts, bodies, documents, and component instances (BL-FND-14, #172).
public enum CustomPropertyKey {
    public static let partNumber = "partNumber"
    public static let description = "description"
    public static let revision = "revision"
    public static let vendor = "vendor"
    public static let standardKeys: [String] = [partNumber, description, revision, vendor]
}

/// A container protocol providing accessors and mutation helpers for metadata dictionaries.
public protocol PropertyContainer {
    var metadata: [String: String] { get set }
}

extension PropertyContainer {
    /// Standard part number.
    public var partNumber: String? {
        get { metadata[CustomPropertyKey.partNumber] }
        set { setProperty(key: CustomPropertyKey.partNumber, value: newValue) }
    }

    /// Standard item description.
    public var itemDescription: String? {
        get { metadata[CustomPropertyKey.description] }
        set { setProperty(key: CustomPropertyKey.description, value: newValue) }
    }

    /// Standard revision identifier.
    public var revision: String? {
        get { metadata[CustomPropertyKey.revision] }
        set { setProperty(key: CustomPropertyKey.revision, value: newValue) }
    }

    /// Standard vendor name.
    public var vendor: String? {
        get { metadata[CustomPropertyKey.vendor] }
        set { setProperty(key: CustomPropertyKey.vendor, value: newValue) }
    }

    /// Dictionary of arbitrary custom key-value pairs excluding standard keys.
    public var customProperties: [String: String] {
        metadata.customProperties
    }

    /// Retrieves a property value by key, trimming leading and trailing whitespace from the key.
    public func property(forKey key: String) -> String? {
        metadata.property(forKey: key)
    }

    /// Sets or removes a property value, trimming whitespace from the key and rejecting empty keys.
    public mutating func setProperty(key: String, value: String?) {
        metadata = metadata.settingProperty(key: key, value: value)
    }
}

// MARK: - Dictionary Helpers

extension Dictionary where Key == String, Value == String {
    /// Returns a new dictionary with the specified property key set or removed.
    ///
    /// Empty or whitespace-only keys are ignored. If `value` is `nil` or empty, the key is removed.
    public func settingProperty(key: String, value: String?) -> [String: String] {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return self }
        var result = self
        if let value, !value.isEmpty {
            result[trimmedKey] = value
        } else {
            result.removeValue(forKey: trimmedKey)
        }
        return result
    }

    /// Retrieves a property value after trimming whitespace from the key.
    public func property(forKey key: String) -> String? {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }
        return self[trimmedKey]
    }

    /// Dictionary containing only custom properties (keys not in `CustomPropertyKey.standardKeys`).
    public var customProperties: [String: String] {
        filter { !CustomPropertyKey.standardKeys.contains($0.key) }
    }
}
