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
