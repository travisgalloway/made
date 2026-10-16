import Testing
import Foundation
import simd
import OCCTSwift
@testable import MadeCore

@Suite struct TopologicalNamingTests {

    // MARK: - Box Sub-Element Resolution

    @Test func testResolveFaceEdgeVertexOnBox() throws {
        guard let boxShape = Shape.box(
            origin: SIMD3(-20, -15, -10),
            width: 40,
            height: 30,
            depth: 20
        ) else {
            Issue.record("Failed to create test box shape")
            return
        }

        let feature = Feature.makeBox(params: BoxParams(width: 40, depth: 30, height: 20))

        // Faces
        let topFaceRef = try #require(feature.generatedTopology["face:top"])
        let topFace = try TopologicalResolver.resolveFace(in: boxShape, reference: topFaceRef)
        #expect(topFace.isPlanar)
        #expect(topFace.normal?.z ?? 0 > 0.99)

        let bottomFaceRef = try #require(feature.generatedTopology["face:bottom"])
        let bottomFace = try TopologicalResolver.resolveFace(in: boxShape, reference: bottomFaceRef)
        #expect(bottomFace.isPlanar)
        #expect(bottomFace.normal?.z ?? 0 < -0.99)

        let frontFaceRef = try #require(feature.generatedTopology["face:front"])
        let frontFace = try TopologicalResolver.resolveFace(in: boxShape, reference: frontFaceRef)
        #expect(frontFace.isPlanar)
        #expect(frontFace.normal?.y ?? 0 < -0.99)

        let backFaceRef = try #require(feature.generatedTopology["face:back"])
        let backFace = try TopologicalResolver.resolveFace(in: boxShape, reference: backFaceRef)
        #expect(backFace.isPlanar)
        #expect(backFace.normal?.y ?? 0 > 0.99)

        let rightFaceRef = try #require(feature.generatedTopology["face:right"])
        let rightFace = try TopologicalResolver.resolveFace(in: boxShape, reference: rightFaceRef)
        #expect(rightFace.isPlanar)
        #expect(rightFace.normal?.x ?? 0 > 0.99)

        let leftFaceRef = try #require(feature.generatedTopology["face:left"])
        let leftFace = try TopologicalResolver.resolveFace(in: boxShape, reference: leftFaceRef)
        #expect(leftFace.isPlanar)
        #expect(leftFace.normal?.x ?? 0 < -0.99)

        // Edges
        let topFrontEdgeRef = try #require(feature.generatedTopology["edge:top-front"])
        let topFrontEdge = try TopologicalResolver.resolveEdge(in: boxShape, reference: topFrontEdgeRef)
        #expect(topFrontEdge.isLine)
        #expect(abs(topFrontEdge.length - 40.0) < 1e-4)

        let frontLeftEdgeRef = try #require(feature.generatedTopology["edge:front-left"])
        let frontLeftEdge = try TopologicalResolver.resolveEdge(in: boxShape, reference: frontLeftEdgeRef)
        #expect(frontLeftEdge.isLine)
        #expect(abs(frontLeftEdge.length - 20.0) < 1e-4)

        let bottomBackEdgeRef = try #require(feature.generatedTopology["edge:bottom-back"])
        let bottomBackEdge = try TopologicalResolver.resolveEdge(in: boxShape, reference: bottomBackEdgeRef)
        #expect(bottomBackEdge.isLine)
        #expect(abs(bottomBackEdge.length - 40.0) < 1e-4)

        // Vertices
        let topFrontLeftVertRef = try #require(feature.generatedTopology["vertex:top-front-left"])
        let topFrontLeftVert = try TopologicalResolver.resolveVertex(in: boxShape, reference: topFrontLeftVertRef)
        #expect(abs(topFrontLeftVert.x - (-20.0)) < 1e-4)
        #expect(abs(topFrontLeftVert.y - (-15.0)) < 1e-4)
        #expect(abs(topFrontLeftVert.z - 10.0) < 1e-4)

        let bottomBackRightVertRef = try #require(feature.generatedTopology["vertex:bottom-back-right"])
        let bottomBackRightVert = try TopologicalResolver.resolveVertex(in: boxShape, reference: bottomBackRightVertRef)
        #expect(abs(bottomBackRightVert.x - 20.0) < 1e-4)
        #expect(abs(bottomBackRightVert.y - 15.0) < 1e-4)
        #expect(abs(bottomBackRightVert.z - (-10.0)) < 1e-4)

        // Subshape conversion
        let faceSubshape = try TopologicalResolver.resolveSubshape(in: boxShape, reference: topFaceRef)
        #expect(faceSubshape.isValid)
        let edgeSubshape = try TopologicalResolver.resolveSubshape(in: boxShape, reference: topFrontEdgeRef)
        #expect(edgeSubshape.isValid)
        let vertSubshape = try TopologicalResolver.resolveSubshape(in: boxShape, reference: topFrontLeftVertRef)
        #expect(vertSubshape.isValid)
    }

