import Testing
import Foundation
import Synchronization
@testable import MadeCore

/// `KernelRequest.evaluateShape`: one request per tree, validated, and evaluated on the engine actor (invariants 1 and 4).
@Suite struct ShapeEvaluationTests {
    private let unit = BoxParams(width: 10, depth: 10, height: 10)
    
    private func client(_ engine: any KernelEngine = LocalKernelEngine()) -> KernelClient {
        KernelClient(engine: engine, debounceDuration: .milliseconds(5))
    }
    
    private func evaluate(_ shape: ShapeNode, on kernel: KernelClient, solid: String = "s") async -> KernelResult<MeshPayload> {
        await kernel.request(.evaluateShape(jobId: JobId(UUID().uuidString), solidId: SolidId(solid), shape: shape))
    }
    
    private func translateChain(_ length: Int) -> ShapeNode {
        var node = ShapeNode.box(unit)
        for _ in 0..<length { node = .translate(node, offset: SIMD3(1, 0, 0)) }
        return node
    }
    
    @Test func testShapeTreeEvaluatesInOneRequest() async throws {
        let seen = Mutex<[KernelRequest]>([])
        let kernel = client(HookedEngine { request in
            seen.withLock { $0.append(request) }
            return true
        })
        let model = (Box(width: 40, depth: 40, height: 10) - Cylinder(radius: 5, height: 20))
            .union(Box(width: 5, depth: 5, height: 5).translated(z: 10))
        
        let payload = try #require(await model.evaluate(on: kernel, solidId: SolidId("m")).value)
        
        #expect(payload.triangleCount > 0)
        let requests = seen.withLock { $0 }
        #expect(requests.count == 1)
        guard case .evaluateShape(_, _, let shape)? = requests.first else {
            Issue.record("Expected one evaluateShape request, saw \(requests)")
            return
        }
        #expect(shape == model.shapeDescription)
    }
    
    @MainActor @Test func testEvaluationNeverRunsOnMainThread() async {
        #expect(pthread_main_np() != 0)
        let onMain = Mutex<Bool?>(nil)
        let kernel = client(HookedEngine { _ in
            onMain.withLock { $0 = pthread_main_np() != 0 }
            return true
        })
        
        let result = await (Box(width: 10, depth: 10, height: 10) - Cylinder(radius: 2, height: 20))
            .evaluate(on: kernel, solidId: SolidId("main"))
        
        #expect(result.isSuccess)
        #expect(onMain.withLock { $0 } == false)
    }
    
    @Test func testTreeMatchesDirectEuclidComposition() async throws {
        let tree = ShapeNode.boolean(
            .union,
            .boolean(.subtract, .box(BoxParams(width: 30, depth: 20, height: 10)), .cylinder(CylinderParams(radius: 4, height: 20), slices: 24)),
            .translate(.boolean(.intersect, .box(unit), .cylinder(CylinderParams(radius: 6, height: 12), slices: 16)), offset: SIMD3(0, 0, 10))
        )
        let direct = EuclidEngine.union(
            EuclidEngine.subtract(EuclidEngine.makeBox(width: 30, depth: 20, height: 10), EuclidEngine.makeCylinder(radius: 4, height: 20, slices: 24)),
            EuclidEngine.intersect(EuclidEngine.makeBox(width: 10, depth: 10, height: 10), EuclidEngine.makeCylinder(radius: 6, height: 12, slices: 16))
                .translated(by: .init(0, 0, 10))
        )
        
        let payload = try #require(await evaluate(tree, on: client()).value)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.triangleCount == EuclidEngine.toMeshPayload(direct).triangleCount)
    }
    
    // MARK: - Validation
    
    @Test func testNonPositiveBoxFails() async {
        let kernel = client()
        let zero = ShapeNode.box(BoxParams(width: 0, depth: 10, height: 10))
        let negative = ShapeNode.box(BoxParams(width: 10, depth: -1, height: 10))
        for shape in [zero, .boolean(.union, .box(unit), negative)] {
            #expect(await evaluate(shape, on: kernel).error?.code == .invalidParams)
        }
    }
    
