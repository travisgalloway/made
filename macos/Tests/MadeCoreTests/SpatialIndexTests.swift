import Testing
import Foundation
import Metal
import simd
@testable import MadeCore

@Suite struct SpatialIndexTests {

    // MARK: - 1. Incremental Lifecycle

    @Test func testCandidateMeshRetainsSpatialIndexOnTransformUpdate() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        var mesh = CandidateMesh(id: SolidId("box-lifecycle"), payload: boxPayload)
        
        let initialIndex = mesh.spatialIndex
        #expect(initialIndex != nil)
        
        let newTransform = Transform(
            position: SIMD3<Float>(10, -5, 25),
            rotation: simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(0, 0, 1)),
            scale: SIMD3<Float>(1.5, 1.5, 1.5)
        )
        mesh.transform = newTransform
        
        // Assert reference identity: zero rebuild across rigid transform updates
        #expect(mesh.spatialIndex === initialIndex)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    @MainActor
    func testBVHLifecycleBuildOnInstallAndRetainedOnUpdateTransform() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        let solidId = SolidId("box-render-lifecycle")
        let payload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let installed = renderer.installMesh(payload, for: solidId, transform: .identity, color: SIMD4<Float>(0.5, 0.5, 0.5, 1.0), isHidden: false)
        #expect(installed)

        let initialMesh = try #require(renderer.meshes[solidId])
        let initialIndex = try #require(initialMesh.spatialIndex)
        #expect(initialMesh.candidateMesh.spatialIndex === initialIndex)

        let updatedTransform = Transform(position: SIMD3<Float>(50, 0, 0))
        let updated = renderer.updateTransform(updatedTransform, for: solidId)
        #expect(updated)

        let updatedMesh = try #require(renderer.meshes[solidId])
        let updatedIndex = try #require(updatedMesh.spatialIndex)

        // Must retain exact spatial index reference identity (===)
        #expect(updatedIndex === initialIndex)
        #expect(updatedMesh.candidateMesh.spatialIndex === initialIndex)
    }

    // MARK: - 2. Raycast Picking Parity

    @Test func testTriangleBVHRaycastMatchesBruteForce() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 30, depth: 40, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-raycast"), payload: boxPayload)
        let bvh = try! #require(mesh.spatialIndex?.triangleBVH)

        // Test rays from various angles aiming at the box
        let testOrigins: [SIMD3<Float>] = [
            SIMD3<Float>(0, -50, 0),
            SIMD3<Float>(0, 50, 0),
            SIMD3<Float>(-50, 0, 0),
            SIMD3<Float>(50, 0, 0),
            SIMD3<Float>(0, 0, 50),
            SIMD3<Float>(0, 0, -50),
            SIMD3<Float>(25, 25, 50),
            SIMD3<Float>(-20, -30, 40)
        ]

        for orig in testOrigins {
            let target = SIMD3<Float>(0, 0, 0)
            let dir = simd_normalize(target - orig)
            let ray = Ray3D(origin: orig, direction: dir)

            let bvhHit = bvh.raycast(ray: ray)

            // Brute-force scan over all triangles
            var bruteHitDist: Float = .greatestFiniteMagnitude
            var bruteHitPoint: SIMD3<Float>? = nil
            var bruteFaceId: Int? = nil

            let triCount = mesh.indices.count / 3
            for t in 0..<triCount {
                let v0 = mesh.positions[Int(mesh.indices[t * 3])]
                let v1 = mesh.positions[Int(mesh.indices[t * 3 + 1])]
                let v2 = mesh.positions[Int(mesh.indices[t * 3 + 2])]

                let e1 = v1 - v0
                let e2 = v2 - v0
                let h = simd_cross(ray.direction, e2)
                let a = simd_dot(e1, h)
                if abs(a) < 1e-7 { continue }
                let f = 1.0 / a
                let s = ray.origin - v0
                let u = f * simd_dot(s, h)
                if u < 0.0 || u > 1.0 { continue }
                let q = simd_cross(s, e1)
                let v = f * simd_dot(ray.direction, q)
                if v < 0.0 || u + v > 1.0 { continue }
                let dist = f * simd_dot(e2, q)
                if dist > 1e-4 && dist < bruteHitDist {
                    bruteHitDist = dist
                    bruteHitPoint = ray.origin + ray.direction * dist
                    let fr = mesh.faceRanges.first(where: { $0.triangleRange.contains(t) })
                    bruteFaceId = fr?.faceId ?? 0
                }
            }

            #expect((bvhHit != nil) == (bruteHitPoint != nil))
            if let bHit = bvhHit, let bPoint = bruteHitPoint {
                #expect(abs(bHit.distance - bruteHitDist) < 1e-4)
                #expect(simd_distance(bHit.hitPoint, bPoint) < 1e-4)
                #expect(bHit.faceId == bruteFaceId)
            }
        }
    }

    // MARK: - 3. Snap Candidate Parity

    @Test func testSnapCandidateParity() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-snap-parity"), payload: boxPayload)
        let spatialIndex = try! #require(mesh.spatialIndex)

        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(
            eye: SIMD3<Float>(30, -50, 40),
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 0, 1)
        )
        let projMatrix = Orientation.makePerspective(
            fovyRadians: .pi / 4,
            aspect: 800.0 / 600.0,
            nearZ: 0.1,
            farZ: 500.0
        )
        let vp = projMatrix * viewMatrix

        // Test corners (vertices + edges) and edge midpoints
        let cornerPoints: [SIMD3<Float>] = [
            SIMD3<Float>(10, 10, 10),
            SIMD3<Float>(-10, -10, -10)
        ]
        let edgeMidpoints: [SIMD3<Float>] = [
            SIMD3<Float>(0, 10, 10),
            SIMD3<Float>(10, 0, -10)
        ]

        for pt in cornerPoints {
            guard let screenPt = projectToScreen(point: pt, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                continue
            }
            let vCands = spatialIndex.vertexBVH.querySnapCandidates(
                pointer: screenPt,
                tolerancePx: 20.0,
                vp: vp,
                viewportSize: viewportSize,
                transform: mesh.transform
            )
            let eCands = spatialIndex.edgeBVH.querySnapCandidates(
                pointer: screenPt,
                tolerancePx: 20.0,
                vp: vp,
                viewportSize: viewportSize,
                transform: mesh.transform
            )
            #expect(!vCands.isEmpty)
            #expect(!eCands.isEmpty)
        }

        for pt in edgeMidpoints {
            guard let screenPt = projectToScreen(point: pt, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
                continue
            }
            let eCands = spatialIndex.edgeBVH.querySnapCandidates(
                pointer: screenPt,
                tolerancePx: 20.0,
                vp: vp,
                viewportSize: viewportSize,
                transform: mesh.transform
            )
            #expect(!eCands.isEmpty)
        }
    }

    // MARK: - 4. 1M-Triangle Performance Benchmark (< 2.0 ms)

    @Test func testSnapCandidateSearch1MTrianglesUnder2ms() {
        // Construct a regular grid mesh of 709 x 709 vertices
        // (708 * 708 * 2 = 1,002,528 triangles)
        let gridDim = 709
        let vertexCount = gridDim * gridDim
        let quadCount = (gridDim - 1) * (gridDim - 1)
        let triangleCount = quadCount * 2

        #expect(triangleCount > 1_000_000)

        var rawPositions = [Float]()
        rawPositions.reserveCapacity(vertexCount * 3)
        let step: Float = 0.5
        for y in 0..<gridDim {
            for x in 0..<gridDim {
                rawPositions.append(Float(x) * step)
                rawPositions.append(Float(y) * step)
                rawPositions.append(0.0)
            }
        }

        var indices = [UInt32]()
        indices.reserveCapacity(triangleCount * 3)
        for y in 0..<(gridDim - 1) {
            for x in 0..<(gridDim - 1) {
                let v0 = UInt32(y * gridDim + x)
                let v1 = UInt32(y * gridDim + x + 1)
                let v2 = UInt32((y + 1) * gridDim + x)
                let v3 = UInt32((y + 1) * gridDim + x + 1)

                indices.append(contentsOf: [v0, v1, v2])
                indices.append(contentsOf: [v1, v3, v2])
            }
        }

        let mesh = CandidateMesh(
            id: SolidId("mesh-1m"),
            rawPositions: rawPositions,
            indices: indices
        )
        #expect(mesh.spatialIndex != nil)

        let viewportSize = CGSize(width: 800, height: 600)
        let eye = SIMD3<Float>(177, 177, 300)
        let target = SIMD3<Float>(177, 177, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 2000.0)

        let vp = projMatrix * viewMatrix
        let queryPoint = SIMD3<Float>(177, 177, 0)
        let screenPoint = projectToScreen(point: queryPoint, viewProjectionMatrix: vp, viewportSize: viewportSize)!

        // Warm up cache
        _ = SnapCandidateGenerator.generateCandidates(
            meshes: [mesh],
            pointer: screenPoint,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            tolerancePx: 20.0
        )

        // Measure candidate search execution time
        let iterations = 10
        let start = DispatchTime.now()
        for _ in 0..<iterations {
            let candidates = SnapCandidateGenerator.generateCandidates(
                meshes: [mesh],
                pointer: screenPoint,
                viewportSize: viewportSize,
                viewMatrix: viewMatrix,
                projectionMatrix: projMatrix,
                tolerancePx: 20.0
            )
            #expect(!candidates.isEmpty)
        }
        let totalElapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000.0
        let averageElapsedSeconds = totalElapsed / Double(iterations)

        // Strictly < 2.0 ms (0.002 s) as mandated by plan & feature contract
        #expect(averageElapsedSeconds < 0.002, "Average query time \(averageElapsedSeconds * 1000.0) ms exceeded 2.0 ms limit")
    }

    // MARK: - 5. Interference Queries

    @Test func testInterferenceDetectionCollidingAndDisjoint() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let boxA = CandidateMesh(id: SolidId("box-a"), payload: boxPayload, transform: .identity)
        
        // Colliding box: overlapping along X by 10 units
        let boxB = CandidateMesh(id: SolidId("box-b"), payload: boxPayload, transform: Transform(position: SIMD3<Float>(10, 0, 0)))
        #expect(checkInterference(meshA: boxA, meshB: boxB))

        let pairs = findInterference(meshA: boxA, meshB: boxB)
        #expect(!pairs.isEmpty)

        // Disjoint box: 100 units away along X
        let boxC = CandidateMesh(id: SolidId("box-c"), payload: boxPayload, transform: Transform(position: SIMD3<Float>(100, 0, 0)))

        let start = DispatchTime.now()
        let collides = checkInterference(meshA: boxA, meshB: boxC)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000.0

        #expect(!collides)
        #expect(elapsed < 0.001) // microsecond broad-phase rejection
        #expect(findInterference(meshA: boxA, meshB: boxC).isEmpty)
    }

    // MARK: - 6. Measurement Queries

    @Test func testMeasurementClosestPointAndDistance() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let box = CandidateMesh(id: SolidId("box-measure"), payload: boxPayload, transform: .identity)

        // Point directly above top face (Z = 10)
        let testPointAbove = SIMD3<Float>(0, 0, 35)
        let resultAbove = closestPointOnMesh(to: testPointAbove, in: box)
        #expect(resultAbove != nil)
        if let res = resultAbove {
            #expect(abs(res.distance - 25.0) < 1e-4)
            #expect(simd_distance(res.point, SIMD3<Float>(0, 0, 10)) < 1e-4)
            if let normal = res.normal {
                #expect(simd_distance(normal, SIMD3<Float>(0, 0, 1)) < 1e-4)
            }
        }

        // Distance between two separated boxes: Box at (0, 0, 0) and Box at (40, 0, 0), sizes 20x20x20
        // Box 1 X range [-10, 10], Box 2 X range [30, 50]. Minimum distance is 20.0
        let boxSeparated = CandidateMesh(
            id: SolidId("box-sep"),
            payload: boxPayload,
            transform: Transform(position: SIMD3<Float>(40, 0, 0))
        )
        let dist = distanceBetweenMeshes(box, boxSeparated)
        #expect(abs(dist - 20.0) < 1e-4)

        // Distance between colliding boxes is 0.0
        let boxOverlap = CandidateMesh(
            id: SolidId("box-over"),
            payload: boxPayload,
            transform: Transform(position: SIMD3<Float>(15, 0, 0))
        )
        #expect(distanceBetweenMeshes(box, boxOverlap) == 0.0)
    }

    // MARK: - 7. Edge Cases

    @Test func testEdgeCasesEmptyMeshAndDegenerateGeometry() {
        // Empty mesh
        let emptyMesh = CandidateMesh(id: SolidId("empty"), positions: [], edges: [])
        #expect(emptyMesh.spatialIndex == nil)
        #expect(!checkInterference(meshA: emptyMesh, meshB: emptyMesh))
        #expect(closestPointOnMesh(to: SIMD3<Float>(0, 0, 0), in: emptyMesh) == nil)
        #expect(distanceBetweenMeshes(emptyMesh, emptyMesh) == .greatestFiniteMagnitude)

        // Mesh without edges (isolated vertices)
        let verticesOnly = CandidateMesh(
            id: SolidId("verts-only"),
            positions: [SIMD3<Float>(1, 2, 3), SIMD3<Float>(4, 5, 6)],
            edges: []
        )
        #expect(verticesOnly.spatialIndex != nil)
        #expect(verticesOnly.spatialIndex?.edgeBVH.primitives.isEmpty == true)
        #expect(verticesOnly.spatialIndex?.vertexBVH.primitives.count == 2)

        // Degenerate zero-area triangles (all vertices coincident)
        let degenMesh = CandidateMesh(
            id: SolidId("degen"),
            rawPositions: [
                0, 0, 0,   0, 0, 0,   0, 0, 0,
                10, 10, 10, 10, 10, 10, 10, 10, 10
            ],
            indices: [0, 1, 2, 3, 4, 5]
        )
        #expect(degenMesh.spatialIndex != nil)
        let ray = Ray3D(origin: SIMD3<Float>(0, -10, 0), direction: SIMD3<Float>(0, 1, 0))
        #expect(degenMesh.spatialIndex?.triangleBVH.raycast(ray: ray) == nil)

        // Behind-camera geometry projection
        let behindPoint = SIMD3<Float>(0, -50, 0)
        let aabbBehind = AABB(point: behindPoint)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(0, -10, 0), target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4, aspect: 1.0, nearZ: 1.0, farZ: 100.0)
        let vp = projMatrix * viewMatrix
        let screenBounds = aabbBehind.projectedScreenBounds(viewProjectionMatrix: vp, viewportSize: CGSize(width: 800, height: 600))
        #expect(screenBounds == nil)
    }
}
