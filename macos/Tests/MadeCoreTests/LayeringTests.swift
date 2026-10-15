import Testing
import Foundation
@testable import MadeCore

/// Invariants 3 and 4 lint: MadeCore is one target, so the compiler cannot stop `Viewport/` from naming an Agent or Scene type,
/// or `Scripting/` from calling Euclid directly.
@Suite struct LayeringTests {
    static let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/MadeCore", isDirectory: true)

    @Test func viewportReferencesNoAgentOrSceneType() throws {
        let forbidden = try Self.forbiddenNames()
        var found: [String] = []
        for file in try Self.swiftFiles(in: "Viewport") {
            let source = try String(contentsOf: file, encoding: .utf8)
            found += Self.violations(in: source, file: file.lastPathComponent, forbidden: forbidden)
        }
        #expect(found.isEmpty, "Viewport references Agent or Scene types:\n\(found.joined(separator: "\n"))")
    }

    static let scriptingForbidden: Set<String> = ["Euclid", "EuclidEngine", "Mesh", "LocalKernelEngine", "ShapeEvaluator", "OCCTSwift", "OCCTEngine", "Shape"]
    static let occtForbidden: Set<String> = ["OCCTSwift", "OCCTEngine", "Shape", "TopoDS_Shape"]

    @Test func scriptingReferencesNoKernelInternals() throws {
        var found: [String] = []
        for file in try Self.swiftFiles(in: "Scripting") {
            let source = try String(contentsOf: file, encoding: .utf8)
            found += Self.violations(in: source, file: file.lastPathComponent, forbidden: Self.scriptingForbidden)
        }
        #expect(found.isEmpty, "Scripting references kernel internals:\n\(found.joined(separator: "\n"))")
    }

    @Test func nonKernelLayersReferenceNoOCCT() throws {
        var found: [String] = []
        for dir in ["Viewport", "Scripting", "Scene"] {
            for file in try Self.swiftFiles(in: dir) {
                let source = try String(contentsOf: file, encoding: .utf8)
                found += Self.violations(in: source, file: file.lastPathComponent, forbidden: Self.occtForbidden)
            }
        }
        #expect(found.isEmpty, "Non-kernel layers reference OCCT types:\n\(found.joined(separator: "\n"))")
    }

    @Test func meshPayloadUsesPageAlignedMeshStorage() {
        let storage = MeshStorage(positionCount: 3, normalCount: 3, indexCount: 3) { p, n, i in
            p[0] = 0; p[1] = 0; p[2] = 0
            n[0] = 0; n[1] = 0; n[2] = 1
            i[0] = 0; i[1] = 1; i[2] = 2
        }
        let payload = MeshPayload(storage: storage)
        #expect(payload.storage.length > 0)
        #expect(payload.storage.length % Int(getpagesize()) == 0)
    }

    @Test func scanIsNotBlind() throws {
        let scriptingFiles = try Self.swiftFiles(in: "Scripting")
        #expect(scriptingFiles.contains { $0.lastPathComponent == "CADDSL.swift" })

        let viewportFiles = try Self.swiftFiles(in: "Viewport")
        #expect(!viewportFiles.isEmpty)
        #expect(viewportFiles.allSatisfy { $0.pathExtension == "swift" })
        let shaders = Self.sourcesRoot.appendingPathComponent("Viewport/Shaders.metal")
        #expect(FileManager.default.fileExists(atPath: shaders.path))
        #expect(!viewportFiles.contains { $0.lastPathComponent == "Shaders.metal" })

        let forbidden = try Self.forbiddenNames()
        for name in ["DocumentModel", "CADToolRegistry", "SolidMeshSink", "SnapshotProvider"] {
            #expect(forbidden.contains(name), "\(name) missing from the forbidden set")
        }
        for name in ["Transform", "MeshPayload", "SolidId"] {
            #expect(!forbidden.contains(name), "\(name) is layer-neutral and must not be forbidden")
        }
    }

    @Test func checkerFlagsAForbiddenName() {
        let found = Self.violations(in: "let d: DocumentModel\n", file: "X.swift", forbidden: ["DocumentModel"])
        #expect(found == ["X.swift:1 DocumentModel"])
    }

