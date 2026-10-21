import Foundation
import Euclid
import OCCTSwift
import simd

/// Runs Tier 1 Euclid CSG geometry in the calling process (ADR-D1, ADR-D9 #247).
///
/// Serves as the in-process execution engine for unbundled development runs, interactive procedural previews,
/// and unit test suites, providing instant test execution and sub-millisecond shape evaluation without XPC overhead.
/// The `MadeKernelService` XPC service hosts an instance in production (Invariants 1 & 7).
public actor LocalKernelEngine: KernelEngine {
    private var solids: [SolidId: MeshPayload] = [:]
    private var euclidMeshes: [SolidId: Euclid.Mesh] = [:]
    private var occtShapes: [SolidId: Shape] = [:]
    
    public init() {}
    
    public func execute(_ request: KernelRequest) async -> KernelResult<MeshPayload> {
        let jobId = request.jobId
        switch request {
        case .makeBox(_, let sId, let params):
            if params.width <= 0 || params.depth <= 0 || params.height <= 0 {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Box dimensions must be positive"))
            }
            let euclid = EuclidEngine.makeBox(width: params.width, depth: params.depth, height: params.height)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            if let shape = Shape.box(
                origin: SIMD3(
                    -Double(params.width) / 2.0,
                    -Double(params.depth) / 2.0,
                    -Double(params.height) / 2.0
                ),
                width: Double(params.width),
                height: Double(params.depth),
                depth: Double(params.height)
            ) {
                occtShapes[sId] = shape
            }
            return .success(jobId: jobId, value: mesh)
            
        case .makeCylinder(_, let sId, let params):
            if params.radius <= 0 || params.height <= 0 {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Cylinder dimensions must be positive"))
            }
            let euclid = EuclidEngine.makeCylinder(radius: params.radius, height: params.height)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            if let shape = Shape.cylinder(
                at: SIMD2(0, 0),
                bottomZ: -Double(params.height) / 2.0,
                radius: Double(params.radius),
                height: Double(params.height)
            ) {
                occtShapes[sId] = shape
            }
            return .success(jobId: jobId, value: mesh)

        case .makeSphere(_, let sId, let params):
            if params.radius <= 0 {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Sphere radius must be positive"))
            }
            let euclid = EuclidEngine.makeSphere(radius: params.radius)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            if let shape = Shape.sphere(radius: Double(params.radius)) {
                occtShapes[sId] = shape
            }
            return .success(jobId: jobId, value: mesh)

        case .makeCone(_, let sId, let params):
            if params.bottomRadius <= 0 || params.topRadius < 0 || params.height <= 0 {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Cone dimensions must be positive"))
            }
            let euclid = EuclidEngine.makeCone(bottomRadius: params.bottomRadius, topRadius: params.topRadius, height: params.height)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            if let shape = Shape.cone(
                at: SIMD3(0, 0, -Double(params.height) / 2.0),
                direction: SIMD3(0, 0, 1),
                bottomRadius: Double(params.bottomRadius),
                topRadius: Double(params.topRadius),
                height: Double(params.height)
            ) {
                occtShapes[sId] = shape
            }
            return .success(jobId: jobId, value: mesh)

        case .makeTorus(_, let sId, let params):
            if params.majorRadius <= 0 || params.minorRadius <= 0 || params.minorRadius >= params.majorRadius {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Torus major radius must be greater than minor radius, and both must be positive"))
            }
            let euclid = EuclidEngine.makeTorus(majorRadius: params.majorRadius, minorRadius: params.minorRadius)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            if let shape = Shape.torus(
                at: SIMD3(0, 0, 0),
                direction: SIMD3(0, 0, 1),
                majorRadius: Double(params.majorRadius),
                minorRadius: Double(params.minorRadius)
            ) {
                occtShapes[sId] = shape
            }
            return .success(jobId: jobId, value: mesh)

        case .makeWedge(_, let sId, let params):
            if params.width <= 0 || params.depth <= 0 || params.height <= 0 || params.topWidth < 0 || params.topWidth > params.width {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Wedge dimensions must be positive and topWidth must be between 0 and width"))
            }
            let euclid = EuclidEngine.makeWedge(width: params.width, depth: params.depth, height: params.height, topWidth: params.topWidth)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            if let shape = Shape.wedge(
                at: SIMD3(-Double(params.width) / 2.0, -Double(params.depth) / 2.0, -Double(params.height) / 2.0),
                direction: SIMD3(0, 0, 1),
                dx: Double(params.width),
                dy: Double(params.depth),
                dz: Double(params.height),
                ltx: Double(params.topWidth)
            ) {
                occtShapes[sId] = shape
            }
            return .success(jobId: jobId, value: mesh)
            
        case .booleanOperation(_, let sId, let op, let solidA, let solidB):
            let shapeA = occtShapes[solidA]
            let shapeB = occtShapes[solidB]
            let euclidA = euclidMeshes[solidA]
            let euclidB = euclidMeshes[solidB]

            guard shapeA != nil || euclidA != nil else {
                return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid A '\(solidA)' not found for boolean operation"))
            }
            guard shapeB != nil || euclidB != nil else {
                return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid B '\(solidB)' not found for boolean operation"))
            }

            if let shapeA, let shapeB {
                do {
                    let resultShape = try OCCTEngine.booleanOperation(op: op, shapeA: shapeA, shapeB: shapeB)
                    if let resultShape {
                        occtShapes[sId] = resultShape
                        if let payload = OCCTEngine.toMeshPayload(resultShape), !payload.isEmpty {
                            solids[sId] = payload
                            return .success(jobId: jobId, value: payload)
                        } else {
                            let emptyPayload = MeshPayload(positions: [], normals: [], indices: [])
                            solids[sId] = emptyPayload
                            return .success(jobId: jobId, value: emptyPayload)
                        }
                    } else if op == .intersect {
                        let emptyPayload = MeshPayload(positions: [], normals: [], indices: [])
                        solids[sId] = emptyPayload
                        return .success(jobId: jobId, value: emptyPayload)
                    } else {
                        return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Boolean \(op.rawValue) operation failed"))
                    }
                } catch {
                    return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Boolean \(op.rawValue) operation failed: \(error)"))
                }
            } else if let meshA = euclidA, let meshB = euclidB {
                let resultMesh: Euclid.Mesh
                switch op {
                case .subtract:
                    resultMesh = EuclidEngine.subtract(meshA, meshB)
                case .union:
                    resultMesh = EuclidEngine.union(meshA, meshB)
                case .intersect:
                    resultMesh = EuclidEngine.intersect(meshA, meshB)
                }

                euclidMeshes[sId] = resultMesh
                let payload = EuclidEngine.toMeshPayload(resultMesh)
                solids[sId] = payload
                return .success(jobId: jobId, value: payload)
            } else {
                return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Cannot perform boolean operation between B-Rep body and mesh-only body"))
            }
            
        case .evaluateShape(_, let sId, let shape):
            if let error = shape.validate() {
                return .failure(jobId: jobId, error: error)
            }
            let euclid = ShapeEvaluator.mesh(for: shape)
            euclidMeshes[sId] = euclid
            let mesh = EuclidEngine.toMeshPayload(euclid)
            solids[sId] = mesh
            return .success(jobId: jobId, value: mesh)
            
        case .tessellate(_, let sId, let tolerances):
            if let shape = occtShapes[sId] {
                let payload: MeshPayload?
                if let tolerances {
                    payload = OCCTEngine.toMeshPayload(shape, tolerances: tolerances.clamped())
                } else {
                    payload = OCCTEngine.toMeshPayload(shape)
                }
                if let payload {
                    solids[sId] = payload
                    return .success(jobId: jobId, value: payload)
                } else {
                    return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to tessellate solid \(sId)"))
                }
            } else if let existing = solids[sId] {
                return .success(jobId: jobId, value: existing)
            }
            return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid \(sId) not found"))
            
        case .importStep(_, let sId, let data):
            if data.isEmpty {
                return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "STEP data is empty"))
            }
            do {
                let shape = try OCCTEngine.importStep(data: data)
                guard let payload = OCCTEngine.toMeshPayload(shape) else {
                    return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to tessellate STEP geometry"))
                }
                solids[sId] = payload
                occtShapes[sId] = shape
                return .success(jobId: jobId, value: payload)
            } catch {
                return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to parse STEP geometry"))
            }

        case .fillet(let jobId, let sId, let edgeRef, let radius):
            return await fillet(solidId: sId, edgeReference: edgeRef, radius: radius, jobId: jobId)

        case .chamfer(let jobId, let solidId, let targetSolidId, let edgeRefs, let mode, let distance, let distance2, let angle):
            return await chamfer(
                solidId: solidId,
                targetSolidId: targetSolidId,
                edgeReferences: edgeRefs,
                mode: mode,
                distance: distance,
                distance2: distance2,
                angle: angle,
                jobId: jobId
            )

        case .shell(let jobId, let solidId, let targetSolidId, let thickness, let removedFaceRefs, let perFaceOverrides):
            return await shell(
                solidId: solidId,
                targetSolidId: targetSolidId,
                thickness: thickness,
                removedFaceReferences: removedFaceRefs,
                perFaceOverrides: perFaceOverrides,
                jobId: jobId
            )

        case .hole(let jobId, let solidId, let targetSolidId, let faceReference, let holeData):
            return await hole(
                solidId: solidId,
                targetSolidId: targetSolidId,
                faceReference: faceReference,
                holeData: holeData,
                jobId: jobId
            )

        case .pattern(let jobId, let solidId, let params):
            return await pattern(solidId: solidId, params: params, jobId: jobId)
        }
    }
    
    public func exportStep(objects: [SceneObject]) async -> KernelResult<Data> {
        let jobId = JobId("export-\(UUID().uuidString)")
        do {
            let data = try OCCTEngine.exportStep(objects: objects, cachedShapes: occtShapes)
            return .success(jobId: jobId, value: data)
        } catch {
            return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Export failed: \(error)"))
        }
    }

    public func exportSTL(objects: [SceneObject], tolerance: Double, unit: LengthUnit, to url: URL) async -> KernelResult<Int> {
        let jobId = JobId("export-stl-\(UUID().uuidString)")
        do {
            let count = try STLExporter.export(
                objects: objects,
                tolerance: tolerance,
                unit: unit,
                to: url,
                cachedShapes: occtShapes,
                cachedMeshes: solids
            )
            return .success(jobId: jobId, value: count)
        } catch let kernelError as KernelError {
            return .failure(jobId: jobId, error: kernelError)
        } catch {
            return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Export failed: \(error)"))
        }
    }

    public func fillet(solidId: SolidId, edgeReference: TopologicalReference, radius: Double, jobId: JobId? = nil) async -> KernelResult<MeshPayload> {
        let jobId = jobId ?? JobId("fillet-\(UUID().uuidString)")
        guard let shape = occtShapes[solidId] else {
            return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid '\(solidId)' not found"))
        }
        do {
            let filletedShape = try OCCTEngine.fillet(shape: shape, edgeReference: edgeReference, radius: radius)
            guard let payload = OCCTEngine.toMeshPayload(filletedShape) else {
                return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to tessellate filleted geometry"))
            }
            occtShapes[solidId] = filletedShape
            solids[solidId] = payload
            return .success(jobId: jobId, value: payload)
        } catch let kernelError as KernelError {
            return .failure(jobId: jobId, error: kernelError)
        } catch {
            return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Fillet failed: \(error)"))
        }
    }

    public func chamfer(
        solidId: SolidId,
        targetSolidId: SolidId? = nil,
        edgeReferences: [TopologicalReference],
        mode: ChamferMode = .equalDistance,
        distance: Double = 1.0,
        distance2: Double = 1.0,
        angle: Double = 45.0,
        jobId: JobId? = nil
    ) async -> KernelResult<MeshPayload> {
        let jobId = jobId ?? JobId("chamfer-\(UUID().uuidString)")
        guard distance > 0 else {
            return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Chamfer distance must be positive"))
        }
        if mode == .twoDistances {
            guard distance2 > 0 else {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Chamfer distance2 must be positive"))
            }
        }
        if mode == .distanceAngle {
            guard angle > 0 && angle < 90 else {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Chamfer angle must be between 0 and 90 degrees"))
            }
        }
        guard !edgeReferences.isEmpty else {
            return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Chamfer requires at least one edge reference"))
        }
        let targetId = targetSolidId ?? solidId
        guard let shape = occtShapes[targetId] ?? occtShapes[solidId] else {
            return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid '\(targetId)' not found"))
        }
        do {
            let chamferedShape = try OCCTEngine.chamfer(
                shape: shape,
                edgeReferences: edgeReferences,
                mode: mode,
                distance: distance,
                distance2: distance2,
                angle: angle
            )
            guard let payload = OCCTEngine.toMeshPayload(chamferedShape) else {
                return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to tessellate chamfered geometry"))
            }
            occtShapes[solidId] = chamferedShape
            solids[solidId] = payload
            return .success(jobId: jobId, value: payload)
        } catch let kernelError as KernelError {
            return .failure(jobId: jobId, error: kernelError)
        } catch {
            return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Chamfer failed: \(error)"))
        }
    }

    public func shell(
        solidId: SolidId,
        targetSolidId: SolidId? = nil,
        thickness: Double,
        removedFaceReferences: [TopologicalReference],
        perFaceOverrides: [FaceThicknessOverride] = [],
        jobId: JobId? = nil
    ) async -> KernelResult<MeshPayload> {
        let jobId = jobId ?? JobId("shell-\(UUID().uuidString)")
        guard thickness > 0 else {
            return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Shell thickness must be greater than zero"))
        }
        for override in perFaceOverrides {
            guard override.thickness > 0 else {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Face thickness override must be greater than zero"))
            }
        }
        let targetId = targetSolidId ?? solidId
        guard let shape = occtShapes[targetId] ?? occtShapes[solidId] else {
            return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid '\(targetId)' not found"))
        }
        do {
            let shelledShape = try OCCTEngine.shell(
                shape: shape,
                thickness: thickness,
                removedFaceReferences: removedFaceReferences,
                perFaceOverrides: perFaceOverrides
            )
            guard let payload = OCCTEngine.toMeshPayload(shelledShape) else {
                return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to tessellate shelled geometry"))
            }
            occtShapes[solidId] = shelledShape
            solids[solidId] = payload
            return .success(jobId: jobId, value: payload)
        } catch let kernelError as KernelError {
            return .failure(jobId: jobId, error: kernelError)
        } catch {
            return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Shell failed: \(error)"))
        }
    }

    public func hole(
        solidId: SolidId,
        targetSolidId: SolidId,
        faceReference: TopologicalReference,
        holeData: HoleFeatureData,
        jobId: JobId? = nil
    ) async -> KernelResult<MeshPayload> {
        let jobId = jobId ?? JobId("hole-\(UUID().uuidString)")
        guard holeData.diameter > 0 else {
            return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Hole diameter must be positive"))
        }
        if !holeData.isThrough {
            guard holeData.depth > 0 else {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Hole depth must be positive"))
            }
        }
        if holeData.standard != .custom {
            guard let designation = holeData.sizeDesignation, HoleStandards.lookup(standard: holeData.standard, designation: designation) != nil else {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Unknown standard hole size: \(holeData.sizeDesignation ?? "none")"))
            }
        }

        let targetId = targetSolidId
        guard let shape = occtShapes[targetId] ?? occtShapes[solidId] else {
            return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Solid '\(targetId)' not found"))
        }

        let face: Face
        do {
            face = try TopologicalResolver.resolveFace(in: shape, reference: faceReference)
        } catch let kernelError as KernelError {
            return .failure(jobId: jobId, error: kernelError)
        } catch {
            return .failure(jobId: jobId, error: KernelError(code: .topologicalReferenceBroken, message: "Failed to resolve face: \(error)"))
        }

        guard face.isPlanar, let faceNormal = face.normal else {
            return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Hole target face must be planar"))
        }

        let n = simd_normalize(faceNormal)
        let centerOfMass = face.surfaceInertia.centerOfMass ?? SIMD3<Double>.zero
        let xAxis: SIMD3<Double>
        if abs(n.z) < 0.9 {
            xAxis = simd_normalize(simd_cross(n, SIMD3<Double>(0, 0, 1)))
        } else {
            xAxis = simd_normalize(simd_cross(n, SIMD3<Double>(0, 1, 0)))
        }
        let yAxis = simd_normalize(simd_cross(n, xAxis))
        let sketchPlane = SketchPlane(
            origin: SIMD3<Float>(Float(centerOfMass.x), Float(centerOfMass.y), Float(centerOfMass.z)),
            normal: SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z)),
            xAxis: SIMD3<Float>(Float(xAxis.x), Float(xAxis.y), Float(xAxis.z))
        )

        var cutDiameter = holeData.diameter
        var cbDia = holeData.counterboreDiameter
        var cbDepth = holeData.counterboreDepth
        var csDia = holeData.countersinkDiameter
        var csAngle = holeData.countersinkAngle

        if holeData.standard != .custom, let designation = holeData.sizeDesignation, let stdSize = HoleStandards.lookup(standard: holeData.standard, designation: designation) {
            switch holeData.holeType {
            case .simple:
                if cutDiameter <= 0 { cutDiameter = stdSize.normalClearanceDiameter }
            case .counterbore:
                if cutDiameter <= 0 { cutDiameter = stdSize.normalClearanceDiameter }
                if cbDia <= 0 { cbDia = stdSize.counterboreDiameter }
                if cbDepth <= 0 { cbDepth = stdSize.counterboreDepth }
            case .countersink:
                if cutDiameter <= 0 { cutDiameter = stdSize.normalClearanceDiameter }
                if csDia <= 0 { csDia = stdSize.countersinkDiameter }
                if csAngle <= 0 { csAngle = stdSize.countersinkAngle }
            case .tapped:
                cutDiameter = stdSize.tapDrillDiameter
            }
        }

        var maxRadius = cutDiameter / 2.0
        if holeData.holeType == .counterbore && cbDia > 0 {
            maxRadius = max(maxRadius, cbDia / 2.0)
        }
        if holeData.holeType == .countersink && csDia > 0 {
            maxRadius = max(maxRadius, csDia / 2.0)
        }

        let points = holeData.points.isEmpty ? [SIMD2<Double>(0, 0)] : holeData.points
        let faceEdges = Shape.fromFace(face)?.edges() ?? []

        var workingShape = shape

        for pt in points {
            let centerF = sketchPlane.unprojectPoint(pt)
            let center = SIMD3<Double>(Double(centerF.x), Double(centerF.y), Double(centerF.z))

            // 1. Center must be inside the face
            if face.classify(point: center, tolerance: 1e-4) != .inside {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Hole breaks through body edge"))
            }

            // 2. Minimum distance from center to any edge of the face must exceed maxRadius
            for edge in faceEdges {
                if let d = edge.distance(to: center) {
                    if d <= maxRadius + 1e-4 {
                        return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Hole breaks through body edge"))
                    }
                }
            }

            // 3. Sample points on the circle perimeter must be inside the face
            let sampleCount = 36
            for i in 0..<sampleCount {
                let angle = Double(i) * 2.0 * .pi / Double(sampleCount)
                let radialOffset = cos(angle) * xAxis + sin(angle) * yAxis
                let samplePoint = center + maxRadius * radialOffset
                if face.classify(point: samplePoint, tolerance: 1e-4) == .outside {
                    return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Hole breaks through body edge"))
                }
            }

            // 4. Blind hole depth vs body thickness check
            let forwardHits = shape.intersectLine(origin: center, direction: -n).filter { $0.parameter > 1e-4 }
            let bodyThickness: Double
            if let minHit = forwardHits.map({ $0.parameter }).min() {
                bodyThickness = minHit
            } else if let (bMin, bMax) = shape.bounds {
                let ext = bMax - bMin
                bodyThickness = max(ext.x, max(ext.y, ext.z))
            } else {
                bodyThickness = 100.0
            }

            if !holeData.isThrough && holeData.depth > bodyThickness + 1e-4 {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Blind hole depth exceeds body thickness. Choose Through All to cut through the body."))
            }

            // 5. Build cutter solid
            let cutDepth = holeData.isThrough ? (bodyThickness + 2.0) : holeData.depth
            let cutterOrigin = center + n * 0.1
            let cutterDir = -n
            let mainRadius = cutDiameter / 2.0

            let cutter: Shape
            switch holeData.holeType {
            case .simple, .tapped:
                guard var cyl = Shape.cylinder(at: cutterOrigin, direction: cutterDir, radius: mainRadius, height: cutDepth + 0.1) else {
                    return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to construct cylinder cutter"))
                }
                if let tipAngle = holeData.drillTipAngle, !holeData.isThrough, tipAngle > 0 {
                    let halfAngle = (tipAngle / 2.0) * .pi / 180.0
                    let tipHeight = mainRadius / tan(halfAngle)
                    let tipOrigin = center + cutterDir * cutDepth
                    if let tipCone = Shape.cone(at: tipOrigin, direction: cutterDir, bottomRadius: mainRadius, topRadius: 0.001, height: tipHeight) {
                        cyl = cyl.union(tipCone) ?? cyl
                    }
                }
                cutter = cyl

            case .counterbore:
                let cbActualDepth = cbDepth > 0 ? cbDepth : min(5.0, cutDepth / 2.0)
                let cbActualDia = cbDia > 0 ? cbDia : mainRadius * 2.0 * 1.5
                guard let cbCyl = Shape.cylinder(at: cutterOrigin, direction: cutterDir, radius: cbActualDia / 2.0, height: cbActualDepth + 0.1),
                      let mainCyl = Shape.cylinder(at: cutterOrigin, direction: cutterDir, radius: mainRadius, height: cutDepth + 0.1) else {
                    return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to construct counterbore cutter"))
                }
                cutter = cbCyl.union(mainCyl) ?? mainCyl

            case .countersink:
                let csActualDia = csDia > 0 ? csDia : mainRadius * 2.0 * 1.5
                let csActualAngle = csAngle > 0 ? csAngle : 90.0
                let halfAngle = (csActualAngle / 2.0) * .pi / 180.0
                let csRadius = csActualDia / 2.0
                let csHeight = max(0.1, (csRadius - mainRadius) / tan(halfAngle))
                let csTopRadius = csRadius + 0.1 * tan(halfAngle)
                guard let csCone = Shape.cone(at: cutterOrigin, direction: cutterDir, bottomRadius: csTopRadius, topRadius: mainRadius, height: csHeight + 0.1),
                      let mainCyl = Shape.cylinder(at: cutterOrigin, direction: cutterDir, radius: mainRadius, height: cutDepth + 0.1) else {
                    return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to construct countersink cutter"))
                }
                cutter = csCone.union(mainCyl) ?? mainCyl
            }

            guard let cutResult = workingShape.subtracting(cutter) else {
                return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to subtract hole cutter from solid"))
            }
            workingShape = cutResult
        }

        guard let payload = OCCTEngine.toMeshPayload(workingShape) else {
            return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to tessellate hole geometry"))
        }
        occtShapes[solidId] = workingShape
        solids[solidId] = payload

        if let baseEuclid = euclidMeshes[targetId] ?? euclidMeshes[solidId] {
            let cylMesh = EuclidEngine.makeCylinder(radius: Float(maxRadius), height: Float(holeData.isThrough ? 100.0 : holeData.depth))
            let sub = EuclidEngine.subtract(baseEuclid, cylMesh)
            euclidMeshes[solidId] = sub
        }

        return .success(jobId: jobId, value: payload)
    }

    private func pattern(
        solidId: SolidId,
        params: PatternParams,
        jobId: JobId
    ) async -> KernelResult<MeshPayload> {
        guard params.count >= 1 else {
            return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Pattern count must be at least 1"))
        }

        if params.patternType == .linear {
            guard params.linearSpacing > 0 else {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Pattern linear spacing must be positive"))
            }
            guard simd_length(params.linearDirection) > 1e-6 else {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Pattern linear direction must not be zero"))
            }
        } else if params.patternType == .circular {
            guard params.totalAngle > 0 else {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Pattern total angle must be positive"))
            }
            guard simd_length(params.axisDirection) > 1e-6 else {
                return .failure(jobId: jobId, error: KernelError(code: .invalidParams, message: "Pattern axis direction must not be zero"))
            }
        }

        let targetId = params.targetSolidId
        guard let baseShape = occtShapes[targetId] ?? occtShapes[solidId] else {
            return .failure(jobId: jobId, error: KernelError(code: .unknownSolid, message: "Unknown solid: \(targetId.rawValue)"))
        }

        var shapes: [Shape] = []
        for i in 0..<params.count {
            if params.count > 1 && params.skippedIndices.contains(i) {
                continue
            }

            let transform: Transform
            if i == 0 {
                transform = .identity
            } else {
                switch params.patternType {
                case .linear:
                    let dir = simd_normalize(SIMD3<Float>(params.linearDirection))
                    let offset = dir * Float(params.linearSpacing * Double(i))
                    transform = Transform(position: offset)
                case .circular:
                    let angularStep: Double
                    if params.isFullCircle || params.totalAngle >= 360.0 {
                        angularStep = 360.0 / Double(params.count)
                    } else {
                        angularStep = params.totalAngle / Double(Swift.max(1, params.count - 1))
                    }
                    let instanceAngle = Double(i) * angularStep
                    let rad = Float(instanceAngle * .pi / 180.0)
                    let axisDir = simd_normalize(SIMD3<Float>(params.axisDirection))
                    let quat = simd_quatf(angle: rad, axis: axisDir)
                    let origin = SIMD3<Float>(params.axisOrigin)
                    let position = origin - quat.act(origin)
                    transform = Transform(position: position, rotation: quat)
                }
            }

            guard let instShape = (transform == .identity) ? baseShape : OCCTEngine.transformed(baseShape, by: transform) else {
                return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to transform pattern instance \(i)"))
            }

            if let baseBodyId = params.baseBodySolidId,
               let baseBodyShape = occtShapes[baseBodyId],
               let bodyBB = baseBodyShape.boundingBox,
               let instBB = instShape.boundingBox {
                let eps = 1e-3
                let isInside = instBB.min.x >= bodyBB.min.x - eps &&
                               instBB.max.x <= bodyBB.max.x + eps &&
                               instBB.min.y >= bodyBB.min.y - eps &&
                               instBB.max.y <= bodyBB.max.y + eps &&
                               instBB.min.z >= bodyBB.min.z - eps &&
                               instBB.max.z <= bodyBB.max.z + eps
                if !isInside {
                    continue
                }
            }

            shapes.append(instShape)
        }

        if shapes.isEmpty {
            shapes.append(baseShape)
        }

        let workingShape: Shape
        if shapes.count == 1 {
            workingShape = shapes[0]
        } else {
            guard let compound = Shape.compound(shapes) else {
                return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to compound pattern instances"))
            }
            workingShape = compound
        }

        guard let payload = OCCTEngine.toMeshPayload(workingShape) else {
            return .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Failed to tessellate pattern geometry"))
        }

        occtShapes[solidId] = workingShape
        solids[solidId] = payload
        return .success(jobId: jobId, value: payload)
    }

    public func dispose(solidId: SolidId) async {
        solids.removeValue(forKey: solidId)
        euclidMeshes.removeValue(forKey: solidId)
        occtShapes.removeValue(forKey: solidId)
    }
    
    /// An in-process job cannot be interrupted.
    public func terminate(jobId: JobId) async -> Bool { false }
    
    /// The in-process cache is never lost on its own.
    public nonisolated func restarts() -> AsyncStream<KernelRestart> {
        AsyncStream { $0.finish() }
    }
    
    public func storeCounts() async -> KernelEngineCounts {
        KernelEngineCounts(solids: solids.count, euclidMeshes: euclidMeshes.count, occtShapes: occtShapes.count)
    }
}
