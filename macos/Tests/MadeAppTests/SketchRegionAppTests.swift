import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite struct SketchRegionTests {

    @MainActor
    @Test func testRegionHoverAndSelectionState() throws {
        let workspace = WorkspaceModel()
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 10.0)
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [circle])

        workspace.refreshSketchStatus(for: sketch.id)
        #expect(workspace.detectedSketchRegions.count == 1)
        let region = workspace.detectedSketchRegions[0]

        // 1. Initial hover is nil
        #expect(workspace.hoveredSketchRegionId == nil)

        // 2. Set hover
        workspace.setHoveredSketchRegion(region.id)
        #expect(workspace.hoveredSketchRegionId == region.id)

        // 3. Select region
        workspace.selectSketchRegion(featureId: sketch.id, regionId: region.id)
        #expect(workspace.selectedSketchRegionId == region.id)

        // 4. Hover exit clears hover
        workspace.setHoveredSketchRegion(nil)
        #expect(workspace.hoveredSketchRegionId == nil)
        #expect(workspace.selectedSketchRegionId == region.id)
    }

    @MainActor
    @Test func testExtrudeSpecificRegionCommand() async throws {
        let workspace = WorkspaceModel()
        // Outer rectangle [-20, 20] x [-20, 20] with inner circle R=5
        let l1 = SketchEntity.line(start: SIMD2(-20, -20), end: SIMD2(20, -20))
        let l2 = SketchEntity.line(start: SIMD2(20, -20), end: SIMD2(20, 20))
        let l3 = SketchEntity.line(start: SIMD2(20, 20), end: SIMD2(-20, 20))
        let l4 = SketchEntity.line(start: SIMD2(-20, 20), end: SIMD2(-20, -20))
        let hole = SketchEntity.circle(center: SIMD2(0, 0), radius: 5.0)

        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4, hole])

        workspace.refreshSketchStatus(for: sketch.id)
        #expect(workspace.detectedSketchRegions.count == 2)

        let plateRegion = try #require(workspace.detectedSketchRegions.first(where: { !$0.innerLoops.isEmpty }))
        let diskRegion = try #require(workspace.detectedSketchRegions.first(where: { $0.innerLoops.isEmpty }))

        // Extrude specifically the plate region with its hole
        let solidId = await workspace.extrudeSketch(
            sketchFeatureId: sketch.id,
            distance: 20.0,
            isSymmetric: false,
            regionId: plateRegion.id
        )
        let sid = try #require(solidId)
        let feat = try #require(workspace.document.feature(for: sid))
        guard case .extrude(let data) = feat.operation else {
            Issue.record("Expected extrude operation")
            return
        }
        #expect(data.regionId == plateRegion.id)
        #expect(data.profile?.holes.count == 1)

        // Extrude specifically the inner disk region as a separate solid
        let solidId2 = await workspace.extrudeSketch(
            sketchFeatureId: sketch.id,
            distance: 30.0,
            isSymmetric: false,
            regionId: diskRegion.id
        )
        let sid2 = try #require(solidId2)
        let feat2 = try #require(workspace.document.feature(for: sid2))
        guard case .extrude(let data2) = feat2.operation else {
            Issue.record("Expected extrude operation")
            return
        }
        #expect(data2.regionId == diskRegion.id)
        #expect(data2.profile?.holes.isEmpty == true)
    }
}
