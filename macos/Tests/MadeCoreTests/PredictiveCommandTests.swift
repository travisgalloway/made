import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct PredictiveCommandTests {

    @Test func testEdgeCommandAvailability() {
        let commands = PredictiveCommandProvider.availableCommands(for: .edge)
        #expect(commands.count == 2)
        let chamfer = commands.first(where: { $0.id == .chamfer })
        #expect(chamfer?.id == .chamfer)
        #expect(chamfer?.title == "Chamfer")
        #expect(chamfer?.isEnabled == true)
        #expect(chamfer?.disabledReason == nil)
        let fillet = commands.first(where: { $0.id == .fillet })
        #expect(fillet?.id == .fillet)
        #expect(fillet?.title == "Fillet")
        #expect(fillet?.isEnabled == false)
        #expect(fillet?.disabledReason != nil)
        #expect(fillet?.disabledReason?.contains("#82") == true)
        #expect(commands.contains(where: { $0.id == .pushPull }) == false)
    }

    @Test func testPlanarFaceCommandAvailability() {
        let commands = PredictiveCommandProvider.availableCommands(for: .face, isPlanarFace: true)
        #expect(commands.count == 3)
        let pushPull = commands.first(where: { $0.id == .pushPull })
        #expect(pushPull?.id == .pushPull)
        #expect(pushPull?.title == "Push-Pull")
        #expect(pushPull?.isEnabled == true)
        #expect(pushPull?.disabledReason == nil)
        let shell = commands.first(where: { $0.id == .shell })
        #expect(shell?.id == .shell)
        #expect(shell?.title == "Shell")
        #expect(shell?.isEnabled == true)
        #expect(shell?.disabledReason == nil)
        let hole = commands.first(where: { $0.id == .hole })
        #expect(hole?.id == .hole)
        #expect(hole?.title == "Hole")
        #expect(hole?.isEnabled == true)
        #expect(hole?.disabledReason == nil)
        #expect(commands.contains(where: { $0.id == .fillet }) == false)
    }

    @Test func testNonPlanarFaceCommandAvailability() {
        let commands = PredictiveCommandProvider.availableCommands(for: .face, isPlanarFace: false)
        #expect(commands.isEmpty)
        #expect(commands.contains(where: { $0.id == .pushPull }) == false)
        #expect(commands.contains(where: { $0.id == .fillet }) == false)
    }

    @Test func testVertexAndEmptySelectionYieldsNoCommands() {
        let vertexCommands = PredictiveCommandProvider.availableCommands(for: .vertex)
        #expect(vertexCommands.isEmpty)
    }

    @Test func testCandidateMeshPlanarityDetection() {
        // Box faces are all planar
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let boxMesh = CandidateMesh(id: SolidId("box"), payload: boxPayload)
        for faceRange in boxPayload.faceRanges {
            #expect(boxMesh.isFacePlanar(forFaceId: faceRange.faceId) == true)
        }

        // Cylinder: side face (0) is curved; top (1) and bottom (2) caps are planar
        let cylPayload = NativeGeometryGenerator.generateCylinder(radius: 10, height: 20, segments: 16)
        let cylMesh = CandidateMesh(id: SolidId("cyl"), payload: cylPayload)
        #expect(cylMesh.isFacePlanar(forFaceId: 0) == false)
        #expect(cylMesh.isFacePlanar(forFaceId: 1) == true)
        #expect(cylMesh.isFacePlanar(forFaceId: 2) == true)

        // Sphere: single curved surface
        let spherePayload = NativeGeometryGenerator.generateSphere(radius: 10)
        let sphereMesh = CandidateMesh(id: SolidId("sphere"), payload: spherePayload)
        for faceRange in spherePayload.faceRanges {
            #expect(sphereMesh.isFacePlanar(forFaceId: faceRange.faceId) == false)
        }
    }

    @Test func testCandidateMeshCentroids() {
        let boxPayload = NativeGeometryGenerator.generateBox(width: 20, depth: 20, height: 20)
        let transform = Transform(position: SIMD3<Float>(10, 20, 30))
        let boxMesh = CandidateMesh(id: SolidId("box"), payload: boxPayload, transform: transform)

        // Edge centroid
        let edge0Centroid = boxMesh.edgeCentroid(forEdgeId: 0)
        #expect(edge0Centroid != nil)
        let subEdgeCentroid = boxMesh.subElementCentroid(elementType: .edge, elementId: 0)
        #expect(subEdgeCentroid == edge0Centroid)

        // Face centroid
        let face0Centroid = boxMesh.faceCentroid(forFaceId: 0)
        #expect(face0Centroid != nil)
        let subFaceCentroid = boxMesh.subElementCentroid(elementType: .face, elementId: 0)
        #expect(subFaceCentroid == face0Centroid)

        // Vertex centroid
        let subVertexCentroid = boxMesh.subElementCentroid(elementType: .vertex, elementId: 0)
        #expect(subVertexCentroid != nil)
    }
}
