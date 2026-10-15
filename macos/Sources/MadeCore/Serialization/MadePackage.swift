import Foundation

/// Typed errors encountered during `.made` package reading and writing.
public enum MadeDocumentError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case corruptDocument(String)
    case missingFile(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported document schema version: \(version). This version of Made only supports schema version 1."
        case .corruptDocument(let details):
            return "Corrupt document: \(details)"
        case .missingFile(let filename):
            return "Missing required file in package: \(filename)"
        }
    }
}

/// Directory package (.made) representation conforming to ADR-D7.
public struct MadePackage: Sendable, Equatable {
    public var manifest: MadeManifest
    public var documentData: DocumentData
    public var assets: [String: Data]
    public var parts: [String: Data]

    public init(
        manifest: MadeManifest = MadeManifest(),
        documentData: DocumentData,
        assets: [String: Data] = [:],
        parts: [String: Data] = [:]
    ) {
        self.manifest = manifest
        self.documentData = documentData
        self.assets = assets
        self.parts = parts
    }

    /// Initializes a MadePackage from an existing FileWrapper package.
    public init(fileWrapper: FileWrapper) throws {
        guard fileWrapper.isDirectory else {
            throw MadeDocumentError.corruptDocument("Expected package directory, but found a regular file.")
        }
        guard let children = fileWrapper.fileWrappers else {
            throw MadeDocumentError.corruptDocument("Empty or unreadable package directory.")
        }

        // 1. Read manifest.json
        guard let manifestWrapper = children["manifest.json"],
              let manifestData = manifestWrapper.regularFileContents else {
            throw MadeDocumentError.missingFile("manifest.json")
        }

        let decodedManifest: MadeManifest
        do {
            decodedManifest = try JSONDecoder().decode(MadeManifest.self, from: manifestData)
        } catch {
            throw MadeDocumentError.corruptDocument("manifest.json is invalid: \(error.localizedDescription)")
        }

        if decodedManifest.schemaVersion > 1 {
            throw MadeDocumentError.unsupportedSchemaVersion(decodedManifest.schemaVersion)
        }
        self.manifest = decodedManifest

        // 2. Read document.json
        guard let docWrapper = children["document.json"],
              let docData = docWrapper.regularFileContents else {
            throw MadeDocumentError.missingFile("document.json")
        }

        var decodedDoc: DocumentData
        do {
            decodedDoc = try DocumentModelCoder.decode(from: docData)
        } catch {
            throw MadeDocumentError.corruptDocument("document.json is invalid: \(error.localizedDescription)")
        }

        if decodedDoc.schemaVersion > 1 {
            throw MadeDocumentError.unsupportedSchemaVersion(decodedDoc.schemaVersion)
        }

        // 3. Read assets/
        var loadedAssets: [String: Data] = [:]
        if let assetsWrapper = children["assets"], assetsWrapper.isDirectory, let assetFiles = assetsWrapper.fileWrappers {
            for (filename, wrapper) in assetFiles {
                if let data = wrapper.regularFileContents {
                    loadedAssets[filename] = data
                }
            }
        }
        self.assets = loadedAssets

        // Link assets into .imported solids where present
        for i in 0..<decodedDoc.objects.count {
            if case .imported(let name, let sourceURL, _) = decodedDoc.objects[i].def {
                let candidateFilenames = [
                    sourceURL?.lastPathComponent,
                    name,
                    name.hasSuffix(".step") || name.hasSuffix(".stp") ? nil : "\(name).step"
                ].compactMap { $0 }

                var matchedData: Data? = nil
                var matchedName: String? = nil
                for candidate in candidateFilenames {
                    if let data = loadedAssets[candidate] {
                        matchedData = data
                        matchedName = candidate
                        break
                    }
                }

                if let matchedData {
                    let url = matchedName.map { URL(fileURLWithPath: "assets/\($0)") }
                    decodedDoc.objects[i].def = .imported(name: name, sourceURL: url, data: matchedData)
                }
            }
        }

        // 4. Read parts/
        var loadedParts: [String: Data] = [:]
        if let partsWrapper = children["parts"], partsWrapper.isDirectory, let partFiles = partsWrapper.fileWrappers {
            for (filename, wrapper) in partFiles {
                if let data = wrapper.regularFileContents {
                    loadedParts[filename] = data
                }
            }
        }
        self.parts = loadedParts

        self.documentData = decodedDoc
    }

    /// Initializes a MadePackage from a directory on disk.
    public init(directoryURL: URL) throws {
        let wrapper: FileWrapper
        do {
            wrapper = try FileWrapper(url: directoryURL, options: .immediate)
        } catch {
            throw MadeDocumentError.corruptDocument("Could not read directory package at \(directoryURL.path): \(error.localizedDescription)")
        }
        try self.init(fileWrapper: wrapper)
    }

    /// Creates a FileWrapper directory package containing manifest.json, document.json, assets/, parts/, and cache/.gitignore.
    public func makeFileWrapper() throws -> FileWrapper {
        let manifestData = try DocumentModelCoder.makeJSONEncoder().encode(manifest)
        var manifestWithNewline = manifestData
        if !manifestWithNewline.isEmpty && manifestWithNewline.last != UInt8(ascii: "\n") {
            manifestWithNewline.append(UInt8(ascii: "\n"))
        }

        let docData = try DocumentModelCoder.encode(documentData)

        var rootWrappers: [String: FileWrapper] = [:]
        rootWrappers["manifest.json"] = FileWrapper(regularFileWithContents: manifestWithNewline)
        rootWrappers["document.json"] = FileWrapper(regularFileWithContents: docData)

        if !assets.isEmpty {
            var assetWrappers: [String: FileWrapper] = [:]
            for (filename, data) in assets {
                assetWrappers[filename] = FileWrapper(regularFileWithContents: data)
            }
            rootWrappers["assets"] = FileWrapper(directoryWithFileWrappers: assetWrappers)
        }

        if !parts.isEmpty {
            var partWrappers: [String: FileWrapper] = [:]
            for (filename, data) in parts {
                partWrappers[filename] = FileWrapper(regularFileWithContents: data)
            }
            rootWrappers["parts"] = FileWrapper(directoryWithFileWrappers: partWrappers)
        }

        // cache/ directory with cache/.gitignore containing *
        let gitignoreData = "*\n".data(using: .utf8) ?? Data()
        let cacheWrappers: [String: FileWrapper] = [
            ".gitignore": FileWrapper(regularFileWithContents: gitignoreData)
        ]
        rootWrappers["cache"] = FileWrapper(directoryWithFileWrappers: cacheWrappers)

        return FileWrapper(directoryWithFileWrappers: rootWrappers)
    }

    /// Writes package atomically to a destination URL.
    public func write(to directoryURL: URL) throws {
        let wrapper = try makeFileWrapper()
        try wrapper.write(to: directoryURL, options: .atomic, originalContentsURL: nil)
    }
}