    @Test func testNonPositiveCylinderFails() async {
        let kernel = client()
        for params in [CylinderParams(radius: 0, height: 10), CylinderParams(radius: 5, height: -2)] {
            #expect(await evaluate(.cylinder(params, slices: 16), on: kernel).error?.code == .invalidParams)
        }
    }
    
    @Test func testSliceCountOutOfRangeFails() async {
        let kernel = client()
        for slices in [ShapeLimits.minSlices - 1, ShapeLimits.maxSlices + 1] {
            let shape = ShapeNode.translate(.cylinder(CylinderParams(radius: 5, height: 10), slices: slices), offset: .zero)
            #expect(await evaluate(shape, on: kernel).error?.code == .invalidParams)
        }
    }
    
    @Test func testNonFiniteValuesFail() async {
        let kernel = client()
        let shapes: [ShapeNode] = [
            .box(BoxParams(width: .nan, depth: 10, height: 10)),
            .box(BoxParams(width: 10, depth: .infinity, height: 10)),
            .translate(.box(unit), offset: SIMD3(.nan, 0, 0)),
            .translate(.box(unit), offset: SIMD3(0, 0, -.infinity))
        ]
        for shape in shapes {
            #expect(await evaluate(shape, on: kernel).error?.code == .invalidParams)
        }
    }
    
    @Test func testDepthOverLimitFails() async {
        let result = await evaluate(translateChain(ShapeLimits.maxDepth + 1), on: client())
        #expect(result.error?.code == .invalidParams)
    }
    
    @Test func testNodeCountOverLimitFails() async {
        func balanced(_ levels: Int) -> ShapeNode {
            levels == 0 ? .box(unit) : .boolean(.union, balanced(levels - 1), balanced(levels - 1))
        }
        // 2^13 - 1 nodes at depth 12: over the node limit, well under the depth limit.
        let result = await evaluate(balanced(12), on: client())
        #expect(result.error?.code == .invalidParams)
        #expect(result.error?.message.contains("nodes") == true)
    }
    
    @Test func testTreeAtLimitsSucceeds() async {
        let result = await evaluate(translateChain(ShapeLimits.maxDepth), on: client())
        #expect(result.isSuccess)
        #expect((result.value?.triangleCount ?? 0) > 0)
    }
    
    // MARK: - Engine state
    
    @Test func testFailureStoresNothing() async throws {
        let engine = LocalKernelEngine()
        let bad = ShapeNode.box(BoxParams(width: -1, depth: 1, height: 1))
        #expect(await engine.execute(.evaluateShape(jobId: JobId("b0"), solidId: SolidId("s"), shape: bad)).error?.code == .invalidParams)
        #expect(await engine.storeCounts() == KernelEngineCounts(solids: 0, euclidMeshes: 0))
        
        let first = try #require(await engine.execute(.evaluateShape(jobId: JobId("g"), solidId: SolidId("s"), shape: .box(unit))).value)
        #expect(await engine.execute(.evaluateShape(jobId: JobId("b1"), solidId: SolidId("s"), shape: bad)).error?.code == .invalidParams)
        let kept = try #require(await engine.execute(.tessellate(jobId: JobId("t"), solidId: SolidId("s"))).value)
        #expect(Array(kept.positions) == Array(first.positions))
    }
    
    @Test func testEmptyIntersectionSucceedsWithZeroTriangles() async throws {
        let disjoint = ShapeNode.boolean(.intersect, .box(unit), .translate(.box(unit), offset: SIMD3(100, 0, 0)))
        let payload = try #require(await evaluate(disjoint, on: client()).value)
        #expect(payload.triangleCount == 0)
    }
    
    @Test func testEvaluatedSolidIsUsableByBoolean() async throws {
        let kernel = client()
        #expect(await evaluate(.translate(.box(unit), offset: SIMD3(5, 0, 0)), on: kernel, solid: "evaluated").isSuccess)
        #expect(await kernel.request(.makeBox(jobId: JobId("b"), solidId: SolidId("box"), params: unit)).isSuccess)
        
        let result = await kernel.request(.booleanOperation(jobId: JobId("u"), solidId: SolidId("u"), op: .union, solidA: SolidId("box"), solidB: SolidId("evaluated")))
        #expect(try #require(result.value).triangleCount > 0)
    }
    
