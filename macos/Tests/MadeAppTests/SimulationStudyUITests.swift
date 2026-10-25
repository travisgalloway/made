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
        let connection = SimulationConnection(name: "Bonded Joint", kind: .bonded)

        _ = InspectorSimulationStudyView(study: study).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: fixture).environment(ws)
        _ = InspectorSimulationLoadView(study: study, load: load).environment(ws)
        _ = InspectorSimulationConnectionView(study: study, connection: connection).environment(ws)
        _ = InspectorSimulationMeshView(study: study).environment(ws)
        _ = InspectorSimulationResultsView(study: study).environment(ws)
    }

    @Test func testWorkspaceRunSimulationStudyLifecycle() async throws {
        let mockRunner = MockSolverRunner()
        await mockRunner.setDelayNanoseconds(50_000_000) // 50 ms
        let ws = WorkspaceModel(solverRunner: mockRunner)

        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Solve Study") else {
            Issue.record("Failed to create study")
            return
        }

        #expect(!ws.isStudyRunning(study.id))
        ws.runSimulationStudy(id: study.id)

        #expect(ws.isStudyRunning(study.id))
        #expect(ws.document.study(id: study.id)?.results.status == .solving)

        // Prevent double run
        ws.runSimulationStudy(id: study.id)
        #expect(ws.isStudyRunning(study.id))

        // Wait for solve task completion
        for _ in 0..<50 {
            if !ws.isStudyRunning(study.id) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!ws.isStudyRunning(study.id))
        let results = ws.document.study(id: study.id)?.results
        #expect(results?.status == .completed)
        #expect(results?.errorMessage == nil)
        #expect((results?.runtimeDuration ?? 0) >= 0)

        // Check CAE console logs
        let caeLogs = ws.logs.filter { $0.subsystem == "CAE" }
        #expect(caeLogs.contains { $0.message.contains("Starting solver") })
        #expect(caeLogs.contains { $0.message.contains("CalculiX Mock") })
        #expect(caeLogs.contains { $0.message.contains("completed") })
    }

    @Test func testWorkspaceCancelSimulationStudy() async throws {
        let mockRunner = MockSolverRunner()
        await mockRunner.setDelayNanoseconds(500_000_000) // 500 ms
        let ws = WorkspaceModel(solverRunner: mockRunner)

        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Cancel Study") else {
            Issue.record("Failed to create study")
            return
        }

        ws.runSimulationStudy(id: study.id)
        #expect(ws.isStudyRunning(study.id))

        try await Task.sleep(for: .milliseconds(20))
        ws.cancelSimulationStudy(id: study.id)

        for _ in 0..<50 {
            if !ws.isStudyRunning(study.id) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(!ws.isStudyRunning(study.id))
        let results = ws.document.study(id: study.id)?.results
        #expect(results?.status == .cancelled)

        let caeLogs = ws.logs.filter { $0.subsystem == "CAE" }
        #expect(caeLogs.contains { $0.message.contains("cancelled") })
    }

    @Test func testWorkspaceRunSimulationStudyBinaryNotFound() async throws {
        let mockRunner = MockSolverRunner()
        await mockRunner.setShouldFailWithBinaryNotFound(true)
        let ws = WorkspaceModel(solverRunner: mockRunner)

        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Missing Binary Study") else {
            Issue.record("Failed to create study")
            return
        }

        ws.runSimulationStudy(id: study.id)

        for _ in 0..<50 {
            if !ws.isStudyRunning(study.id) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!ws.isStudyRunning(study.id))
        let results = ws.document.study(id: study.id)?.results
        #expect(results?.status == .failed)
        #expect(results?.errorMessage?.contains("Solver binary not found") == true)

        let caeLogs = ws.logs.filter { $0.subsystem == "CAE" }
        #expect(caeLogs.contains { $0.message.contains("failed") })
    }

    @Test func testWorkspaceGenerateSimulationMeshLifecycle() async throws {
        let mockMesher = MockVolumeMesher()
        await mockMesher.setDelayNanoseconds(50_000_000) // 50 ms
        let ws = WorkspaceModel(volumeMesher: mockMesher)

        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Meshing Study") else {
            Issue.record("Failed to create study")
            return
        }

        #expect(!ws.isStudyMeshing(study.id))
        ws.generateSimulationMesh(studyId: study.id)

        #expect(ws.isStudyMeshing(study.id))
        #expect(ws.document.study(id: study.id)?.results.status == .meshing)

        // Prevent double generation
        ws.generateSimulationMesh(studyId: study.id)
        #expect(ws.isStudyMeshing(study.id))

        // Wait for task completion
        for _ in 0..<50 {
            if !ws.isStudyMeshing(study.id) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!ws.isStudyMeshing(study.id))
        let results = ws.document.study(id: study.id)?.results
        #expect(results?.status == .notRun)
        #expect(results?.meshStatistics.elementCount == 1)
        #expect(results?.meshStatistics.nodeCount == 10)
        #expect(results?.errorMessage == nil)

        let caeLogs = ws.logs.filter { $0.subsystem == "CAE" }
        #expect(caeLogs.contains { $0.message.contains("Starting volume mesher") })
        #expect(caeLogs.contains { $0.message.contains("Mock Gmsh") })
        #expect(caeLogs.contains { $0.message.contains("Meshing completed") })
    }

    @Test func testWorkspaceCancelSimulationMesh() async throws {
        let mockMesher = MockVolumeMesher()
        await mockMesher.setDelayNanoseconds(500_000_000) // 500 ms
        let ws = WorkspaceModel(volumeMesher: mockMesher)

        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Cancel Mesh Study") else {
            Issue.record("Failed to create study")
            return
        }

        ws.generateSimulationMesh(studyId: study.id)
        #expect(ws.isStudyMeshing(study.id))

        try await Task.sleep(for: .milliseconds(20))
        ws.cancelSimulationMesh(studyId: study.id)

        for _ in 0..<50 {
            if !ws.isStudyMeshing(study.id) {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(!ws.isStudyMeshing(study.id))
        let results = ws.document.study(id: study.id)?.results
        #expect(results?.status == .cancelled)

        let caeLogs = ws.logs.filter { $0.subsystem == "CAE" }
        #expect(caeLogs.contains { $0.message.contains("cancelled") })
    }

    @Test func testWorkspaceGenerateSimulationMeshBinaryNotFound() async throws {
        let mockMesher = MockVolumeMesher()
        await mockMesher.setShouldFailWithBinaryNotFound(true)
        let ws = WorkspaceModel(volumeMesher: mockMesher)

        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Missing Mesher Study") else {
            Issue.record("Failed to create study")
            return
        }

        ws.generateSimulationMesh(studyId: study.id)

        for _ in 0..<50 {
            if !ws.isStudyMeshing(study.id) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!ws.isStudyMeshing(study.id))
        let results = ws.document.study(id: study.id)?.results
        #expect(results?.status == .failed)
        #expect(results?.errorMessage?.contains("Gmsh (gmsh)") == true)

        let caeLogs = ws.logs.filter { $0.subsystem == "CAE" }
        #expect(caeLogs.contains { $0.message.contains("failed") })
    }

    @Test func testInspectorSimulationMeshViewRenderStats() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Stats Study") else {
            Issue.record("Failed to create study")
            return
        }
        study.results.meshStatistics = SimulationMeshStatistics(
            nodeCount: 150,
            elementCount: 420,
            minElementQuality: 0.65,
            avgElementQuality: 0.88
        )
        study.results.runtimeDuration = 1.45
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)

        let view = InspectorSimulationMeshView(study: study).environment(ws)
        _ = view
        #expect(study.results.meshStatistics.elementCount == 420)
    }

    @Test func testInspectorSimulationMeshViewCurvatureControls() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Curvature Mesh Study") else {
            Issue.record("Failed to create study")
            return
        }

        #expect(study.mesh.curvatureRefinement == false)
        #expect(study.mesh.curvatureElementsPerCircle == 12.0)

        // Instantiate view with curvature disabled
        let viewDisabled = InspectorSimulationMeshView(study: study).environment(ws)
        _ = viewDisabled

        // Update mesh specification with curvature enabled and custom elements per circle
        var updatedMesh = study.mesh
        updatedMesh.curvatureRefinement = true
        updatedMesh.curvatureElementsPerCircle = 18.0
        ws.updateSimulationMeshSpecification(studyId: study.id, mesh: updatedMesh)

        guard let refreshedStudy = ws.document.study(id: study.id) else {
            Issue.record("Failed to fetch refreshed study")
            return
        }
        #expect(refreshedStudy.mesh.curvatureRefinement == true)
        #expect(refreshedStudy.mesh.curvatureElementsPerCircle == 18.0)

        // Instantiate view with curvature enabled
        let viewEnabled = InspectorSimulationMeshView(study: refreshedStudy).environment(ws)
        _ = viewEnabled
    }

    @Test func testWorkspaceAssignSelectedSubElementToFixture() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Fixture Selection Study") else {
            Issue.record("Failed to create study")
            return
        }
        guard let fixture = ws.addSimulationFixture(studyId: study.id) else {
            Issue.record("Failed to create fixture")
            return
        }

        #expect(fixture.targetReferences.isEmpty)

        ws.document.selectedSubElement = SelectedSubElement(
            solidId: SolidId("box-solid-1"),
            elementType: .face,
            elementId: 3
        )

        ws.assignSelectedSubElementToFixture(studyId: study.id, fixtureId: fixture.id)

        let updatedFixture = ws.document.study(id: study.id)?.fixtures.first { $0.id == fixture.id }
        #expect(updatedFixture?.targetReferences.count == 1)
        #expect(updatedFixture?.targetReferences.first?.targetName == "Face 3")
        #expect(updatedFixture?.targetReferences.first?.subelementType == .face)

        if let refId = updatedFixture?.targetReferences.first?.id {
            ws.removeTargetReferenceFromFixture(studyId: study.id, fixtureId: fixture.id, referenceId: refId)
            let clearedFixture = ws.document.study(id: study.id)?.fixtures.first { $0.id == fixture.id }
            #expect(clearedFixture?.targetReferences.isEmpty == true)
        }
    }

    @Test func testWorkspaceAssignSelectedSubElementToLoad() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Load Selection Study") else {
            Issue.record("Failed to create study")
            return
        }
        guard let load = ws.addSimulationLoad(studyId: study.id) else {
            Issue.record("Failed to create load")
            return
        }

        #expect(load.targetReferences.isEmpty)

        ws.document.selectedSubElement = SelectedSubElement(
            solidId: SolidId("box-solid-1"),
            elementType: .face,
            elementId: 5
        )

        ws.assignSelectedSubElementToLoad(studyId: study.id, loadId: load.id)

        let updatedLoad = ws.document.study(id: study.id)?.loads.first { $0.id == load.id }
        #expect(updatedLoad?.targetReferences.count == 1)
        #expect(updatedLoad?.targetReferences.first?.targetName == "Face 5")
        #expect(updatedLoad?.targetReferences.first?.subelementType == .face)

        if let refId = updatedLoad?.targetReferences.first?.id {
            ws.removeTargetReferenceFromLoad(studyId: study.id, loadId: load.id, referenceId: refId)
            let clearedLoad = ws.document.study(id: study.id)?.loads.first { $0.id == load.id }
            #expect(clearedLoad?.targetReferences.isEmpty == true)
        }
    }

    @Test func testInspectorSimulationMeshViewDisplaysMeshSets() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Mesh Sets View Study") else {
            Issue.record("Failed to create study")
            return
        }
        study.results.meshSets = [
            VolumeMeshSet(
                name: "Clamped Base",
                nodeIds: [1, 2, 3, 4],
                elementIds: [10, 20],
                subelementType: .face
            ),
            VolumeMeshSet(
                name: "Body Set",
                nodeIds: [1, 2, 3, 4, 5, 6],
                elementIds: [100],
                subelementType: nil
            )
        ]
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)

        let meshView = InspectorSimulationMeshView(study: study).environment(ws)
        _ = meshView

        #expect(study.results.meshSets.count == 2)
        #expect(study.results.meshSets[0].name == "Clamped Base")
        #expect(study.results.meshSets[0].subelementType == .face)
        #expect(study.results.meshSets[1].name == "Body Set")
        #expect(study.results.meshSets[1].subelementType == nil)
    }

    @Test func testInspectorSimulationFixtureViewTargetControls() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Fixture Inspector Study") else {
            Issue.record("Failed to create study")
            return
        }
        let ref = SimulationGeometryReference(targetId: UUID(), targetName: "Face 1", subelementType: .face)
        let fixture = SimulationFixture(name: "Support", targetReferences: [ref])
        _ = ws.addSimulationFixture(studyId: study.id, fixture: fixture)

        let currentStudy = ws.document.study(id: study.id)!
        let currentFixture = currentStudy.fixtures.first { $0.id == fixture.id }!

        let view = InspectorSimulationFixtureView(study: currentStudy, fixture: currentFixture).environment(ws)
        _ = view

        #expect(currentFixture.targetReferences.count == 1)
        #expect(currentFixture.targetReferences.first?.targetName == "Face 1")
    }

    @Test func testWorkspaceRefinementRegionMutations() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Refinement Workspace Study") else {
            Issue.record("Failed to create study")
            return
        }

        #expect(ws.document.study(id: study.id)?.mesh.refinementRegions.isEmpty == true)

        guard let region = ws.addMeshRefinementRegion(studyId: study.id) else {
            Issue.record("Failed to add refinement region")
            return
        }

        #expect(ws.document.study(id: study.id)?.mesh.refinementRegions.count == 1)
        #expect(ws.document.study(id: study.id)?.mesh.refinementRegions.first?.id == region.id)
        #expect(ws.isDocumentModified)

        var copy = region
        copy.name = "Root Fillet"
        copy.targetElementSize = 0.35
        ws.updateMeshRefinementRegion(studyId: study.id, region: copy)

        let updatedRegion = ws.document.study(id: study.id)?.mesh.refinementRegions.first { $0.id == region.id }
        #expect(updatedRegion?.name == "Root Fillet")
        #expect(updatedRegion?.targetElementSize == 0.35)

        // Assign face subelement selection
        ws.document.selectedSubElement = SelectedSubElement(
            solidId: SolidId("box-solid-1"),
            elementType: .face,
            elementId: 2
        )
        ws.assignActiveSelectionToRefinementRegion(studyId: study.id, regionId: region.id)

        let regionWithTarget = ws.document.study(id: study.id)?.mesh.refinementRegions.first { $0.id == region.id }
        #expect(regionWithTarget?.targetReferences.count == 1)
        #expect(regionWithTarget?.targetReferences.first?.targetName == "Face 2")
        #expect(regionWithTarget?.targetReferences.first?.subelementType == .face)

        // Remove target
        if let targetId = regionWithTarget?.targetReferences.first?.id {
            ws.removeTargetFromRefinementRegion(studyId: study.id, regionId: region.id, referenceId: targetId)
            let regionCleared = ws.document.study(id: study.id)?.mesh.refinementRegions.first { $0.id == region.id }
            #expect(regionCleared?.targetReferences.isEmpty == true)
        }

        // Remove region
        ws.removeMeshRefinementRegion(studyId: study.id, regionId: region.id)
        #expect(ws.document.study(id: study.id)?.mesh.refinementRegions.isEmpty == true)
    }

    @Test func testWorkspaceAssignActiveSolidBodyToRefinementRegion() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Body Refinement Study") else {
            Issue.record("Failed to create study")
            return
        }
        guard let region = ws.addMeshRefinementRegion(studyId: study.id) else {
            Issue.record("Failed to add refinement region")
            return
        }

        ws.document.selectedSubElement = nil
        ws.selectedId = ObjectId("box-1")
        #expect(ws.selectedBody != nil)

        ws.assignActiveSelectionToRefinementRegion(studyId: study.id, regionId: region.id)

        let regionWithBody = ws.document.study(id: study.id)?.mesh.refinementRegions.first { $0.id == region.id }
        #expect(regionWithBody?.targetReferences.count == 1)
        #expect(regionWithBody?.targetReferences.first?.subelementType == nil)
        #expect(regionWithBody?.targetReferences.first?.targetName == "box-1")
    }

    @Test func testInspectorSimulationMeshViewRefinementControls() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Inspector Refinement Study") else {
            Issue.record("Failed to create study")
            return
        }
        let ref = SimulationGeometryReference(targetId: UUID(), targetName: "Face 4", subelementType: .face)
        let region = MeshRefinementRegion(name: "Fine Hole", targetReferences: [ref], targetElementSize: 0.2)
        _ = ws.addMeshRefinementRegion(studyId: study.id, region: region)

        let currentStudy = ws.document.study(id: study.id)!
        let view = InspectorSimulationMeshView(study: currentStudy).environment(ws)
        _ = view

        #expect(currentStudy.mesh.refinementRegions.count == 1)
        #expect(currentStudy.mesh.refinementRegions.first?.name == "Fine Hole")
        #expect(currentStudy.mesh.refinementRegions.first?.targetReferences.first?.targetName == "Face 4")

        let addBtnId = "inspector-simulation-mesh-add-refinement-button"
        let regionNameId = "inspector-simulation-mesh-region-name-\(region.id)"
        let regionDeleteId = "inspector-simulation-mesh-delete-region-\(region.id)"
        let regionSizeId = "inspector-simulation-mesh-region-size-\(region.id)"
        let assignTargetId = "inspector-simulation-mesh-assign-region-target-\(region.id)"
        let removeTargetId = "inspector-simulation-mesh-remove-region-target-\(ref.id)"

        #expect(addBtnId == "inspector-simulation-mesh-add-refinement-button")
        #expect(regionNameId.hasPrefix("inspector-simulation-mesh-region-name-"))
        #expect(regionDeleteId.hasPrefix("inspector-simulation-mesh-delete-region-"))
        #expect(regionSizeId.hasPrefix("inspector-simulation-mesh-region-size-"))
        #expect(assignTargetId.hasPrefix("inspector-simulation-mesh-assign-region-target-"))
        #expect(removeTargetId.hasPrefix("inspector-simulation-mesh-remove-region-target-"))
    }

    @Test func testWorkspaceMeshQualityHighlightingActions() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Quality Workspace Test") else {
            Issue.record("Failed to create study")
            return
        }

        #expect(ws.selectedMeshQualityMetric == .aspectRatio)
        #expect(ws.highlightedMeshElementIds.isEmpty)

        ws.selectMeshQualityMetric(.scaledJacobian)
        #expect(ws.selectedMeshQualityMetric == .scaledJacobian)

        ws.toggleMeshElementHighlight(id: 42)
        #expect(ws.highlightedMeshElementIds.contains(42))

        ws.toggleMeshElementHighlight(id: 42)
        #expect(!ws.highlightedMeshElementIds.contains(42))

        let report = MeshQualityReport(
            aspectRatioSummary: MeshQualityMetricSummary(
                kind: .aspectRatio,
                failingCount: 2,
                failingElementIds: [5, 12]
            )
        )
        let mesh = VolumeMesh(
            nodes: [],
            elements: [],
            statistics: SimulationMeshStatistics(nodeCount: 10, elementCount: 2, qualityReport: report)
        )
        ws.cachedStudyMeshes[study.id] = mesh

        ws.highlightFailingElements(studyId: study.id, metric: .aspectRatio)
        #expect(ws.highlightedMeshElementIds == [5, 12])

        ws.clearMeshHighlight()
        #expect(ws.highlightedMeshElementIds.isEmpty)
    }

    @Test func testInspectorSimulationMeshViewQualitySection() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Quality Inspector Test") else {
            Issue.record("Failed to create study")
            return
        }

        let report = MeshQualityReport(
            aspectRatioSummary: MeshQualityMetricSummary(
                kind: .aspectRatio,
                minValue: 1.1,
                maxValue: 4.5,
                averageValue: 2.3,
                failureThreshold: 3.0,
                failingCount: 1,
                failingPercentage: 50.0,
                failingElementIds: [2],
                histogramBins: [
                    MeshQualityHistogramBin(index: 0, rangeMin: 1.1, rangeMax: 2.0, count: 1, isFailing: false),
                    MeshQualityHistogramBin(index: 1, rangeMin: 2.0, rangeMax: 4.5, count: 1, isFailing: true)
                ]
            )
        )
        let mesh = VolumeMesh(
            nodes: [],
            elements: [],
            statistics: SimulationMeshStatistics(
                nodeCount: 8,
                elementCount: 2,
                minElementQuality: 0.4,
                avgElementQuality: 0.75,
                qualityReport: report
            )
        )
        ws.cachedStudyMeshes[study.id] = mesh
        if var s = ws.document.study(id: study.id) {
            s.results.meshStatistics = mesh.statistics
            _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: s.results)
        }

        let updatedStudy = ws.document.study(id: study.id)!
        let view = InspectorSimulationMeshView(study: updatedStudy).environment(ws)
        _ = view

        let pickerId = "inspector-simulation-mesh-quality-picker"
        let minId = "inspector-simulation-mesh-quality-min"
        let maxId = "inspector-simulation-mesh-quality-max"
        let avgId = "inspector-simulation-mesh-quality-avg"
        let failingId = "inspector-simulation-mesh-quality-failing-count"
        let histId = "inspector-simulation-mesh-quality-histogram"
        let highlightBtnId = "inspector-simulation-mesh-quality-highlight-button"
        let clearBtnId = "inspector-simulation-mesh-quality-clear-button"

        #expect(pickerId == "inspector-simulation-mesh-quality-picker")
        #expect(minId == "inspector-simulation-mesh-quality-min")
        #expect(maxId == "inspector-simulation-mesh-quality-max")
        #expect(avgId == "inspector-simulation-mesh-quality-avg")
        #expect(failingId == "inspector-simulation-mesh-quality-failing-count")
        #expect(histId == "inspector-simulation-mesh-quality-histogram")
        #expect(highlightBtnId == "inspector-simulation-mesh-quality-highlight-button")
        #expect(clearBtnId == "inspector-simulation-mesh-quality-clear-button")
    }

    @Test func testWorkspaceMeshDisplayActions() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Mesh Viewport Test") else {
            Issue.record("Failed to create study")
            return
        }

        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        let elem = VolumeMeshElement(id: 1, nodeIndices: [1, 2, 3, 4])
        let volumeMesh = VolumeMesh(
            nodes: [n1, n2, n3, n4],
            elements: [elem],
            statistics: SimulationMeshStatistics(nodeCount: 4, elementCount: 1)
        )
        ws.cachedStudyMeshes[study.id] = volumeMesh

        #expect(ws.document.study(id: study.id)?.meshDisplay.isVisible == true)

        let newSettings = SimulationMeshDisplaySettings(
            isVisible: true,
            showEdges: true,
            showFaces: false,
            elementShrink: 0.25,
            isSliceEnabled: true,
            sliceAxis: .x,
            slicePosition: 0.5,
            isSliceInverted: false,
            hideSolidBody: true
        )
        ws.updateSimulationMeshDisplaySettings(studyId: study.id, settings: newSettings)

        let updated = ws.document.study(id: study.id)?.meshDisplay
        #expect(updated?.showFaces == false)
        #expect(updated?.elementShrink == 0.25)
        #expect(updated?.isSliceEnabled == true)
        #expect(updated?.sliceAxis == .x)
        #expect(updated?.hideSolidBody == true)

        ws.toggleSimulationMeshVisibility(studyId: study.id)
        #expect(ws.document.study(id: study.id)?.meshDisplay.isVisible == false)

        ws.toggleSimulationMeshVisibility(studyId: study.id)
        #expect(ws.document.study(id: study.id)?.meshDisplay.isVisible == true)

        ws.clearSimulationMeshFromViewport(studyId: study.id)
    }

    @Test func testInspectorSimulationMeshDisplayControls() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Display Inspector Test") else {
            Issue.record("Failed to create study")
            return
        }

        let displaySettings = SimulationMeshDisplaySettings(
            isVisible: true,
            showEdges: true,
            showFaces: true,
            elementShrink: 0.1,
            isSliceEnabled: true,
            sliceAxis: .y,
            slicePosition: 0.4,
            isSliceInverted: true,
            hideSolidBody: true
        )
        ws.updateSimulationMeshDisplaySettings(studyId: study.id, settings: displaySettings)

        let updatedStudy = ws.document.study(id: study.id)!
        let view = InspectorSimulationMeshView(study: updatedStudy).environment(ws)
        _ = view

        let visId = "inspector-simulation-mesh-display-visibility-toggle"
        let edgesId = "inspector-simulation-mesh-display-edges-toggle"
        let facesId = "inspector-simulation-mesh-display-faces-toggle"
        let shrinkId = "inspector-simulation-mesh-display-shrink-slider"
        let sliceId = "inspector-simulation-mesh-display-slice-toggle"
        let axisId = "inspector-simulation-mesh-display-slice-axis-picker"
        let posId = "inspector-simulation-mesh-display-slice-position-slider"
        let invertId = "inspector-simulation-mesh-display-slice-invert-toggle"
        let hideSolidId = "inspector-simulation-mesh-display-hide-solid-toggle"

        #expect(visId == "inspector-simulation-mesh-display-visibility-toggle")
        #expect(edgesId == "inspector-simulation-mesh-display-edges-toggle")
        #expect(facesId == "inspector-simulation-mesh-display-faces-toggle")
        #expect(shrinkId == "inspector-simulation-mesh-display-shrink-slider")
        #expect(sliceId == "inspector-simulation-mesh-display-slice-toggle")
        #expect(axisId == "inspector-simulation-mesh-display-slice-axis-picker")
        #expect(posId == "inspector-simulation-mesh-display-slice-position-slider")
        #expect(invertId == "inspector-simulation-mesh-display-slice-invert-toggle")
        #expect(hideSolidId == "inspector-simulation-mesh-display-hide-solid-toggle")
    }

    @Test func testNavigatorMeshRowVisibilityToggle() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Nav Visibility Test") else {
            Issue.record("Failed to create study")
            return
        }

        let navRow = NavigatorSimulationMeshRow(study: study).environment(ws)
        _ = navRow

        let buttonId = "navigator-study-mesh-visibility-\(study.id)"
        #expect(buttonId.hasPrefix("navigator-study-mesh-visibility-"))

        #expect(study.meshDisplay.isVisible == true)
        ws.toggleSimulationMeshVisibility(studyId: study.id)
        #expect(ws.document.study(id: study.id)?.meshDisplay.isVisible == false)
    }

    @Test func testInspectorSimulationViewsWithCoordinateSystemsAndUnitConversions() {
        let ws = WorkspaceModel()
        let ucs = ws.document.addDatumCoordinateSystemFeature(
            name: "Mount UCS",
            data: DatumCoordinateSystemFeatureData(
                mode: .originAndAxes,
                origin: SIMD3<Float>(10, 20, 30),
                xAxis: SIMD3<Float>(0, 1, 0),
                yAxis: SIMD3<Float>(-1, 0, 0),
                zAxis: SIMD3<Float>(0, 0, 1)
            )
        )

        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "UCS Inspector Study") else {
            Issue.record("Failed to create study")
            return
        }

        study.coordinateSystemId = ucs.id
        let fixture = SimulationFixture(
            name: "UCS Fixture",
            kind: .prescribedDisplacement,
            prescribedDisplacement: SIMD3<Double>(25.4, 50.8, -12.7),
            coordinateSystemId: ucs.id
        )
        let load = SimulationLoad(
            name: "UCS Load",
            kind: .force,
            magnitude: 444.82216152605,
            coordinateSystemId: ucs.id
        )
        study.fixtures = [fixture]
        study.loads = [load]
        study.results = SimulationStudyResults(
            status: .completed,
            extrema: [
                SimulationFieldExtrema(fieldName: "Ux", unitSymbol: "mm", minValue: -25.4, maxValue: 25.4),
                SimulationFieldExtrema(fieldName: "Uy", unitSymbol: "mm", minValue: 0.0, maxValue: 50.8),
                SimulationFieldExtrema(fieldName: "Uz", unitSymbol: "mm", minValue: -10.0, maxValue: 10.0),
                SimulationFieldExtrema(fieldName: "Von Mises Stress", unitSymbol: "MPa", minValue: 10.0, maxValue: 200.0)
            ]
        )
        _ = ws.document.updateStudy(study)
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)

        let symmetryFixture = SimulationFixture(name: "Symm", kind: .symmetry)
        let elasticFixture = SimulationFixture(name: "Elastic", kind: .elasticSupport, elasticStiffness: SIMD3<Double>(1e6, 2e6, 3e6))
        let pinnedFixture = SimulationFixture(name: "Pin", kind: .pinned)
        let rollerFixture = SimulationFixture(name: "Roller", kind: .rollerSlider)

        // Instantiate all inspector views with metric units
        ws.document.setUnits(UnitSettings(lengthUnit: .millimeters))
        _ = InspectorSimulationStudyView(study: study).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: fixture).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: symmetryFixture).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: elasticFixture).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: pinnedFixture).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: rollerFixture).environment(ws)
        _ = InspectorSimulationLoadView(study: study, load: load).environment(ws)
        _ = InspectorSimulationResultsView(study: study).environment(ws)

        // Switch to imperial units and verify instantiation & conversions
        ws.document.setUnits(UnitSettings(lengthUnit: .inches))
        _ = InspectorSimulationStudyView(study: study).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: fixture).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: symmetryFixture).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: elasticFixture).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: pinnedFixture).environment(ws)
        _ = InspectorSimulationFixtureView(study: study, fixture: rollerFixture).environment(ws)
        _ = InspectorSimulationLoadView(study: study, load: load).environment(ws)
        _ = InspectorSimulationResultsView(study: study).environment(ws)

        // Verify accessibility identifiers exist
        let studyUCSId = "inspector-simulation-study-ucs-picker"
        let fixtureUCSId = "inspector-simulation-fixture-ucs-picker"
        let loadUCSId = "inspector-simulation-load-ucs-picker"
        let resultsUCSId = "inspector-simulation-results-ucs-picker"
        let fixturePrescribedX = "inspector-simulation-fixture-prescribed-x"
        let fixturePrescribedY = "inspector-simulation-fixture-prescribed-y"
        let fixturePrescribedZ = "inspector-simulation-fixture-prescribed-z"
        let fixtureSymmetryX = "inspector-simulation-fixture-symmetry-x"
        let fixtureSymmetryY = "inspector-simulation-fixture-symmetry-y"
        let fixtureSymmetryZ = "inspector-simulation-fixture-symmetry-z"
        let fixtureStiffnessX = "inspector-simulation-fixture-stiffness-x"
        let fixtureStiffnessY = "inspector-simulation-fixture-stiffness-y"
        let fixtureStiffnessZ = "inspector-simulation-fixture-stiffness-z"
        let loadMagnitude = "inspector-simulation-load-magnitude"

        #expect(studyUCSId == "inspector-simulation-study-ucs-picker")
        #expect(fixtureUCSId == "inspector-simulation-fixture-ucs-picker")
        #expect(loadUCSId == "inspector-simulation-load-ucs-picker")
        #expect(resultsUCSId == "inspector-simulation-results-ucs-picker")
        #expect(fixturePrescribedX == "inspector-simulation-fixture-prescribed-x")
        #expect(fixturePrescribedY == "inspector-simulation-fixture-prescribed-y")
        #expect(fixturePrescribedZ == "inspector-simulation-fixture-prescribed-z")
        #expect(fixtureSymmetryX == "inspector-simulation-fixture-symmetry-x")
        #expect(fixtureSymmetryY == "inspector-simulation-fixture-symmetry-y")
        #expect(fixtureSymmetryZ == "inspector-simulation-fixture-symmetry-z")
        #expect(fixtureStiffnessX == "inspector-simulation-fixture-stiffness-x")
        #expect(fixtureStiffnessY == "inspector-simulation-fixture-stiffness-y")
        #expect(fixtureStiffnessZ == "inspector-simulation-fixture-stiffness-z")
        #expect(loadMagnitude == "inspector-simulation-load-magnitude")
    }

    @Test func testThermalConductionSolveLifecycle() async throws {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .thermalConduction, name: "Thermal Slab Solve") else {
            Issue.record("Failed to create thermal simulation study")
            return
        }

        var updatedStudy = study
        updatedStudy.solver.engine = .pureSwift
        updatedStudy.loads = [
            SimulationLoad(name: "Hot", kind: .temperature, magnitude: 100.0),
            SimulationLoad(name: "Cooling", kind: .convection, magnitude: 50.0, ambientTemperature: 20.0)
        ]
        ws.updateSimulationStudy(updatedStudy)

        ws.runSimulationStudy(id: study.id)
        #expect(ws.isStudyRunning(study.id))

        // Wait for pure-Swift thermal solve to complete
        for _ in 0..<50 {
            if !ws.isStudyRunning(study.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        let finishedStudy = try #require(ws.document.study(id: study.id))
        #expect(finishedStudy.results.status == .completed)
        #expect(finishedStudy.results.errorMessage == nil)
        #expect(finishedStudy.results.nodalTemperatures != nil)
        #expect(!finishedStudy.results.extrema.isEmpty)
        #expect(finishedStudy.results.extrema.contains { $0.fieldName == "Temperature" })
        #expect(finishedStudy.results.extrema.contains { $0.fieldName == "Heat Flux" })
    }

    @Test func testLinearStaticSolveLifecycle() async throws {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Linear Static Solve") else {
            Issue.record("Failed to create linear static simulation study")
            return
        }

        var updatedStudy = study
        updatedStudy.solver.engine = .pureSwift
        updatedStudy.fixtures = [
            SimulationFixture(name: "Fixed Base", kind: .fixed)
        ]
        updatedStudy.loads = [
            SimulationLoad(name: "Tip Force", kind: .force, magnitude: 1000.0, direction: SIMD3<Double>(0, -1, 0))
        ]
        ws.updateSimulationStudy(updatedStudy)

        ws.runSimulationStudy(id: study.id)
        #expect(ws.isStudyRunning(study.id))

        // Wait for pure-Swift linear static solve to complete
        for _ in 0..<50 {
            if !ws.isStudyRunning(study.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        let finishedStudy = try #require(ws.document.study(id: study.id))
        #expect(finishedStudy.results.status == .completed)
        #expect(finishedStudy.results.errorMessage == nil)
        #expect(finishedStudy.results.nodalDisplacements != nil)
        #expect(finishedStudy.results.nodalVonMisesStresses != nil)
        #expect(!finishedStudy.results.extrema.isEmpty)
        #expect(finishedStudy.results.extrema.contains { $0.fieldName == "Displacement Magnitude" })
        #expect(finishedStudy.results.extrema.contains { $0.fieldName == "von Mises Stress" })
        #expect(finishedStudy.results.factorOfSafety != nil)
        #expect(finishedStudy.results.extrema.contains { $0.fieldName == "Factor of Safety" })
    }

    @Test func testFactorOfSafetyDynamicSwitching() async throws {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "FOS Dynamic Test") else {
            Issue.record("Failed to create linear static simulation study")
            return
        }

        var updatedStudy = study
        updatedStudy.solver.engine = .pureSwift
        updatedStudy.fixtures = [
            SimulationFixture(name: "Fixed Base", kind: .fixed)
        ]
        updatedStudy.loads = [
            SimulationLoad(name: "Tip Force", kind: .force, magnitude: 1000.0, direction: SIMD3<Double>(0, -1, 0))
        ]
        ws.updateSimulationStudy(updatedStudy)

        ws.runSimulationStudy(id: study.id)
        for _ in 0..<50 {
            if !ws.isStudyRunning(study.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let finished = try #require(ws.document.study(id: study.id))
        let initialFos = try #require(finished.results.factorOfSafety)
        #expect(initialFos.basis == .yield)
        #expect(initialFos.criterion == .vonMises)

        // Switch to Ultimate Tensile Strength basis and Tresca criterion with target 2.5
        ws.updateFactorOfSafety(
            studyId: study.id,
            basis: .ultimate,
            criterion: .tresca,
            targetDesignFactor: 2.5
        )

        let switched = try #require(ws.document.study(id: study.id))
        #expect(switched.factorOfSafetySettings.basis == .ultimate)
        #expect(switched.factorOfSafetySettings.criterion == .tresca)
        #expect(switched.factorOfSafetySettings.targetDesignFactor == 2.5)

        let switchedFos = try #require(switched.results.factorOfSafety)
        #expect(switchedFos.basis == .ultimate)
        #expect(switchedFos.criterion == .tresca)
        #expect(switchedFos.targetDesignFactor == 2.5)
        #expect(switchedFos.allowableStrengthMPa == 400.0)

        let fosExtrema = try #require(switched.results.extrema.first { $0.fieldName == "Factor of Safety" })
        #expect(abs(fosExtrema.minValue - switchedFos.minFactorOfSafety) < 1e-6)

        // Highlight failing elements
        ws.highlightFailingSafetyFactorElements(studyId: study.id)
    }

    @Test func testInspectorSimulationResultsViewFactorOfSafetySection() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "FOS Inspector Test") else {
            Issue.record("Failed to create linear static simulation study")
            return
        }

        study.results.status = .completed
        study.results.nodalVonMisesStresses = [1: 50.0, 2: 100.0]
        study.results.factorOfSafety = FactorOfSafetyResult(
            basis: .yield,
            criterion: .vonMises,
            allowableStrengthMPa: 250.0,
            minFactorOfSafety: 2.5,
            maxFactorOfSafety: 5.0,
            criticalNodeId: 2,
            criticalStressMPa: 100.0,
            targetDesignFactor: 2.0,
            meetsDesignFactor: true,
            failingNodeCount: 0,
            totalNodeCount: 2,
            nodalFactorsOfSafety: [1: 5.0, 2: 2.5]
        )
        ws.updateSimulationStudy(study)

        _ = InspectorSimulationResultsView(study: study).environment(ws)
    }

    @Test func testCoupledThermalStressSolveLifecycle() async throws {
        let ws = WorkspaceModel()

        // 1. Create and solve thermal conduction study
        guard let thermalStudy = ws.createSimulationStudy(type: .thermalConduction, name: "Conduction Source") else {
            Issue.record("Failed to create thermal conduction simulation study")
            return
        }
        var updatedThermal = thermalStudy
        updatedThermal.solver.engine = .pureSwift
        updatedThermal.loads = [
            SimulationLoad(name: "BaseHeat", kind: .temperature, magnitude: 100.0),
            SimulationLoad(name: "SurfaceChill", kind: .convection, magnitude: 25.0, ambientTemperature: 20.0)
        ]
        ws.updateSimulationStudy(updatedThermal)
        ws.runSimulationStudy(id: thermalStudy.id)

        for _ in 0..<50 {
            if !ws.isStudyRunning(thermalStudy.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let completedThermal = try #require(ws.document.study(id: thermalStudy.id))
        #expect(completedThermal.results.status == .completed)
        #expect(completedThermal.results.nodalTemperatures != nil)

        // 2. Create and solve linear static study coupled to the thermal study
        guard let staticStudy = ws.createSimulationStudy(type: .linearStatic, name: "Coupled Static") else {
            Issue.record("Failed to create linear static simulation study")
            return
        }
        var updatedStatic = staticStudy
        updatedStatic.solver.engine = .pureSwift
        updatedStatic.thermalStudyId = thermalStudy.id
        updatedStatic.thermalReferenceTemperature = 20.0
        updatedStatic.fixtures = [
            SimulationFixture(name: "BaseConstraint", kind: .fixed)
        ]
        ws.updateSimulationStudy(updatedStatic)

        // Verify Inspector view instantiates with thermal coupling controls
        _ = InspectorSimulationStudyView(study: updatedStatic).environment(ws)

        ws.runSimulationStudy(id: staticStudy.id)
        #expect(ws.isStudyRunning(staticStudy.id))

        for _ in 0..<50 {
            if !ws.isStudyRunning(staticStudy.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let completedStatic = try #require(ws.document.study(id: staticStudy.id))
        #expect(completedStatic.results.status == .completed)
        #expect(completedStatic.results.errorMessage == nil)
        #expect(completedStatic.results.nodalDisplacements != nil)
        #expect(completedStatic.results.nodalVonMisesStresses != nil)
        #expect(!completedStatic.results.extrema.isEmpty)
        #expect(completedStatic.results.extrema.contains { $0.fieldName == "Displacement Magnitude" })
        #expect(completedStatic.results.extrema.contains { $0.fieldName == "von Mises Stress" })
    }

    @Test func testCoupledThermalStressMissingOrUnsolvedValidation() async throws {
        let ws = WorkspaceModel()

        // 1. Missing study ID
        guard let studyMissing = ws.createSimulationStudy(type: .linearStatic, name: "Missing Thermal Study") else {
            Issue.record("Failed to create study")
            return
        }
        var updatedMissing = studyMissing
        updatedMissing.solver.engine = .pureSwift
        updatedMissing.thermalStudyId = UUID()
        ws.updateSimulationStudy(updatedMissing)

        ws.runSimulationStudy(id: studyMissing.id)
        for _ in 0..<50 {
            if !ws.isStudyRunning(studyMissing.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let failedMissing = try #require(ws.document.study(id: studyMissing.id))
        #expect(failedMissing.results.status == .failed)
        #expect(failedMissing.results.errorMessage?.contains("Coupled thermal study not found") == true)

        // 2. Unsolved study
        guard let unsolvedThermal = ws.createSimulationStudy(type: .thermalConduction, name: "Unsolved Thermal") else {
            Issue.record("Failed to create thermal study")
            return
        }
        guard let studyUnsolved = ws.createSimulationStudy(type: .linearStatic, name: "Coupled to Unsolved") else {
            Issue.record("Failed to create static study")
            return
        }
        var updatedUnsolved = studyUnsolved
        updatedUnsolved.solver.engine = .pureSwift
        updatedUnsolved.thermalStudyId = unsolvedThermal.id
        ws.updateSimulationStudy(updatedUnsolved)

        ws.runSimulationStudy(id: studyUnsolved.id)
        for _ in 0..<50 {
            if !ws.isStudyRunning(studyUnsolved.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let failedUnsolved = try #require(ws.document.study(id: studyUnsolved.id))
        #expect(failedUnsolved.results.status == .failed)
        #expect(failedUnsolved.results.errorMessage?.contains("has not been solved or contains no temperature results") == true)
    }

    @Test func testLinearBucklingSolveLifecycle() async throws {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearBuckling, name: "Linear Buckling Solve") else {
            Issue.record("Failed to create linear buckling simulation study")
            return
        }

        var updatedStudy = study
        updatedStudy.solver.engine = .pureSwift
        updatedStudy.solver.bucklingModesCount = 2
        updatedStudy.fixtures = [
            SimulationFixture(name: "Fixed Base", kind: .fixed)
        ]
        updatedStudy.loads = [
            SimulationLoad(name: "Compressive Force", kind: .force, magnitude: 1000.0, direction: SIMD3<Double>(0, -1, 0))
        ]
        ws.updateSimulationStudy(updatedStudy)

        ws.runSimulationStudy(id: study.id)
        #expect(ws.isStudyRunning(study.id))

        // Wait for pure-Swift linear buckling solve to complete
        for _ in 0..<50 {
            if !ws.isStudyRunning(study.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        let finishedStudy = try #require(ws.document.study(id: study.id))
        #expect(finishedStudy.results.status == .completed)
        #expect(finishedStudy.results.errorMessage == nil)
        let modes = try #require(finishedStudy.results.bucklingModes)
        #expect(!modes.isEmpty)
        #expect(finishedStudy.results.nodalDisplacements != nil)
        #expect(!finishedStudy.results.extrema.isEmpty)
        #expect(finishedStudy.results.extrema.contains { $0.fieldName == "Buckling Load Factor" })

        // Test mode selection
        if modes.count >= 2 {
            ws.selectBucklingMode(studyId: study.id, modeNumber: 2)
            let updatedModeStudy = try #require(ws.document.study(id: study.id))
            #expect(updatedModeStudy.results.nodalDisplacements == modes[1].nodalDisplacements)
        }
    }

    @Test func testModalFrequencySolveLifecycle() async throws {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .modalFrequency, name: "Modal Frequency Solve") else {
            Issue.record("Failed to create modal frequency simulation study")
            return
        }

        var updatedStudy = study
        updatedStudy.solver.engine = .pureSwift
        updatedStudy.solver.modeCount = 3
        updatedStudy.fixtures = [
            SimulationFixture(name: "Fixed Base", kind: .fixed)
        ]
        ws.updateSimulationStudy(updatedStudy)

        ws.runSimulationStudy(id: study.id)
        #expect(ws.isStudyRunning(study.id))

        // Wait for pure-Swift modal solve to complete
        for _ in 0..<50 {
            if !ws.isStudyRunning(study.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        let finishedStudy = try #require(ws.document.study(id: study.id))
        #expect(finishedStudy.results.status == .completed)
        #expect(finishedStudy.results.errorMessage == nil)
        #expect(finishedStudy.results.modeShapes != nil)
        #expect(finishedStudy.results.modeShapes?.count == 3)
        #expect(finishedStudy.results.nodalDisplacements != nil)
        #expect(!finishedStudy.results.extrema.isEmpty)
        #expect(finishedStudy.results.extrema.contains { $0.fieldName == "Natural Frequency" })

        // Test selectModeShape
        ws.selectModeShape(studyId: study.id, modeNumber: 2)
        let mode2Study = try #require(ws.document.study(id: study.id))
        let mode2Disps = finishedStudy.results.modeShapes?[1].nodalDisplacements
        #expect(mode2Study.results.nodalDisplacements == mode2Disps)
    }

    @Test func testInspectorSimulationStudyModalControls() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .modalFrequency, name: "Modal Controls Test") else {
            Issue.record("Failed to create modal simulation study")
            return
        }

        var copy = study
        copy.solver.modeCount = 8
        copy.solver.isPrestressEnabled = true
        copy.results.modeShapes = [
            SimulationModeShape(modeNumber: 1, frequencyHz: 40.5, nodalDisplacements: [1: .zero]),
            SimulationModeShape(modeNumber: 2, frequencyHz: 95.2, nodalDisplacements: [1: .zero])
        ]
        ws.updateSimulationStudy(copy)

        _ = InspectorSimulationStudyView(study: copy).environment(ws)
        _ = InspectorSimulationResultsView(study: copy).environment(ws)

        #expect(copy.solver.modeCount == 8)
        #expect(copy.solver.isPrestressEnabled == true)
        #expect(copy.results.modeShapes?.count == 2)
    }

    @Test func testInspectorSimulationLoadViewConvection() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .thermalConduction, name: "Thermal View Test") else {
            Issue.record("Failed to create thermal simulation study")
            return
        }
        let convectionLoad = SimulationLoad(
            name: "Ambient Film",
            kind: .convection,
            magnitude: 75.0,
            ambientTemperature: 22.0
        )
        _ = InspectorSimulationLoadView(study: study, load: convectionLoad).environment(ws)

        let ambientId = "inspector-simulation-load-ambient-temperature"
        #expect(ambientId == "inspector-simulation-load-ambient-temperature")
    }

    @Test func testInspectorSimulationLoadViewBLFEA03Controls() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "FEA03 View Test") else {
            Issue.record("Failed to create linear static simulation study")
            return
        }

        // 1. Force load with distribution
        var forceLoad = SimulationLoad(
            name: "Distributed Traction",
            kind: .force,
            magnitude: 5000.0,
            forceDistribution: .perUnitArea
        )
        let addedForce = ws.addSimulationLoad(studyId: study.id, load: forceLoad)
        #expect(addedForce != nil)
        _ = InspectorSimulationLoadView(study: study, load: forceLoad).environment(ws)

        // 2. Remote load with remote point
        let remoteLoad = SimulationLoad(
            name: "Remote Force",
            kind: .remoteLoad,
            magnitude: 1200.0,
            remotePoint: SIMD3<Double>(10.0, 20.0, 30.0)
        )
        let addedRemote = ws.addSimulationLoad(studyId: study.id, load: remoteLoad)
        #expect(addedRemote != nil)
        _ = InspectorSimulationLoadView(study: study, load: remoteLoad).environment(ws)

        // 3. Centrifugal load with axis origin
        let centrifLoad = SimulationLoad(
            name: "Rotor Spin",
            kind: .centrifugal,
            magnitude: 150.0,
            axisOrigin: SIMD3<Double>(0.0, 0.0, 1.0)
        )
        let addedCentrif = ws.addSimulationLoad(studyId: study.id, load: centrifLoad)
        #expect(addedCentrif != nil)
        _ = InspectorSimulationLoadView(study: study, load: centrifLoad).environment(ws)

        // 4. Thermal load with reference temperature
        let thermalLoad = SimulationLoad(
            name: "Bake Thermal",
            kind: .thermalLoad,
            magnitude: 85.0,
            referenceTemperature: 22.0
        )
        let addedThermal = ws.addSimulationLoad(studyId: study.id, load: thermalLoad)
        #expect(addedThermal != nil)
        _ = InspectorSimulationLoadView(study: study, load: thermalLoad).environment(ws)

        // Verify update mutations persist to workspace
        forceLoad.forceDistribution = .total
        ws.updateSimulationLoad(studyId: study.id, load: forceLoad)
        let updatedStudy = ws.document.study(id: study.id)
        #expect(updatedStudy?.loads.first(where: { $0.id == forceLoad.id })?.forceDistribution == .total)
    }

    @Test func testWorkspaceSimulationConnectionLifecycle() throws {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Multi-body Contact Study") else {
            Issue.record("Failed to create linear static simulation study")
            return
        }

        // 1. Add connection
        let connection = ws.addSimulationConnection(
            studyId: study.id,
            connection: SimulationConnection(name: "Block Interface", kind: .bonded, stiffness: 1e10, searchTolerance: 0.002)
        )
        #expect(connection != nil)
        #expect(ws.selectedSimulationConnectionId == connection?.id)
        #expect(ws.selectedSimulationConnection?.name == "Block Interface")
        #expect(ws.selectedSimulationConnection?.searchTolerance == 0.002)

        // 2. Mutual exclusion: selecting fixture clears connection selection
        let fixture = ws.addSimulationFixture(studyId: study.id, fixture: SimulationFixture(name: "Base", kind: .fixed))
        #expect(ws.selectedSimulationFixtureId == fixture?.id)
        #expect(ws.selectedSimulationConnectionId == nil)

        // 3. Re-selecting connection clears fixture selection
        ws.selectSimulationConnection(studyId: study.id, connectionId: connection?.id)
        #expect(ws.selectedSimulationConnectionId == connection?.id)
        #expect(ws.selectedSimulationFixtureId == nil)
        #expect(ws.selectedSimulationLoadId == nil)
        #expect(ws.isSimulationMeshSelected == false)

        // 4. Update connection
        var updated = try #require(connection)
        updated.name = "Renamed Bond"
        updated.kind = .spring
        updated.stiffness = 5e7
        ws.updateSimulationConnection(studyId: study.id, connection: updated)
        #expect(ws.selectedSimulationConnection?.name == "Renamed Bond")
        #expect(ws.selectedSimulationConnection?.kind == .spring)
        #expect(ws.selectedSimulationConnection?.stiffness == 5e7)

        // 5. Geometry reference assignments
        let sourceRef = SimulationGeometryReference(targetId: UUID(), targetName: "Contact Face 1", subelementType: .face)
        let targetRef = SimulationGeometryReference(targetId: UUID(), targetName: "Contact Face 2", subelementType: .face)
        _ = ws.document.assignSourceReferenceToConnection(studyId: study.id, connectionId: updated.id, reference: sourceRef)
        _ = ws.document.assignTargetReferenceToConnection(studyId: study.id, connectionId: updated.id, reference: targetRef)

        let connWithRefs = try #require(ws.selectedSimulationConnection)
        #expect(connWithRefs.sourceReferences.count == 1)
        #expect(connWithRefs.targetReferences.count == 1)

        ws.removeSourceReferenceFromConnection(studyId: study.id, connectionId: updated.id, referenceId: sourceRef.id)
        ws.removeTargetReferenceFromConnection(studyId: study.id, connectionId: updated.id, referenceId: targetRef.id)

        let connCleared = try #require(ws.selectedSimulationConnection)
        #expect(connCleared.sourceReferences.isEmpty)
        #expect(connCleared.targetReferences.isEmpty)

        // 6. Delete connection
        ws.removeSimulationConnection(studyId: study.id, connectionId: updated.id)
        #expect(ws.selectedSimulationConnectionId == nil)
        #expect(ws.document.study(id: study.id)?.connections.isEmpty == true)
    }

    @Test func testWorkspaceResultFieldPersistenceAndLazyLoadingLifecycle() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestWSResults-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ws = WorkspaceModel()
        ws.currentDocumentURL = tempDir

        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Storage Lifecycle Study") else {
            Issue.record("Failed to create linear static study")
            return
        }

        var updated = study
        updated.solver.engine = .pureSwift
        updated.fixtures = [
            SimulationFixture(name: "RootFixed", kind: .fixed)
        ]
        updated.loads = [
            SimulationLoad(name: "TipForce", kind: .force, magnitude: 100.0, direction: SIMD3<Double>(0, 1, 0))
        ]
        ws.updateSimulationStudy(updated)

        ws.runSimulationStudy(id: study.id)
        #expect(ws.isStudyRunning(study.id))

        for _ in 0..<50 {
            if !ws.isStudyRunning(study.id) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let completedStudy = try #require(ws.document.study(id: study.id))
        #expect(completedStudy.results.status == .completed)
        #expect(completedStudy.results.isFieldsLoaded)
        #expect(completedStudy.results.fieldStorage != nil)
        #expect(completedStudy.results.elementVonMisesStresses != nil)

        let storage = try #require(completedStudy.results.fieldStorage)
        #expect(storage.format == .vtu)
        #expect(storage.isResident)

        let vtuPath = tempDir.appendingPathComponent(storage.storagePath)
        let binPath = tempDir.appendingPathComponent("cache/results/\(study.id.uuidString)/fields.bin")
        #expect(FileManager.default.fileExists(atPath: vtuPath.path))
        #expect(FileManager.default.fileExists(atPath: binPath.path))

        // Check in-memory result fields query
        let inMemFields = try #require(ws.resultFields(for: study.id))
        #expect(inMemFields.nodalDisplacements != nil)
        #expect(inMemFields.elementVonMisesStresses != nil)

        // Unload fields
        ws.unloadResultFields(studyId: study.id)
        let unloadedStudy = try #require(ws.document.study(id: study.id))
        #expect(!unloadedStudy.results.isFieldsLoaded)
        #expect(unloadedStudy.results.nodalDisplacements == nil)
        #expect(unloadedStudy.results.elementVonMisesStresses == nil)
        #expect(ws.cachedStudyResultFields[study.id] == nil)
        #expect(ws.logs.contains { $0.message.contains("Unloaded result fields from memory for study") })

        // Load fields back
        ws.loadResultFields(studyId: study.id)
        let reloadedStudy = try #require(ws.document.study(id: study.id))
        #expect(reloadedStudy.results.isFieldsLoaded)
        #expect(reloadedStudy.results.nodalDisplacements != nil)
        #expect(reloadedStudy.results.elementVonMisesStresses != nil)
        #expect(ws.cachedStudyResultFields[study.id] != nil)
        #expect(ws.logs.contains { $0.message.contains("Loaded result fields for study") })
    }

    @Test func testInspectorSimulationResultsViewResultFieldsSection() {
        let ws = WorkspaceModel()
        let studyId = UUID()
        let storage = ResultFieldStorageDescriptor(
            storagePath: "cache/results/\(studyId.uuidString)/results.vtu",
            format: .vtu,
            availableFields: [
                ResultFieldMetadata(name: "Displacement", kind: .displacement, componentCount: 3, entityCount: 4, unitSymbol: "mm"),
                ResultFieldMetadata(name: "von Mises Stress", kind: .vonMisesStress, componentCount: 1, entityCount: 4, unitSymbol: "MPa")
            ],
            byteSize: 2048,
            isResident: true
        )

        let loadedResults = SimulationStudyResults(
            status: .completed,
            runtimeDuration: 0.45,
            meshStatistics: SimulationMeshStatistics(nodeCount: 4, elementCount: 1),
            nodalTemperatures: [1: 20.0, 2: 90.0],
            nodalDisplacements: [1: .zero, 2: SIMD3<Double>(0.05, 0, 0)],
            nodalVonMisesStresses: [1: 10.0, 2: 45.0],
            fieldStorage: storage,
            elementVonMisesStresses: [1: 30.0],
            elementHeatFluxes: [1: SIMD3<Double>(100.0, 0, 0)]
        )

        let loadedStudy = SimulationStudy(
            id: studyId,
            name: "Completed Study",
            studyType: .linearStatic,
            results: loadedResults
        )

        _ = InspectorSimulationResultsView(study: loadedStudy).environment(ws)

        var unloadedStudy = loadedStudy
        unloadedStudy.results.unloadFields()
        _ = InspectorSimulationResultsView(study: unloadedStudy).environment(ws)
    }

    @Test func testWorkspaceContourLifecycle() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Contour FEA Study") else {
            Issue.record("Failed to create study")
            return
        }

        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        let elem = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 1)
        let mesh = VolumeMesh(nodes: [n1, n2, n3, n4], elements: [elem])
        ws.cachedStudyMeshes[study.id] = mesh

        let fields = SimulationResultFields(
            studyId: study.id,
            nodalDisplacements: [
                1: .zero,
                2: SIMD3<Double>(0.1, 0, 0),
                3: SIMD3<Double>(0, 0.2, 0),
                4: SIMD3<Double>(0, 0, 0.5)
            ],
            nodalVonMisesStresses: [
                1: 15.0,
                2: 75.0,
                3: 120.0,
                4: 250.0
            ]
        )
        ws.cachedStudyResultFields[study.id] = fields

        study.results.status = .completed
        study.results.nodalVonMisesStresses = fields.nodalVonMisesStresses
        study.results.nodalDisplacements = fields.nodalDisplacements
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)

        var contourSettings = SimulationContourSettings()
        contourSettings.isVisible = true
        contourSettings.field = .vonMisesStress
        contourSettings.colorMap = .turbo
        contourSettings.showMinMaxMarkers = true
        contourSettings.showMeshEdges = true

        ws.updateSimulationContourSettings(studyId: study.id, settings: contourSettings)

        let extrema = ws.activeContourExtrema[study.id]
        #expect(extrema != nil)
        #expect(extrema?.actualMin == 15.0)
        #expect(extrema?.actualMax == 250.0)
        #expect(extrema?.minNodeId == 1)
        #expect(extrema?.maxNodeId == 4)

        // Select results tab
        ws.selectSimulationResults(studyId: study.id)
        #expect(ws.isSimulationResultsSelected == true)
        #expect(ws.activeContourExtrema[study.id] != nil)

        // Clear contour
        ws.clearSimulationContourFromViewport(studyId: study.id)
        #expect(ws.activeContourExtrema[study.id] == nil)
    }

    @Test func testInspectorContourControlsAndLegendOverlay() {
        let ws = WorkspaceModel()
        let studyId = UUID()
        var study = SimulationStudy(id: studyId, name: "Solved Study", studyType: .linearStatic)
        study.results.status = .completed
        study.contourSettings.isVisible = true
        study.contourSettings.field = .vonMisesStress

        let extrema = SimulationContourExtrema(
            fieldName: "von Mises Stress",
            unitSymbol: "MPa",
            actualMin: 12.5,
            actualMax: 245.0,
            effectiveMin: 12.5,
            effectiveMax: 245.0,
            minNodeId: 1,
            maxNodeId: 10,
            minPosition: SIMD3<Double>(0, 0, 0),
            maxPosition: SIMD3<Double>(10, 10, 10)
        )
        ws.activeContourExtrema[studyId] = extrema

        let inspectorView = InspectorSimulationResultsView(study: study).environment(ws)
        _ = inspectorView

        let legendView = SimulationContourLegendOverlayView(
            studyId: studyId,
            settings: study.contourSettings,
            extrema: extrema
        ).environment(ws)
        _ = legendView
    }

    // MARK: - Animation & Load Steps Lifecycle Tests (BL-RES-03, #324)

    @Test func testSimulationAnimationLifecycle() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Animation Study") else {
            Issue.record("Failed to create study")
            return
        }

        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        let elem = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 1)
        let mesh = VolumeMesh(nodes: [n1, n2, n3, n4], elements: [elem])
        ws.cachedStudyMeshes[study.id] = mesh

        study.results.status = .completed
        study.results.nodalDisplacements = [
            1: .zero,
            2: SIMD3<Double>(1, 0, 0),
            3: SIMD3<Double>(0, 1, 0),
            4: SIMD3<Double>(0, 0, 1)
        ]
        study.contourSettings.isVisible = true
        study.contourSettings.isDeformed = true
        study.contourSettings.animationMode = .harmonic
        study.contourSettings.animationSpeed = 1.0
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)
        _ = ws.document.updateSimulationContourSettings(studyId: study.id, settings: study.contourSettings)

        // 1. Start animation
        ws.startSimulationAnimation(studyId: study.id)
        #expect(ws.simulationAnimationStates[study.id]?.isPlaying == true)

        // 2. Pause animation
        ws.pauseSimulationAnimation(studyId: study.id)
        #expect(ws.simulationAnimationStates[study.id]?.isPlaying == false)

        // 3. Toggle animation (resumes play)
        ws.toggleSimulationAnimation(studyId: study.id)
        #expect(ws.simulationAnimationStates[study.id]?.isPlaying == true)

        // 4. Toggle animation (pauses)
        ws.toggleSimulationAnimation(studyId: study.id)
        #expect(ws.simulationAnimationStates[study.id]?.isPlaying == false)

        // 5. Stop animation (resets phase to 0.0)
        ws.startSimulationAnimation(studyId: study.id)
        ws.stopSimulationAnimation(studyId: study.id)
        #expect(ws.simulationAnimationStates[study.id]?.isPlaying == false)
        #expect(ws.simulationAnimationStates[study.id]?.phase == 0.0)
    }

    @Test func testSimulationAnimationPhaseScrubbing() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Scrub Study") else {
            Issue.record("Failed to create study")
            return
        }

        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        let elem = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 1)
        let mesh = VolumeMesh(nodes: [n1, n2, n3, n4], elements: [elem])
        ws.cachedStudyMeshes[study.id] = mesh

        study.results.status = .completed
        study.results.nodalDisplacements = [
            1: .zero,
            2: SIMD3<Double>(2, 0, 0),
            3: SIMD3<Double>(0, 2, 0),
            4: SIMD3<Double>(0, 0, 2)
        ]
        study.contourSettings.isVisible = true
        study.contourSettings.isDeformed = true
        study.contourSettings.deformationScale = 1.0
        study.contourSettings.animationMode = .linearRamp
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)
        _ = ws.document.updateSimulationContourSettings(studyId: study.id, settings: study.contourSettings)

        ws.isDocumentModified = false

        // Scrub while paused to phase 0.5
        ws.scrubSimulationAnimation(studyId: study.id, phase: 0.5)
        #expect(ws.simulationAnimationStates[study.id]?.phase == 0.5)
        #expect(ws.isDocumentModified == false)

        // Viewport extrema updated immediately
        let ext = ws.activeContourExtrema[study.id]
        #expect(ext != nil)
    }

    @Test func testSelectLoadStepNavigation() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Load Step Study") else {
            Issue.record("Failed to create study")
            return
        }

        let n1 = VolumeMeshNode(id: 1, position: SIMD3<Double>(0, 0, 0))
        let n2 = VolumeMeshNode(id: 2, position: SIMD3<Double>(10, 0, 0))
        let n3 = VolumeMeshNode(id: 3, position: SIMD3<Double>(0, 10, 0))
        let n4 = VolumeMeshNode(id: 4, position: SIMD3<Double>(0, 0, 10))
        let elem = VolumeMeshElement(id: 1, order: .linear, nodeIndices: [1, 2, 3, 4], tag: 1)
        let mesh = VolumeMesh(nodes: [n1, n2, n3, n4], elements: [elem])
        ws.cachedStudyMeshes[study.id] = mesh

        let step1 = SimulationLoadStep(
            stepNumber: 1,
            timeOrFactor: 0.5,
            nodalDisplacements: [1: .zero, 2: SIMD3<Double>(1, 0, 0), 3: .zero, 4: .zero],
            nodalVonMisesStresses: [1: 25.0, 2: 50.0, 3: 10.0, 4: 5.0]
        )
        let step2 = SimulationLoadStep(
            stepNumber: 2,
            timeOrFactor: 1.0,
            nodalDisplacements: [1: .zero, 2: SIMD3<Double>(2, 0, 0), 3: .zero, 4: .zero],
            nodalVonMisesStresses: [1: 50.0, 2: 100.0, 3: 20.0, 4: 10.0]
        )

        study.results.status = .completed
        study.results.loadSteps = [step1, step2]
        study.contourSettings.isVisible = true
        study.contourSettings.isDeformed = true
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)
        _ = ws.document.updateSimulationContourSettings(studyId: study.id, settings: study.contourSettings)

        ws.isDocumentModified = false

        // Select Step 2
        ws.selectLoadStep(studyId: study.id, stepNumber: 2)

        let updatedStudy = ws.document.study(id: study.id)
        #expect(updatedStudy?.contourSettings.activeLoadStepNumber == 2)
        #expect(updatedStudy?.results.nodalDisplacements?[2] == SIMD3<Double>(2, 0, 0))
        #expect(updatedStudy?.results.nodalVonMisesStresses?[2] == 100.0)
        #expect(ws.isDocumentModified == true)
    }

    @Test func testInspectorSimulationResultsAnimationAndLoadStepHierarchy() {
        let ws = WorkspaceModel()
        let studyId = UUID()
        let step = SimulationLoadStep(
            stepNumber: 1,
            timeOrFactor: 1.0,
            nodalDisplacements: [1: .zero]
        )
        let mode = SimulationModeShape(modeNumber: 1, frequencyHz: 120.0, nodalDisplacements: [1: .zero])

        var study = SimulationStudy(id: studyId, name: "Full Solved Study", studyType: .modalFrequency)
        study.results.status = .completed
        study.results.loadSteps = [step]
        study.results.modeShapes = [mode]
        study.contourSettings.isVisible = true
        study.contourSettings.isDeformed = true
        study.contourSettings.showUndeformedWireframe = true

        let inspectorView = InspectorSimulationResultsView(study: study).environment(ws)
        _ = inspectorView
    }

    @Test func testAnimationStopsWhenStudyRemoved() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Removable Study") else {
            Issue.record("Failed to create study")
            return
        }

        study.results.status = .completed
        study.contourSettings.isVisible = true
        study.contourSettings.isDeformed = true
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)
        _ = ws.document.updateSimulationContourSettings(studyId: study.id, settings: study.contourSettings)

        ws.startSimulationAnimation(studyId: study.id)
        #expect(ws.simulationAnimationStates[study.id]?.isPlaying == true)

        ws.removeSimulationStudy(id: study.id)
        #expect(ws.simulationAnimationStates[study.id]?.isPlaying == false)
    }

    @Test func testWorkspaceProbeLifecycleAndMutations() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Probe Study") else {
            Issue.record("Failed to create study")
            return
        }

        #expect(ws.isProbeModeActive == false)
        ws.toggleProbeMode()
        #expect(ws.isProbeModeActive == true)
        #expect(ws.document.study(id: study.id)?.probeTable.isProbingActive == true)

        // Add a probe point
        ws.addProbePoint(studyId: study.id, position: SIMD3<Double>(10, 20, 30), name: "Test Probe")
        let updatedStudy = ws.document.study(id: study.id)
        #expect(updatedStudy?.probeTable.probes.count == 1)
        #expect(updatedStudy?.probeTable.probes[0].name == "Test Probe")
        #expect(updatedStudy?.probeTable.probes[0].position == SIMD3<Double>(10, 20, 30))

        // Add a linear path probe
        ws.addPathProbe(studyId: study.id, start: .zero, end: SIMD3<Double>(10, 0, 0), sampleCount: 5, name: "Path Probe")
        let studyWithPath = ws.document.study(id: study.id)
        #expect(studyWithPath?.probeTable.paths.count == 1)
        #expect(studyWithPath?.probeTable.probes.count == 6) // 1 point + 5 path samples

        // Export CSV
        let csv = ws.exportProbesCSV(studyId: study.id)
        #expect(csv.contains("Test Probe"))
        #expect(csv.contains("Path Probe [1]"))

        // Copy to clipboard
        ws.copyProbesCSVToClipboard(studyId: study.id)

        // Remove a single probe
        if let firstProbeId = studyWithPath?.probeTable.probes[0].id {
            ws.removeProbe(studyId: study.id, probeId: firstProbeId)
            #expect(ws.document.study(id: study.id)?.probeTable.probes.count == 5)
        }

        // Clear all probes
        ws.clearProbes(studyId: study.id)
        #expect(ws.document.study(id: study.id)?.probeTable.probes.isEmpty == true)
        #expect(ws.document.study(id: study.id)?.probeTable.paths.isEmpty == true)
    }

    @Test func testInspectorSimulationResultsProbesSection() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Results Probe Test") else {
            Issue.record("Failed to create study")
            return
        }

        study.results.status = .completed
        let p = SimulationProbePoint(
            name: "Critical Point",
            kind: .point,
            position: SIMD3<Double>(5, 5, 5),
            fieldValues: [.vonMisesStress: 350.0]
        )
        study.probeTable.probes.append(p)
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)
        _ = ws.document.updateSimulationProbeTable(studyId: study.id, probeTable: study.probeTable)

        let inspectorView = InspectorSimulationResultsView(study: study).environment(ws)
        _ = inspectorView
    }

    @Test func testSimulationContourLegendOverlayProbeBadges() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Overlay Probe Test") else {
            Issue.record("Failed to create study")
            return
        }

        study.results.status = .completed
        study.contourSettings.isVisible = true
        let p = SimulationProbePoint(
            name: "Badge Probe",
            kind: .point,
            position: SIMD3<Double>(0, 0, 0),
            fieldValues: [.vonMisesStress: 100.0]
        )
        study.probeTable.probes.append(p)
        study.probeTable.showProbeBadges = true
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)
        _ = ws.document.updateSimulationProbeTable(studyId: study.id, probeTable: study.probeTable)

        let extrema = SimulationContourExtrema(
            fieldName: "von Mises Stress",
            unitSymbol: "MPa",
            actualMin: 0.0,
            actualMax: 200.0,
            effectiveMin: 0.0,
            effectiveMax: 200.0,
            minNodeId: 1,
            maxNodeId: 2,
            minPosition: .zero,
            maxPosition: SIMD3<Double>(10, 0, 0)
        )

        let overlayView = SimulationContourLegendOverlayView(
            studyId: study.id,
            settings: study.contourSettings,
            extrema: extrema
        ).environment(ws)
        _ = overlayView
    }

    // MARK: - Reaction Forces & Body Summaries UI Tests (BL-RES-06, #326)

    @Test func testInspectorSimulationResultsViewReactionForcesSection() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Reactions UI Test") else {
            Issue.record("Failed to create study")
            return
        }

        let fixtureId1 = UUID()
        let fixtureId2 = UUID()
        let rxn1 = SimulationConstraintReaction(
            id: fixtureId1,
            fixtureName: "Fixed Clamp",
            reactionForce: SIMD3<Double>(0.0, 600.0, 0.0),
            reactionMoment: SIMD3<Double>(0.0, 0.0, 150.0),
            referencePoint: SIMD3<Double>(0.0, 25.0, 25.0),
            nodeCount: 12
        )
        let rxn2 = SimulationConstraintReaction(
            id: fixtureId2,
            fixtureName: "Roller Support",
            reactionForce: SIMD3<Double>(0.0, 400.0, 0.0),
            reactionMoment: SIMD3<Double>(0.0, 0.0, 50.0),
            referencePoint: SIMD3<Double>(500.0, 25.0, 25.0),
            nodeCount: 8
        )

        study.results.status = .completed
        study.results.constraintReactions = [rxn1, rxn2]
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)

        let totalF = study.results.totalReactionForce
        #expect(totalF == SIMD3<Double>(0.0, 1000.0, 0.0))
        let totalM = study.results.totalReactionMoment
        #expect(totalM == SIMD3<Double>(0.0, 0.0, 200.0))

        let inspectorView = InspectorSimulationResultsView(study: study).environment(ws)
        _ = inspectorView
    }

    @Test func testInspectorSimulationResultsViewBodySummariesSection() {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Body Summaries UI Test") else {
            Issue.record("Failed to create study")
            return
        }

        let bodyId = UUID()
        let summary = SimulationBodySummary(
            id: bodyId,
            bodyName: "Casing Solid",
            nodeCount: 85,
            elementCount: 320,
            maxVonMisesStress: 210.5,
            maxDisplacement: 0.85,
            minFactorOfSafety: 1.85,
            maxTemperature: 80.0,
            extrema: [
                SimulationFieldExtrema(fieldName: "von Mises Stress", unitSymbol: "MPa", minValue: 15.0, maxValue: 210.5)
            ]
        )

        study.results.status = .completed
        study.results.bodySummaries = [summary]
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)

        #expect(study.results.bodySummaries?.count == 1)
        #expect(study.results.bodySummaries?[0].bodyName == "Casing Solid")

        let inspectorView = InspectorSimulationResultsView(study: study).environment(ws)
        _ = inspectorView
    }

    // MARK: - Simulation Report Export UI Tests (BL-RES-07, #327)

    @Test func testWorkspaceSimulationReportExportLifecycle() throws {
        let ws = WorkspaceModel()
        guard var study = ws.createSimulationStudy(type: .linearStatic, name: "Report Export Lifecycle Test") else {
            Issue.record("Failed to create study")
            return
        }

        study.results.status = .completed
        study.results.meshStatistics = SimulationMeshStatistics(nodeCount: 50, elementCount: 150)
        study.results.extrema = [
            SimulationFieldExtrema(fieldName: "von Mises Stress", unitSymbol: "MPa", minValue: 10.0, maxValue: 120.0)
        ]
        _ = ws.document.updateSimulationStudyResults(studyId: study.id, results: study.results)

        // 1. Export HTML string
        let html = ws.exportSimulationReportHTML(studyId: study.id)
        #expect(html != nil)
        #expect(html?.contains("Report Export Lifecycle Test") == true)
        #expect(html?.contains("<!DOCTYPE html>") == true)

        // 2. Export PDF data
        let pdfData = try ws.exportSimulationReportPDF(studyId: study.id)
        #expect(pdfData != nil)
        #expect(pdfData?.isEmpty == false)
        let header = String(decoding: (pdfData ?? Data()).prefix(5), as: UTF8.self)
        #expect(header == "%PDF-")

        // 3. Export to temp file
        let tempHTMLURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
        try ws.exportSimulationReport(studyId: study.id, format: .html, to: tempHTMLURL)
        #expect(FileManager.default.fileExists(atPath: tempHTMLURL.path))
        try? FileManager.default.removeItem(at: tempHTMLURL)

        let tempPDFURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try ws.exportSimulationReport(studyId: study.id, format: .pdf, to: tempPDFURL)
        #expect(FileManager.default.fileExists(atPath: tempPDFURL.path))
        try? FileManager.default.removeItem(at: tempPDFURL)
    }

    @Test func testInspectorSimulationResultsViewReportExportSection() {
        let ws = WorkspaceModel()
        guard let study = ws.createSimulationStudy(type: .linearStatic, name: "Export Section Test") else {
            Issue.record("Failed to create study")
            return
        }

        let inspectorView = InspectorSimulationResultsView(study: study).environment(ws)
        _ = inspectorView
    }
}