    // MARK: - Cylinder Sub-Element Resolution

    @Test func testResolveFaceEdgeVertexOnCylinder() throws {
        guard let cylShape = Shape.cylinder(
            at: SIMD2(0, 0),
            bottomZ: -20,
            radius: 15,
            height: 40
        ) else {
            Issue.record("Failed to create test cylinder shape")
            return
        }

        let feature = Feature.makeCylinder(params: CylinderParams(radius: 15, height: 40))

        // Faces
        let topFaceRef = try #require(feature.generatedTopology["face:top"])
        let topFace = try TopologicalResolver.resolveFace(in: cylShape, reference: topFaceRef)
        #expect(topFace.isPlanar)
        #expect(topFace.normal?.z ?? 0 > 0.99)

        let bottomFaceRef = try #require(feature.generatedTopology["face:bottom"])
        let bottomFace = try TopologicalResolver.resolveFace(in: cylShape, reference: bottomFaceRef)
        #expect(bottomFace.isPlanar)
        #expect(bottomFace.normal?.z ?? 0 < -0.99)

        let sideFaceRef = try #require(feature.generatedTopology["face:side"])
        let sideFace = try TopologicalResolver.resolveFace(in: cylShape, reference: sideFaceRef)
        #expect(sideFace.surfaceType == .cylinder)

        // Edges
        let topEdgeRef = try #require(feature.generatedTopology["edge:top"])
        let topEdge = try TopologicalResolver.resolveEdge(in: cylShape, reference: topEdgeRef)
        #expect(topEdge.isCircle)
        #expect(abs(topEdge.length - (2.0 * Double.pi * 15.0)) < 0.1)

        let bottomEdgeRef = try #require(feature.generatedTopology["edge:bottom"])
        let bottomEdge = try TopologicalResolver.resolveEdge(in: cylShape, reference: bottomEdgeRef)
        #expect(bottomEdge.isCircle)
        #expect(abs(bottomEdge.length - (2.0 * Double.pi * 15.0)) < 0.1)

        let seamEdgeRef = try #require(feature.generatedTopology["edge:seam"])
        let seamEdge = try TopologicalResolver.resolveEdge(in: cylShape, reference: seamEdgeRef)
        #expect(seamEdge.isLine)
        #expect(abs(seamEdge.length - 40.0) < 1e-4)

        // Vertices
        let topSeamRef = try #require(feature.generatedTopology["vertex:top-seam"])
        let topSeam = try TopologicalResolver.resolveVertex(in: cylShape, reference: topSeamRef)
        #expect(topSeam.z > 0)
        #expect(abs(topSeam.z - 20.0) < 1e-4)

        let bottomSeamRef = try #require(feature.generatedTopology["vertex:bottom-seam"])
        let bottomSeam = try TopologicalResolver.resolveVertex(in: cylShape, reference: bottomSeamRef)
        #expect(bottomSeam.z < 0)
        #expect(abs(bottomSeam.z - (-20.0)) < 1e-4)

        // Subshape conversion
        let sideSubshape = try TopologicalResolver.resolveSubshape(in: cylShape, reference: sideFaceRef)
        #expect(sideSubshape.isValid)
        let topEdgeSubshape = try TopologicalResolver.resolveSubshape(in: cylShape, reference: topEdgeRef)
        #expect(topEdgeSubshape.isValid)
        let seamSubshape = try TopologicalResolver.resolveSubshape(in: cylShape, reference: seamEdgeRef)
        #expect(seamSubshape.isValid)
    }

