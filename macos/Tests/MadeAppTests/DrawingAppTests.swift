import Testing
import Foundation
import SwiftUI
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct DrawingAppTests {

    @Test func testNewDrawingShortcutConstants() {
        #expect(WorkspaceModel.newDrawingShortcutKey == "d")
        #expect(WorkspaceModel.newDrawingShortcutModifiers == [.command, .shift])
    }

    @Test func testNewDrawingDocumentInWorkspace() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        #expect(ws.document.documentType == .drawing)
        #expect(ws.document.sheets.count == 1)
        #expect(ws.document.activeSheet?.name == "Sheet 1")
        #expect(ws.document.activeSheet?.size == .isoA3)
        #expect(ws.document.activeSheet?.orientation == .landscape)
        #expect(!ws.isDocumentModified)
        #expect(ws.currentDocumentURL == nil)
    }

    @Test func testSheetOperationsInWorkspace() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        // 1. Add sheet
        let sheet2 = ws.addSheet(name: "Fabrication Details", size: .ansiC, orientation: .landscape)
        #expect(ws.document.sheets.count == 2)
        #expect(ws.document.activeSheetId == sheet2.id)
        #expect(ws.isDocumentModified)

        // 2. Duplicate sheet
        let duplicate = ws.duplicateSheet(id: sheet2.id)
        #expect(duplicate != nil)
        #expect(ws.document.sheets.count == 3)
        #expect(ws.document.sheets[2].name == "Fabrication Details Copy")
        #expect(ws.document.activeSheetId == duplicate?.id)

        // 3. Update sheet
        if var active = ws.document.activeSheet {
            active.scale = "1:5"
            active.titleBlockTemplate = .minimal
            let updated = ws.updateSheet(active)
            #expect(updated)
            #expect(ws.document.activeSheet?.scale == "1:5")
            #expect(ws.document.activeSheet?.titleBlockTemplate == .minimal)
        }

        // 4. Set sheet property
        let propSet = ws.setSheetProperty(sheetId: sheet2.id, key: "DrawnBy", value: "CAD Specialist")
        #expect(propSet)
        #expect(ws.document.sheets.first(where: { $0.id == sheet2.id })?.property(forKey: "DrawnBy") == "CAD Specialist")

        // 5. Remove sheet
        ws.document.undoManager?.removeAllActions()
        if let dupId = duplicate?.id {
            let removed = ws.removeSheet(id: dupId)
            #expect(removed)
            #expect(ws.document.sheets.count == 2)
        }

        // 6. Undo through workspace
        ws.undo()
        #expect(ws.document.sheets.count == 3)

        // 7. Redo through workspace
        ws.redo()
        #expect(ws.document.sheets.count == 2)
    }

    @Test func testWorkspacePackageSaveAndReopenDrawing() throws {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        _ = ws.addSheet(name: "Sheet 2", size: .isoA4, orientation: .portrait)
        ws.setDocumentProperty(key: CustomPropertyKey.partNumber, value: "PRJ-DRAW-001")
        ws.setDocumentProperty(key: CustomPropertyKey.description, value: "Project Assembly Drawing")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("DrawingWorkspaceTest.made")
        let package = try ws.makePackage()
        try package.write(to: packageURL)

        // Open in new workspace
        let ws2 = WorkspaceModel()
        let opened = ws2.openDocument(at: packageURL)
        #expect(opened)
        #expect(ws2.document.documentType == .drawing)
        #expect(ws2.document.sheets.count == 2)
        #expect(ws2.document.sheets[0].name == "Sheet 1")
        #expect(ws2.document.sheets[1].name == "Sheet 2")
        #expect(ws2.document.sheets[1].size == .isoA4)
        #expect(ws2.document.metadata[CustomPropertyKey.partNumber] == "PRJ-DRAW-001")
        #expect(ws2.document.metadata[CustomPropertyKey.description] == "Project Assembly Drawing")
    }

    @Test func testDrawingViewWorkspaceActionsAndUndo() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        #expect(ws.document.activeSheet?.views.isEmpty == true)

        // 1. Add base view
        let base = ws.addBaseView(standardView: .front, scale: .half, displayStyle: .visibleLinesOnly)
        #expect(base != nil)
        #expect(ws.document.activeSheet?.views.count == 1)
        #expect(ws.selectedDrawingViewId == base?.id)
        #expect(ws.selectedDrawingView?.standardView == .front)
        #expect(ws.isDocumentModified)

        // 2. Add projected view
        guard let baseId = base?.id else { return }
        let projected = ws.addProjectedView(parentViewId: baseId, direction: .right)
        #expect(projected != nil)
        #expect(ws.document.activeSheet?.views.count == 2)
        #expect(projected?.parentViewId == baseId)
        #expect(projected?.kind == .projected)

        // 3. Reposition view
        guard let projId = projected?.id else { return }
        let repositioned = ws.repositionDrawingView(id: projId, positionMM: SIMD2(250, 180))
        #expect(repositioned)
        #expect(ws.document.activeSheet?.views.first(where: { $0.id == projId })?.positionMM == SIMD2(250, 180))

        // 4. Update view
        if var proj = ws.document.activeSheet?.views.first(where: { $0.id == projId }) {
            proj.displayStyle = .hiddenLinesVisible
            let updated = ws.updateDrawingView(proj)
            #expect(updated)
            #expect(ws.document.activeSheet?.views.first(where: { $0.id == projId })?.displayStyle == .hiddenLinesVisible)
        }

        // 5. Select drawing view
        ws.selectDrawingView(baseId)
        #expect(ws.selectedDrawingViewId == baseId)
        #expect(ws.selectedDrawingView?.name == base?.name)

        // 6. Test undo and redo for remove
        ws.document.undoManager?.removeAllActions()
        let removedProj = ws.removeDrawingView(id: projId)
        #expect(removedProj)
        #expect(ws.document.activeSheet?.views.count == 1)

        ws.undo()
        #expect(ws.document.activeSheet?.views.count == 2)
        #expect(ws.document.activeSheet?.views.contains(where: { $0.id == projId }) == true)

        ws.redo()
        #expect(ws.document.activeSheet?.views.count == 1)

        // 7. Add projected view back and test parent view removal unlinking child
        let readdedProj = ws.addProjectedView(parentViewId: baseId, direction: .below)
        guard let readdedId = readdedProj?.id else { return }
        #expect(ws.document.activeSheet?.views.count == 2)

        let removed = ws.removeDrawingView(id: baseId)
        #expect(removed)
        #expect(ws.document.activeSheet?.views.count == 1)
        #expect(ws.document.activeSheet?.views.first?.id == readdedId)
        #expect(ws.document.activeSheet?.views.first?.parentViewId == nil)
        #expect(ws.document.activeSheet?.views.first?.kind == .base)
    }

    @Test func testDerivedViewWorkspaceActionsAndUndo() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        // 1. Add base view
        let base = ws.addBaseView(standardView: .front, scale: .full, displayStyle: .visibleLinesOnly)
        guard let baseId = base?.id else {
            Issue.record("Failed to create base view")
            return
        }
        #expect(ws.document.activeSheet?.views.count == 1)

        // 2. Add section view
        let section = ws.addSectionView(
            parentViewId: baseId,
            startPointMM: SIMD2(-25, 0),
            endPointMM: SIMD2(25, 0),
            arrowDirection: SIMD2(0, 1),
            label: "A",
            hatchPattern: HatchPatternDefinition(style: .ansi31, angleDegrees: 45.0, spacingMM: 3.0)
        )
        #expect(section != nil)
        #expect(section?.kind == .section)
        #expect(section?.parentViewId == baseId)
        #expect(section?.sectionDefinition?.label == "A")
        #expect(section?.hatchPattern?.style == .ansi31)
        #expect(ws.document.activeSheet?.views.count == 2)

        // 3. Add detail view
        let detail = ws.addDetailView(
            parentViewId: baseId,
            centerMM: SIMD2(10, 10),
            radiusMM: 12.0,
            scale: .double,
            label: "B"
        )
        #expect(detail != nil)
        #expect(detail?.kind == .detail)
        #expect(detail?.parentViewId == baseId)
        #expect(detail?.detailDefinition?.radiusMM == 12.0)
        #expect(detail?.scale == .double)
        #expect(ws.document.activeSheet?.views.count == 3)

        // 4. Add auxiliary view
        let aux = ws.addAuxiliaryView(
            parentViewId: baseId,
            angleDegrees: 30.0,
            distanceMM: 50.0,
            label: "C"
        )
        #expect(aux != nil)
        #expect(aux?.kind == .auxiliary)
        #expect(aux?.parentViewId == baseId)
        #expect(aux?.auxiliaryDefinition?.angleDegrees == 30.0)
        #expect(aux?.customViewDirection != nil)
        #expect(ws.document.activeSheet?.views.count == 4)

        // 5. Add broken view and test undo/redo
        ws.document.undoManager?.removeAllActions()
        let broken = ws.addBrokenView(
            parentViewId: baseId,
            orientation: .horizontal,
            startMM: -15.0,
            endMM: 15.0,
            gapMM: 5.0,
            style: .zigzag
        )
        #expect(broken != nil)
        #expect(broken?.kind == .broken)
        #expect(broken?.parentViewId == baseId)
        #expect(broken?.breakDefinition?.breakSpan == 30.0)
        #expect(broken?.breakDefinition?.compressionOffset == 25.0)
        #expect(ws.document.activeSheet?.views.count == 5)

        // 6. Test undo and redo for adding broken view
        ws.undo()
        #expect(ws.document.activeSheet?.views.count == 4)
        #expect(ws.document.activeSheet?.views.contains(where: { $0.id == broken?.id }) == false)

        ws.redo()
        #expect(ws.document.activeSheet?.views.count == 5)
        #expect(ws.document.activeSheet?.views.contains(where: { $0.id == broken?.id }) == true)

        // 7. Test recomputeDrawingViewHLR
        if let secId = section?.id {
            ws.recomputeDrawingViewHLR(viewId: secId)
            let updatedSec = ws.document.activeSheet?.views.first(where: { $0.id == secId })
            #expect(updatedSec?.kind == .section)
        }

        // 8. Test parent removal unlinks all derived views to .base
        ws.document.undoManager?.removeAllActions()
        let removedBase = ws.removeDrawingView(id: baseId)
        #expect(removedBase)
        #expect(ws.document.activeSheet?.views.count == 4)
        for child in ws.document.activeSheet?.views ?? [] {
            #expect(child.parentViewId == nil)
            #expect(child.kind == .base)
        }

        // 9. Undo parent removal restores children kinds and parent references
        ws.undo()
        #expect(ws.document.activeSheet?.views.count == 5)
        let restoredSec = ws.document.activeSheet?.views.first(where: { $0.id == section?.id })
        #expect(restoredSec?.kind == .section)
        #expect(restoredSec?.parentViewId == baseId)
        let restoredDet = ws.document.activeSheet?.views.first(where: { $0.id == detail?.id })
        #expect(restoredDet?.kind == .detail)
        #expect(restoredDet?.parentViewId == baseId)
    }
}