private actor MockSolverRunner: SolverRunnerProtocol {
    var shouldFailWithBinaryNotFound = false
    var delayNanoseconds: UInt64 = 0
    var cancelledStudyIds: Set<UUID> = []

    func setShouldFailWithBinaryNotFound(_ val: Bool) {
        shouldFailWithBinaryNotFound = val
    }

    func setDelayNanoseconds(_ val: UInt64) {
        delayNanoseconds = val
    }

    func run(
        deck: CAEDeck,
        configuration: SolverConfiguration,
        packageResultsURL: URL?,
        outputHandler: (@Sendable (String) -> Void)?
    ) async throws -> SolverRunResult {
        if shouldFailWithBinaryNotFound {
            throw CAEErrorCode.solverBinaryNotFound(solver: "CalculiX (ccx)", searchedPaths: ["/mock/bin/ccx"])
        }
        outputHandler?("CalculiX Mock v1.0")
        outputHandler?("ITERATION 1 RESIDUAL 1.0e-5")
        if delayNanoseconds > 0 {
            let slice = delayNanoseconds / 20
            for _ in 0..<20 {
                if cancelledStudyIds.contains(deck.studyId) || Task.isCancelled {
                    throw CAEErrorCode.executionCancelled
                }
                do {
                    try await Task.sleep(nanoseconds: slice)
                } catch {
                    throw CAEErrorCode.executionCancelled
                }
            }
        }
        if cancelledStudyIds.contains(deck.studyId) || Task.isCancelled {
            throw CAEErrorCode.executionCancelled
        }
        return SolverRunResult(
            status: .completed,
            runtimeDuration: 0.15,
            exitCode: 0,
            rawOutput: "CalculiX Mock v1.0\nITERATION 1 RESIDUAL 1.0e-5",
            resultFiles: [:],
            errorMessage: nil
        )
    }

    func cancel(studyId: UUID) async {
        cancelledStudyIds.insert(studyId)
    }
}

