import Foundation
import Euclid
import OCCTSwift

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
