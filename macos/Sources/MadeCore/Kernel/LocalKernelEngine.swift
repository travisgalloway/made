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
            
        case .tessellate(_, let sId):
            if let existing = solids[sId] {
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

    public func fillet(solidId: SolidId, edgeReference: TopologicalReference, radius: Double) async -> KernelResult<MeshPayload> {
        let jobId = JobId("fillet-\(UUID().uuidString)")
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