    // MARK: - Sphere Sub-Element Resolution

    @Test func testResolveFaceEdgeVertexOnSphere() throws {
        guard let sphShape = Shape.sphere(radius: 15) else {
            Issue.record("Failed to create test sphere shape")
            return
        }

        let feature = Feature.makeSphere(params: SphereParams(radius: 15))

        let surfRef = try #require(feature.generatedTopology["face:surface"])
        let surfFace = try TopologicalResolver.resolveFace(in: sphShape, reference: surfRef)
        #expect(surfFace.surfaceType == .sphere)

        let seamRef = try #require(feature.generatedTopology["edge:seam"])
        let seamEdge = try TopologicalResolver.resolveEdge(in: sphShape, reference: seamRef)
        #expect(seamEdge.length > 0)

        let northRef = try #require(feature.generatedTopology["vertex:north-pole"])
        let northVert = try TopologicalResolver.resolveVertex(in: sphShape, reference: northRef)
        #expect(northVert.z > 0)

        let southRef = try #require(feature.generatedTopology["vertex:south-pole"])
        let southVert = try TopologicalResolver.resolveVertex(in: sphShape, reference: southRef)
        #expect(southVert.z < 0)
    }

    // MARK: - Cone Sub-Element Resolution

    @Test func testResolveFaceEdgeVertexOnCone() throws {
        guard let coneShape = Shape.cone(
            at: SIMD3(0, 0, -15),
            direction: SIMD3(0, 0, 1),
            bottomRadius: 15,
            topRadius: 5,
            height: 30
        ) else {
            Issue.record("Failed to create test cone shape")
            return
        }

        let feature = Feature.makeCone(params: ConeParams(bottomRadius: 15, topRadius: 5, height: 30))

        let bottomRef = try #require(feature.generatedTopology["face:bottom"])
        let bottomFace = try TopologicalResolver.resolveFace(in: coneShape, reference: bottomRef)
        #expect(bottomFace.isPlanar)
        #expect(bottomFace.normal?.z ?? 0 < -0.99)

        let topRef = try #require(feature.generatedTopology["face:top"])
        let topFace = try TopologicalResolver.resolveFace(in: coneShape, reference: topRef)
        #expect(topFace.isPlanar)
        #expect(topFace.normal?.z ?? 0 > 0.99)

        let sideRef = try #require(feature.generatedTopology["face:side"])
        let sideFace = try TopologicalResolver.resolveFace(in: coneShape, reference: sideRef)
        #expect(sideFace.surfaceType == .cone)

        let bottomEdgeRef = try #require(feature.generatedTopology["edge:bottom"])
        let bottomEdge = try TopologicalResolver.resolveEdge(in: coneShape, reference: bottomEdgeRef)
        #expect(bottomEdge.isCircle)

        let topEdgeRef = try #require(feature.generatedTopology["edge:top"])
        let topEdge = try TopologicalResolver.resolveEdge(in: coneShape, reference: topEdgeRef)
        #expect(topEdge.isCircle)

        let seamEdgeRef = try #require(feature.generatedTopology["edge:seam"])
        let seamEdge = try TopologicalResolver.resolveEdge(in: coneShape, reference: seamEdgeRef)
        #expect(seamEdge.length > 0)
    }

    // MARK: - Torus Sub-Element Resolution

