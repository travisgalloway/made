import Testing
import Foundation
@testable import MadeCore

@Suite @MainActor struct SimulationDocumentModelTests {

    @Test func testDefaultDocumentHasNoStudies() {
        let doc = DocumentModel()
        #expect(doc.studies.isEmpty)
        #expect(doc.activeStudyId == nil)
        #expect(doc.activeStudy == nil)
    }

    @Test func testAddAndRemoveStudyWithUndo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let study = SimulationStudy(name: "Structural Analysis", studyType: .linearStatic)
        doc.addStudy(study)

        #expect(doc.studies.count == 1)
        #expect(doc.activeStudyId == study.id)
        #expect(doc.study(id: study.id)?.name == "Structural Analysis")

        undoManager.undo()
        #expect(doc.studies.isEmpty)
        #expect(doc.activeStudyId == nil)

        undoManager.redo()
        #expect(doc.studies.count == 1)
        #expect(doc.activeStudyId == study.id)

        undoManager.removeAllActions()
        doc.removeStudy(id: study.id)
        #expect(doc.studies.isEmpty)
        #expect(doc.activeStudyId == nil)

        undoManager.undo()
        #expect(doc.studies.count == 1)
        #expect(doc.activeStudyId == study.id)
    }

    @Test func testRenameAndToggleStudyWithUndo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let study = SimulationStudy(name: "Initial Name", studyType: .modalFrequency)
        doc.addStudy(study)
        doc.setActiveStudy(id: study.id)
        undoManager.removeAllActions()

        doc.renameStudy(id: study.id, name: "Vibration Test")
        #expect(doc.study(id: study.id)?.name == "Vibration Test")

        undoManager.undo()
        #expect(doc.study(id: study.id)?.name == "Initial Name")

        undoManager.redo()
        #expect(doc.study(id: study.id)?.name == "Vibration Test")

        undoManager.removeAllActions()
        doc.toggleStudyCollapsed(id: study.id)
        #expect(doc.study(id: study.id)?.isCollapsed == true)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.isCollapsed == false)
    }

    @Test func testSetActiveStudyWithUndo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let studyA = SimulationStudy(name: "Study A", studyType: .linearStatic)
        let studyB = SimulationStudy(name: "Study B", studyType: .thermalConduction)
        doc.addStudy(studyA)
        doc.addStudy(studyB)
        doc.setActiveStudy(id: studyA.id)
        undoManager.removeAllActions()

        #expect(doc.activeStudyId == studyA.id)

        doc.setActiveStudy(id: studyB.id)
        #expect(doc.activeStudyId == studyB.id)

        undoManager.undo()
        #expect(doc.activeStudyId == studyA.id)

        undoManager.redo()
        #expect(doc.activeStudyId == studyB.id)
    }

    @Test func testFixtureMutationsWithUndo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let study = SimulationStudy(name: "Bracket Study", studyType: .linearStatic)
        doc.addStudy(study)
        undoManager.removeAllActions()

        let fixture = SimulationFixture(name: "Fixed Base", kind: .fixed)
        doc.addSimulationFixture(studyId: study.id, fixture: fixture)

        #expect(doc.study(id: study.id)?.fixtures.count == 1)
        #expect(doc.study(id: study.id)?.fixtures.first?.id == fixture.id)

        undoManager.removeAllActions()
        var updatedFixture = fixture
        updatedFixture.name = "Clamped Support"
        doc.updateSimulationFixture(studyId: study.id, fixture: updatedFixture)
        #expect(doc.study(id: study.id)?.fixtures.first?.name == "Clamped Support")

        undoManager.undo()
        #expect(doc.study(id: study.id)?.fixtures.first?.name == "Fixed Base")

        undoManager.removeAllActions()
        doc.removeSimulationFixture(studyId: study.id, fixtureId: fixture.id)
        #expect(doc.study(id: study.id)?.fixtures.isEmpty == true)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.fixtures.count == 1)
    }

    @Test func testLoadMutationsWithUndo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let study = SimulationStudy(name: "Bracket Study", studyType: .linearStatic)
        doc.addStudy(study)
        undoManager.removeAllActions()

        let load = SimulationLoad(name: "Point Force", kind: .force, magnitude: 250.0)
        doc.addSimulationLoad(studyId: study.id, load: load)

        #expect(doc.study(id: study.id)?.loads.count == 1)
        #expect(doc.study(id: study.id)?.loads.first?.magnitude == 250.0)

        undoManager.removeAllActions()
        var updatedLoad = load
        updatedLoad.magnitude = 500.0
        doc.updateSimulationLoad(studyId: study.id, load: updatedLoad)
        #expect(doc.study(id: study.id)?.loads.first?.magnitude == 500.0)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.loads.first?.magnitude == 250.0)

        undoManager.removeAllActions()
        doc.removeSimulationLoad(studyId: study.id, loadId: load.id)
        #expect(doc.study(id: study.id)?.loads.isEmpty == true)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.loads.count == 1)
    }

    @Test func testGeometryGroupDocumentMutationsAndUndoRedo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let study = SimulationStudy(name: "Bracket Study", studyType: .linearStatic)
        doc.addStudy(study)
        undoManager.removeAllActions()

        let group = SimulationGeometryGroup(
            name: "Clamp Group",
            targetReferences: [
                SimulationGeometryReference(targetId: UUID(), targetName: "Face 1", subelementType: .face)
            ]
        )
        doc.addSimulationGeometryGroup(studyId: study.id, group: group)

        #expect(doc.study(id: study.id)?.groups.count == 1)
        #expect(doc.study(id: study.id)?.groups.first?.name == "Clamp Group")

        undoManager.undo()
        #expect(doc.study(id: study.id)?.groups.isEmpty == true)

        undoManager.redo()
        #expect(doc.study(id: study.id)?.groups.count == 1)

        undoManager.removeAllActions()
        var updated = group
        updated.name = "Updated Clamp Group"
        doc.updateSimulationGeometryGroup(studyId: study.id, group: updated)
        #expect(doc.study(id: study.id)?.groups.first?.name == "Updated Clamp Group")

        undoManager.undo()
        #expect(doc.study(id: study.id)?.groups.first?.name == "Clamp Group")

        undoManager.removeAllActions()
        doc.removeSimulationGeometryGroup(studyId: study.id, groupId: group.id)
        #expect(doc.study(id: study.id)?.groups.isEmpty == true)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.groups.count == 1)
    }

    @Test func testFixtureAndLoadTargetReferenceMutationsWithUndoRedo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let fixture = SimulationFixture(name: "Base")
        let load = SimulationLoad(name: "Force")
        let study = SimulationStudy(name: "Bracket Study", fixtures: [fixture], loads: [load])
        doc.addStudy(study)
        undoManager.removeAllActions()

        let ref1 = SimulationGeometryReference(targetId: UUID(), targetName: "Face 1", subelementType: .face)
        doc.assignTargetReferenceToFixture(studyId: study.id, fixtureId: fixture.id, reference: ref1)
        #expect(doc.study(id: study.id)?.fixtures.first?.targetReferences.count == 1)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.fixtures.first?.targetReferences.isEmpty == true)

        undoManager.redo()
        #expect(doc.study(id: study.id)?.fixtures.first?.targetReferences.count == 1)

        undoManager.removeAllActions()
        doc.removeTargetReferenceFromFixture(studyId: study.id, fixtureId: fixture.id, referenceId: ref1.id)
        #expect(doc.study(id: study.id)?.fixtures.first?.targetReferences.isEmpty == true)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.fixtures.first?.targetReferences.count == 1)

        // Load targets
        undoManager.removeAllActions()
        let ref2 = SimulationGeometryReference(targetId: UUID(), targetName: "Face 2", subelementType: .face)
        doc.assignTargetReferenceToLoad(studyId: study.id, loadId: load.id, reference: ref2)
        #expect(doc.study(id: study.id)?.loads.first?.targetReferences.count == 1)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.loads.first?.targetReferences.isEmpty == true)

        undoManager.redo()
        #expect(doc.study(id: study.id)?.loads.first?.targetReferences.count == 1)

        undoManager.removeAllActions()
        doc.removeTargetReferenceFromLoad(studyId: study.id, loadId: load.id, referenceId: ref2.id)
        #expect(doc.study(id: study.id)?.loads.first?.targetReferences.isEmpty == true)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.loads.first?.targetReferences.count == 1)
    }

    @Test func testGroupDeletionCascadeRemovesGroupFromFixturesAndLoads() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let group = SimulationGeometryGroup(name: "Shared Group")
        let fixture = SimulationFixture(name: "Base", groupNames: ["Shared Group"])
        let load = SimulationLoad(name: "Force", groupNames: ["Shared Group"])
        let study = SimulationStudy(name: "Cascade Study", groups: [group], fixtures: [fixture], loads: [load])
        doc.addStudy(study)
        undoManager.removeAllActions()

        doc.removeSimulationGeometryGroup(studyId: study.id, groupId: group.id)
        #expect(doc.study(id: study.id)?.groups.isEmpty == true)
        #expect(doc.study(id: study.id)?.fixtures.first?.groupNames.isEmpty == true)
        #expect(doc.study(id: study.id)?.loads.first?.groupNames.isEmpty == true)

        undoManager.undo()
        #expect(doc.study(id: study.id)?.groups.count == 1)
        #expect(doc.study(id: study.id)?.fixtures.first?.groupNames == ["Shared Group"])
        #expect(doc.study(id: study.id)?.loads.first?.groupNames == ["Shared Group"])
    }

    @Test func testUpdateSimulationMeshSpecificationWithUndoRedo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let study = SimulationStudy(name: "Mesh Undo Study", studyType: .linearStatic)
        doc.addStudy(study)
        undoManager.removeAllActions()

        let initialMesh = doc.study(id: study.id)?.mesh
        #expect(initialMesh?.elementOrder == .quadratic)
        #expect(initialMesh?.targetElementSize == 5.0)
        #expect(initialMesh?.curvatureRefinement == false)

        var updatedMesh = initialMesh ?? MeshSpecification()
        updatedMesh.elementOrder = .linear
        updatedMesh.targetElementSize = 2.5
        updatedMesh.minElementSize = 0.5
        updatedMesh.curvatureRefinement = true
        updatedMesh.curvatureElementsPerCircle = 16.0

        let result = doc.updateSimulationMeshSpecification(studyId: study.id, mesh: updatedMesh)
        #expect(result == .success(()))

        let currentMesh = doc.study(id: study.id)?.mesh
        #expect(currentMesh?.elementOrder == .linear)
        #expect(currentMesh?.targetElementSize == 2.5)
        #expect(currentMesh?.minElementSize == 0.5)
        #expect(currentMesh?.curvatureRefinement == true)
        #expect(currentMesh?.curvatureElementsPerCircle == 16.0)

        undoManager.undo()
        let undoneMesh = doc.study(id: study.id)?.mesh
        #expect(undoneMesh == initialMesh)
        #expect(undoneMesh?.elementOrder == .quadratic)
        #expect(undoneMesh?.curvatureRefinement == false)

        undoManager.redo()
        let redoneMesh = doc.study(id: study.id)?.mesh
        #expect(redoneMesh == updatedMesh)
        #expect(redoneMesh?.elementOrder == .linear)
        #expect(redoneMesh?.curvatureRefinement == true)
        #expect(redoneMesh?.curvatureElementsPerCircle == 16.0)
    }

    @Test func testUpdateMeshSpecificationWithRefinementRegionsUndoRedo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let study = SimulationStudy(name: "Refinement Undo Study", studyType: .linearStatic)
        doc.addStudy(study)
        undoManager.removeAllActions()

        let initialMesh = doc.study(id: study.id)?.mesh
        #expect(initialMesh?.refinementRegions.isEmpty == true)

        var updatedMesh = initialMesh ?? MeshSpecification()
        let region = MeshRefinementRegion(
            name: "Critical Fillet",
            targetReferences: [SimulationGeometryReference(targetId: UUID(), targetName: "Face 4", subelementType: .face)],
            targetElementSize: 0.25
        )
        updatedMesh.refinementRegions = [region]

        let result = doc.updateSimulationMeshSpecification(studyId: study.id, mesh: updatedMesh)
        #expect(result == .success(()))

        let currentMesh = doc.study(id: study.id)?.mesh
        #expect(currentMesh?.refinementRegions.count == 1)
        #expect(currentMesh?.refinementRegions.first?.name == "Critical Fillet")
        #expect(currentMesh?.refinementRegions.first?.targetElementSize == 0.25)

        undoManager.undo()
        let undoneMesh = doc.study(id: study.id)?.mesh
        #expect(undoneMesh?.refinementRegions.isEmpty == true)

        undoManager.redo()
        let redoneMesh = doc.study(id: study.id)?.mesh
        #expect(redoneMesh?.refinementRegions.count == 1)
        #expect(redoneMesh?.refinementRegions.first?.name == "Critical Fillet")
    }

    @Test func testUpdateSimulationMeshDisplaySettingsWithUndoRedo() {
        let doc = DocumentModel()
        let undoManager = UndoManager()
        doc.undoManager = undoManager

        let study = SimulationStudy(name: "Display Undo Study", studyType: .linearStatic)
        doc.addStudy(study)
        undoManager.removeAllActions()

        let initialSettings = doc.study(id: study.id)?.meshDisplay
        #expect(initialSettings?.isVisible == true)
        #expect(initialSettings?.elementShrink == 0.0)

        let newSettings = SimulationMeshDisplaySettings(
            isVisible: true,
            showEdges: true,
            showFaces: false,
            elementShrink: 0.4,
            isSliceEnabled: true,
            sliceAxis: .x,
            slicePosition: 0.3,
            isSliceInverted: true,
            hideSolidBody: true
        )

        let result = doc.updateSimulationMeshDisplaySettings(studyId: study.id, settings: newSettings)
        #expect(result == .success(()))

        let currentSettings = doc.study(id: study.id)?.meshDisplay
        #expect(currentSettings?.showFaces == false)
        #expect(currentSettings?.elementShrink == 0.4)
        #expect(currentSettings?.isSliceEnabled == true)
        #expect(currentSettings?.sliceAxis == .x)
        #expect(currentSettings?.isSliceInverted == true)
        #expect(currentSettings?.hideSolidBody == true)

        undoManager.undo()
        let undoneSettings = doc.study(id: study.id)?.meshDisplay
        #expect(undoneSettings?.showFaces == true)
        #expect(undoneSettings?.elementShrink == 0.0)
        #expect(undoneSettings?.isSliceEnabled == false)

        undoManager.redo()
        let redoneSettings = doc.study(id: study.id)?.meshDisplay
        #expect(redoneSettings?.showFaces == false)
        #expect(redoneSettings?.elementShrink == 0.4)
        #expect(redoneSettings?.isSliceEnabled == true)
    }
}
