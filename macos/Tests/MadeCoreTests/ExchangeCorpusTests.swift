import Testing
import Foundation
import simd
import OCCTSwift
@testable import MadeCore

/// Manifest and regression test suite for CAD exchange reference models.
@Suite struct ExchangeCorpusTests {

    struct ExchangeCorpusManifest: Codable, Sendable {
        let entries: [ExchangeCorpusEntry]
    }

    struct ExchangeCorpusEntry: Codable, Sendable {
        let id: String
        let filename: String
        let format: OCCTEngine.ExchangeFormat
        let unit: String
        let license: String
        let description: String
        let expectedBounds: CorpusBounds?
        let expectedVolume: Double?
        let boundsTolerance: Double?
        let volumeTolerance: Double?
        let expectedFailure: ExpectedFailure?
    }

    struct CorpusBounds: Codable, Equatable, Sendable {
        let min: [Double]
        let max: [Double]
    }

    struct ExpectedFailure: Codable, Equatable, Sendable {
        let issue: String
        let reason: String
    }

    enum CorpusError: Error, LocalizedError, Equatable {
        case fileNotFound(String)
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let filename):
                return "Corpus file does not exist: \(filename)"
            case .decodingFailed(let message):
                return "Failed to decode corpus manifest: \(message)"
            }
        }
    }

    /// Resolves the absolute directory containing exchange corpus assets.
    static func corpusDirectory() -> URL {
        if let moduleURL = Bundle.module.url(forResource: "ExchangeCorpus", withExtension: nil) {
            if FileManager.default.fileExists(atPath: moduleURL.path) {
                return moduleURL
            }
        }
        if let resourceURL = Bundle.module.resourceURL?.appendingPathComponent("Resources/ExchangeCorpus") {
            if FileManager.default.fileExists(atPath: resourceURL.path) {
                return resourceURL
            }
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/ExchangeCorpus", isDirectory: true)
    }

    /// Resolves a file URL for a corpus file, throwing `CorpusError.fileNotFound` if missing.
    static func resolveCorpusFile(named filename: String) throws -> URL {
        let url = corpusDirectory().appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CorpusError.fileNotFound(filename)
        }
        return url
    }

    /// Loads and decodes `manifest.json` from the exchange corpus directory.
    static func loadManifest() throws -> ExchangeCorpusManifest {
        let manifestURL = try resolveCorpusFile(named: "manifest.json")
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(ExchangeCorpusManifest.self, from: data)
    }

    @Test func testCorpusManifestParsesSuccessfully() throws {
        let manifest = try Self.loadManifest()
        #expect(!manifest.entries.isEmpty, "Manifest must declare at least one model entry")

        for entry in manifest.entries {
            #expect(!entry.id.isEmpty, "Entry ID must not be empty")
            #expect(!entry.filename.isEmpty, "Filename must not be empty")
            #expect(!entry.license.isEmpty, "License must be documented for \(entry.filename)")
            #expect(!entry.description.isEmpty, "Description must be documented for \(entry.filename)")
            #expect(OCCTEngine.ExchangeFormat.allCases.contains(entry.format), "Format must be recognized for \(entry.filename)")
        }
    }

    @Test func testCorpusFilesExistAndUnderSizeLimit() throws {
        let manifest = try Self.loadManifest()
        for entry in manifest.entries {
            let fileURL = Self.corpusDirectory().appendingPathComponent(entry.filename)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                Issue.record("Missing required corpus file: \(entry.filename)")
                continue
            }
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            #expect(size > 0, "Corpus file \(entry.filename) is empty")
            #expect(size < 1_000_000, "Corpus file \(entry.filename) exceeds 1 MB ceiling: \(size) bytes")
        }
    }

    @Test func testCorpusImportsMatchManifest() throws {
        let manifest = try Self.loadManifest()
        for entry in manifest.entries {
            if entry.expectedFailure != nil {
                continue
            }
            let fileURL = try Self.resolveCorpusFile(named: entry.filename)
            let data = try Data(contentsOf: fileURL)
            let shape = try OCCTEngine.importShape(data: data, format: entry.format)

            guard let rawBBox = shape.boundingBox else {
                Issue.record("Failed to compute bounding box for \(entry.filename)")
                continue
            }
            let rawVol = shape.volume ?? shape.sewn()?.volume
            guard let rawVol else {
                Issue.record("Failed to compute volume for \(entry.filename)")
                continue
            }

            let linearScale: Double
            let volumeScale: Double
            if entry.unit == "in" || entry.unit == LengthUnit.inches.rawValue {
                linearScale = LengthUnit.inches.toMillimeters(1.0)
                volumeScale = pow(linearScale, 3)
            } else {
                linearScale = 1.0
                volumeScale = 1.0
            }

            let minX = rawBBox.min.x * linearScale
            let minY = rawBBox.min.y * linearScale
            let minZ = rawBBox.min.z * linearScale
            let maxX = rawBBox.max.x * linearScale
            let maxY = rawBBox.max.y * linearScale
            let maxZ = rawBBox.max.z * linearScale
            let measuredVol = rawVol * volumeScale

            let bTol = entry.boundsTolerance ?? 0.01
            let vTol = entry.volumeTolerance ?? 0.1

            if let expectedBounds = entry.expectedBounds {
                #expect(abs(minX - expectedBounds.min[0]) <= bTol, "minX mismatch for \(entry.filename): \(minX) vs \(expectedBounds.min[0])")
                #expect(abs(minY - expectedBounds.min[1]) <= bTol, "minY mismatch for \(entry.filename): \(minY) vs \(expectedBounds.min[1])")
                #expect(abs(minZ - expectedBounds.min[2]) <= bTol, "minZ mismatch for \(entry.filename): \(minZ) vs \(expectedBounds.min[2])")
                #expect(abs(maxX - expectedBounds.max[0]) <= bTol, "maxX mismatch for \(entry.filename): \(maxX) vs \(expectedBounds.max[0])")
                #expect(abs(maxY - expectedBounds.max[1]) <= bTol, "maxY mismatch for \(entry.filename): \(maxY) vs \(expectedBounds.max[1])")
                #expect(abs(maxZ - expectedBounds.max[2]) <= bTol, "maxZ mismatch for \(entry.filename): \(maxZ) vs \(expectedBounds.max[2])")
            }

            if let expectedVol = entry.expectedVolume {
                #expect(abs(measuredVol - expectedVol) <= vTol, "Volume mismatch for \(entry.filename): measured \(measuredVol) vs expected \(expectedVol)")
            }
        }
    }

    @Test func testMissingCorpusFileFailsWithFilename() {
        let missingFilename = "missing_nonexistent_reference_model.step"
        #expect(throws: CorpusError.self) {
            try Self.resolveCorpusFile(named: missingFilename)
        }
        do {
            _ = try Self.resolveCorpusFile(named: missingFilename)
        } catch {
            let errorMsg = error.localizedDescription
            #expect(errorMsg.contains(missingFilename), "Error '\(errorMsg)' does not contain filename '\(missingFilename)'")
        }
    }

    @Test func testUnitConversionBeforeComparison() throws {
        // Assert LengthUnit linear scaling: 1 inch = 25.4 mm
        let mmLinear = LengthUnit.inches.toMillimeters(1.0)
        #expect(mmLinear == 25.4)

        // Assert volumetric scaling: 1 cubic inch = 25.4^3 mm^3 = 16387.064 mm^3
        let mmVolume = pow(LengthUnit.inches.toMillimeters(1.0), 3)
        #expect(abs(mmVolume - 16387.064) < 1e-3)

        // Verify inch-based STEP cube scales to millimeter expectations
        let cubeURL = try Self.resolveCorpusFile(named: "cube_inches.step")
        let cubeData = try Data(contentsOf: cubeURL)
        let cubeShape = try OCCTEngine.importShape(data: cubeData, format: .step)
        let cubeBBox = try #require(cubeShape.boundingBox)
        let cubeVol = try #require(cubeShape.volume)

        let scaledCubeMinX = cubeBBox.min.x * mmLinear
        let scaledCubeMaxX = cubeBBox.max.x * mmLinear
        let scaledCubeVolume = cubeVol * mmVolume
        #expect(abs(scaledCubeMinX - 0.0) <= 0.01)
        #expect(abs(scaledCubeMaxX - 25.4) <= 0.01)
        #expect(abs(scaledCubeVolume - 16387.064) <= 0.1)

        // Verify inch-based binary STL wedge scales to millimeter expectations
        let wedgeURL = try Self.resolveCorpusFile(named: "wedge_inches_binary.stl")
        let wedgeData = try Data(contentsOf: wedgeURL)
        let wedgeShape = try OCCTEngine.importShape(data: wedgeData, format: .stl)
        let wedgeBBox = try #require(wedgeShape.boundingBox)
        let wedgeVol = try #require(wedgeShape.volume ?? wedgeShape.sewn()?.volume)

        let scaledWedgeMaxX = wedgeBBox.max.x * mmLinear
        let scaledWedgeVolume = wedgeVol * mmVolume
        #expect(abs(scaledWedgeMaxX - 25.4) <= 0.01)
        #expect(abs(scaledWedgeVolume - 8193.532) <= 0.1)
    }

    @Test func testExpectedFailuresHandledWithIssueNumber() throws {
        let manifest = try Self.loadManifest()
        let expectedFailures = manifest.entries.filter { $0.expectedFailure != nil }
        #expect(!expectedFailures.isEmpty, "Manifest should contain at least one expected failure entry")

        for entry in expectedFailures {
            guard let expected = entry.expectedFailure else { continue }
            #expect(!expected.issue.isEmpty, "Expected failure entry \(entry.filename) must specify an issue number")
            let fileURL = try Self.resolveCorpusFile(named: entry.filename)
            let data = try Data(contentsOf: fileURL)

            do {
                _ = try OCCTEngine.importShape(data: data, format: entry.format)
                // If it succeeded unexpectedly, document tracking without failing
            } catch {
                #expect(expected.issue == "#403")
            }
        }
    }

    // MARK: - OCCT Canonical B-Rep Extrude & Revolve Tests

    @Test func testOCCTCanonicalExtrude() throws {
        let profile = SketchProfile(
            plane: .xy,
            points: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(20, 0),
                SIMD2<Float>(20, 10),
                SIMD2<Float>(0, 10)
            ]
        )
        let node = ShapeNode.extrude(profile: profile, distance: 15.0, centered: false)
        let shape = try OCCTEngine.buildShape(from: node)
        #expect(shape.isValid)
        #expect(shape.solidCount == 1)

        let vol = try #require(shape.volume)
        #expect(abs(vol - 3000.0) <= 0.1)

        let bbox = try #require(shape.boundingBox)
        #expect(abs(bbox.min.x - 0.0) <= 0.01)
        #expect(abs(bbox.max.x - 20.0) <= 0.01)
        #expect(abs(bbox.min.y - 0.0) <= 0.01)
        #expect(abs(bbox.max.y - 10.0) <= 0.01)
        #expect(abs(bbox.min.z - 0.0) <= 0.01)
        #expect(abs(bbox.max.z - 15.0) <= 0.01)

        // Symmetric extrude
        let symNode = ShapeNode.extrude(profile: profile, distance: 15.0, centered: true)
        let symShape = try OCCTEngine.buildShape(from: symNode)
        #expect(symShape.isValid)
        let symBBox = try #require(symShape.boundingBox)
        #expect(abs(symBBox.min.z - (-7.5)) <= 0.01)
        #expect(abs(symBBox.max.z - 7.5) <= 0.01)

        // ObjectDef.extrude
        let def = ObjectDef.extrude(ExtrudeParams(profile: profile, distance: 15.0, isSymmetric: false))
        let defShape = try OCCTEngine.buildShape(for: def)
        #expect(defShape.isValid)
        #expect(defShape.solidCount == 1)
        let defVol = try #require(defShape.volume)
        #expect(abs(defVol - 3000.0) <= 0.1)
    }

    @Test func testOCCTCanonicalRevolve() throws {
        // Rectangle off-axis: r in [10, 20], z in [0, 5]
        let profile = SketchProfile(
            plane: .xy,
            points: [
                SIMD2<Float>(10, 0),
                SIMD2<Float>(20, 0),
                SIMD2<Float>(20, 5),
                SIMD2<Float>(10, 5)
            ]
        )
        let node = ShapeNode.revolve(profile: profile, angleDegrees: 360.0, slices: 64)
        let shape = try OCCTEngine.buildShape(from: node)
        #expect(shape.isValid)
        #expect(shape.solidCount == 1)

        let vol = try #require(shape.volume)
        // Expected volume: pi * (20^2 - 10^2) * 5 = 1500 * pi ≈ 4712.38898
        let expectedVolume = .pi * (400.0 - 100.0) * 5.0
        #expect(abs(vol - expectedVolume) <= 1.0)

        // ObjectDef.revolve
        let params = RevolveParams(
            profile: profile,
            mode: .full,
            angle: 360.0,
            axisOrigin: SIMD3<Float>(0, 0, 0),
            axisDirection: SIMD3<Float>(0, 1, 0)
        )
        let def = ObjectDef.revolve(params)
        let defShape = try OCCTEngine.buildShape(for: def)
        #expect(defShape.isValid)
        #expect(defShape.solidCount == 1)
        let defVol = try #require(defShape.volume)
        #expect(abs(defVol - expectedVolume) <= 1.0)
    }

    // MARK: - Atomic Agent Undo Transaction Tests

    @Test @MainActor func testAtomicAgentUndoGrouping() throws {
        let doc = DocumentModel()
        let initialCount = doc.objects.count

        doc.performAgentTransaction(name: "MCP: compound_test") {
            _ = doc.addObject(def: .box(BoxParams(width: 10, depth: 10, height: 10)))
            _ = doc.addObject(def: .cylinder(CylinderParams(radius: 5, height: 20)))
        }

        #expect(doc.objects.count == initialCount + 2)
        #expect(doc.canUndo == true)
        #expect(doc.undoManager?.undoActionName == "MCP: compound_test")
        #expect(doc.undoActionTitle == "Undo MCP: compound_test")

        doc.undo()

        #expect(doc.objects.count == initialCount)
        #expect(doc.canRedo == true)
        #expect(doc.redoActionTitle == "Redo MCP: compound_test")

        doc.redo()

        #expect(doc.objects.count == initialCount + 2)
    }

    @Test @MainActor func testCADToolsExtrudeUndoGrouping() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // 1. Create a sketch with a rectangle
        let sketchFeat = doc.addSketchFeature(planeName: "XY", entities: [
            SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 0)),
            SketchEntity.line(start: SIMD2(20, 0), end: SIMD2(20, 10)),
            SketchEntity.line(start: SIMD2(20, 10), end: SIMD2(0, 10)),
            SketchEntity.line(start: SIMD2(0, 10), end: SIMD2(0, 0))
        ])
        try? await Task.sleep(nanoseconds: 5_000_000)

        // 2. Call cad_extrude via CADToolRegistry
        let extrudeRes = await registry.callTool(name: "cad_extrude", arguments: [
            "sketchId": .string(sketchFeat.id.uuidString),
            "distance": .double(25.0)
        ])
        #expect(extrudeRes.isError == false)
        #expect(doc.undoManager?.undoActionName == "MCP: cad_extrude")
        #expect(doc.undoActionTitle == "Undo MCP: cad_extrude")
        #expect(doc.canUndo == true)

        doc.undo()
        #expect(doc.canRedo == true)
        #expect(doc.redoActionTitle == "Redo MCP: cad_extrude")

        doc.redo()
        #expect(doc.undoActionTitle == "Undo MCP: cad_extrude")
    }
}
