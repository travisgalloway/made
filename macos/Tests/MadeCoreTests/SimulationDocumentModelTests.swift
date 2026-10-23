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
}
