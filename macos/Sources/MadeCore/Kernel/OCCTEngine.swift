import Foundation
import simd
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

    enum ExchangeFormat: String, Sendable, CaseIterable, Codable {
        case step
        case iges
        case stl
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
        return try importStep(from: tempURL, unitInMeters: unitInMeters)
    }

    /// Imports a STEP file from a file URL into an OCCT B-Rep Shape, scaling to millimeters.
    static func importStep(from url: URL, unitInMeters: Double = 0.001) throws -> Shape {
        do {
            return try Shape.loadSTEP(from: url, unitInMeters: unitInMeters)
        } catch {
            do {
                return try Shape.loadRobust(fromPath: url.path)
            } catch {
                throw EngineError.parseFailed("Failed to parse STEP geometry: \(error)")
            }
        }
    }

    /// Imports an IGES file from raw binary data into an OCCT B-Rep Shape.
    static func importIges(data: Data) throws -> Shape {
        guard !data.isEmpty else {
            throw EngineError.emptyData
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".iges")
        try data.write(to: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        return try importIges(from: tempURL)
    }

    /// Imports an IGES file from a file URL into an OCCT B-Rep Shape.
    static func importIges(from url: URL) throws -> Shape {
        do {
            return try Shape.loadIGES(from: url)
        } catch {
            do {
                return try Shape.loadIGESRobust(from: url)
            } catch {
                throw EngineError.parseFailed("Failed to parse IGES geometry: \(error)")
            }
        }
    }

    /// Imports an STL file from raw binary or ASCII data into an OCCT B-Rep Shape.
    static func importStl(data: Data) throws -> Shape {
        guard !data.isEmpty else {
            throw EngineError.emptyData
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".stl")
        try data.write(to: tempURL)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        return try importStl(from: tempURL)
    }

    /// Imports an STL file from a file URL into an OCCT B-Rep Shape.
    static func importStl(from url: URL) throws -> Shape {
        do {
            return try Shape.loadSTL(from: url)
        } catch {
            do {
                return try Shape.loadSTLRobust(from: url)
            } catch {
                throw EngineError.parseFailed("Failed to parse STL geometry: \(error)")
            }
        }
    }

    /// Imports a model from raw data for the specified exchange format into an OCCT B-Rep Shape.
    static func importShape(data: Data, format: ExchangeFormat, unitInMeters: Double = 0.001) throws -> Shape {
        switch format {
        case .step:
            return try importStep(data: data, unitInMeters: unitInMeters)
        case .iges:
            return try importIges(data: data)
        case .stl:
            return try importStl(data: data)
        }
    }

    /// Imports a model from a file URL for the specified exchange format into an OCCT B-Rep Shape.
    static func importShape(from url: URL, format: ExchangeFormat, unitInMeters: Double = 0.001) throws -> Shape {
        switch format {
        case .step:
            return try importStep(from: url, unitInMeters: unitInMeters)
        case .iges:
            return try importIges(from: url)
        case .stl:
            return try importStl(from: url)
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
        case .sphere(let params):
            guard let shape = Shape.sphere(radius: Double(params.radius)) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .cone(let params):
            guard let shape = Shape.cone(
                at: SIMD3(0, 0, -Double(params.height) / 2.0),
                direction: SIMD3(0, 0, 1),
                bottomRadius: Double(params.bottomRadius),
                topRadius: Double(params.topRadius),
                height: Double(params.height)
            ) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .torus(let params):
            guard let shape = Shape.torus(
                at: SIMD3(0, 0, 0),
                direction: SIMD3(0, 0, 1),
                majorRadius: Double(params.majorRadius),
                minorRadius: Double(params.minorRadius)
            ) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .wedge(let params):
            guard let shape = Shape.wedge(
                at: SIMD3(-Double(params.width) / 2.0, -Double(params.depth) / 2.0, -Double(params.height) / 2.0),
                direction: SIMD3(0, 0, 1),
                dx: Double(params.width),
                dy: Double(params.depth),
                dz: Double(params.height),
                ltx: Double(params.topWidth)
            ) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .imported(_, let sourceURL, let data, _, _, _):
            if let data {
                return try importStep(data: data)
            } else if let sourceURL {
                if sourceURL.pathExtension.lowercased() == "made" || (try? FileWrapper(url: sourceURL, options: []).isDirectory) == true {
                    if let pkg = try? MadePackage(directoryURL: sourceURL),
                       let stepData = try? exportStep(objects: pkg.documentData.objects) {
                        return try importStep(data: stepData)
                    }
                } else if let fileData = try? Data(contentsOf: sourceURL) {
                    return try importStep(data: fileData)
                }
            }
            throw EngineError.emptyData
        case .extrude(let params):
            return try buildExtrude(profile: params.profile, distance: params.distance, isSymmetric: params.isSymmetric)
        case .revolve(let params):
            return try buildRevolve(params: params)
        case .part(_, let shape):
            if let shape {
                return try buildShape(from: shape)
            }
            throw EngineError.tessellationFailed
        case .boolean, .chamfer, .shell, .hole, .pattern, .mirror:
            throw EngineError.tessellationFailed
        }
    }

    /// Evaluates a `ShapeNode` AST directly into a canonical OCCT B-Rep `Shape`.
    static func buildShape(from node: ShapeNode) throws -> Shape {
        switch node {
        case .box(let p):
            guard let shape = Shape.box(
                origin: SIMD3(
                    -Double(p.width) / 2.0,
                    -Double(p.depth) / 2.0,
                    -Double(p.height) / 2.0
                ),
                width: Double(p.width),
                height: Double(p.depth),
                depth: Double(p.height)
            ) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .cylinder(let p, _):
            guard let shape = Shape.cylinder(
                at: SIMD2(0, 0),
                bottomZ: -Double(p.height) / 2.0,
                radius: Double(p.radius),
                height: Double(p.height)
            ) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .sphere(let p, _):
            guard let shape = Shape.sphere(radius: Double(p.radius)) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .cone(let p, _):
            guard let shape = Shape.cone(
                at: SIMD3(0, 0, -Double(p.height) / 2.0),
                direction: SIMD3(0, 0, 1),
                bottomRadius: Double(p.bottomRadius),
                topRadius: Double(p.topRadius),
                height: Double(p.height)
            ) else {
                throw EngineError.tessellationFailed
            }
            return shape
        case .extrude(let profile, let distance, let centered):
            return try buildExtrude(profile: profile, distance: Double(distance), isSymmetric: centered)
        case .revolve(let profile, let angleDegrees, _):
            return try buildRevolve(profile: profile, angleDegrees: Double(angleDegrees))
        case .revolveSolid(let params, _):
            return try buildRevolve(params: params)
        case .translate(let child, let offset):
            let shape = try buildShape(from: child)
            guard let res = shape.translated(by: SIMD3<Double>(Double(offset.x), Double(offset.y), Double(offset.z))) else {
                throw EngineError.tessellationFailed
            }
            return res
        case .rotate(let child, let axis, let angleDegrees):
            let shape = try buildShape(from: child)
            let rad = Double(angleDegrees) * .pi / 180.0
            let ax = SIMD3<Double>(Double(axis.x), Double(axis.y), Double(axis.z))
            guard let res = shape.rotated(axis: ax, angle: rad) else {
                throw EngineError.tessellationFailed
            }
            return res
        case .scale(let child, let factor):
            let shape = try buildShape(from: child)
            if abs(factor.x - factor.y) < 1e-6 && abs(factor.y - factor.z) < 1e-6 {
                guard let res = shape.scaled(by: Double(factor.x)) else {
                    throw EngineError.tessellationFailed
                }
                return res
            } else {
                let transform = Transform(scale: factor)
                guard let res = transformed(shape, by: transform) else {
                    throw EngineError.tessellationFailed
                }
                return res
            }
        case .boolean(let op, let lhs, let rhs):
            let sA = try buildShape(from: lhs)
            let sB = try buildShape(from: rhs)
            guard let res = try booleanOperation(op: op, shapeA: sA, shapeB: sB) else {
                throw EngineError.tessellationFailed
            }
            return res
        }
    }

    /// Builds a planar OCCT `Shape` (face with optional holes) from a 2D sketch profile in world 3D coordinates.
    static func buildFace(from profile: SketchProfile) throws -> Shape {
        guard profile.points.count >= 3 else {
            throw EngineError.tessellationFailed
        }
        let plane = profile.plane
        let planeNorm = simd_length(plane.normal) > 1e-6 ? simd_normalize(SIMD3<Double>(plane.normal)) : SIMD3<Double>(0, 0, 1)
        let rawX = simd_length(plane.xAxis) > 1e-6 ? simd_normalize(SIMD3<Double>(plane.xAxis)) : SIMD3<Double>(1, 0, 0)
        let planeX = simd_normalize(rawX - simd_dot(rawX, planeNorm) * planeNorm)
        let planeY = simd_cross(planeNorm, planeX)
        let planeOrigin = SIMD3<Double>(plane.origin)

        func unproject(_ pt: SIMD2<Float>) -> SIMD3<Double> {
            planeOrigin + Double(pt.x) * planeX + Double(pt.y) * planeY
        }

        var pts = orientedProfilePoints(profile.points, clockwise: false)
        if pts.count >= 2, let first = pts.first, let last = pts.last, simd_distance(first, last) < 1e-5 {
            pts.removeLast()
        }
        guard pts.count >= 3 else {
            throw EngineError.tessellationFailed
        }
        let outerPoints3D = pts.map { unproject($0) }
        guard let outerWire = Wire.polygon3D(outerPoints3D, closed: true) else {
            throw EngineError.tessellationFailed
        }

        var holeWires: [Wire] = []
        for hole in profile.holes {
            var hPts = hole
            if hPts.count >= 2, let first = hPts.first, let last = hPts.last, simd_distance(first, last) < 1e-5 {
                hPts.removeLast()
            }
            guard hPts.count >= 3 else { continue }
            let holePoints3D = hPts.map { unproject($0) }
            if let hWire = Wire.polygon3D(holePoints3D, closed: true) {
                holeWires.append(hWire)
            }
        }

        let faceShape: Shape?
        if holeWires.isEmpty {
            faceShape = Shape.face(from: outerWire, planar: true)
        } else {
            faceShape = Shape.face(outer: outerWire, holes: holeWires)
        }
        guard let faceShape else {
            throw EngineError.tessellationFailed
        }
        return faceShape
    }

    /// Extrudes a sketch profile into a canonical OCCT B-Rep solid along its plane normal.
    static func buildExtrude(profile: SketchProfile, distance: Double, isSymmetric: Bool = false) throws -> Shape {
        guard abs(distance) > 1e-6 else {
            throw EngineError.tessellationFailed
        }
        let face = try buildFace(from: profile)
        let plane = profile.plane
        let planeNorm = simd_length(plane.normal) > 1e-6 ? simd_normalize(SIMD3<Double>(plane.normal)) : SIMD3<Double>(0, 0, 1)
        let vec = planeNorm * distance
        guard let extruded = face.extruded(by: vec) else {
            throw EngineError.tessellationFailed
        }
        if isSymmetric {
            let offset = planeNorm * (-distance / 2.0)
            guard let translated = extruded.translated(by: offset) else {
                throw EngineError.tessellationFailed
            }
            return translated
        }
        return extruded
    }

    /// Revolves a sketch profile around the sketch plane's in-plane vertical axis (u = 0).
    static func buildRevolve(profile: SketchProfile, angleDegrees: Double) throws -> Shape {
        guard angleDegrees > 1e-6 else {
            throw EngineError.tessellationFailed
        }
        let face = try buildFace(from: profile)
        let plane = profile.plane
        let planeNorm = simd_length(plane.normal) > 1e-6 ? simd_normalize(SIMD3<Double>(plane.normal)) : SIMD3<Double>(0, 0, 1)
        let rawX = simd_length(plane.xAxis) > 1e-6 ? simd_normalize(SIMD3<Double>(plane.xAxis)) : SIMD3<Double>(1, 0, 0)
        let planeX = simd_normalize(rawX - simd_dot(rawX, planeNorm) * planeNorm)
        let planeY = simd_cross(planeNorm, planeX)
        let axisOrigin = SIMD3<Double>(plane.origin)
        let axisDirection = planeY

        if angleDegrees >= 360.0 - 1e-4 {
            guard let revolved = face.revolved(axisOrigin: axisOrigin, axisDirection: axisDirection) else {
                throw EngineError.tessellationFailed
            }
            return revolved
        } else {
            let angleRad = angleDegrees * .pi / 180.0
            guard let revolved = face.revolved(axisOrigin: axisOrigin, axisDirection: axisDirection, angle: angleRad) else {
                throw EngineError.tessellationFailed
            }
            return revolved
        }
    }

    /// Revolves a sketch profile according to full 3D `RevolveParams`.
    static func buildRevolve(params: RevolveParams) throws -> Shape {
        let dirLen = simd_length(params.axisDirection)
        guard dirLen > 1e-6 else {
            throw EngineError.tessellationFailed
        }
        let axisDirection = simd_normalize(SIMD3<Double>(Double(params.axisDirection.x), Double(params.axisDirection.y), Double(params.axisDirection.z)))
        let axisOrigin = SIMD3<Double>(Double(params.axisOrigin.x), Double(params.axisOrigin.y), Double(params.axisOrigin.z))

        let face = try buildFace(from: params.profile)

        let isFull = params.mode == .full || (params.mode == .angle && params.angle >= 360.0 - 1e-4)
        if isFull {
            guard let revolved = face.revolved(axisOrigin: axisOrigin, axisDirection: axisDirection) else {
                throw EngineError.tessellationFailed
            }
            return revolved
        }

        switch params.mode {
        case .full:
            guard let revolved = face.revolved(axisOrigin: axisOrigin, axisDirection: axisDirection) else {
                throw EngineError.tessellationFailed
            }
            return revolved
        case .angle:
            let angleRad = params.angle * .pi / 180.0
            guard let revolved = face.revolved(axisOrigin: axisOrigin, axisDirection: axisDirection, angle: angleRad) else {
                throw EngineError.tessellationFailed
            }
            return revolved
        case .symmetric:
            let halfAngleRad = (params.angle / 2.0) * .pi / 180.0
            let totalAngleRad = params.angle * .pi / 180.0
            guard let centeredFace = face
                .translated(by: -axisOrigin)?
                .rotated(axis: axisDirection, angle: -halfAngleRad)?
                .translated(by: axisOrigin) else {
                throw EngineError.tessellationFailed
            }
            guard let revolved = centeredFace.revolved(axisOrigin: axisOrigin, axisDirection: axisDirection, angle: totalAngleRad) else {
                throw EngineError.tessellationFailed
            }
            return revolved
        case .twoDirection:
            let angle2Rad = params.angle2 * .pi / 180.0
            let totalAngleRad = (params.angle + params.angle2) * .pi / 180.0
            guard let startFace = face
                .translated(by: -axisOrigin)?
                .rotated(axis: axisDirection, angle: -angle2Rad)?
                .translated(by: axisOrigin) else {
                throw EngineError.tessellationFailed
            }
            guard let revolved = startFace.revolved(axisOrigin: axisOrigin, axisDirection: axisDirection, angle: totalAngleRad) else {
                throw EngineError.tessellationFailed
            }
            return revolved
        }
    }

    private static func orientedProfilePoints(_ points: [SIMD2<Float>], clockwise: Bool) -> [SIMD2<Float>] {
        var twiceArea: Double = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            twiceArea += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        let isCCW = twiceArea > 0
        if clockwise {
            return isCCW ? points.reversed() : points
        } else {
            return isCCW ? points : points.reversed()
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

    /// Converts an OCCT Shape into an engine-neutral, GPU-ready `MeshPayload` backed by page-aligned `MeshStorage`
    /// using user-configured geometric tolerances.
    static func toMeshPayload(_ shape: Shape, tolerances: KernelTolerances) -> MeshPayload? {
        let clamped = tolerances.clamped()
        let deflection = clamped.chordalTolerance
        let angle: Double
        if abs(clamped.angularTolerance - KernelTolerances.defaultAngularTolerance) < 1e-6 {
            angle = 0.5
        } else {
            angle = max(clamped.angularTolerance * .pi / 180.0, 0.01)
        }
        return toMeshPayload(shape, deflection: deflection, angle: angle)
    }

    /// Converts an OCCT Shape into an engine-neutral, GPU-ready `MeshPayload` backed by page-aligned `MeshStorage`.
    ///
    /// Tessellates the shape using enhanced mesh parameters, extracts per-face triangle ranges and per-edge
    /// discretized polylines, and copies position, normal, and index buffers directly into shared memory.
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
        params.allowQualityDecrease = true

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

        // Extract face ranges
        let triangles = mesh.trianglesWithFaces()
        var faceRanges: [FaceTriangleRange] = []
        if !triangles.isEmpty {
            var currentFaceId: Int? = nil
            var startTri = 0
            for (triIndex, triangle) in triangles.enumerated() {
                let fid = Int(triangle.faceIndex)
                if let curr = currentFaceId {
                    if curr != fid {
                        faceRanges.append(FaceTriangleRange(faceId: curr, triangleRange: startTri..<triIndex))
                        currentFaceId = fid
                        startTri = triIndex
                    }
                } else {
                    currentFaceId = fid
                    startTri = triIndex
                }
            }
            if let curr = currentFaceId {
                faceRanges.append(FaceTriangleRange(faceId: curr, triangleRange: startTri..<triangles.count))
            }
        }

        // Extract edge polylines & segment ranges
        let rawPolylines = shape.allEdgePolylinesIndexed(deflection: deflection)
        var edgePolylines: [EdgePolyline] = []
        var edgeSegmentRanges: [EdgeSegmentRange] = []
        var currentSegmentOffset = 0
        for item in rawPolylines {
            let pts = item.points.map { SIMD3<Float>(Float($0.x), Float($0.y), Float($0.z)) }
            let segCount = max(0, pts.count - 1)
            let segRange = currentSegmentOffset..<(currentSegmentOffset + segCount)
            currentSegmentOffset += segCount
            let poly = EdgePolyline(edgeId: item.edgeIndex, points: pts, segmentRange: segRange)
            edgePolylines.append(poly)
            edgeSegmentRanges.append(EdgeSegmentRange(edgeId: item.edgeIndex, segmentRange: segRange))
        }

        // Extract vertices
        let rawVertices = shape.vertices()
        var vertexPoints: [VertexPoint] = []
        vertexPoints.reserveCapacity(rawVertices.count)
        for (idx, v) in rawVertices.enumerated() {
            vertexPoints.append(VertexPoint(
                vertexId: idx,
                position: SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
            ))
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

        return MeshPayload(
            storage: storage,
            faceRanges: faceRanges,
            edgePolylines: edgePolylines,
            edgeSegmentRanges: edgeSegmentRanges,
            vertexPoints: vertexPoints
        )
    }

    /// Fillets an edge in an OCCT shape identified by a persistent topological reference.
    static func fillet(shape: Shape, edgeReference: TopologicalReference, radius: Double) throws -> Shape {
        let edge = try TopologicalResolver.resolveEdge(in: shape, reference: edgeReference)
        guard let filleted = shape.filleted(edges: [edge], radius: radius) else {
            throw EngineError.tessellationFailed
        }
        return filleted
    }

    /// Chamfers edges in an OCCT shape identified by persistent topological references.
    static func chamfer(
        shape: Shape,
        edgeReferences: [TopologicalReference],
        mode: ChamferMode,
        distance: Double,
        distance2: Double,
        angle: Double
    ) throws -> Shape {
        guard let builder = ChamferBuilder(shape: shape) else {
            throw KernelError(code: .geometryFailed, message: "Failed to initialize ChamferBuilder")
        }

        for edgeRef in edgeReferences {
            let edge = try TopologicalResolver.resolveEdge(in: shape, reference: edgeRef)
            if builder.contour(for: edge) != 0 {
                continue
            }
            switch mode {
            case .equalDistance:
                builder.addEdge(edge, distance: distance)
            case .twoDistances:
                guard let (f1, _) = edge.adjacentFaces(in: shape) else {
                    throw KernelError(code: .geometryFailed, message: "Chamfer failed: edge has no adjacent face")
                }
                builder.addEdge(edge, face: f1, distance1: distance, distance2: distance2)
            case .distanceAngle:
                guard let (f1, _) = edge.adjacentFaces(in: shape) else {
                    throw KernelError(code: .geometryFailed, message: "Chamfer failed: edge has no adjacent face")
                }
                let angleRad = angle * .pi / 180.0
                builder.addEdge(edge, face: f1, distance: distance, angle: angleRad)
            }
        }

        guard let result = builder.build(), result.isValid else {
            throw KernelError(code: .geometryFailed, message: "Chamfer failed: distance may be larger than adjacent face")
        }
        return result
    }

    /// Hollows an OCCT shape to uniform wall thickness with optional removed open faces and per-face thickness overrides.
    static func shell(
        shape: Shape,
        thickness: Double,
        removedFaceReferences: [TopologicalReference],
        perFaceOverrides: [FaceThicknessOverride]
    ) throws -> Shape {
        guard thickness > 0 else {
            throw KernelError(code: .invalidParams, message: "Shell thickness must be greater than zero")
        }
        guard let bbox = shape.boundingBox else {
            throw KernelError(code: .geometryFailed, message: "Failed to compute bounding box for shell")
        }
        let minDimension = min(bbox.max.x - bbox.min.x, bbox.max.y - bbox.min.y, bbox.max.z - bbox.min.z)
        guard thickness <= minDimension / 2.0 else {
            throw KernelError(
                code: .geometryFailed,
                message: "Shell thickness \(thickness) exceeds half of smallest dimension (\(minDimension / 2.0))"
            )
        }
        for override in perFaceOverrides {
            guard override.thickness > 0 else {
                throw KernelError(code: .invalidParams, message: "Face thickness override must be greater than zero")
            }
            guard override.thickness <= minDimension / 2.0 else {
                throw KernelError(
                    code: .geometryFailed,
                    message: "Shell override thickness \(override.thickness) exceeds half of smallest dimension (\(minDimension / 2.0))"
                )
            }
        }

        var openFaces: [Face] = []
        for ref in removedFaceReferences {
            let face = try TopologicalResolver.resolveFace(in: shape, reference: ref)
            guard face.isPlanar else {
                throw KernelError(code: .geometryFailed, message: "Removed face must be planar for shell operation")
            }
            openFaces.append(face)
        }

        let shelled: Shape?
        if !openFaces.isEmpty {
            shelled = shape.shelled(thickness: -abs(thickness), openFaces: openFaces)
        } else if !perFaceOverrides.isEmpty {
            var overridesMap: [Int: Double] = [:]
            for override in perFaceOverrides {
                let face = try TopologicalResolver.resolveFace(in: shape, reference: override.faceReference)
                overridesMap[face.index] = -abs(override.thickness)
            }
            if let inner = shape.offsetPerFace(defaultOffset: -abs(thickness), faceOffsets: overridesMap) {
                shelled = shape.subtracting(inner)
            } else {
                shelled = nil
            }
        } else {
            shelled = shape.shelled(thickness: -abs(thickness))
                ?? shape.offset(by: -abs(thickness), joinType: .intersection).flatMap { shape.subtracting($0) }
                ?? shape.offset(by: -abs(thickness)).flatMap { shape.subtracting($0) }
        }

        guard let result = shelled, result.isValid else {
            throw KernelError(code: .geometryFailed, message: "Shell operation failed to produce a valid shape")
        }
        return result
    }

    /// Evaluates an exact B-Rep boolean operation (`union`, `subtract`, or `intersect`) between two OCCT shapes.
    static func booleanOperation(op: BooleanOp, shapeA: Shape, shapeB: Shape, fuzzyValue: Double = 0) throws -> Shape? {
        switch op {
        case .union:
            return shapeA.union(shapeB, fuzzyValue: fuzzyValue)
        case .subtract:
            return shapeA.subtracting(shapeB, fuzzyValue: fuzzyValue)
        case .intersect:
            return shapeA.intersection(shapeB, fuzzyValue: fuzzyValue)
        }
    }

    /// Mirrors an OCCT shape across a plane defined by its normal and origin point.
    static func mirrored(_ shape: Shape, planeNormal: SIMD3<Double>, planeOrigin: SIMD3<Double> = .zero) throws -> Shape {
        let len = simd_length(planeNormal)
        guard len > 1e-6 else {
            throw KernelError(code: .invalidParams, message: "Mirror plane normal must not be zero length")
        }
        let normalizedNormal = planeNormal / len
        guard let mirroredShape = shape.mirrored(planeNormal: normalizedNormal, planeOrigin: planeOrigin) else {
            throw EngineError.tessellationFailed
        }
        return mirroredShape
    }

    #if DEBUG
    static func sampleBoxStepData(origin: SIMD3<Double> = .zero, width: Double = 10, height: Double = 10, depth: Double = 10) -> Data? {
        guard let shape = Shape.box(origin: origin, width: width, height: height, depth: depth) else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".step")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        do {
            try shape.writeSTEP(to: tempURL)
            return try Data(contentsOf: tempURL)
        } catch {
            return nil
        }
    }

    static func measureShape(_ shape: Shape) throws -> (volume: Double, min: SIMD3<Double>, max: SIMD3<Double>) {
        let vol = shape.volume ?? shape.sewn()?.volume
        guard let vol, let bb = shape.boundingBox else {
            throw EngineError.tessellationFailed
        }
        return (vol, bb.min, bb.max)
    }

    static func measureShape(data: Data, format: ExchangeFormat = .step, unitInMeters: Double = 0.001) throws -> (volume: Double, min: SIMD3<Double>, max: SIMD3<Double>) {
        let shape = try importShape(data: data, format: format, unitInMeters: unitInMeters)
        return try measureShape(shape)
    }

    static func solidCount(data: Data) throws -> Int {
        let shape = try importStep(data: data)
        return shape.solidCount
    }
    #endif
}