    @Test func checkerIgnoresCommentsAndStrings() {
        let source = """
            // DocumentModel
            /* SnapshotProvider /* nested DocumentModel */ still comment */
            let a = "DocumentModel"
            let b = \"\"\"
                SnapshotProvider
                \"\"\"
            let c = "escaped \\" DocumentModel"
            """
        let found = Self.violations(in: source, file: "X.swift", forbidden: ["DocumentModel", "SnapshotProvider"])
        #expect(found.isEmpty, "\(found)")
    }

    @Test func checkerIgnoresSubstrings() {
        let source = "let a: DocumentModelish\nlet myDocumentModel = 1\n"
        let found = Self.violations(in: source, file: "X.swift", forbidden: ["DocumentModel"])
        #expect(found.isEmpty, "\(found)")
    }

    @Test func checkerCollectsAttributedAndModifiedDeclarations() {
        let source = """
            @MainActor
            public final class Foo {
                enum Kind {}
            }
            public protocol Bar: AnyObject {}
            public typealias Baz = Int
            @MainActor public enum Qux {}
            extension Foo {}
            """
        let names = Self.declaredTypeNames(in: source)
        #expect(names == ["Foo", "Bar", "Baz", "Qux"])
    }

    // MARK: - Checker

    static func swiftFiles(in directory: String) throws -> [URL] {
        let root = sourcesRoot.appendingPathComponent(directory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: root.path])
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    static func forbiddenNames() throws -> Set<String> {
        var names = Set<String>()
        for directory in ["Agent", "Scene"] {
            for file in try swiftFiles(in: directory) {
                names.formUnion(declaredTypeNames(in: try String(contentsOf: file, encoding: .utf8)))
            }
        }
        return names
    }

    /// Top-level declarations only: they start at column 0, after optional attributes and modifiers.
    static func declaredTypeNames(in source: String) -> Set<String> {
        let declaration = #/^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|package|final|private|fileprivate|internal|open|indirect|nonisolated)\s+)*(?:class|struct|enum|protocol|actor|typealias)\s+([A-Z]\w*)/#
        var names = Set<String>()
        for line in strippingCommentsAndStrings(source).split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = line.prefixMatch(of: declaration) {
                names.insert(String(match.1))
            }
        }
        return names
    }

    static func violations(in source: String, file: String, forbidden: Set<String>) -> [String] {
        var found: [String] = []
        let lines = strippingCommentsAndStrings(source).split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            for match in line.matches(of: #/[A-Za-z_]\w*/#) where forbidden.contains(String(match.0)) {
                found.append("\(file):\(index + 1) \(match.0)")
            }
        }
        return found
    }

    /// Blanks comments and string literals but keeps newlines, so reported line numbers stay correct.
    static func strippingCommentsAndStrings(_ source: String) -> String {
        let chars = Array(source)
        var out = ""
        var i = 0
        func at(_ offset: Int, _ text: String) -> Bool {
            let pattern = Array(text)
            guard i + offset + pattern.count <= chars.count else { return false }
            return Array(chars[(i + offset)..<(i + offset + pattern.count)]) == pattern
        }
        while i < chars.count {
            if at(0, "//") {
                while i < chars.count && chars[i] != "\n" { i += 1 }
            } else if at(0, "/*") {
                var depth = 0
                while i < chars.count {
                    if at(0, "/*") { depth += 1; i += 2 }
                    else if at(0, "*/") { depth -= 1; i += 2; if depth == 0 { break } }
                    else { if chars[i] == "\n" { out.append("\n") }; i += 1 }
                }
            } else if at(0, "\"\"\"") {
                i += 3
                while i < chars.count && !at(0, "\"\"\"") {
                    if chars[i] == "\\" { i += 1 }
                    if i < chars.count && chars[i] == "\n" { out.append("\n") }
                    i += 1
                }
                i += 3
            } else if chars[i] == "\"" {
                i += 1
                while i < chars.count && chars[i] != "\"" && chars[i] != "\n" {
                    if chars[i] == "\\" { i += 1 }
                    i += 1
                }
                i += 1
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }
}
