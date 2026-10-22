import Testing
import Foundation
import simd
import OCCTSwift
@testable import MadeCore

@Suite struct HiddenLineRemovalTests {

    @Test func testBoxTopViewVisibleAndHiddenSharpEdges() throws {
        let box = try #require(Shape.box(width: 20, height: 20, depth: 20))
        let result = HLREngine.computeHLR(shape: box, direction: HLRStandardView.top.direction)

        #expect(result.visibleEdges.count == 4, "Top view of box must have 4 visible edges (top square)")
        #expect(result.hiddenEdges.count == 4, "Top view of box must have 4 hidden edges (bottom square)")
        #expect(result.silhouetteEdges.count == 0, "Box has sharp planar edges, no curved silhouettes")
        #expect(result.tangentEdges.count == 0, "Box has no filleted smooth tangent transitions")

        let bounds = try #require(result.bounds2D)
        #expect(bounds.width > 0 && bounds.height > 0)
    }

    @Test func testBoxIsometricViewVisibleAndHiddenEdges() throws {
        let box = try #require(Shape.box(width: 20, height: 20, depth: 20))
        let result = HLREngine.computeHLR(shape: box, direction: HLRStandardView.isometric.direction)

        #expect(result.visibleSharpEdges.count == 9, "Isometric view reveals 9 visible edges of a box")
        #expect(result.hiddenSharpEdges.count == 3, "Isometric view leaves 3 hidden edges at the back of a box")
        #expect(result.edges.count == 12, "Box must have 12 total edges in HLR projection")
    }

    @Test func testCylinderSideViewSilhouetteAndSharpEdges() throws {
        let cylinder = try #require(Shape.cylinder(radius: 10, height: 30))
        let result = HLREngine.computeHLR(shape: cylinder, direction: HLRStandardView.right.direction)

        #expect(result.visibleSilhouetteEdges.count == 2, "Side view of cylinder must project 2 silhouette outline edges")
        #expect(result.visibleSharpEdges.count > 0, "Top and bottom circular rims project visible sharp lines")
    }

    @Test func testCylinderTopViewEndOn() throws {
        let cylinder = try #require(Shape.cylinder(radius: 10, height: 30))
        let result = HLREngine.computeHLR(shape: cylinder, direction: HLRStandardView.top.direction)

        #expect(result.silhouetteEdges.count == 0, "End-on view of cylinder produces circular rims, not silhouette outlines")
        #expect(result.visibleSharpEdges.count == 1, "Top circular rim is visible")
        #expect(result.hiddenSharpEdges.count == 1, "Bottom circular rim is hidden")
    }

    @Test func testFilletedBoxTangentEdges() throws {
        let box = try #require(Shape.box(width: 30, height: 30, depth: 30))
        let filleted = try #require(box.filleted(radius: 3.0))

        let result = HLREngine.computeHLR(shape: filleted, direction: HLRStandardView.isometric.direction)
        #expect(result.tangentEdges.count > 0, "Filleted box must produce smooth tangent transition edges")
        #expect(result.visibleTangentEdges.count > 0, "Isometric view of filleted box must contain visible tangent edges")
    }

    @Test func testSphereSilhouetteOnly() throws {
        let sphere = try #require(Shape.sphere(radius: 15))
        let result = HLREngine.computeHLR(shape: sphere, direction: HLRStandardView.top.direction)

        #expect(result.visibleSharpEdges.count == 0, "Sphere has no sharp visible edges")
        #expect(result.hiddenSharpEdges.count == 0, "Sphere has no sharp hidden edges")
        #expect(result.silhouetteEdges.count > 0, "Sphere projection is defined entirely by its silhouette outline")
        #expect(result.tangentEdges.count == 0, "Sphere has no tangent transitions")
    }



    @Test func testAssemblyOcclusionMultiObject() throws {
        // Front object A occludes back object B
        let frontBox = SceneObject(
            id: SolidId("front-box"),
            name: "FrontBox",
            def: .box(BoxParams(width: 40, depth: 40, height: 10)),
            transform: Transform(position: SIMD3<Float>(0, 0, 30))
        )
        let backBox = SceneObject(
            id: SolidId("back-box"),
            name: "BackBox",
            def: .box(BoxParams(width: 20, depth: 20, height: 10)),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )

        let result = HLREngine.computeHLR(
            objects: [frontBox, backBox],
            direction: HLRStandardView.top.direction
        )

        #expect(!result.edges.isEmpty)
        // Back box is completely behind front box from top view; all its edges must be hidden
        #expect(result.hiddenEdges.count >= 8, "Back box edges and back of front box must be categorized as hidden")
        #expect(result.visibleEdges.count == 4, "Only the 4 top edges of front box should be visible")
    }

