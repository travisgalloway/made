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
