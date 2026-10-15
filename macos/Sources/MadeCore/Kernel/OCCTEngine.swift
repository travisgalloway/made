import Foundation
import OCCTSwift

/// Geometry engine wrapper bridging OCCT B-Rep shapes and meshes to MadeCore's engine-neutral representation.
///
/// Strictly internal to `MadeCore/Kernel` to uphold Invariant 4 (no OCCT symbols leak to Viewport, Scripting, or Scene).
enum OCCTEngine {
    enum EngineError: Error, Sendable {
        case emptyData
        case parseFailed(String)
        case tessellationFailed
    }

    /// Imports a STEP file from raw binary data into an OCCT B-Rep Shape.
    ///
    /// Writes the data to a temporary file, invokes OCCT's robust STEP reader with healing and sewing,
    /// and cleans up the temporary file upon completion.
    static func importStep(data: Data) throws -> Shape {
        guard !data.isEmpty else {
            throw EngineError.emptyData
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".step")
        try data.write(to: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            return try Shape.loadRobust(fromPath: tempURL.path)
        } catch {
            do {
                return try Shape.load(fromPath: tempURL.path)
            } catch {
                throw EngineError.parseFailed("Failed to parse STEP geometry: \(error)")
            }
        }
    }

    /// Converts an OCCT Shape into an engine-neutral, GPU-ready `MeshPayload` backed by page-aligned `MeshStorage`.
    ///
    /// Tessellates the shape using enhanced mesh parameters and copies position, normal, and index buffers
    /// directly into shared memory.
    static func toMeshPayload(_ shape: Shape, deflection: Double = 0.1, angle: Double = 0.5) -> MeshPayload? {
        var params = MeshParameters.default
        params.deflection = deflection
        params.angle = angle
        params.deflectionInterior = 0
        params.angleInterior = 0
        params.minSize = 0
        params.relative = false
        params.inParallel = true
        params.internalVertices = true
        params.controlSurfaceDeflection = true
        params.adjustMinSize = false
        params.allowQualityDecrease = false

        guard let mesh = shape.mesh(parameters: params),
              mesh.triangleCount > 0,
              mesh.vertexCount > 0 else {
            return nil
        }

        let vertexData = mesh.vertexData
        let normalData = mesh.normalData
        let indices = mesh.indices

        guard !vertexData.isEmpty, !indices.isEmpty else {
            return nil
        }

        let storage = MeshStorage(
            positionCount: vertexData.count,
            normalCount: normalData.count,
            indexCount: indices.count
        ) { positions, normals, idxs in
            vertexData.withUnsafeBufferPointer { vBuf in
                guard let src = vBuf.baseAddress, let dst = positions.baseAddress else { return }
                dst.initialize(from: src, count: vBuf.count)
            }
            normalData.withUnsafeBufferPointer { nBuf in
                guard let src = nBuf.baseAddress, let dst = normals.baseAddress else { return }
                dst.initialize(from: src, count: nBuf.count)
            }
            indices.withUnsafeBufferPointer { iBuf in
                guard let src = iBuf.baseAddress, let dst = idxs.baseAddress else { return }
                dst.initialize(from: src, count: iBuf.count)
            }
        }

        return MeshPayload(storage: storage)
    }

    #if DEBUG
    static func sampleBoxStepData() -> Data? {
        guard let shape = Shape.box(width: 10, height: 10, depth: 10) else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".step")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        do {
            try shape.writeSTEP(to: tempURL)
            return try Data(contentsOf: tempURL)
        } catch {
            return nil
        }
    }
    #endif
}