    @Test func testLocalKernelEngineAndClientAsyncHLR() async throws {
        let engine = LocalKernelEngine()
        let client = KernelClient(engine: engine, debounceDuration: .milliseconds(5))

        let solidId = SolidId("hlr-test-box")
        let makeReq = KernelRequest.makeBox(
            jobId: JobId("box-job"),
            solidId: solidId,
            params: BoxParams(width: 20, depth: 20, height: 20)
        )
        let makeResult = await client.request(makeReq)
        #expect(makeResult.isSuccess)

        let hlrResult = await client.computeHLR(solidId: solidId, view: .top)
        #expect(hlrResult.isSuccess)
        let value = try #require(hlrResult.value)
        #expect(value.visibleEdges.count == 4)
        #expect(value.hiddenEdges.count == 4)

        // Test objects overload
        let boxObj = SceneObject(
            id: solidId,
            name: "BoxObj",
            def: .box(BoxParams(width: 20, depth: 20, height: 20))
        )
        let objResult = await client.computeHLR(objects: [boxObj], view: .isometric)
        #expect(objResult.isSuccess)
        let objValue = try #require(objResult.value)
        #expect(objValue.visibleSharpEdges.count == 9)
    }

    @Test func testHLROptionsFiltering() throws {
        let box = try #require(Shape.box(width: 20, height: 20, depth: 20))

        // Without hidden lines
        let noHiddenOptions = HLROptions(includeHidden: false)
        let noHiddenResult = HLREngine.computeHLR(
            shape: box,
            direction: HLRStandardView.isometric.direction,
            options: noHiddenOptions
        )
        #expect(noHiddenResult.hiddenEdges.count == 0)
        #expect(noHiddenResult.visibleEdges.count == 9)

        // With 3D model curve extraction enabled
        let options3D = HLROptions(compute3D: true)
        let result3D = HLREngine.computeHLR(
            shape: box,
            direction: HLRStandardView.top.direction,
            options: options3D
        )
        #expect(result3D.visibleEdges.allSatisfy { !$0.points3D.isEmpty }, "3D points should be populated when compute3D is true")

        // Without silhouettes on cylinder
        let cylinder = try #require(Shape.cylinder(radius: 10, height: 30))
        let noSilhouetteOptions = HLROptions(includeSilhouette: false)
        let noSilResult = HLREngine.computeHLR(
            shape: cylinder,
            direction: HLRStandardView.right.direction,
            options: noSilhouetteOptions
        )
        #expect(noSilResult.silhouetteEdges.count == 0)
    }

    @Test func testDegenerateAndEmptyInputs() async throws {
        let box = try #require(Shape.box(width: 20, height: 20, depth: 20))

        // Zero-length direction vector
        let zeroDirResult = HLREngine.computeHLR(shape: box, direction: SIMD3<Double>(0, 0, 0))
        #expect(zeroDirResult.edges.isEmpty)

        // Empty objects array
        let emptyObjResult = HLREngine.computeHLR(objects: [], direction: HLRStandardView.top.direction)
        #expect(emptyObjResult.edges.isEmpty)

        // Missing solidId in engine
        let engine = LocalKernelEngine()
        let missingSolidResult = await engine.computeHLR(
            request: HLRRequest(solidId: SolidId("non-existent"), direction: SIMD3(0, 0, 1))
        )
        #expect(!missingSolidResult.isSuccess)
        if case .failure(_, let err) = missingSolidResult {
            #expect(err.code == .unknownSolid)
        }

        // Invalid request without objects or solidId
        let invalidReq = HLRRequest(direction: SIMD3(0, 0, 1))
        let invalidResult = await engine.computeHLR(request: invalidReq)
        #expect(!invalidResult.isSuccess)
        if case .failure(_, let err) = invalidResult {
            #expect(err.code == .invalidParams)
        }
    }
}
