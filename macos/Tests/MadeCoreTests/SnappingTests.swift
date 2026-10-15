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
}
