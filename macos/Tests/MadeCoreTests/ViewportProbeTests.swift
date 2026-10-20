import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct ViewportProbeTests {
    @Test func testFormattingDeterministicAndOrdered() {
        let hitB = ViewportProbeHit(id: SolidId("box-2"), normalizedOffset: SIMD2<Double>(0.75, 0.25))
        let hitA = ViewportProbeHit(id: SolidId("box-1"), normalizedOffset: SIMD2<Double>(0.5, 0.5))
        let snapshot = ViewportProbeSnapshot(
            state: "ready",
            renders: 42,
            draws: 8,
            reason: "selectionChange",
            selection: "box-1",
            hits: [hitB, hitA]
        )

        let formatted = snapshot.formatted()
        #expect(formatted == "state=ready;renders=42;draws=8;reason=selectionChange;selection=box-1;hits=box-1:0.500,0.500|box-2:0.750,0.250")
    }

    @Test func testFormattingThreeDecimalRounding() {
        let hit = ViewportProbeHit(id: SolidId("cylinder-1"), normalizedOffset: SIMD2<Double>(0.123456, 0.987654))
        let snapshot = ViewportProbeSnapshot(
            state: "ready",
            renders: 1,
            draws: 1,
            reason: "init",
            selection: "cylinder-1",
            hits: [hit]
        )

        let formatted = snapshot.formatted()
        #expect(formatted == "state=ready;renders=1;draws=1;reason=init;selection=cylinder-1;hits=cylinder-1:0.123,0.988")
    }

    @Test func testEmptyStatesFormattingAndParsing() {
        let emptySnapshot = ViewportProbeSnapshot(
            state: "ready",
            renders: 0,
            draws: 0,
            reason: "",
            selection: "",
            hits: []
        )

        let formatted = emptySnapshot.formatted()
        #expect(formatted == "state=ready;renders=0;draws=0;reason=;selection=;hits=")

        let parsed = ViewportProbe.parse(formatted)
        #expect(parsed == emptySnapshot)
    }

    @Test func testParseRoundtripWithCoordinates() {
        let original = ViewportProbeSnapshot(
            state: "ready",
            renders: 5,
            draws: 3,
            reason: "drag",
            selection: "box-1",
            hits: [
                ViewportProbeHit(id: SolidId("box-1"), normalizedOffset: SIMD2<Double>(0.500, 0.500)),
                ViewportProbeHit(id: SolidId("sphere-1"), normalizedOffset: SIMD2<Double>(0.200, 0.800))
            ]
        )

        let formatted = original.formatted()
        let parsed = ViewportProbe.parse(formatted)
        #expect(parsed == original)
    }

    @Test func testProjectHitsProjectionAndFrustumCulling() {
        // Orthographic camera looking down -Z axis from (0, 0, 100) towards (0, 0, 0)
        let eye = SIMD3<Float>(0, 0, 100)
        let target = SIMD3<Float>(0, 0, 0)
        let viewMatrix = Orientation.makeLookAt(eye: eye, target: target, up: Orientation.worldUp)
        let projMatrix = Orientation.makeOrthographic(left: -50, right: 50, bottom: -50, top: 50, nearZ: 1.0, farZ: 200.0)

        // Mesh 1: centered at (0, 0, 0) -> should project to exactly (0.5, 0.5)
        let centerPts = [
            SIMD3<Float>(-5, -5, -5),
            SIMD3<Float>(5, 5, 5)
        ]
        let centerMesh = CandidateMesh(id: SolidId("box-center"), positions: centerPts, edges: [])

        // Mesh 2: off-center at (25, 25, 0) -> NDC (+0.5, +0.5) -> dx = 0.75, dy = 0.25 (since y is inverted)
        let offCenterPts = [
            SIMD3<Float>(20, 20, -5),
            SIMD3<Float>(30, 30, 5)
        ]
        let offCenterMesh = CandidateMesh(id: SolidId("box-offcenter"), positions: offCenterPts, edges: [])

        // Mesh 3: outside frustum at (100, 100, 0) -> culled
        let outsidePts = [
            SIMD3<Float>(90, 90, -5),
            SIMD3<Float>(110, 110, 5)
        ]
        let outsideMesh = CandidateMesh(id: SolidId("box-outside"), positions: outsidePts, edges: [])

        // Mesh 4: behind near plane at (0, 0, 200) -> culled
        let behindPts = [
            SIMD3<Float>(-5, -5, 195),
            SIMD3<Float>(5, 5, 205)
        ]
        let behindMesh = CandidateMesh(id: SolidId("box-behind"), positions: behindPts, edges: [])

        let hits = ViewportProbe.projectHits(
            candidateMeshes: [outsideMesh, offCenterMesh, centerMesh, behindMesh],
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )

        // Only centerMesh and offCenterMesh should pass frustum culling, sorted alphabetically
        #expect(hits.count == 2)
        #expect(hits[0].id == SolidId("box-center"))
        #expect(abs(hits[0].x - 0.5) < 1e-4)
        #expect(abs(hits[0].y - 0.5) < 1e-4)

        #expect(hits[1].id == SolidId("box-offcenter"))
        #expect(abs(hits[1].x - 0.75) < 1e-4)
        #expect(abs(hits[1].y - 0.25) < 1e-4)
    }

    @Test func testProjectHitsEmptyCandidateMeshes() {
        let viewMatrix = matrix_identity_float4x4
        let projMatrix = matrix_identity_float4x4
        let hits = ViewportProbe.projectHits(
            candidateMeshes: [],
            viewMatrix: viewMatrix,
            projectionMatrix: projMatrix
        )
        #expect(hits.isEmpty)
    }
}
