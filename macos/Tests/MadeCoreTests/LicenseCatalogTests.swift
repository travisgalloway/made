import Foundation
import Testing
@testable import MadeCore

@Suite struct LicenseCatalogTests {
    static let macosRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let repoRoot = macosRoot.deletingLastPathComponent()

    @Test func bundledCatalogLoadsAndMatchesRepoLicense() throws {
        let catalog = try LicenseCatalog.loadBundled()
        #expect(catalog.sourceURL.absoluteString == "https://github.com/travisgalloway/made")
        #expect(catalog.buildFromSourceGuideURL.absoluteString.contains("docs/guides/building-from-source.md"))

        let madeEntry = try #require(catalog.entries.first { $0.id == "made" })
        #expect(madeEntry.name == "made")
        #expect(madeEntry.spdxIdentifier == "MPL-2.0")
        #expect(madeEntry.copyright.contains("Travis Galloway"))
        #expect(madeEntry.kind == .application)

        let rootLicense = try String(contentsOf: Self.repoRoot.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(madeEntry.licenseText == rootLicense)

        let euclidEntry = try #require(catalog.entries.first { $0.id == "euclid" })
        #expect(euclidEntry.name == "Euclid")
        #expect(euclidEntry.version == "0.9.6")
        #expect(euclidEntry.spdxIdentifier == "MIT")
        #expect(euclidEntry.copyright.contains("Nick Lockwood"))
        #expect(euclidEntry.kind == .package)
        #expect(euclidEntry.licenseText.contains("MIT License"))
        #expect(euclidEntry.licenseText.contains("Permission is hereby granted, free of charge"))
    }

    @Test func everyPackageDependencyHasMatchingLicenseEntry() throws {
        let catalog = try LicenseCatalog.loadBundled()
        let packageSwift = try String(
            contentsOf: Self.macosRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let declaredDependencies = Self.extractPackageDependencies(from: packageSwift)
        #expect(!declaredDependencies.isEmpty, "Package.swift should declare at least one dependency")

        let resolvedPins = try Self.extractResolvedPins(
            from: Self.macosRoot.appendingPathComponent("Package.resolved")
        )

        let verificationErrors = Self.verifyDependencies(
            declared: declaredDependencies,
            resolvedPins: resolvedPins,
            in: catalog
        )
        #expect(verificationErrors.isEmpty, "Missing or mismatched package license entries:\n\(verificationErrors.joined(separator: "\n"))")
    }

    @Test func missingPackageDependencyInCatalogIsDetected() throws {
        let catalog = try LicenseCatalog.loadBundled()
        var declared = Self.extractPackageDependencies(
            from: """
            dependencies: [
                .package(url: "https://github.com/nicklockwood/Euclid.git", from: "0.9.6"),
                .package(url: "https://github.com/SecondMouseAU/OCCTSwift.git", from: "0.14.0")
            ]
            """
        )
        #expect(declared.count == 2)
        let errors = Self.verifyDependencies(declared: declared, resolvedPins: ["euclid": "0.9.6", "occtswift": "0.14.0"], in: catalog)
        #expect(errors.count == 1)
        #expect(errors[0].contains("occtswift"))

        declared = Self.extractPackageDependencies(
            from: """
            dependencies: [
                .package(path: "../libs/MadeSolver")
            ]
            """
        )
        #expect(declared == [.init(identity: "madesolver", minVersion: nil)])
        let localErrors = Self.verifyDependencies(declared: declared, resolvedPins: [:], in: catalog)
        #expect(localErrors.count == 1)
        #expect(localErrors[0].contains("madesolver"))
    }

    @Test func everyBundledHelperHasLicenseEntry() throws {
        let catalog = try LicenseCatalog.loadBundled()
        let helpersDir = Self.macosRoot.appendingPathComponent("Support/Helpers", isDirectory: true)
        let bundledHelpers = Self.discoverHelperExecutables(in: helpersDir)
        let missing = Self.verifyHelpers(bundledHelpers, in: catalog)
        #expect(missing.isEmpty, "Bundled helper programs without license entries: \(missing.joined(separator: ", "))")

        let registeredHelpers = Self.verifyHelpers(["ccx", "gmsh"], in: catalog)
        #expect(registeredHelpers.isEmpty, "ccx and gmsh should have registered helper entries in licenses.json")

        let simulatedMissing = Self.verifyHelpers(["unregistered-helper"], in: catalog)
        #expect(simulatedMissing == ["unregistered-helper"])
    }

    @Test func releaseNotesMarkdownContainsAllEntriesAndLinks() throws {
        let catalog = try LicenseCatalog.loadBundled()
        let markdown = catalog.formattedReleaseNotesMarkdown()
        #expect(markdown.contains(catalog.sourceURL.absoluteString))
        #expect(markdown.contains(catalog.buildFromSourceGuideURL.absoluteString))
        for entry in catalog.entries {
            #expect(markdown.contains(entry.name))
            #expect(markdown.contains(entry.version))
            #expect(markdown.contains(entry.spdxIdentifier))
            #expect(markdown.contains(entry.copyright))
            #expect(markdown.contains(entry.homepageURL.absoluteString))
        }
    }

    @Test func filteringMatchesNameIDSPDXVersionAndCopyright() throws {
        let catalog = try LicenseCatalog.loadBundled()
        #expect(catalog.entries(matching: "").count == catalog.entries.count)
        #expect(catalog.entries(matching: "   ").count == catalog.entries.count)
        #expect(catalog.entries(matching: "Euclid").map(\.id) == ["euclid"])
        #expect(catalog.entries(matching: "MPL-2.0").map(\.id) == ["made"])
        #expect(catalog.entries(matching: "Lockwood").map(\.id) == ["euclid"])
        #expect(catalog.entries(matching: "0.9.6").map(\.id) == ["euclid"])
        #expect(catalog.entries(matching: "nonexistent-pkg-xyz").isEmpty)
    }

    @Test func loaderRejectsMalformedAndUnsafeCatalogs() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LicenseCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // 1. Missing manifest
        #expect(throws: LicenseCatalogError.missingManifest) {
            try LicenseCatalog.load(from: tempRoot)
        }

        // 2. Invalid JSON
        let manifestURL = tempRoot.appendingPathComponent("licenses.json")
        try Data("not json".utf8).write(to: manifestURL)
        #expect {
            try LicenseCatalog.load(from: tempRoot)
        } throws: { error in
            guard case LicenseCatalogError.invalidManifest = error else { return false }
            return true
        }