    @Test func testResolveFaceEdgeVertexOnTorus() throws {
        guard let torusShape = Shape.torus(
            at: SIMD3(0, 0, 0),
            direction: SIMD3(0, 0, 1),
            majorRadius: 20,
            minorRadius: 5
        ) else {
            Issue.record("Failed to create test torus shape")
            return
        }

        let feature = Feature.makeTorus(params: TorusParams(majorRadius: 20, minorRadius: 5))

        let surfRef = try #require(feature.generatedTopology["face:surface"])
        let surfFace = try TopologicalResolver.resolveFace(in: torusShape, reference: surfRef)
        #expect(surfFace.surfaceType == .torus)

        let majSeamRef = try #require(feature.generatedTopology["edge:major-seam"])
        let majSeam = try TopologicalResolver.resolveEdge(in: torusShape, reference: majSeamRef)
        #expect(majSeam.isCircle)

        let minSeamRef = try #require(feature.generatedTopology["edge:minor-seam"])
        let minSeam = try TopologicalResolver.resolveEdge(in: torusShape, reference: minSeamRef)
        #expect(minSeam.isCircle)

        let vertRef = try #require(feature.generatedTopology["vertex:seam"])
        let vert = try TopologicalResolver.resolveVertex(in: torusShape, reference: vertRef)
        #expect(!vert.x.isNaN)
    }

    // MARK: - Wedge Sub-Element Resolution

    @Test func testResolveFaceEdgeVertexOnWedge() throws {
        guard let wedgeShape = Shape.wedge(
            at: SIMD3(-15, -15, -15),
            direction: SIMD3(0, 0, 1),
            dx: 30,
            dy: 30,
            dz: 30,
            ltx: 10
        ) else {
            Issue.record("Failed to create test wedge shape")
            return
        }

        let feature = Feature.makeWedge(params: WedgeParams(width: 30, depth: 30, height: 30, topWidth: 10))

        let bottomFaceRef = try #require(feature.generatedTopology["face:bottom"])
        let bottomFace = try TopologicalResolver.resolveFace(in: wedgeShape, reference: bottomFaceRef)
        #expect(bottomFace.isPlanar)

        let topFaceRef = try #require(feature.generatedTopology["face:top"])
        let topFace = try TopologicalResolver.resolveFace(in: wedgeShape, reference: topFaceRef)
        #expect(topFace.isPlanar)

        let topFrontEdgeRef = try #require(feature.generatedTopology["edge:top-front"])
        let topFrontEdge = try TopologicalResolver.resolveEdge(in: wedgeShape, reference: topFrontEdgeRef)
        #expect(topFrontEdge.isLine)

        let vertRef = try #require(feature.generatedTopology["vertex:top-front-left"])
        let vert = try TopologicalResolver.resolveVertex(in: wedgeShape, reference: vertRef)
        #expect(!vert.x.isNaN)
    }

    // MARK: - Upstream Dimension Changes & Invariance

