import Foundation

/// Typed errors encountered during `.made` package reading and writing.
public enum MadeDocumentError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case corruptDocument(String)
    case missingFile(String)
    case unreadableFile(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            if version > MadeManifest.currentSchemaVersion {
                return "This document was created by a newer version of Made (schema version \(version)). This version of Made supports schema versions up to \(MadeManifest.currentSchemaVersion). Please update Made to open this file."
            } else {
                return "Unsupported document schema version: \(version). This version of Made supports schema versions from \(MadeManifest.minimumSupportedSchemaVersion) to \(MadeManifest.currentSchemaVersion)."
            }
        case .corruptDocument(let details):
            return "Corrupt document: \(details)"
        case .missingFile(let filename):
            return "Missing required file in package: \(filename)"
        case .unreadableFile(let filename):
            return "Cannot read source file: \(filename)"
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
    public init(fileWrapper: FileWrapper, packageURL: URL? = nil) throws {
        guard fileWrapper.isDirectory else {
            throw MadeDocumentError.corruptDocument("Expected package directory, but found a regular file.")
        }
        guard let children = fileWrapper.fileWrappers else {
            throw MadeDocumentError.corruptDocument("Empty or unreadable package directory.")
        }

        // 1. Read manifest.json
        guard let manifestWrapper = children["manifest.json"],
              let rawManifestData = manifestWrapper.regularFileContents else {
            throw MadeDocumentError.missingFile("manifest.json")
        }

        // 2. Read document.json
        guard let docWrapper = children["document.json"],
              let rawDocData = docWrapper.regularFileContents else {
            throw MadeDocumentError.missingFile("document.json")
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

        // 4. Read parts/
        var loadedParts: [String: Data] = [:]
        if let partsWrapper = children["parts"], partsWrapper.isDirectory, let partFiles = partsWrapper.fileWrappers {
            for (filename, wrapper) in partFiles {
                if let data = wrapper.regularFileContents {
                    loadedParts[filename] = data
                }
            }
        }

        // 5. Inspect schema version
        struct ManifestHeader: Decodable {
            let schemaVersion: Int?
        }
        let manifestHeader: ManifestHeader
        do {
            manifestHeader = try JSONDecoder().decode(ManifestHeader.self, from: rawManifestData)
        } catch {
            throw MadeDocumentError.corruptDocument("manifest.json is invalid: \(error.localizedDescription)")
        }

        let rawVersion = manifestHeader.schemaVersion ?? 1
        if rawVersion > MadeManifest.currentSchemaVersion {
            throw MadeDocumentError.unsupportedSchemaVersion(rawVersion)
        }
        if rawVersion < MadeManifest.minimumSupportedSchemaVersion {
            throw MadeDocumentError.unsupportedSchemaVersion(rawVersion)
        }

        struct DocumentHeader: Decodable {
            let schemaVersion: Int?
        }
        if let docHeader = try? JSONDecoder().decode(DocumentHeader.self, from: rawDocData),
           let docVersion = docHeader.schemaVersion,
           docVersion > MadeManifest.currentSchemaVersion {
            throw MadeDocumentError.unsupportedSchemaVersion(docVersion)
        }

        var manifestData = rawManifestData
        var docData = rawDocData

        if rawVersion < MadeManifest.currentSchemaVersion {
            var packageData = DocumentPackageData(
                manifestData: manifestData,
                documentData: docData,
                assets: loadedAssets,
                parts: loadedParts
            )
            try DocumentMigrator.shared.migrate(
                package: &packageData,
                from: rawVersion,
                to: MadeManifest.currentSchemaVersion
            )
            manifestData = packageData.manifestData
            docData = packageData.documentData
            loadedAssets = packageData.assets
            loadedParts = packageData.parts
        }

        let decodedManifest: MadeManifest
        do {
            decodedManifest = try JSONDecoder().decode(MadeManifest.self, from: manifestData)
        } catch {
            throw MadeDocumentError.corruptDocument("manifest.json is invalid: \(error.localizedDescription)")
        }
        self.manifest = decodedManifest

        var decodedDoc: DocumentData
        do {
            decodedDoc = try DocumentModelCoder.decode(from: docData, packageURL: packageURL)
        } catch {
            throw MadeDocumentError.corruptDocument("document.json is invalid: \(error.localizedDescription)")
        }

        if decodedDoc.schemaVersion > MadeManifest.currentSchemaVersion {
            throw MadeDocumentError.unsupportedSchemaVersion(decodedDoc.schemaVersion)
        }

        // Link assets into .imported solids where present
        for i in 0..<decodedDoc.objects.count {
            if case .imported(let name, let sourceURL, _, let isLinked, let lastModifiedDate, let fileChecksum) = decodedDoc.objects[i].def {
                guard !isLinked else { continue }
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
                    let url = matchedName.map { name in
                        if let packageURL {
                            return packageURL.appendingPathComponent("assets/\(name)")
                        } else {
                            return URL(fileURLWithPath: "assets/\(name)")
                        }
                    }
                    decodedDoc.objects[i].def = .imported(
                        name: name,
                        sourceURL: url,
                        data: matchedData,
                        isLinked: isLinked,
                        lastModifiedDate: lastModifiedDate,
                        fileChecksum: fileChecksum
                    )
                }
            }
        }

        if var features = decodedDoc.features {
            for i in 0..<features.count {
                if case .imported(var imp) = features[i].operation {
                    guard !imp.isLinked else { continue }
                    let candidateFilenames = [
                        imp.sourceURL?.lastPathComponent,
                        imp.name,
                        imp.name.hasSuffix(".step") || imp.name.hasSuffix(".stp") ? nil : "\(imp.name).step"
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
                        let url = matchedName.map { name in
                            if let packageURL {
                                return packageURL.appendingPathComponent("assets/\(name)")
                            } else {
                                return URL(fileURLWithPath: "assets/\(name)")
                            }
                        }
                        imp.sourceURL = url
                        imp.data = matchedData
                        features[i].operation = .imported(imp)
                    }
                }
            }
            decodedDoc.features = features
        }

        // Link assets into sketch underlays where imageData is missing
        if var features = decodedDoc.features {
            for i in 0..<features.count {
                if case .sketch(var sketchData) = features[i].operation {
                    var underlaysChanged = false
                    for u in 0..<sketchData.underlays.count {
                        if sketchData.underlays[u].imageData == nil,
                           let assetFilename = sketchData.underlays[u].assetFilename,
                           let assetData = loadedAssets[assetFilename] {
                            sketchData.underlays[u].imageData = assetData
                            underlaysChanged = true
                        }
                    }
                    if underlaysChanged {
                        features[i].operation = .sketch(sketchData)
                    }
                }
            }
            decodedDoc.features = features
        }

        // Link parts into .part solids and features where present
        for i in 0..<decodedDoc.objects.count {
            if case .part(let url, let shape) = decodedDoc.objects[i].def {
                let filename = url.lastPathComponent
                if !filename.isEmpty && filename != "/" {
                    if let packageURL {
                        decodedDoc.objects[i].def = .part(
                            url: packageURL.appendingPathComponent("parts/\(filename)"),
                            shape: shape
                        )
                    }
                }
            }
        }

        if var features = decodedDoc.features {
            for i in 0..<features.count {
                if case .part(var partData) = features[i].operation {
                    let filename = partData.url.lastPathComponent
                    if !filename.isEmpty && filename != "/" {
                        if let packageURL {
                            partData.url = packageURL.appendingPathComponent("parts/\(filename)")
                            features[i].operation = .part(partData)
                        }
                    }
                }
            }
            decodedDoc.features = features
        }

        self.assets = loadedAssets
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
        try self.init(fileWrapper: wrapper, packageURL: directoryURL)
    }

    /// Creates a FileWrapper directory package containing manifest.json, document.json, assets/, parts/, and cache/.gitignore.
    public func makeFileWrapper(packageURL: URL? = nil) throws -> FileWrapper {
        let manifestData = try DocumentModelCoder.makeJSONEncoder(packageURL: packageURL).encode(manifest)
        var manifestWithNewline = manifestData
        if !manifestWithNewline.isEmpty && manifestWithNewline.last != UInt8(ascii: "\n") {
            manifestWithNewline.append(UInt8(ascii: "\n"))
        }

        let docData = try DocumentModelCoder.encode(documentData, packageURL: packageURL)

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
        let wrapper = try makeFileWrapper(packageURL: directoryURL)
        try wrapper.write(to: directoryURL, options: .atomic, originalContentsURL: nil)
    }
}