        // 3. Empty entries
        try Self.writeManifest(entriesJSON: "[]", to: manifestURL)
        #expect(throws: LicenseCatalogError.emptyEntries) {
            try LicenseCatalog.load(from: tempRoot)
        }

        // 4. Unsafe licenseFile path traversal
        try Self.writeManifest(
            entriesJSON: """
            [{
              "id": "pkg",
              "name": "Pkg",
              "version": "1.0.0",
              "spdxIdentifier": "MIT",
              "copyright": "Copyright 2026",
              "homepageURL": "https://example.com/pkg",
              "licenseFile": "../secret.txt",
              "kind": "package"
            }]
            """,
            to: manifestURL
        )
        #expect(throws: LicenseCatalogError.unsafeLicenseFileName(id: "pkg", file: "../secret.txt")) {
            try LicenseCatalog.load(from: tempRoot)
        }

        // 5. Missing license file
        try Self.writeManifest(
            entriesJSON: """
            [{
              "id": "pkg",
              "name": "Pkg",
              "version": "1.0.0",
              "spdxIdentifier": "MIT",
              "copyright": "Copyright 2026",
              "homepageURL": "https://example.com/pkg",
              "licenseFile": "missing.txt",
              "kind": "package"
            }]
            """,
            to: manifestURL
        )
        #expect(throws: LicenseCatalogError.missingLicenseFile(id: "pkg", file: "missing.txt")) {
            try LicenseCatalog.load(from: tempRoot)
        }

        // 6. Empty license text file
        let licenseURL = tempRoot.appendingPathComponent("empty.txt")
        try Data("   \n\t  ".utf8).write(to: licenseURL)
        try Self.writeManifest(
            entriesJSON: """
            [{
              "id": "pkg",
              "name": "Pkg",
              "version": "1.0.0",
              "spdxIdentifier": "MIT",
              "copyright": "Copyright 2026",
              "homepageURL": "https://example.com/pkg",
              "licenseFile": "empty.txt",
              "kind": "package"
            }]
            """,
            to: manifestURL
        )
        #expect(throws: LicenseCatalogError.emptyLicenseText(id: "pkg", file: "empty.txt")) {
            try LicenseCatalog.load(from: tempRoot)
        }

        // 7. Duplicate IDs (case-insensitive)
        let validLicenseURL = tempRoot.appendingPathComponent("valid.txt")
        try Data("MIT License text".utf8).write(to: validLicenseURL)
        try Self.writeManifest(
            entriesJSON: """
            [
              {
                "id": "pkg",
                "name": "Pkg",
                "version": "1.0.0",
                "spdxIdentifier": "MIT",
                "copyright": "Copyright 2026",
                "homepageURL": "https://example.com/pkg",
                "licenseFile": "valid.txt",
                "kind": "package"
              },
              {
                "id": "PKG",
                "name": "Pkg 2",
                "version": "1.0.0",
                "spdxIdentifier": "MIT",
                "copyright": "Copyright 2026",
                "homepageURL": "https://example.com/pkg2",
                "licenseFile": "valid.txt",
                "kind": "package"
              }
            ]
            """,
            to: manifestURL
        )
        #expect(throws: LicenseCatalogError.duplicateEntryID("PKG")) {
            try LicenseCatalog.load(from: tempRoot)
        }

        // 8. Non-https URL rejected
        try Self.writeManifest(
            entriesJSON: """
            [{
              "id": "pkg",
              "name": "Pkg",
              "version": "1.0.0",
              "spdxIdentifier": "MIT",
              "copyright": "Copyright 2026",
              "homepageURL": "http://example.com/pkg",
              "licenseFile": "valid.txt",
              "kind": "package"
            }]
            """,
            to: manifestURL
        )
        #expect(throws: LicenseCatalogError.invalidURL(field: "pkg.homepageURL", value: "http://example.com/pkg")) {
            try LicenseCatalog.load(from: tempRoot)
        }
    }

    @Test func buildFromSourceGuideFileExistsInRepository() throws {
        let guideURL = Self.repoRoot.appendingPathComponent("docs/guides/building-from-source.md")
        #expect(FileManager.default.fileExists(atPath: guideURL.path))
    }

    // MARK: - Verification Helpers

    struct DeclaredDependency: Equatable {
        let identity: String
        let minVersion: String?
    }

    static func extractPackageDependencies(from packageSwift: String) -> [DeclaredDependency] {
        var results: [DeclaredDependency] = []
        let urlPattern = #/\.package\s*\(\s*url:\s*"([^"]+)"(?:\s*,\s*(?:from|exact):\s*"([^"]+)")?/#
        for match in packageSwift.matches(of: urlPattern) {
            let urlString = String(match.1)
            let lastComponent = urlString.split(separator: "/").last.map(String.init) ?? urlString
            let identity = (lastComponent.hasSuffix(".git") ? String(lastComponent.dropLast(4)) : lastComponent).lowercased()
            let version = match.2.map(String.init)
            results.append(DeclaredDependency(identity: identity, minVersion: version))
        }

        let pathPattern = #/\.package\s*\(\s*(?:name:\s*"[^"]+"\s*,\s*)?path:\s*"([^"]+)"/#
        for match in packageSwift.matches(of: pathPattern) {
            let pathString = String(match.1)
            let lastComponent = pathString.split(separator: "/").last.map(String.init) ?? pathString
            results.append(DeclaredDependency(identity: lastComponent.lowercased(), minVersion: nil))
        }
        return results
    }

    private struct ResolvedFile: Decodable {
        struct Pin: Decodable {
            struct State: Decodable {
                let version: String?
            }
            let identity: String
            let state: State
        }
        let pins: [Pin]
    }

    static func extractResolvedPins(from resolvedURL: URL) throws -> [String: String] {
        let data = try Data(contentsOf: resolvedURL)
        let decoded = try JSONDecoder().decode(ResolvedFile.self, from: data)
        var map: [String: String] = [:]
        for pin in decoded.pins {
            if let version = pin.state.version {
                map[pin.identity.lowercased()] = version
            }
        }
        return map
    }

    static func verifyDependencies(
        declared: [DeclaredDependency],
        resolvedPins: [String: String],
        in catalog: LicenseCatalog
    ) -> [String] {
        var errors: [String] = []
        let packageEntries = Dictionary(
            uniqueKeysWithValues: catalog.entries
                .filter { $0.kind == .package }
                .map { ($0.id.lowercased(), $0) }
        )

        for dep in declared {
            guard let entry = packageEntries[dep.identity] else {
                errors.append("Package dependency '\(dep.identity)' in Package.swift has no package license entry in licenses.json")
                continue
            }
            if let resolvedVersion = resolvedPins[dep.identity], entry.version != resolvedVersion {
                errors.append("Package dependency '\(dep.identity)' version in licenses.json (\(entry.version)) does not match Package.resolved (\(resolvedVersion))")
            } else if let minVersion = dep.minVersion, resolvedPins[dep.identity] == nil, entry.version != minVersion {
                errors.append("Package dependency '\(dep.identity)' version in licenses.json (\(entry.version)) does not match Package.swift (\(minVersion))")
            }
        }

        let declaredIDs = Set(declared.map(\.identity))
        for (id, entry) in resolvedPins where packageEntries[id] == nil && !declaredIDs.contains(id) {
            errors.append("Resolved package pin '\(id)' (\(entry)) in Package.resolved has no package license entry in licenses.json")
        }

        return errors
    }

    static func discoverHelperExecutables(in directory: URL) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return items.map { $0.lastPathComponent.lowercased() }.sorted()
    }

    static func verifyHelpers(_ helpers: [String], in catalog: LicenseCatalog) -> [String] {
        let helperIDs = Set(
            catalog.entries
                .filter { $0.kind == .helper }
                .map { $0.id.lowercased() }
        )
        return helpers.filter { !helperIDs.contains($0.lowercased()) }
    }

    private static func writeManifest(entriesJSON: String, to url: URL) throws {
        let json = """
        {
          "sourceURL": "https://github.com/travisgalloway/made",
          "buildFromSourceGuideURL": "https://github.com/travisgalloway/made/blob/main/docs/guides/building-from-source.md",
          "entries": \(entriesJSON)
        }
        """
        try Data(json.utf8).write(to: url)
    }
}