    @Test func testUpstreamBoxDimensionChangeResolvesSameLogicalEdge() throws {
        let feature = Feature.makeBox(params: BoxParams(width: 40, depth: 30, height: 20))
        let topFrontRef = try #require(feature.generatedTopology["edge:top-front"])

        // Scale-up: 80x50x35
        let scaledUpShape = try #require(Shape.box(
            origin: SIMD3(-40, -25, -17.5),
            width: 80,
            height: 50,
            depth: 35
        ))
        let scaledUpEdge = try TopologicalResolver.resolveEdge(in: scaledUpShape, reference: topFrontRef)
        #expect(scaledUpEdge.isLine)
        #expect(abs(scaledUpEdge.length - 80.0) < 1e-4)
        let (f1, f2Opt) = try #require(scaledUpEdge.adjacentFaces(in: scaledUpShape))
        let f2 = try #require(f2Opt)
        let n1 = try #require(f1.normal)
        let n2 = try #require(f2.normal)
        let hasTop = n1.z > 0.99 || n2.z > 0.99
        let hasFront = n1.y < -0.99 || n2.y < -0.99
        #expect(hasTop && hasFront)

        // Scale-down: 10x10x10
        let scaledDownShape = try #require(Shape.box(
            origin: SIMD3(-5, -5, -5),
            width: 10,
            height: 10,
            depth: 10
        ))
        let scaledDownEdge = try TopologicalResolver.resolveEdge(in: scaledDownShape, reference: topFrontRef)
        #expect(scaledDownEdge.isLine)
        #expect(abs(scaledDownEdge.length - 10.0) < 1e-4)

        // Non-uniform scaling: 100x30x20
        let nonUniformShape = try #require(Shape.box(
            origin: SIMD3(-50, -15, -10),
            width: 100,
            height: 30,
            depth: 20
        ))
        let nonUniformEdge = try TopologicalResolver.resolveEdge(in: nonUniformShape, reference: topFrontRef)
        #expect(nonUniformEdge.isLine)
        #expect(abs(nonUniformEdge.length - 100.0) < 1e-4)
    }

    // MARK: - Fillet Across Upstream Dimension Changes

    @Test func testFilletAcrossUpstreamDimensionChange() async throws {
        let engine = LocalKernelEngine()
        let solidId = SolidId("box-fillet-test")
        let feature = Feature.makeBox(solidId: solidId, params: BoxParams(width: 40, depth: 30, height: 20))
        let topFrontRef = try #require(feature.generatedTopology["edge:top-front"])

        // Initial box creation
        let initRes = await engine.execute(.makeBox(
            jobId: JobId("box-init"),
            solidId: solidId,
            params: BoxParams(width: 40, depth: 30, height: 20)
        ))
        #expect(initRes.isSuccess)

        // Fillet edge:top-front with radius 2.0
        let fillet1 = await engine.fillet(solidId: solidId, edgeReference: topFrontRef, radius: 2.0)
        #expect(fillet1.isSuccess)
        let mesh1 = try #require(fillet1.value)
        #expect(mesh1.indices.count > 0)

        // Change upstream dimensions: scale up to 80x50x35
        let resizeRes1 = await engine.execute(.makeBox(
            jobId: JobId("box-scale-up"),
            solidId: solidId,
            params: BoxParams(width: 80, depth: 50, height: 35)
        ))
        #expect(resizeRes1.isSuccess)

        // Re-apply fillet with the SAME persistent TopologicalReference
        let fillet2 = await engine.fillet(solidId: solidId, edgeReference: topFrontRef, radius: 2.0)
        #expect(fillet2.isSuccess)
        let mesh2 = try #require(fillet2.value)
        #expect(mesh2.indices.count > 0)

        // Change upstream dimensions: scale down to 10x10x10
        let resizeRes2 = await engine.execute(.makeBox(
            jobId: JobId("box-scale-down"),
            solidId: solidId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        ))
        #expect(resizeRes2.isSuccess)

        // Re-apply fillet with radius 1.0 using the SAME reference
        let fillet3 = await engine.fillet(solidId: solidId, edgeReference: topFrontRef, radius: 1.0)
        #expect(fillet3.isSuccess)
        let mesh3 = try #require(fillet3.value)
        #expect(mesh3.indices.count > 0)
    }

    // MARK: - Cylinder Fillet Across Dimension Changes

    @Test func testCylinderFilletAcrossDimensionChange() async throws {
        let engine = LocalKernelEngine()
        let solidId = SolidId("cyl-fillet-test")
        let feature = Feature.makeCylinder(solidId: solidId, params: CylinderParams(radius: 15, height: 40))
        let topEdgeRef = try #require(feature.generatedTopology["edge:top"])

        // Initial cylinder
        let initRes = await engine.execute(.makeCylinder(
            jobId: JobId("cyl-init"),
            solidId: solidId,
            params: CylinderParams(radius: 15, height: 40)
        ))
        #expect(initRes.isSuccess)

        // Fillet circular top edge
        let fillet1 = await engine.fillet(solidId: solidId, edgeReference: topEdgeRef, radius: 1.5)
        #expect(fillet1.isSuccess)
        let mesh1 = try #require(fillet1.value)
        #expect(mesh1.indices.count > 0)

        // Upstream radius and height edit
        let resizeRes = await engine.execute(.makeCylinder(
            jobId: JobId("cyl-resize"),
            solidId: solidId,
            params: CylinderParams(radius: 25, height: 60)
        ))
        #expect(resizeRes.isSuccess)

        // Fillet again with the SAME topological reference
        let fillet2 = await engine.fillet(solidId: solidId, edgeReference: topEdgeRef, radius: 1.5)
        #expect(fillet2.isSuccess)
        let mesh2 = try #require(fillet2.value)
        #expect(mesh2.indices.count > 0)
    }

    // MARK: - Error Handling & Edge Cases

    @Test func testBrokenAndMismatchedReferencesFailCleanly() throws {
        guard let boxShape = Shape.box(width: 20, height: 20, depth: 20) else {
            Issue.record("Failed to create test box")
            return
        }

        let dummyId = UUID()

        // Mismatched element type: face query on resolveEdge
        let faceRef = TopologicalReference(
            sourceFeatureId: dummyId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")]
        )
        #expect(throws: KernelError.self) {
            try TopologicalResolver.resolveEdge(in: boxShape, reference: faceRef)
        }

        // Mismatched element type: edge query on resolveFace
        let edgeRef = TopologicalReference(
            sourceFeatureId: dummyId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:top-front")]
        )
        #expect(throws: KernelError.self) {
            try TopologicalResolver.resolveFace(in: boxShape, reference: edgeRef)
        }

        // Mismatched element type: vertex query on resolveEdge
        let vertRef = TopologicalReference(
            sourceFeatureId: dummyId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:top-front-left")]
        )
        #expect(throws: KernelError.self) {
            try TopologicalResolver.resolveEdge(in: boxShape, reference: vertRef)
        }

        // Non-existent labels
        let fakeFaceRef = TopologicalReference(
            sourceFeatureId: dummyId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:nonexistent")]
        )
        #expect(throws: KernelError.self) {
            try TopologicalResolver.resolveFace(in: boxShape, reference: fakeFaceRef)
        }

        let fakeEdgeRef = TopologicalReference(
            sourceFeatureId: dummyId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:nonexistent")]
        )
        #expect(throws: KernelError.self) {
            try TopologicalResolver.resolveEdge(in: boxShape, reference: fakeEdgeRef)
        }

        let fakeVertRef = TopologicalReference(
            sourceFeatureId: dummyId,
            elementType: .vertex,
            historyPath: [HistoryStep(kind: .generated, label: "vertex:nonexistent")]
        )
        #expect(throws: KernelError.self) {
            try TopologicalResolver.resolveVertex(in: boxShape, reference: fakeVertRef)
        }

        // Incompatible geometry: cylinder references on box shape
        let cylSideRef = TopologicalReference(
            sourceFeatureId: dummyId,
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:side")]
        )
        #expect(throws: KernelError.self) {
            try TopologicalResolver.resolveFace(in: boxShape, reference: cylSideRef)
        }

        let cylTopEdgeRef = TopologicalReference(
            sourceFeatureId: dummyId,
            elementType: .edge,
            historyPath: [HistoryStep(kind: .generated, label: "edge:top")]
        )
        #expect(throws: KernelError.self) {
            try TopologicalResolver.resolveEdge(in: boxShape, reference: cylTopEdgeRef)
        }
    }

    @Test func testFilletInvalidRadiusFailsGracefully() async throws {
        let engine = LocalKernelEngine()
        let solidId = SolidId("box-invalid-fillet")
        let feature = Feature.makeBox(solidId: solidId, params: BoxParams(width: 10, depth: 10, height: 10))
        let topFrontRef = try #require(feature.generatedTopology["edge:top-front"])

        let res = await engine.execute(.makeBox(
            jobId: JobId("init"),
            solidId: solidId,
            params: BoxParams(width: 10, depth: 10, height: 10)
        ))
        #expect(res.isSuccess)

        // Excessive radius: 100mm fillet on a 10mm box
        let failRes = await engine.fillet(solidId: solidId, edgeReference: topFrontRef, radius: 100.0)
        #expect(!failRes.isSuccess)
        #expect(failRes.error?.code == .geometryFailed)

        // Fillet on unknown solid
        let unknownSolidRes = await engine.fillet(solidId: SolidId("nonexistent"), edgeReference: topFrontRef, radius: 1.0)
        #expect(!unknownSolidRes.isSuccess)
        #expect(unknownSolidRes.error?.code == .unknownSolid)
    }
}
