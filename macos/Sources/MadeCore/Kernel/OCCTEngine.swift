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

    /// Imports a STEP file from raw binary data into an OCCT B-Rep Shape, scaling to millimeters.
    ///
    /// Writes the data to a temporary file, invokes OCCT's STEP reader with system unit scaling (defaulting
    /// to 0.001 m = 1 mm), with fallback to robust repair, and cleans up the temporary file upon completion.
    static func importStep(data: Data, unitInMeters: Double = 0.001) throws -> Shape {
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
            return try Shape.loadSTEP(from: tempURL, unitInMeters: unitInMeters)
        } catch {
            do {
                return try Shape.loadRobust(fromPath: tempURL.path)
            } catch {
                throw EngineError.parseFailed("Failed to parse STEP geometry: \(error)")
            }
        }
    }

    /// Synthesizes or retrieves an OCCT `Shape` for an exportable `ObjectDef`.
    static func buildShape(for def: ObjectDef, cachedShape: Shape? = nil) throws -> Shape {
        if let cachedShape { return cachedShape }
        switch def {
        case .box(let params):
            guard let shape = Shape.box(
                origin: SIMD3(
                    -Double(params.width) / 2.0,
                    -Double(params.depth) / 2.0,
                    -Double(params.height) / 2.0
                ),
                width: Double(params.width),
                height: Double(params.depth),
                depth: Double(params.height)
            ) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .cylinder(let params):
            guard let shape = Shape.cylinder(
                at: SIMD2(0, 0),
                bottomZ: -Double(params.height) / 2.0,
                radius: Double(params.radius),
                height: Double(params.height)
            ) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .imported(_, let sourceURL, let data):
            if let data {
                return try importStep(data: data)
            } else if let sourceURL, let fileData = try? Data(contentsOf: sourceURL) {
                return try importStep(data: fileData)
            }
            throw EngineError.emptyData
        case .boolean:
            // Boolean shape export will be delivered with topological boolean recovery in #35 / #143
            throw EngineError.tessellationFailed
        case .part:
            throw EngineError.tessellationFailed
        }
    }

    /// Applies an affine `Transform` to an OCCT `Shape`.
    static func transformed(_ shape: Shape, by transform: Transform) -> Shape? {
        if transform == .identity { return shape }
        let m = transform.matrix
        // Interleaved 3x4 row-major layout:
        // [r00, r01, r02, tx,  r10, r11, r12, ty,  r20, r21, r22, tz]
        let values: [Double] = [
            Double(m.columns.0.x), Double(m.columns.1.x), Double(m.columns.2.x), Double(m.columns.3.x),
            Double(m.columns.0.y), Double(m.columns.1.y), Double(m.columns.2.y), Double(m.columns.3.y),
            Double(m.columns.0.z), Double(m.columns.1.z), Double(m.columns.2.z), Double(m.columns.3.z)
        ]
        guard let matrix3D = TransformMatrix3D(values) else { return nil }
        return shape.transformed(byMatrix: matrix3D)
    }

    /// Serializes a single OCCT `Shape` to binary STEP data.
    static func exportStep(shape: Shape, name: String? = nil) throws -> Data {
        guard shape.isValid else { throw EngineError.tessellationFailed }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".step")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try shape.writeSTEP(to: tempURL, name: name)
        return try Data(contentsOf: tempURL)
    }

    /// Transforms, optionally compounds, and serializes multiple scene objects to binary STEP data.
    static func exportStep(objects: [SceneObject], cachedShapes: [SolidId: Shape] = [:]) throws -> Data {
        guard !objects.isEmpty else { throw EngineError.emptyData }
        var transformedShapes: [Shape] = []
        for obj in objects {
            let baseShape = try buildShape(for: obj.def, cachedShape: cachedShapes[obj.id])
            guard let transformedShape = transformed(baseShape, by: obj.transform) else {
                throw EngineError.tessellationFailed
            }
            transformedShapes.append(transformedShape)
        }
        let exportShape: Shape
        if transformedShapes.count == 1 {
            exportShape = transformedShapes[0]
        } else {
            guard let compound = Shape.compound(transformedShapes) else {
                throw EngineError.tessellationFailed
            }
            exportShape = compound
        }
        return try exportStep(shape: exportShape, name: objects.count == 1 ? objects[0].name : "Scene")
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

    static func measureShape(data: Data) throws -> (volume: Double, min: SIMD3<Double>, max: SIMD3<Double>) {
        let shape = try importStep(data: data)
        guard let vol = shape.volume, let bb = shape.boundingBox else {
            throw EngineError.tessellationFailed
        }
        return (vol, bb.min, bb.max)
    }

    static func solidCount(data: Data) throws -> Int {
        let shape = try importStep(data: data)
        return shape.solidCount
    }
    #endif
}