    @Test func testRapidEvaluationsConflate() async {
        let kernel = KernelClient(debounceDuration: .milliseconds(50))
        let solidId = SolidId("rapid")
        let t1 = Task { await kernel.request(.evaluateShape(jobId: JobId("e1"), solidId: solidId, shape: .box(unit))) }
        await waitForPending(kernel, solidId, JobId("e1"))
        let t2 = Task { await kernel.request(.evaluateShape(jobId: JobId("e2"), solidId: solidId, shape: .cylinder(CylinderParams(radius: 3, height: 3), slices: 12))) }
        await waitForPending(kernel, solidId, JobId("e2"))
        
        let (r1, r2) = await (t1.value, t2.value)
        #expect(r1.error?.code == .cancelled)
        #expect(r2.isSuccess)
        #expect(r2.jobId == JobId("e2"))
    }
    
    private func waitForPending(_ client: KernelClient, _ solidId: SolidId, _ jobId: JobId) async {
        for _ in 0..<1_000 {
            if await client.pendingJobId(for: solidId) == jobId { return }
            await Task.yield()
        }
        Issue.record("Job \(jobId) never became pending")
    }

    @Test func testSphereConeExtrudeRevolveRotateScaleEvaluate() async throws {
        let kernel = client()
        let rectProfile = SketchProfile(
            plane: SketchPlane.xy.offset(5),
            points: [SIMD2(-10, -5), SIMD2(10, -5), SIMD2(10, 5), SIMD2(-10, 5)]
        )
        let revolveProfile = SketchProfile(
            plane: .xz,
            points: [SIMD2(4, -5), SIMD2(8, -5), SIMD2(8, 5), SIMD2(4, 5)]
        )
        let complex = ShapeNode.boolean(
            .union,
            .rotate(
                .scale(.extrude(profile: rectProfile, distance: 12, centered: false), factor: SIMD3(1, 1, 1.5)),
                axis: SIMD3(0, 0, 1),
                angleDegrees: 45
            ),
            .boolean(
                .union,
                .sphere(SphereParams(radius: 6), slices: 24),
                .boolean(
                    .union,
                    .cone(ConeParams(bottomRadius: 6, topRadius: 2, height: 10), slices: 24),
                    .revolve(profile: revolveProfile, angleDegrees: 360, slices: 24)
                )
            )
        )
        let payload = try #require(await evaluate(complex, on: kernel).value)
        #expect(payload.triangleCount > 0)
    }

    @Test func testNewShapeNodeValidationRejectsInvalidInputs() async {
        let kernel = client()
        let validProfile = SketchProfile(
            plane: .xy,
            points: [SIMD2(2, 0), SIMD2(6, 0), SIMD2(6, 4), SIMD2(2, 4)]
        )
        let crossingProfile = SketchProfile(
            plane: .xy,
            points: [SIMD2(-2, 0), SIMD2(4, 0), SIMD2(4, 4), SIMD2(-2, 4)]
        )
        let degenerateProfile = SketchProfile(
            plane: .xy,
            points: [SIMD2(0, 0), SIMD2(5, 0), SIMD2(10, 0)]
        )
        let invalidCases: [ShapeNode] = [
            .sphere(SphereParams(radius: 0), slices: 16),
            .cone(ConeParams(bottomRadius: 0, topRadius: 0, height: 10), slices: 16),
            .cone(ConeParams(bottomRadius: -1, topRadius: 2, height: 10), slices: 16),
            .extrude(profile: validProfile, distance: 0, centered: false),
            .extrude(profile: degenerateProfile, distance: 10, centered: false),
            .revolve(profile: crossingProfile, angleDegrees: 360, slices: 16),
            .revolve(profile: validProfile, angleDegrees: 0, slices: 16),
            .revolve(profile: validProfile, angleDegrees: 400, slices: 16),
            .rotate(.box(unit), axis: .zero, angleDegrees: 90),
            .scale(.box(unit), factor: SIMD3(1, 0, 1))
        ]
        for node in invalidCases {
            #expect(await evaluate(node, on: kernel).error?.code == .invalidParams)
        }
    }
}
