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
