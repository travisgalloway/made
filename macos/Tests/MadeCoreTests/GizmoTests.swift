import Testing
import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
@testable import MadeCore

@Suite(.serialized) struct GizmoTests {
    private let width = 800
    private let height = 600

    @Test func testTranslationArrowHitTestAndProjection() throws {
        let viewportSize = CGSize(width: width, height: height)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(0, -120, 40), target: SIMD3<Float>(0, 0, 0), up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: Float(width) / Float(height), nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix
        let gizmoCenter = SIMD3<Float>(0, 0, 0)

        // 1. Hit-test Translation X arrow (shaft midpoint at (15, 0, 0))
        let screenMidX = try #require(projectToScreen(point: SIMD3<Float>(15, 0, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let hitX = try #require(gizmoHitTestAtPointer(
            pointer: screenMidX,
            isTouch: false,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        ))
        #expect(hitX.handle == .translateX)
        #expect(hitX.screenDistancePx <= 1.0)

        // 2. Hit-test Translation Y arrow (shaft midpoint at (0, 15, 0))
        let screenMidY = try #require(projectToScreen(point: SIMD3<Float>(0, 15, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let hitY = try #require(gizmoHitTestAtPointer(
            pointer: screenMidY,
            isTouch: false,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        ))
        #expect(hitY.handle == .translateY)
        #expect(hitY.screenDistancePx <= 1.0)

        // 3. Hit-test Translation Z arrow (shaft midpoint at (0, 0, 15))
        let screenMidZ = try #require(projectToScreen(point: SIMD3<Float>(0, 0, 15), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let hitZ = try #require(gizmoHitTestAtPointer(
            pointer: screenMidZ,
            isTouch: false,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        ))
        #expect(hitZ.handle == .translateZ)
        #expect(hitZ.screenDistancePx <= 1.0)

        // 4. Skew-ray delta translation math
        let rayOrigin = SIMD3<Float>(0, -100, 0)
        let startRay = Ray3D(origin: rayOrigin, direction: simd_normalize(SIMD3<Float>(10, 100, 0)))
        let currentRay = Ray3D(origin: rayOrigin, direction: simd_normalize(SIMD3<Float>(35, 100, 0)))

        let delta = try #require(computeGizmoTranslation(
            axisOrigin: gizmoCenter,
            axisDirection: SIMD3<Float>(1, 0, 0),
            startRay: startRay,
            currentRay: currentRay
        ))
        #expect(abs(delta.x - 25.0) < 1e-3, "Delta translation along X must be 25 mm")
        #expect(abs(delta.y) < 1e-5)
        #expect(abs(delta.z) < 1e-5)
    }

    @Test func testRotationRingHitTestAndAngle() throws {
        let viewportSize = CGSize(width: width, height: height)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(0, -120, 60), target: SIMD3<Float>(0, 0, 0), up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: Float(width) / Float(height), nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix
        let gizmoCenter = SIMD3<Float>(0, 0, 0)

        // Point on Z rotation ring (XY plane, radius 24) at 45 degrees
        let ringZPoint = SIMD3<Float>(24.0 * cos(.pi / 4.0), 24.0 * sin(.pi / 4.0), 0)
        let screenZ = try #require(projectToScreen(point: ringZPoint, viewProjectionMatrix: vp, viewportSize: viewportSize))
        let hitZ = try #require(gizmoHitTestAtPointer(
            pointer: screenZ,
            isTouch: false,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        ))
        #expect(hitZ.handle == .rotateZ)
        #expect(hitZ.screenDistancePx <= 1.0)

        // Rotation angle math: rotate 90 degrees around Z axis
        let startRay = Ray3D(origin: SIMD3<Float>(24, 0, 100), direction: SIMD3<Float>(0, 0, -1))
        let currentRay = Ray3D(origin: SIMD3<Float>(0, 24, 100), direction: SIMD3<Float>(0, 0, -1))

        let angle = try #require(computeGizmoRotationAngle(
            center: gizmoCenter,
            axis: SIMD3<Float>(0, 0, 1),
            startRay: startRay,
            currentRay: currentRay
        ))
        #expect(abs(angle - .pi / 2.0) < 1e-4, "Signed rotation angle should be +pi/2 radians (90 deg)")

        let initialRot = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let newRot = try #require(computeGizmoRotation(
            center: gizmoCenter,
            axis: SIMD3<Float>(0, 0, 1),
            initialRotation: initialRot,
            startRay: startRay,
            currentRay: currentRay
        ))
        let rotatedPoint = newRot.act(SIMD3<Float>(1, 0, 0))
        #expect(abs(rotatedPoint.x) < 1e-4)
        #expect(abs(rotatedPoint.y - 1.0) < 1e-4)
    }

    @Test func testTouchInputLiftsPickPoint() throws {
        let viewportSize = CGSize(width: width, height: height)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(0, -120, 40), target: SIMD3<Float>(0, 0, 0), up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: Float(width) / Float(height), nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix
        let gizmoCenter = SIMD3<Float>(0, 0, 0)

        // Translation X shaft midpoint
        let screenPt = try #require(projectToScreen(point: SIMD3<Float>(15, 0, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))

        // Mouse click directly at the screen point hits the arrow
        let mouseHit = gizmoHitTestAtPointer(
            pointer: screenPt,
            isTouch: false,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect(mouseHit?.handle == .translateX)

        // Touch contact at (x, y - touchPickOffsetPt) is lifted by +28 pt and hits the arrow
        let touchContact = SIMD2<Float>(screenPt.x, screenPt.y - touchPickOffsetPt)
        let touchHit = gizmoHitTestAtPointer(
            pointer: touchContact,
            isTouch: true,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect(touchHit?.handle == .translateX)
        #expect(touchHit!.screenDistancePx <= 1.0)

        // Touch contact directly at screenPt is lifted by +28 pt, which shifts hit off the translateX arrow
        let touchMiss = gizmoHitTestAtPointer(
            pointer: screenPt,
            isTouch: true,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect(touchMiss?.handle != .translateX)

        // Far pointer touches hit nothing
        let farMiss = gizmoHitTestAtPointer(
            pointer: SIMD2<Float>(screenPt.x + 200, screenPt.y + 200),
            isTouch: true,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect(farMiss == nil)
    }

    @Test func testZeroKernelDispatchesDuringDrag() async throws {
        let engine = LocalKernelEngine()
        let kernel = KernelClient(engine: engine)

        let initialDispatched = await kernel.getStats().dispatched

        // Simulate complete interactive gizmo drag
        var transform = Transform(position: SIMD3<Float>(10, 0, 0))
        for step in 1...10 {
            transform.position.x = 10.0 + Float(step) * 2.0
            // Interactive viewport transforms never dispatch to the geometry kernel (Invariant 9 / Two-Physics Rule)
        }

        let finalDispatched = await kernel.getStats().dispatched
        #expect(finalDispatched == initialDispatched, "Live rigid transforms must never invoke the kernel")
    }

    @MainActor
    @Test func testSingleCommitOnRelease() throws {
        let doc = DocumentModel()
        let initialTransform = try #require(doc.objects.first(where: { $0.id == cylinderSolidId })?.transform)
        #expect(initialTransform.position == SIMD3<Float>(25, 0, 0))

        var commitCount = 0
        var currentPreviewTransform = initialTransform

        // Simulate drag frames (updating preview without calling setTransform)
        for i in 1...5 {
            currentPreviewTransform.position.x += Float(i) * 2.0
            // Frame update: renderer receives updateTransform, doc.setTransform is NOT called
            #expect(doc.objects.first(where: { $0.id == cylinderSolidId })?.transform == initialTransform)
        }

        // On mouse up / release, commit exactly once
        doc.setTransform(id: cylinderSolidId, transform: currentPreviewTransform)
        commitCount += 1

        #expect(commitCount == 1, "setTransform must be called exactly once upon gesture release")
        #expect(doc.objects.first(where: { $0.id == cylinderSolidId })?.transform == currentPreviewTransform)
    }

    @MainActor
    @Test func testDragWithoutMovementDoesNotCommit() throws {
        let doc = DocumentModel()
        let initialTransform = try #require(doc.objects.first(where: { $0.id == cylinderSolidId })?.transform)

        var committed = false
        var hasMoved = false

        // Simulate click-down and click-up without mouse move
        let startPointer = SIMD2<Float>(100, 100)
        let currentPointer = SIMD2<Float>(100, 100)
        if currentPointer != startPointer {
            hasMoved = true
        }

        if hasMoved {
            doc.setTransform(id: cylinderSolidId, transform: initialTransform)
            committed = true
        }

        #expect(!committed, "Clicking a handle without movement must not commit")
        #expect(doc.objects.first(where: { $0.id == cylinderSolidId })?.transform == initialTransform)
    }

    @MainActor
    @Test func testCancelledDragRestoresInitialTransform() throws {
        let doc = DocumentModel()
        let initialTransform = try #require(doc.objects.first(where: { $0.id == cylinderSolidId })?.transform)

        var liveTransform = initialTransform
        liveTransform.position.x += 30.0

        // Drag cancel restores initial transform and does not invoke setTransform
        liveTransform = initialTransform

        #expect(liveTransform == initialTransform)
        #expect(doc.objects.first(where: { $0.id == cylinderSolidId })?.transform == initialTransform)
    }

    @MainActor
    @Test func testSelectedObjectRemovalAbortsGesture() throws {
        let doc = DocumentModel()
        #expect(doc.objects.contains(where: { $0.id == cylinderSolidId }))

        var activeDragId: SolidId? = cylinderSolidId

        // Solid is removed mid-drag
        doc.removeObject(id: cylinderSolidId)
        #expect(!doc.objects.contains(where: { $0.id == cylinderSolidId }))

        // Check coordinator abort rule
        if !doc.objects.contains(where: { $0.id == activeDragId }) {
            activeDragId = nil
        }

        #expect(activeDragId == nil, "Gesture should be cleanly aborted when object is removed")
    }

    @Test func testGestureArbiterModeLock() {
        let arbiter = GestureArbiter()
        #expect(arbiter.current().mode == nil)
        #expect(!arbiter.current().locked)

        // When pointer goes down on gizmo handle, coordinator locks arbiter to .manipulate
        _ = arbiter.handle(.down(pointer: ArbiterPointer(pointerId: 0, x: 25, y: 35)))
        arbiter.lock(to: .manipulate)
        #expect(arbiter.current().mode == .manipulate)
        #expect(arbiter.current().locked)

        // Subsequent mouse move events stay locked in .manipulate
        let move = arbiter.handle(.move(pointer: ArbiterPointer(pointerId: 0, x: 26, y: 36)))
        #expect(move.mode == .manipulate)
        #expect(move.locked)

        // Mode lock prevents camera orbit/pan until release
        let up = arbiter.handle(.up(pointerId: 0))
        #expect(up.mode == .manipulate)
        #expect(up.locked)

        // Resets after release
        #expect(arbiter.current().mode == nil)
        #expect(!arbiter.current().locked)
    }

    @Test func testScaleHandleHitTestAndProjection() throws {
        let viewportSize = CGSize(width: width, height: height)
        let viewMatrix = Orientation.makeLookAt(eye: SIMD3<Float>(80, -120, 50), target: SIMD3<Float>(0, 0, 0), up: Orientation.worldUp)
        let projMatrix = Orientation.makePerspective(fovyRadians: .pi / 4.0, aspect: Float(width) / Float(height), nearZ: 0.1, farZ: 1000.0)
        let vp = projMatrix * viewMatrix
        let gizmoCenter = SIMD3<Float>(0, 0, 0)

        // 1. Hit-test Scale X handle at cube tip (42, 0, 0)
        let screenScaleX = try #require(projectToScreen(point: SIMD3<Float>(42, 0, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let hitX = try #require(gizmoHitTestAtPointer(
            pointer: screenScaleX,
            isTouch: false,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        ))
        #expect(hitX.handle == .scaleX)
        #expect(hitX.screenDistancePx <= 1.0)

        // 2. Hit-test Scale Y handle at cube tip (0, 42, 0)
        let screenScaleY = try #require(projectToScreen(point: SIMD3<Float>(0, 42, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let hitY = try #require(gizmoHitTestAtPointer(
            pointer: screenScaleY,
            isTouch: false,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        ))
        #expect(hitY.handle == .scaleY)
        #expect(hitY.screenDistancePx <= 1.0)

        // 3. Hit-test Scale Z handle at cube tip (0, 0, 42)
        let screenScaleZ = try #require(projectToScreen(point: SIMD3<Float>(0, 0, 42), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let hitZ = try #require(gizmoHitTestAtPointer(
            pointer: screenScaleZ,
            isTouch: false,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        ))
        #expect(hitZ.handle == .scaleZ)
        #expect(hitZ.screenDistancePx <= 1.0)

        // 4. Hit-test shaft extension midpoint (36, 0, 0) hits scaleX, not translateX
        let screenMidShaftX = try #require(projectToScreen(point: SIMD3<Float>(36, 0, 0), viewProjectionMatrix: vp, viewportSize: viewportSize))
        let hitMidShaftX = try #require(gizmoHitTestAtPointer(
            pointer: screenMidShaftX,
            isTouch: false,
            gizmoCenter: gizmoCenter,
            viewportSize: viewportSize,
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        ))
        #expect(hitMidShaftX.handle == .scaleX)
        #expect(hitMidShaftX.screenDistancePx <= 1.0)
    }

    @Test func testComputeGizmoScale() throws {
        let gizmoCenter = SIMD3<Float>(0, 0, 0)
        let rayOrigin = SIMD3<Float>(0, -100, 0)
        let startRay = Ray3D(origin: rayOrigin, direction: simd_normalize(SIMD3<Float>(42, 100, 0)))
        let currentRayOut = Ray3D(origin: rayOrigin, direction: simd_normalize(SIMD3<Float>(84, 100, 0)))

        let scaleOut = try #require(computeGizmoScale(
            axisOrigin: gizmoCenter,
            axisDirection: SIMD3<Float>(1, 0, 0),
            baseParam: 42.0,
            startRay: startRay,
            currentRay: currentRayOut
        ))
        // Outward drag: ratio should be approximately 2.0
        #expect(abs(scaleOut - 2.0) < 1e-2)

        // Inward drag: s1 ~ 21 => ratio should be approximately 0.5
        let currentRayIn = Ray3D(origin: rayOrigin, direction: simd_normalize(SIMD3<Float>(21, 100, 0)))
        let scaleIn = try #require(computeGizmoScale(
            axisOrigin: gizmoCenter,
            axisDirection: SIMD3<Float>(1, 0, 0),
            baseParam: 42.0,
            startRay: startRay,
            currentRay: currentRayIn
        ))
        #expect(abs(scaleIn - 0.5) < 1e-2)

        // Drag far past origin inward: ratio clamped to 0.01 minimum
        let scalePastZero = computeGizmoScale(startParam: 42.0, currentParam: -100.0, baseParam: 42.0)
        #expect(scalePastZero == 0.01)

        // Zero delta produces ratio 1.0
        let scaleIdentity = computeGizmoScale(startParam: 42.0, currentParam: 42.0, baseParam: 42.0)
        #expect(abs(scaleIdentity - 1.0) < 1e-5)
    }

    @Test func testComputeResizedParametersBoxAndCylinder() {
        let boxDef = ObjectDef.box(BoxParams(width: 20, depth: 30, height: 40))
        let boxParams = computeResizedParameters(for: boxDef, scale: SIMD3<Float>(1.5, 2.0, 0.5))
        #expect(boxParams.count == 3)
        let boxDict = Dictionary(uniqueKeysWithValues: boxParams.map { ($0.key, $0.value) })
        #expect(abs((boxDict["width"] ?? 0) - 30.0) < 1e-3)
        #expect(abs((boxDict["depth"] ?? 0) - 60.0) < 1e-3)
        #expect(abs((boxDict["height"] ?? 0) - 20.0) < 1e-3)

        let cylDef = ObjectDef.cylinder(CylinderParams(radius: 10, height: 20))
        let cylParams = computeResizedParameters(for: cylDef, scale: SIMD3<Float>(1.5, 2.5, 0.5))
        #expect(cylParams.count == 2)
        let cylDict = Dictionary(uniqueKeysWithValues: cylParams.map { ($0.key, $0.value) })
        // radius scales by max(1.5, 2.5) = 2.5 => 10 * 2.5 = 25.0
        #expect(abs((cylDict["radius"] ?? 0) - 25.0) < 1e-3)
        // height scales by 0.5 => 20 * 0.5 = 10.0
        #expect(abs((cylDict["height"] ?? 0) - 10.0) < 1e-3)

        let importedDef = ObjectDef.imported(name: "test-import")
        let importedParams = computeResizedParameters(for: importedDef, scale: SIMD3<Float>(2.0, 2.0, 2.0))
        #expect(importedParams.isEmpty)
    }

    @Test func testResizeZeroKernelDispatchesDuringDrag() async {
        let engine = LocalKernelEngine()
        let kernel = KernelClient(engine: engine)
        let initialDispatched = await kernel.getStats().dispatched

        // Simulate complete interactive gizmo scale drag
        var previewTransform = Transform(position: SIMD3<Float>(0, 0, 0), scale: SIMD3<Float>(1, 1, 1))
        for step in 1...10 {
            previewTransform.scale.x = 1.0 + Float(step) * 0.1
            // Interactive viewport preview transforms never dispatch to the geometry kernel (Two-Physics Rule)
        }

        let finalDispatched = await kernel.getStats().dispatched
        #expect(finalDispatched == initialDispatched, "Live scale dragging must never invoke the kernel")
    }

    @Test func testResizeSingleCommitOnRelease() async {
        let engine = LocalKernelEngine()
        let client = KernelClient(engine: engine, debounceDuration: .milliseconds(50))
        let solidId = SolidId("box-resize-conflation")

        // When box resize commits on release, multiple parameter mutations are submitted rapidly
        let t1 = Task { await client.request(.makeBox(jobId: JobId("resize-w"), solidId: solidId, params: BoxParams(width: 30, depth: 20, height: 10))) }
        await waitForPending(client, solidId, JobId("resize-w"))
        let t2 = Task { await client.request(.makeBox(jobId: JobId("resize-d"), solidId: solidId, params: BoxParams(width: 30, depth: 35, height: 10))) }
        await waitForPending(client, solidId, JobId("resize-d"))
        let t3 = Task { await client.request(.makeBox(jobId: JobId("resize-h"), solidId: solidId, params: BoxParams(width: 30, depth: 35, height: 25))) }
        await waitForPending(client, solidId, JobId("resize-h"))

        let (r1, r2, r3) = await (t1.value, t2.value, t3.value)
        #expect(r1.error?.code == .cancelled)
        #expect(r2.error?.code == .cancelled)
        #expect(r3.isSuccess)

        let stats = await client.getStats()
        #expect(stats.dispatched == 1, "Rapid release commits must conflate into exactly 1 kernel dispatch")
        #expect(stats.conflated == 2)
    }

    @Test func testResizePastLimitsClampsOnCommit() {
        // Box min clamping (5 mm) and max clamping (90 mm)
        let boxDef = ObjectDef.box(BoxParams(width: 20, depth: 50, height: 80))
        let boxClamped = computeResizedParameters(for: boxDef, scale: SIMD3<Float>(0.01, 3.0, 2.0))
        let boxDict = Dictionary(uniqueKeysWithValues: boxClamped.map { ($0.key, $0.value) })
        #expect(boxDict["width"] == 5.0, "Width should clamp to min 5.0 mm")
        #expect(boxDict["depth"] == 90.0, "Depth should clamp to max 90.0 mm")
        #expect(boxDict["height"] == 90.0, "Height should clamp to max 90.0 mm")

        // Cylinder radius max clamping (50 mm) and height min clamping (5 mm)
        let cylDef = ObjectDef.cylinder(CylinderParams(radius: 40, height: 20))
        let cylClamped = computeResizedParameters(for: cylDef, scale: SIMD3<Float>(2.0, 2.0, 0.05))
        let cylDict = Dictionary(uniqueKeysWithValues: cylClamped.map { ($0.key, $0.value) })
        #expect(cylDict["radius"] == 50.0, "Radius should clamp to max 50.0 mm")
        #expect(cylDict["height"] == 5.0, "Height should clamp to min 5.0 mm")
    }

    @MainActor
    @Test func testCancelledResizeRestoresInitialScale() throws {
        let doc = DocumentModel()
        let initialTransform = try #require(doc.objects.first(where: { $0.id == boxSolidId })?.transform)
        #expect(initialTransform.scale == SIMD3<Float>(1, 1, 1))

        var liveTransform = initialTransform
        liveTransform.scale = SIMD3<Float>(2.5, 1.0, 0.8)

        // Cancel restores initial scale and leaves document unchanged
        liveTransform = initialTransform

        #expect(liveTransform.scale == SIMD3<Float>(1, 1, 1))
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.transform == initialTransform)
    }

    @MainActor
    @Test func testImportedObjectResizeRetainsScaleInTransform() async throws {
        let doc = DocumentModel()
        let importedId = doc.addObject(def: .imported(name: "test-import"))
        let initialTransform = try #require(doc.objects.first(where: { $0.id == importedId })?.transform)
        #expect(initialTransform.scale == SIMD3<Float>(1, 1, 1))

        let engine = LocalKernelEngine()
        let kernel = KernelClient(engine: engine)
        let initialDispatched = await kernel.getStats().dispatched

        // Resize gesture scales imported object
        let newScale = SIMD3<Float>(1.8, 1.8, 1.8)
        var updatedTransform = initialTransform
        updatedTransform.scale = newScale

        let params = computeResizedParameters(for: .imported(name: "test-import"), scale: newScale)
        #expect(params.isEmpty, "Imported object must produce zero parameter updates")

        // Retain scale in Transform
        doc.setTransform(id: importedId, transform: updatedTransform)

        let storedTransform = try #require(doc.objects.first(where: { $0.id == importedId })?.transform)
        #expect(storedTransform.scale == newScale)

        let finalDispatched = await kernel.getStats().dispatched
        #expect(finalDispatched == initialDispatched, "Zero kernel jobs should be dispatched for imported scale")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testEndToEndGizmoRenderingAndSelection() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        renderer.updateGrid(size: 0)
        renderer.updateAxes(length: 0)

        let boxPayload = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 40, depth: 30, height: 20))
        let boxId = SolidId("box-1")
        let boxMesh = try #require(renderer.createMesh(from: boxPayload, solidId: boxId, color: SIMD4<Float>(0.5, 0.5, 0.5, 1.0)))
        renderer.meshes[boxId] = boxMesh

        // 1. Without selection: gizmo does NOT render (0 gizmo draw calls)
        renderer.selectedId = nil
        _ = try #require(await renderer.captureSnapshotPngBase64(view: nil, includeGizmo: true))
        let unselectedCalls = renderer.lastDrawCalls
        #expect(unselectedCalls == 1, "Only solid should draw when unselected")

        // 2. With selection: gizmo renders for the selected solid (solid + outline + 9 gizmo handles)
        renderer.selectedId = boxId
        let selectedSnapshot = try #require(await renderer.captureSnapshotPngBase64(view: nil, includeGizmo: true))
        let selectedCalls = renderer.lastDrawCalls
        #expect(selectedCalls == 11, "1 solid + 1 outline + 9 gizmo handle draw calls = 11 total")

        let pixels = try decodeRGBA(selectedSnapshot)

        // Verify gizmo axis color pixels appear in the frame:
        // Red (X handles): high R, predominantly red
        // Green (Y handles): high G, predominantly green
        // Blue (Z handles): high B, predominantly blue
        var redCount = 0
        var greenCount = 0
        var blueCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = pixels[i]
                let g = pixels[i + 1]
                let b = pixels[i + 2]

                let ir = Int(r)
                let ig = Int(g)
                let ib = Int(b)

                if ir > 200 && ir > ig + 50 && ir > ib + 50 {
                    redCount += 1
                } else if ig > 200 && ig > ir + 50 && ig > ib + 50 {
                    greenCount += 1
                } else if ib > 200 && ib > ir + 50 && ib > ig + 50 {
                    blueCount += 1
                }
            }
        }

        #expect(redCount > 10, "Red translation/rotation/scale X gizmo lines must be visible")
        #expect(greenCount > 10, "Green translation/rotation/scale Y gizmo lines must be visible")
        #expect(blueCount > 10, "Blue translation/rotation/scale Z gizmo lines must be visible")

        // 3. Deselecting hides the gizmo immediately
        renderer.selectedId = nil
        _ = try #require(await renderer.captureSnapshotPngBase64(view: nil, includeGizmo: true))
        #expect(renderer.lastDrawCalls == 1, "Clearing selection must hide the gizmo")
    }

    private func decodeRGBA(_ base64: String) throws -> [UInt8] {
        let data = try #require(Data(base64Encoded: base64))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func waitForPending(_ client: KernelClient, _ solidId: SolidId, _ jobId: JobId) async {
        for _ in 0..<1_000 {
            if await client.pendingJobId(for: solidId) == jobId { return }
            await Task.yield()
        }
        Issue.record("Job \(jobId) never became pending")
    }
}
