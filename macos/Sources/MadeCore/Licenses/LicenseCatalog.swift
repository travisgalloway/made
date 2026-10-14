import Foundation

/// Role of a licensed component in a `made` distribution.
public enum LicenseComponentKind: String, Codable, Sendable, Equatable, CaseIterable {
    case application
    case package
    case helper
}

/// One component entry in the open source licenses catalog.
public struct LicenseEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let spdxIdentifier: String
    public let copyright: String
    public let homepageURL: URL
    public let licenseText: String
    public let kind: LicenseComponentKind

    public init(
        id: String,
        name: String,
        version: String,
        spdxIdentifier: String,
        copyright: String,
        homepageURL: URL,
        licenseText: String,
        kind: LicenseComponentKind
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.spdxIdentifier = spdxIdentifier
        self.copyright = copyright
        self.homepageURL = homepageURL
        self.licenseText = licenseText
        self.kind = kind
    }
}

/// Errors encountered while loading the bundled open source licenses catalog.
public enum LicenseCatalogError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingManifest
    case invalidManifest(String)
    case emptyEntries
    case duplicateEntryID(String)
    case missingEntryField(id: String, field: String)
    case invalidURL(field: String, value: String)
    case unsafeLicenseFileName(id: String, file: String)
    case missingLicenseFile(id: String, file: String)
    case emptyLicenseText(id: String, file: String)

    public var description: String {
        switch self {
        case .missingManifest:
            return "Resources/licenses.json is missing from the resource bundle."
        case .invalidManifest(let detail):
            return "Resources/licenses.json could not be decoded: \(detail)"
        case .emptyEntries:
            return "Resources/licenses.json contains no license entries."
        case .duplicateEntryID(let id):
            return "Duplicate license entry id '\(id)'."
        case .missingEntryField(let id, let field):
            return "License entry '\(id)' has an empty '\(field)' field."
        case .invalidURL(let field, let value):
            return "Invalid URL for '\(field)': '\(value)'."
        case .unsafeLicenseFileName(let id, let file):
            return "License entry '\(id)' specifies an unsafe file name '\(file)'."
        case .missingLicenseFile(let id, let file):
            return "License entry '\(id)' references missing file '\(file)'."
        case .emptyLicenseText(let id, let file):
            return "License file '\(file)' for entry '\(id)' is empty."
        }
    }
}

/// Catalog of open source licenses loaded from bundled resource files.
public struct LicenseCatalog: Sendable, Equatable {
    public let sourceURL: URL
    public let buildFromSourceGuideURL: URL
    public let entries: [LicenseEntry]

    public init(sourceURL: URL, buildFromSourceGuideURL: URL, entries: [LicenseEntry]) {
        self.sourceURL = sourceURL
        self.buildFromSourceGuideURL = buildFromSourceGuideURL
        self.entries = entries
    }

    private struct ManifestRecord: Decodable {
        let sourceURL: String
        let buildFromSourceGuideURL: String
        let entries: [EntryRecord]
    }

    private struct EntryRecord: Decodable {
        let id: String
        let name: String
        let version: String
        let spdxIdentifier: String
        let copyright: String
        let homepageURL: String
        let licenseFile: String
        let kind: LicenseComponentKind
    }

    /// Loads the catalog from the `MadeCore` resource bundle.
    public static func loadBundled() throws -> LicenseCatalog {
        guard let directory = Bundle.module.resourceURL?.appendingPathComponent("Resources", isDirectory: true) else {
            throw LicenseCatalogError.missingManifest
        }
        return try load(from: directory)
    }

    /// Loads and validates a license catalog from a directory containing `licenses.json` and its referenced text files.
    public static func load(from directory: URL) throws -> LicenseCatalog {
        let manifestURL = directory.appendingPathComponent("licenses.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw LicenseCatalogError.missingManifest
        }

        let data: Data
        let manifest: ManifestRecord
        do {
            data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(ManifestRecord.self, from: data)
        } catch {
            throw LicenseCatalogError.invalidManifest(error.localizedDescription)
        }

        let sourceURL = try parseHTTPSURL(manifest.sourceURL, field: "sourceURL")
        let guideURL = try parseHTTPSURL(manifest.buildFromSourceGuideURL, field: "buildFromSourceGuideURL")

        guard !manifest.entries.isEmpty else {
            throw LicenseCatalogError.emptyEntries
        }

        var seenIDs = Set<String>()
        var loadedEntries: [LicenseEntry] = []
        loadedEntries.reserveCapacity(manifest.entries.count)

        for record in manifest.entries {
            let id = record.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw LicenseCatalogError.missingEntryField(id: record.id, field: "id")
            }
            guard seenIDs.insert(id.lowercased()).inserted else {
                throw LicenseCatalogError.duplicateEntryID(id)
            }

            let name = try requireNonEmpty(record.name, id: id, field: "name")
            let version = try requireNonEmpty(record.version, id: id, field: "version")
            let spdx = try requireNonEmpty(record.spdxIdentifier, id: id, field: "spdxIdentifier")
            let copyright = try requireNonEmpty(record.copyright, id: id, field: "copyright")
            let homepageURL = try parseHTTPSURL(record.homepageURL, field: "\(id).homepageURL")
            let fileName = try requireNonEmpty(record.licenseFile, id: id, field: "licenseFile")

            guard !fileName.contains("/"), !fileName.contains("\\"), !fileName.contains(".."), fileName != "." else {
                throw LicenseCatalogError.unsafeLicenseFileName(id: id, file: fileName)
            }

            let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let rawText = try? String(contentsOf: fileURL, encoding: .utf8) else {
                throw LicenseCatalogError.missingLicenseFile(id: id, file: fileName)
            }

            let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                throw LicenseCatalogError.emptyLicenseText(id: id, file: fileName)
            }

            loadedEntries.append(
                LicenseEntry(
                    id: id,
                    name: name,
                    version: version,
                    spdxIdentifier: spdx,
                    copyright: copyright,
                    homepageURL: homepageURL,
                    licenseText: rawText,
                    kind: record.kind
                )
            )
        }

        return LicenseCatalog(
            sourceURL: sourceURL,
            buildFromSourceGuideURL: guideURL,
            entries: loadedEntries
        )
    }

    /// Formats the catalog as Markdown suitable for release notes and third-party notices.
    public func formattedReleaseNotesMarkdown() -> String {
        var lines: [String] = [
            "## Open Source Licenses",
            "",
            "- Source repository: \(sourceURL.absoluteString)",
            "- Build from source guide: \(buildFromSourceGuideURL.absoluteString)",
            "",
            "| Component | Version | License | Copyright | Homepage |",
            "| --- | --- | --- | --- | --- |"
        ]
        for entry in entries {
            lines.append("| \(entry.name) | \(entry.version) | `\(entry.spdxIdentifier)` | \(entry.copyright) | \(entry.homepageURL.absoluteString) |")
        }
        return lines.joined(separator: "\n")
    }

    /// Filter entries by search query across name, id, SPDX identifier, version, and copyright.
    public func entries(matching query: String) -> [LicenseEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(trimmed)
                || entry.id.localizedCaseInsensitiveContains(trimmed)
                || entry.spdxIdentifier.localizedCaseInsensitiveContains(trimmed)
                || entry.version.localizedCaseInsensitiveContains(trimmed)
                || entry.copyright.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private static func requireNonEmpty(_ value: String, id: String, field: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LicenseCatalogError.missingEntryField(id: id, field: field)
        }
        return trimmed
    }

    private static func parseHTTPSURL(_ value: String, field: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            throw LicenseCatalogError.invalidURL(field: field, value: value)
        }
        return url
    }
}
