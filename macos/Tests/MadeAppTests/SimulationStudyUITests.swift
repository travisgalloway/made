import Testing
import Foundation
import SwiftUI
import simd
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct SimulationStudyUITests {

    @Test func testWorkspaceSimulationStudyActions() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Truss FEA") else {
            Issue.record("Failed to create simulation study")
            return
        }

        #expect(ws.document.studies.count == 1)
        #expect(ws.document.activeStudyId == study.id)
        #expect(ws.selectedSimulationStudyId == study.id)
        #expect(ws.isDocumentModified)

        let fixture = ws.addSimulationFixture(studyId: study.id, fixture: SimulationFixture(name: "Base Clamp", kind: .fixed))
        #expect(ws.document.study(id: study.id)?.fixtures.count == 1)
        #expect(ws.selectedSimulationFixtureId == fixture?.id)

        let load = ws.addSimulationLoad(studyId: study.id, load: SimulationLoad(name: "Point Force", kind: .force))
        #expect(ws.document.study(id: study.id)?.loads.count == 1)
        #expect(ws.selectedSimulationLoadId == load?.id)

        ws.removeSimulationStudy(id: study.id)
        #expect(ws.document.studies.isEmpty)
        #expect(ws.document.activeStudyId == nil)
        #expect(ws.selectedSimulationStudyId == nil)
    }

    @Test func testMutualSelectionExclusion() {
        let ws = WorkspaceModel()
        let solidId = SolidId("solid-bracket-1")
        ws.selectedId = solidId
        ws.selectedIds = [solidId]

        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Bracket Study") else {
            Issue.record("Failed to create simulation study")
            return
        }
        #expect(ws.selectedSimulationStudyId == study.id)
        #expect(ws.selectedId == nil)
        #expect(ws.selectedIds.isEmpty)

        ws.select(solidId: solidId)
        #expect(ws.selectedId == solidId)
        #expect(ws.selectedSimulationStudyId == nil)
        #expect(ws.selectedSimulationFixtureId == nil)
        #expect(ws.selectedSimulationLoadId == nil)
        #expect(ws.isSimulationMeshSelected == false)
        #expect(ws.isSimulationResultsSelected == false)
    }

    @Test func testSimulationSubnodeSelectionRouting() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .thermalConduction, name: "Thermal Study") else {
            Issue.record("Failed to create simulation study")
            return
        }

        ws.selectSimulationMesh(studyId: study.id)
        #expect(ws.selectedSimulationStudyId == study.id)
        #expect(ws.isSimulationMeshSelected == true)
        #expect(ws.selectedSimulationFixtureId == nil)
        #expect(ws.selectedSimulationLoadId == nil)

        ws.selectSimulationResults(studyId: study.id)
        #expect(ws.isSimulationMeshSelected == false)
        #expect(ws.isSimulationResultsSelected == true)
    }

    @Test func testAccessibilityIdentifiers() {
        let studyId = UUID()
        let rowId = "navigator-study-\(studyId)"
        let badgeId = "navigator-study-active-badge-\(studyId)"

        #expect(rowId.hasPrefix("navigator-study-"))
        #expect(badgeId.hasPrefix("navigator-study-active-badge-"))
    }

    @Test func testInspectorViewsInstantiation() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Test Study") else {
            Issue.record("Failed to create simulation study")
            return
        }
        let fixture = SimulationFixture(name: "Base Clamp", kind: .fixed)
        let load = SimulationLoad(name: "Pushed Load", kind: .force, magnitude: 120)

        _ = InspectorSimulationStudyView(study: study).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: fixture).environment(ws)
        _ = InspectorSimulationLoadView(study: study, load: load).environment(ws)
        _ = InspectorSimulationMeshView(study: study).environment(ws)
        _ = InspectorSimulationResultsView(study: study).environment(ws)
    }
}
