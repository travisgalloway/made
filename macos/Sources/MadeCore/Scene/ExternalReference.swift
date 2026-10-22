import Foundation
import CryptoKit

/// Status of an external reference file linked into a Made document.
public enum ExternalLinkStatus: String, Sendable, Codable, Equatable {
    case upToDate
    case outOfDate
    case missingFile
}

/// Metadata descriptor for an external linked reference file.
public struct ExternalReferenceDescriptor: Sendable, Codable, Equatable {
    public var sourceURL: URL
    public var isLinked: Bool
    public var lastModifiedDate: Date?
    public var fileChecksum: String?

    public init(
        sourceURL: URL,
        isLinked: Bool = true,
        lastModifiedDate: Date? = nil,
        fileChecksum: String? = nil
    ) {
        self.sourceURL = sourceURL
        self.isLinked = isLinked
        self.lastModifiedDate = lastModifiedDate
        self.fileChecksum = fileChecksum
    }

    /// Evaluates the link status of the referenced file against recorded modification timestamp.
    public func checkStatus() -> ExternalLinkStatus {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .missingFile
        }
        guard let recorded = lastModifiedDate else {
            return .upToDate
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let currentMod = attrs[.modificationDate] as? Date else {
            return .upToDate
        }
        return currentMod.timeIntervalSince(recorded) > 0.001 ? .outOfDate : .upToDate
    }

    /// Returns the current modification date of the file on disk if available.
    public static func modificationDate(of url: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }

    /// Computes a hex SHA256 checksum of the target file or directory package on disk.
    public static func computeChecksum(of url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            let docJSONURL = url.appendingPathComponent("document.json")
            if let data = try? Data(contentsOf: docJSONURL) {
                let digest = SHA256.hash(data: data)
                return digest.compactMap { String(format: "%02x", $0) }.joined()
            }
            return nil
        } else {
            guard let data = try? Data(contentsOf: url) else { return nil }
            let digest = SHA256.hash(data: data)
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        }
    }

    /// Determines if a file URL represents a supported external reference format (.step, .stp, or .made).
    public static func isSupportedExternalReference(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "step" || ext == "stp" || ext == "made"
    }
}