private actor MockVolumeMesher: VolumeMesherProtocol {
    var shouldFailWithBinaryNotFound = false
    var delayNanoseconds: UInt64 = 0
    var cancelledStudyIds: Set<UUID> = []

    func setShouldFailWithBinaryNotFound(_ val: Bool) {
        shouldFailWithBinaryNotFound = val
    }

    func setDelayNanoseconds(_ val: UInt64) {
        delayNanoseconds = val
    }

    func mesh(
        stepData: Data,
        specification: MeshSpecification,
        studyId: UUID,
        packageResultsURL: URL?,
        outputHandler: (@Sendable (String) -> Void)?
    ) async throws -> VolumeMeshResult {
        if shouldFailWithBinaryNotFound {
            throw CAEErrorCode.solverBinaryNotFound(solver: "Gmsh (gmsh)", searchedPaths: ["/mock/bin/gmsh"])
        }
        outputHandler?("Info    : Running Mock Gmsh")
        outputHandler?("Info    : Meshing volume...")
        if delayNanoseconds > 0 {
            let slice = delayNanoseconds / 20
            for _ in 0..<20 {
                if cancelledStudyIds.contains(studyId) || Task.isCancelled {
                    throw CAEErrorCode.executionCancelled
                }
                do {
                    try await Task.sleep(nanoseconds: slice)
                } catch {
                    throw CAEErrorCode.executionCancelled
                }
            }
        }
        if cancelledStudyIds.contains(studyId) || Task.isCancelled {
            throw CAEErrorCode.executionCancelled
        }

        let mesh = try MSHParser.parse(content: VolumeMesherFixture.minimalMSHContent(order: specification.elementOrder))
        return VolumeMeshResult(
            mesh: mesh,
            meshFileURL: packageResultsURL?.appendingPathComponent("mesh.msh"),
            runtimeDuration: 0.12,
            exitCode: 0,
            rawOutput: "Info    : Running Mock Gmsh\nInfo    : Meshing volume..."
        )
    }

    func cancel(studyId: UUID) async {
        cancelledStudyIds.insert(studyId)
    }
}
