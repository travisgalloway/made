import Foundation
import os

/// Metadata descriptor associated with a crash recovery snapshot (.made package).
public struct CrashRecoveryMetadata: Codable, Sendable, Equatable {
    public static let currentVersion: Int = 1

    public var version: Int
    public var savedAt: Date
    public var originalDocumentURL: URL?
    public var documentTitle: String

    public init(
        version: Int = Self.currentVersion,
        savedAt: Date = Date(),
        originalDocumentURL: URL? = nil,
        documentTitle: String
    ) {
        self.version = version
        self.savedAt = savedAt
        self.originalDocumentURL = originalDocumentURL
        self.documentTitle = documentTitle
    }
}

/// A validated pending recovery record containing decoded metadata and package locations.
public struct CrashRecoveryRecord: Sendable, Equatable, Identifiable {
    public var metadata: CrashRecoveryMetadata
    public var packageURL: URL
    public var metadataURL: URL

    public var id: URL { packageURL }

    public init(
        metadata: CrashRecoveryMetadata,
        packageURL: URL,
        metadataURL: URL
    ) {
        self.metadata = metadata
        self.packageURL = packageURL
        self.metadataURL = metadataURL
    }
}

/// Store managing persistence, discovery, and lifecycle of crash recovery snapshots on disk.
public struct CrashRecoveryStore: Sendable {
    private static let logger = Logger(subsystem: "com.made.app", category: "Recovery")

    public static let packageFilename = "recovery.made"
    public static let metadataFilename = "recovery.json"

    public let recoveryDirectoryURL: URL

    public init(recoveryDirectoryURL: URL = Self.defaultRecoveryDirectoryURL) {
        self.recoveryDirectoryURL = recoveryDirectoryURL
    }

    /// Default system-wide recovery directory at `~/Library/Application Support/made/Recovery/`.
    public static var defaultRecoveryDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: ("~/Library/Application Support" as NSString).expandingTildeInPath, isDirectory: true)
        return appSupport
            .appendingPathComponent("made", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
    }

    public var packageURL: URL {
        recoveryDirectoryURL.appendingPathComponent(Self.packageFilename, isDirectory: true)
    }

    public var metadataURL: URL {
        recoveryDirectoryURL.appendingPathComponent(Self.metadataFilename, isDirectory: false)
    }

    /// Writes the recovery snapshot (.made package and recovery.json descriptor) atomically.
    public func saveSnapshot(package: MadePackage, metadata: CrashRecoveryMetadata) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: recoveryDirectoryURL.path) {
            try fm.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
        }

        // If package destination already exists, remove it first to ensure clean atomic replacement.
        if fm.fileExists(atPath: packageURL.path) {
            try? fm.removeItem(at: packageURL)
        }

        try package.write(to: packageURL)

        let encoder = DocumentModelCoder.makeJSONEncoder()
        var metaData = try encoder.encode(metadata)
        if !metaData.isEmpty && metaData.last != UInt8(ascii: "\n") {
            metaData.append(UInt8(ascii: "\n"))
        }
        try metaData.write(to: metadataURL, options: .atomic)
    }

    /// Inspects the recovery directory for a valid, non-corrupted recovery snapshot.
    /// Returns nil if no snapshot exists or if the snapshot is corrupted or unreadable.
    public func loadPendingRecovery() -> CrashRecoveryRecord? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: packageURL.path), fm.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        do {
            let metaData = try Data(contentsOf: metadataURL)
            let decoder = DocumentModelCoder.makeJSONDecoder()
            let metadata = try decoder.decode(CrashRecoveryMetadata.self, from: metaData)

            guard metadata.version <= CrashRecoveryMetadata.currentVersion else {
                Self.logger.warning("Unsupported recovery metadata version: \(metadata.version)")
                return nil
            }

            // Validate that the package directory is a readable .made bundle
            _ = try MadePackage(directoryURL: packageURL)

            return CrashRecoveryRecord(
                metadata: metadata,
                packageURL: packageURL,
                metadataURL: metadataURL
            )
        } catch {
            Self.logger.error("Failed to load crash recovery snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    /// Clears any active recovery snapshot files from the recovery directory.
    public func clearRecovery() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: packageURL.path) {
            try fm.removeItem(at: packageURL)
        }
        if fm.fileExists(atPath: metadataURL.path) {
            try fm.removeItem(at: metadataURL)
        }
    }

    /// Discards a specific recovery record from disk.
    public func discardRecord(_ record: CrashRecoveryRecord) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: record.packageURL.path) {
            try fm.removeItem(at: record.packageURL)
        }
        if fm.fileExists(atPath: record.metadataURL.path) {
            try fm.removeItem(at: record.metadataURL)
        }
    }
}
