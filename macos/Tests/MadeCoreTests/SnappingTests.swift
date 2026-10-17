import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SnappingTests {
    @Test func testGridSnapRoundsXYAndPreservesZ() {
        let input = SIMD3<Float>(14.2, 26.8, 5.5)
        let snapped = snapToGrid(input, spacing: 10.0)
        
        #expect(snapped.x == 10.0)
        #expect(snapped.y == 30.0)
        #expect(snapped.z == 5.5)
    }
    
    @Test func testPriorityVertexBeatsCloserEdgeAndGrid() {
        let vertexCandidate = SnapCandidate(
            kind: .vertex,
            point: SIMD3<Float>(10, 10, 0),
            screenDistancePx: 15.0 // Further, but higher priority
        )
        let edgeCandidate = SnapCandidate(
            kind: .edge,
            point: SIMD3<Float>(12, 10, 0),
            screenDistancePx: 8.0 // Closer, but lower priority
        )
        let gridCandidate = SnapCandidate(
            kind: .grid,
            point: SIMD3<Float>(0, 0, 0),
            screenDistancePx: 2.0 // Closest, but lowest priority
        )
        
        let result = resolveSnap(candidates: [gridCandidate, edgeCandidate, vertexCandidate], tolerancePx: 20.0)
        
        #expect(result != nil)
        #expect((result?.kind) == .vertex)
        #expect((result?.point) == (SIMD3<Float>(10, 10, 0)))
    }
    
    @Test func testEdgeBeatsCloserGrid() {
        let edgeCandidate = SnapCandidate(
            kind: .edge,
            point: SIMD3<Float>(5, 5, 0),
            screenDistancePx: 12.0
        )
        let gridCandidate = SnapCandidate(
            kind: .grid,
            point: SIMD3<Float>(0, 0, 0),
            screenDistancePx: 4.0
        )
        
        let result = resolveSnap(candidates: [gridCandidate, edgeCandidate], tolerancePx: 20.0)
        
        #expect(result != nil)
        #expect((result?.kind) == .edge)
        #expect((result?.point) == (SIMD3<Float>(5, 5, 0)))
    }
    
    @Test func testCandidateBeyondToleranceIsIgnored() {
        let candidate = SnapCandidate(
            kind: .vertex,
            point: SIMD3<Float>(10, 10, 0),
            screenDistancePx: 25.0 // Exceeds tolerance of 20
        )
        
        let result = resolveSnap(candidates: [candidate], tolerancePx: 20.0)
        #expect(result == nil)
    }
    
    @Test func testEmptyCandidateListReturnsNoSnap() {
        let result = resolveSnap(candidates: [], tolerancePx: 20.0)
        #expect(result == nil)
    }
    
    @Test func testEqualPriorityCandidatesResolveByDistance() {
        let v1 = SnapCandidate(kind: .vertex, point: SIMD3<Float>(1, 0, 0), screenDistancePx: 14.0)
        let v2 = SnapCandidate(kind: .vertex, point: SIMD3<Float>(2, 0, 0), screenDistancePx: 6.0)
        let v3 = SnapCandidate(kind: .vertex, point: SIMD3<Float>(3, 0, 0), screenDistancePx: 18.0)
        
        let winner = resolveSnap(candidates: [v1, v2, v3], tolerancePx: 20.0)
        #expect(winner != nil)
        #expect((winner?.kind) == .vertex)
        #expect((winner?.point) == (SIMD3<Float>(2, 0, 0)))
    }
    
    @Test func testCandidateAtExactToleranceBoundaryIsIncluded() {
        let candidate = SnapCandidate(kind: .vertex, point: SIMD3<Float>(5, 5, 0), screenDistancePx: 20.0)
        let result = resolveSnap(candidates: [candidate], tolerancePx: 20.0)
        #expect(result != nil)
        #expect((result?.point) == (SIMD3<Float>(5, 5, 0)))
    }
    
    @Test func testCandidateJustBeyondToleranceIsExcluded() {
        let candidate = SnapCandidate(kind: .vertex, point: SIMD3<Float>(5, 5, 0), screenDistancePx: 20.01)
        let result = resolveSnap(candidates: [candidate], tolerancePx: 20.0)
        #expect(result == nil)
    }
    
    @Test func testNegativeCoordinatesAndHalfPitchTies() {
        let snapped1 = snapToGrid(SIMD3<Float>(-14.9, -15.1, 0), spacing: 10.0)
        #expect(snapped1.x == (-10.0))
        #expect(snapped1.y == (-20.0))
        
        // Ensure -0.0 is cleanly converted to 0.0
        let nearZero = snapToGrid(SIMD3<Float>(-0.0001, 0.0001, 0), spacing: 10.0)
        #expect(nearZero.x == 0.0)
        #expect(nearZero.y == 0.0)
        #expect(!(nearZero.x.sign == .minus))
        #expect(!(nearZero.y.sign == .minus))
        
        // Half-pitch behavior
        let half = snapToGrid(SIMD3<Float>(15.0, -25.0, 0), spacing: 10.0)
        #expect(half.x == 20.0)
        #expect(half.y == (-30.0))
    }
    
    @Test func testClosestPointOnSegment() {
        let p1 = SIMD3<Float>(0, 0, 0)
        let p2 = SIMD3<Float>(10, 0, 0)
        let s1 = SIMD2<Float>(0, 100)
        let s2 = SIMD2<Float>(100, 100)
        
        // 1. Pointer midway between ends
        let pointerMid = SIMD2<Float>(50, 105)
        let resMid = closestPointOnSegment(p1: p1, p2: p2, s1: s1, s2: s2, screenPointer: pointerMid)
        #expect(abs(resMid.worldPoint.x - 5.0) <= 1e-4)
        #expect(abs(resMid.worldPoint.y - 0.0) <= 1e-4)
        #expect(abs(resMid.screenDistancePx - 5.0) <= 1e-4)
        
        // 2. Pointer clamped before start
        let pointerBefore = SIMD2<Float>(-20, 100)
        let resBefore = closestPointOnSegment(p1: p1, p2: p2, s1: s1, s2: s2, screenPointer: pointerBefore)
        #expect(resBefore.worldPoint == p1)
        #expect(abs(resBefore.screenDistancePx - 20.0) <= 1e-4)
        
        // 3. Pointer clamped after end
        let pointerAfter = SIMD2<Float>(120, 100)
        let resAfter = closestPointOnSegment(p1: p1, p2: p2, s1: s1, s2: s2, screenPointer: pointerAfter)
        #expect(resAfter.worldPoint == p2)
        #expect(abs(resAfter.screenDistancePx - 20.0) <= 1e-4)
        
        // 4. Degenerate zero-length segment
        let resDegen = closestPointOnSegment(p1: p1, p2: p1, s1: s1, s2: s1, screenPointer: pointerMid)
        #expect(resDegen.worldPoint == p1)
    }
    
    @Test func testCandidateGenerationFromBoxMesh() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-1"), payload: boxPayload)
        
        #expect(mesh.positions.count == 24)
        let uniquePositions = Set(mesh.positions.map { "\($0.x),\($0.y),\($0.z)" })
        #expect(uniquePositions.count == 8)
        #expect(!mesh.edges.isEmpty)
        
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(
            eye: SIMD3<Float>(0, -60, 60),
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 0, 1)
        )
        let projMatrix = Orientation.makePerspective(
            fovyRadians: 45.0 * Float.pi / 180.0,
            aspect: 800.0 / 600.0,
            nearZ: 0.1,
            farZ: 500.0
        )
        let vp = projMatrix * viewMatrix
        
        // Project a corner vertex to screen and query candidates near it
        let testCorner = SIMD3<Float>(10, -10, 10)
        guard let screenCorner = projectToScreen(point: testCorner, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
            Issue.record("Failed to project corner vertex to screen")
            return
        }
        
        let candidates = SnapCandidateGenerator.generateCandidates(
            meshes: [mesh],
            pointer: screenCorner,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )
        
        #expect(!candidates.isEmpty)
        let hasVertexSnap = candidates.contains { $0.kind == .vertex && simd_distance($0.point, testCorner) < 1e-4 }
        #expect(hasVertexSnap)
    }
    
    @Test func testCandidateGenerationFromCylinderMesh() {
        let cylPayload = NativeGeometryGenerator.generateCylinder(radius: 10, height: 20, segments: 16)
        let mesh = CandidateMesh(id: SolidId("cyl-1"), payload: cylPayload)
        
        #expect(!mesh.positions.isEmpty)
        #expect(!mesh.edges.isEmpty)
    }
    
    @Test func testMeshTransformAffectsCandidatePositions() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 10, depth: 10, height: 10)
        var mesh = CandidateMesh(id: SolidId("box-transform"), payload: boxPayload)
        let translation = SIMD3<Float>(40, 0, 0)
        mesh.transform = Transform(position: translation)
        
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(
            eye: SIMD3<Float>(40, -50, 50),
            target: SIMD3<Float>(40, 0, 0),
            up: SIMD3<Float>(0, 0, 1)
        )
        let projMatrix = Orientation.makePerspective(
            fovyRadians: 45.0 * Float.pi / 180.0,
            aspect: 800.0 / 600.0,
            nearZ: 0.1,
            farZ: 500.0
        )
        let vp = projMatrix * viewMatrix
        
        // Expected transformed corner
        let expectedCorner = SIMD3<Float>(45, -5, 5)
        guard let screenPos = projectToScreen(point: expectedCorner, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
            Issue.record("Failed to project transformed corner")
            return
        }
        
        let candidates = SnapCandidateGenerator.generateCandidates(
            meshes: [mesh],
            pointer: screenPos,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )
        
        let transformedCandidate = candidates.first { $0.kind == .vertex && simd_distance($0.point, expectedCorner) < 1e-4 }
        #expect(transformedCandidate != nil)
    }
    
    @Test func testScreenPointToRayAndGroundPlaneIntersection() {
        let viewportSize = CGSize(width: 800, height: 600)
        let eye = SIMD3<Float>(0, -100, 100)
        let target = SIMD3<Float>(0, 0, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(
            fovyRadians: 45.0 * Float.pi / 180.0,
            aspect: 800.0 / 600.0,
            nearZ: 0.1,
            farZ: 500.0
        )
        
        let centerPointer = SIMD2<Float>(400, 300)
        guard let ray = screenPointToRay(screenPoint: centerPointer, viewportSize: viewportSize, viewMatrix: viewMatrix, projectionMatrix: projMatrix) else {
            Issue.record("Failed to compute ray for screen center")
            return
        }
        
        guard let groundHit = ray.intersectPlaneZZero() else {
            Issue.record("Expected ground plane intersection")
            return
        }
        
        #expect(abs(groundHit.x - 0.0) <= 1e-2)
        #expect(abs(groundHit.y - 0.0) <= 1e-2)
        #expect(abs(groundHit.z - 0.0) <= 1e-4)
        
        // Ray parallel to ground
        let parallelRay = Ray3D(origin: SIMD3<Float>(0, 0, 10), direction: SIMD3<Float>(1, 0, 0))
        #expect(parallelRay.intersectPlaneZZero() == nil)
        
        // Ray pointing upwards away from ground
        let upwardRay = Ray3D(origin: SIMD3<Float>(0, 0, 10), direction: SIMD3<Float>(0, 0, 1))
        #expect(upwardRay.intersectPlaneZZero() == nil)
    }
    
    @Test func testProjectToScreenRejectsBehindCamera() {
        let viewportSize = CGSize(width: 800, height: 600)
        let eye = SIMD3<Float>(0, 0, 50)
        let target = SIMD3<Float>(0, 0, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
        let projMatrix = Orientation.makePerspective(
            fovyRadians: 45.0 * Float.pi / 180.0,
            aspect: 800.0 / 600.0,
            nearZ: 0.1,
            farZ: 500.0
        )
        let vp = projMatrix * viewMatrix
        
        // Point at (0, 0, 100) is behind camera eye (0, 0, 50) when looking at (0, 0, 0)
        let behindPoint = SIMD3<Float>(0, 0, 100)
        let screen = projectToScreen(point: behindPoint, viewProjectionMatrix: vp, viewportSize: viewportSize)
        #expect(screen == nil)
    }
    
    @Test func testResolveSnapAtPointerEndToEnd() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box"), payload: boxPayload)
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(
            eye: SIMD3<Float>(0, -60, 60),
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 0, 1)
        )
        let projMatrix = Orientation.makePerspective(
            fovyRadians: 45.0 * Float.pi / 180.0,
            aspect: 800.0 / 600.0,
            nearZ: 0.1,
            farZ: 500.0
        )
        let vp = projMatrix * viewMatrix
        
        // 1. Pointer right on a vertex
        let corner = SIMD3<Float>(10, -10, 10)
        let screenCorner = projectToScreen(point: corner, viewProjectionMatrix: vp, viewportSize: viewportSize)!
        let vertexSnap = resolveSnapAtPointer(
            meshes: [mesh],
            pointer: screenCorner,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect((vertexSnap?.kind) == .vertex)
        #expect((vertexSnap?.point) == corner)
        
        // 2. Pointer on edge between (10, -10, 10) and (10, 10, 10) at y = 0
        let edgeMid = SIMD3<Float>(10, 0, 10)
        let screenEdgeMid = projectToScreen(point: edgeMid, viewProjectionMatrix: vp, viewportSize: viewportSize)!
        let edgeSnap = resolveSnapAtPointer(
            meshes: [mesh],
            pointer: screenEdgeMid,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect((edgeSnap?.kind) == .edge)
        #expect(abs((edgeSnap?.point.x ?? 0) - 10.0) <= 1e-3)
        #expect(abs((edgeSnap?.point.y ?? 0) - 0.0) <= 1e-3)
        #expect(abs((edgeSnap?.point.z ?? 0) - 10.0) <= 1e-3)
        
        // 3. Pointer far out on ground plane (Z = 0) near (31.0, 31.0, 0.0) -> snaps to (30, 30, 0)
        let groundPt = SIMD3<Float>(31.0, 31.0, 0.0)
        let screenGround = projectToScreen(point: groundPt, viewProjectionMatrix: vp, viewportSize: viewportSize)!
        let gridSnap = resolveSnapAtPointer(
            meshes: [mesh],
            pointer: screenGround,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect((gridSnap?.kind) == .grid)
        #expect((gridSnap?.point) == (SIMD3<Float>(30, 30, 0)))
    }
    
    @Test func testRemovingSolidDropsItsCandidates() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("box-to-remove"), payload: boxPayload)
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(
            eye: SIMD3<Float>(0, -60, 60),
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 0, 1)
        )
        let projMatrix = Orientation.makePerspective(
            fovyRadians: 45.0 * Float.pi / 180.0,
            aspect: 800.0 / 600.0,
            nearZ: 0.1,
            farZ: 500.0
        )
        let vp = projMatrix * viewMatrix
        
        let corner = SIMD3<Float>(10, -10, 10)
        let screenCorner = projectToScreen(point: corner, viewProjectionMatrix: vp, viewportSize: viewportSize)!
        
        var meshes = [mesh]
        let beforeRemoval = resolveSnapAtPointer(
            meshes: meshes,
            pointer: screenCorner,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect((beforeRemoval?.kind) == .vertex)
        
        // Remove solid from meshes
        meshes.removeAll { $0.id == SolidId("box-to-remove") }
        let afterRemoval = resolveSnapAtPointer(
            meshes: meshes,
            pointer: screenCorner,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect((afterRemoval?.kind) != .vertex)
    }

    @Test func testSnappingWithOrthographicProjection() {
        let viewportSize = CGSize(width: 800, height: 600)
        let eye = SIMD3<Float>(0, -100, 100)
        let target = SIMD3<Float>(0, 0, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: SIMD3<Float>(0, 0, 1))
        
        let aspect: Float = 800.0 / 600.0
        let dist = simd_length(eye - target)
        let halfH = dist * 0.4
        let halfW = halfH * aspect
        let projMatrix = Orientation.makeOrthographic(
            left: -halfW, right: halfW,
            bottom: -halfH, top: halfH,
            nearZ: 0.1, farZ: 1000.0
        )
        let vp = projMatrix * viewMatrix
        
        // 1. Ray unprojection and round-trip screen projection
        let testPointer = SIMD2<Float>(450, 320)
        let ray = screenPointToRay(
            screenPoint: testPointer,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect(ray != nil)
        guard let ray else { return }
        
        // Pick a point along the ray
        let pointAlongRay = ray.origin + ray.direction * 50.0
        let projectedScreen = projectToScreen(
            point: pointAlongRay,
            viewProjectionMatrix: vp,
            viewportSize: viewportSize
        )
        #expect(projectedScreen != nil)
        if let projectedScreen {
            #expect(abs(projectedScreen.x - testPointer.x) <= 1e-3)
            #expect(abs(projectedScreen.y - testPointer.y) <= 1e-3)
        }
        
        // 2. Snap candidate resolution under orthographic projection
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let mesh = CandidateMesh(id: SolidId("ortho-box"), payload: boxPayload)
        let corner = SIMD3<Float>(10, -10, 10)
        guard let screenCorner = projectToScreen(point: corner, viewProjectionMatrix: vp, viewportSize: viewportSize) else {
            Issue.record("Failed to project corner to screen")
            return
        }
        
        let snapResult = resolveSnapAtPointer(
            meshes: [mesh],
            pointer: screenCorner,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect(snapResult != nil)
        #expect(snapResult?.kind == .vertex)
        #expect(snapResult?.point == corner)
    }

    // MARK: - 2D Sketch Snapping & Priority Hierarchy Tests (BL-SKT-17)

    @Test func testSnapKindPriorityHierarchyOrder() {
        let sorted = SnapKind.allCases.sorted()
        #expect(sorted == [.endpoint, .vertex, .center, .intersection, .midpoint, .quadrant, .edge, .grid])
        
        #expect(SnapKind.endpoint < SnapKind.vertex)
        #expect(SnapKind.vertex < SnapKind.center)
        #expect(SnapKind.center < SnapKind.intersection)
        #expect(SnapKind.intersection < SnapKind.midpoint)
        #expect(SnapKind.midpoint < SnapKind.quadrant)
        #expect(SnapKind.quadrant < SnapKind.edge)
        #expect(SnapKind.edge < SnapKind.grid)
        
        #expect(SnapKind.endpoint.priority == 0)
        #expect(SnapKind.vertex.priority == 1)
        #expect(SnapKind.center.priority == 2)
        #expect(SnapKind.intersection.priority == 3)
        #expect(SnapKind.midpoint.priority == 4)
        #expect(SnapKind.quadrant.priority == 5)
        #expect(SnapKind.edge.priority == 6)
        #expect(SnapKind.grid.priority == 7)
    }

    @Test func testResolveSnapStrictPriorityAcrossAllKinds() {
        // Construct candidates where lower-priority kinds are physically closer on screen
        let candidates = [
            SnapCandidate(kind: .grid, point: SIMD3<Float>(0, 0, 0), screenDistancePx: 1.0),
            SnapCandidate(kind: .edge, point: SIMD3<Float>(1, 0, 0), screenDistancePx: 2.0),
            SnapCandidate(kind: .quadrant, point: SIMD3<Float>(2, 0, 0), screenDistancePx: 3.0),
            SnapCandidate(kind: .midpoint, point: SIMD3<Float>(3, 0, 0), screenDistancePx: 4.0),
            SnapCandidate(kind: .intersection, point: SIMD3<Float>(4, 0, 0), screenDistancePx: 5.0),
            SnapCandidate(kind: .center, point: SIMD3<Float>(5, 0, 0), screenDistancePx: 6.0),
            SnapCandidate(kind: .vertex, point: SIMD3<Float>(6, 0, 0), screenDistancePx: 7.0),
            SnapCandidate(kind: .endpoint, point: SIMD3<Float>(7, 0, 0), screenDistancePx: 8.0)
        ]
        
        // Endpoint (priority 0) must win even though distance is 8.0 vs 1.0 for grid
        let winner1 = resolveSnap(candidates: candidates, tolerancePx: 20.0)
        #expect(winner1?.kind == .endpoint)
        #expect(winner1?.point == SIMD3<Float>(7, 0, 0))

        // Remove endpoint -> vertex wins
        let winner2 = resolveSnap(candidates: candidates.filter { $0.kind != .endpoint }, tolerancePx: 20.0)
        #expect(winner2?.kind == .vertex)
        #expect(winner2?.point == SIMD3<Float>(6, 0, 0))

        // Remove vertex -> center wins
        let winner3 = resolveSnap(candidates: candidates.filter { $0.kind != .endpoint && $0.kind != .vertex }, tolerancePx: 20.0)
        #expect(winner3?.kind == .center)
        #expect(winner3?.point == SIMD3<Float>(5, 0, 0))

        // Remove center -> intersection wins
        let winner4 = resolveSnap(candidates: candidates.filter { $0.kind.priority >= 3 }, tolerancePx: 20.0)
        #expect(winner4?.kind == .intersection)
        #expect(winner4?.point == SIMD3<Float>(4, 0, 0))

        // Remove intersection -> midpoint wins
        let winner5 = resolveSnap(candidates: candidates.filter { $0.kind.priority >= 4 }, tolerancePx: 20.0)
        #expect(winner5?.kind == .midpoint)
        #expect(winner5?.point == SIMD3<Float>(3, 0, 0))

        // Remove midpoint -> quadrant wins
        let winner6 = resolveSnap(candidates: candidates.filter { $0.kind.priority >= 5 }, tolerancePx: 20.0)
        #expect(winner6?.kind == .quadrant)
        #expect(winner6?.point == SIMD3<Float>(2, 0, 0))

        // Remove quadrant -> edge wins
        let winner7 = resolveSnap(candidates: candidates.filter { $0.kind.priority >= 6 }, tolerancePx: 20.0)
        #expect(winner7?.kind == .edge)
        #expect(winner7?.point == SIMD3<Float>(1, 0, 0))

        // Remove edge -> grid wins
        let winner8 = resolveSnap(candidates: candidates.filter { $0.kind.priority >= 7 }, tolerancePx: 20.0)
        #expect(winner8?.kind == .grid)
        #expect(winner8?.point == SIMD3<Float>(0, 0, 0))
    }

    @Test func testRay3DPlaneIntersectionMath() {
        let ray = Ray3D(origin: SIMD3<Float>(0, 0, 50), direction: SIMD3<Float>(0, 0, -1))
        
        // 1. Ground plane Z = 0
        let hitGround = ray.intersectPlane(origin: .zero, normal: SIMD3<Float>(0, 0, 1))
        #expect(hitGround != nil)
        #expect(hitGround == SIMD3<Float>(0, 0, 0))

        // 2. SketchPlane offset in Z
        let offsetPlane = SketchPlane.xy.offset(20.0)
        let hitOffset = ray.intersectPlane(offsetPlane)
        #expect(hitOffset != nil)
        #expect(hitOffset == SIMD3<Float>(0, 0, 20))

        // 3. Parallel ray (direction perpendicular to normal) returns nil
        let parallelRay = Ray3D(origin: SIMD3<Float>(10, 20, 30), direction: SIMD3<Float>(1, 0, 0))
        #expect(parallelRay.intersectPlane(SketchPlane.xy) == nil)

        // 4. Ray pointing away from plane (t <= 0) returns nil
        let upwardRay = Ray3D(origin: SIMD3<Float>(0, 0, 10), direction: SIMD3<Float>(0, 0, 1))
        #expect(upwardRay.intersectPlane(SketchPlane.xy) == nil)
    }

    @Test func testGenerateSketchCandidatesEndpointsAndMidpoints() {
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(40, 0))
        let plane = SketchPlane.xy
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(20, -50, 50), target: SIMD3<Float>(20, 0, 0), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 500.0)
        let vp = projMatrix * viewMatrix

        // Query near midpoint (20, 0, 0)
        let midWorld = SIMD3<Float>(20, 0, 0)
        let screenMid = projectToScreen(point: midWorld, viewProjectionMatrix: vp, viewportSize: viewportSize)!
        
        let candidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [line],
            plane: plane,
            pointer: screenMid,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )

        let midpointCandidate = candidates.first { $0.kind == .midpoint }
        #expect(midpointCandidate != nil)
        #expect(midpointCandidate?.planePoint == SIMD2<Double>(20, 0))
        #expect(abs(midpointCandidate!.point.x - 20.0) <= 1e-4)

        // Query near endpoint (40, 0, 0)
        let endWorld = SIMD3<Float>(40, 0, 0)
        let screenEnd = projectToScreen(point: endWorld, viewProjectionMatrix: vp, viewportSize: viewportSize)!

        let endCandidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [line],
            plane: plane,
            pointer: screenEnd,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )

        let endCandidate = endCandidates.first { $0.kind == .endpoint }
        #expect(endCandidate != nil)
        #expect(endCandidate?.planePoint == SIMD2<Double>(40, 0))
    }

    @Test func testGenerateSketchCandidatesArcMidpointAndTrajectory() {
        // 90° arc from (10, 0) to (0, 10) centered at (0, 0), radius 10, counter-clockwise
        let arc = SketchEntity.arc(start: SIMD2<Double>(10, 0), end: SIMD2<Double>(0, 10), center: SIMD2<Double>(0, 0), clockwise: false)
        let plane = SketchPlane.xy
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(5, -40, 40), target: SIMD3<Float>(5, 5, 0), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 500.0)
        let vp = projMatrix * viewMatrix

        // Arc midpoint is at 45°: (10*cos(45°), 10*sin(45°)) ≈ (7.071, 7.071)
        let expectedMid = SIMD2<Double>(10.0 * cos(.pi / 4.0), 10.0 * sin(.pi / 4.0))
        let midWorld = plane.unprojectPoint(expectedMid)
        let screenMid = projectToScreen(point: midWorld, viewProjectionMatrix: vp, viewportSize: viewportSize)!

        let candidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [arc],
            plane: plane,
            pointer: screenMid,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )

        let midCandidate = candidates.first { $0.kind == .midpoint }
        #expect(midCandidate != nil)
        if let midCandidate, let planePt = midCandidate.planePoint {
            #expect(abs(planePt.x - expectedMid.x) <= 1e-4)
            #expect(abs(planePt.y - expectedMid.y) <= 1e-4)
        }
    }

    @Test func testGenerateSketchCandidatesCenterAndQuadrants() {
        let circle = SketchEntity.circle(center: SIMD2<Double>(20, 20), radius: 10.0)
        let plane = SketchPlane.xy
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(20, -20, 50), target: SIMD3<Float>(20, 20, 0), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 500.0)
        let vp = projMatrix * viewMatrix

        // 1. Center snap
        let centerScreen = projectToScreen(point: SIMD3<Float>(20, 20, 0), viewProjectionMatrix: vp, viewportSize: viewportSize)!
        let centerCandidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [circle],
            plane: plane,
            pointer: centerScreen,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )
        let centerCandidate = centerCandidates.first { $0.kind == .center }
        #expect(centerCandidate != nil)
        #expect(centerCandidate?.planePoint == SIMD2<Double>(20, 20))

        // 2. Right quadrant snap at (30, 20)
        let quadScreen = projectToScreen(point: SIMD3<Float>(30, 20, 0), viewProjectionMatrix: vp, viewportSize: viewportSize)!
        let quadCandidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [circle],
            plane: plane,
            pointer: quadScreen,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )
        let quadCandidate = quadCandidates.first { $0.kind == .quadrant }
        #expect(quadCandidate != nil)
        #expect(quadCandidate?.planePoint == SIMD2<Double>(30, 20))
    }

    @Test func testArcQuadrantClippingRejectsPointsOutsideSweep() {
        // Arc from 0° (10, 0) to 90° (0, 10), CCW. Only quadrants in sweep are 0° and 90°
        // Cardinals 180° (-10, 0) and 270° (0, -10) must be rejected!
        let arc = SketchEntity.arc(start: SIMD2<Double>(10, 0), end: SIMD2<Double>(0, 10), center: SIMD2<Double>(0, 0), clockwise: false)
        let plane = SketchPlane.xy
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(0, -40, 40), target: SIMD3<Float>(0, 0, 0), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 500.0)
        let vp = projMatrix * viewMatrix

        // Test pointer near 180° quadrant (-10, 0, 0)
        let offQuadScreen = projectToScreen(point: SIMD3<Float>(-10, 0, 0), viewProjectionMatrix: vp, viewportSize: viewportSize)!
        let candidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [arc],
            plane: plane,
            pointer: offQuadScreen,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )

        let offQuad = candidates.first { $0.kind == .quadrant && $0.planePoint == SIMD2<Double>(-10, 0) }
        #expect(offQuad == nil, "180° quadrant outside arc sweep must be rejected")
    }

    @Test func testGenerateSketchCandidatesIntersections() {
        // Crossing lines: (0, 10) -> (20, 10) and (10, 0) -> (10, 20), intersection at (10, 10)
        let l1 = SketchEntity.line(start: SIMD2<Double>(0, 10), end: SIMD2<Double>(20, 10))
        let l2 = SketchEntity.line(start: SIMD2<Double>(10, 0), end: SIMD2<Double>(10, 20))
        let plane = SketchPlane.xy
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(10, -20, 40), target: SIMD3<Float>(10, 10, 0), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 500.0)
        let vp = projMatrix * viewMatrix

        let isectScreen = projectToScreen(point: SIMD3<Float>(10, 10, 0), viewProjectionMatrix: vp, viewportSize: viewportSize)!
        let candidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [l1, l2],
            plane: plane,
            pointer: isectScreen,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )

        let isectCandidate = candidates.first { $0.kind == .intersection }
        #expect(isectCandidate != nil)
        #expect(isectCandidate?.planePoint == SIMD2<Double>(10, 10))
        #expect(isectCandidate?.point == SIMD3<Float>(10, 10, 0))
    }

    @Test func testNonIntersectingEntitiesProduceNoIntersections() {
        // Two parallel lines
        let l1 = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(20, 0))
        let l2 = SketchEntity.line(start: SIMD2<Double>(0, 10), end: SIMD2<Double>(20, 10))
        let plane = SketchPlane.xy
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(10, -20, 40), target: SIMD3<Float>(10, 5, 0), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 500.0)

        let candidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [l1, l2],
            plane: plane,
            pointer: SIMD2<Float>(400, 300),
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )
        let isects = candidates.filter { $0.kind == .intersection }
        #expect(isects.isEmpty)
    }

    @Test func testSketchPlaneUVGridSnappingOnAngledPlane() {
        let normal = simd_normalize(SIMD3<Float>(0, 1, 1))
        let origin = SIMD3<Float>(0, 10, 10)
        let xAxis = SIMD3<Float>(1, 0, 0)
        let plane = SketchPlane(origin: origin, normal: normal, xAxis: xAxis)

        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(10, -20, 80), target: SIMD3<Float>(10, 10, 10), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 500.0)
        let vp = projMatrix * viewMatrix

        // Pick a target UV point on the grid: (20.0, 10.0)
        let targetUV = SIMD2<Double>(20.0, 10.0)
        let targetWorld = plane.unprojectPoint(targetUV)
        let screenTarget = projectToScreen(point: targetWorld, viewProjectionMatrix: vp, viewportSize: viewportSize)!

        let candidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [],
            plane: plane,
            pointer: screenTarget,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )

        let gridCandidate = candidates.first { $0.kind == .grid }
        #expect(gridCandidate != nil)
        if let gridCandidate, let planePt = gridCandidate.planePoint {
            #expect(abs(planePt.x - 20.0) <= 1e-4)
            #expect(abs(planePt.y - 10.0) <= 1e-4)
        }
    }

    @Test func testDegenerateEntitiesProduceNoCandidates() {
        let degenLine = SketchEntity.line(start: SIMD2<Double>(5, 5), end: SIMD2<Double>(5, 5))
        let degenCircle = SketchEntity.circle(center: SIMD2<Double>(10, 10), radius: 0.0)
        let plane = SketchPlane.xy
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(5, -20, 20), target: SIMD3<Float>(5, 5, 0), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 500.0)

        let candidates = SnapCandidateGenerator.generateSketchCandidates(
            entities: [degenLine, degenCircle],
            plane: plane,
            pointer: SIMD2<Float>(400, 300),
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 0.0, // disable grid to inspect entity candidates
            tolerancePx: 50.0
        )
        #expect(candidates.isEmpty, "Degenerate entities must produce zero snap candidates")
    }

    @Test func testEndToEndSketchPlaneSnapResolution() {
        let line = SketchEntity.line(start: SIMD2<Double>(0, 0), end: SIMD2<Double>(20, 0))
        let plane = SketchPlane.xy
        let viewportSize = CGSize(width: 800, height: 600)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(10, -30, 30), target: SIMD3<Float>(10, 0, 0), up: SIMD3<Float>(0, 0, 1))
        let projMatrix = Orientation.makePerspective(fovyRadians: 45.0 * Float.pi / 180.0, aspect: 800.0 / 600.0, nearZ: 0.1, farZ: 500.0)
        let vp = projMatrix * viewMatrix

        let screenStart = projectToScreen(point: SIMD3<Float>(0, 0, 0), viewProjectionMatrix: vp, viewportSize: viewportSize)!
        let result = resolveSnapAtPointer(
            meshes: [],
            sketchEntities: [line],
            sketchPlane: plane,
            pointer: screenStart,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix,
            gridSpacing: 10.0,
            tolerancePx: 20.0
        )

        #expect(result != nil)
        #expect(result?.kind == .endpoint)
        #expect(result?.point == SIMD3<Float>(0, 0, 0))
        #expect(result?.screenPoint != nil)
        #expect(result?.planePoint == SIMD2<Double>(0, 0))
    }
}
