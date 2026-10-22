import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct DrawingViewTests {

    @Test func testScaleFactorAndPresets() {
        let full = DrawingViewScale.full
        #expect(full.scaleFactor == 1.0)
        #expect(full.displayString == "1:1")

        let half = DrawingViewScale.half
        #expect(half.scaleFactor == 0.5)
        #expect(half.displayString == "1:2")

        let double = DrawingViewScale.double
        #expect(double.scaleFactor == 2.0)
        #expect(double.displayString == "2:1")

        let tenth = DrawingViewScale.tenth
        #expect(tenth.scaleFactor == 0.1)
        #expect(tenth.displayString == "1:10")

        let fifth = DrawingViewScale.fifth
        #expect(fifth.scaleFactor == 0.2)
        #expect(fifth.displayString == "1:5")

        let quintuple = DrawingViewScale.quintuple
        #expect(quintuple.scaleFactor == 5.0)
        #expect(quintuple.displayString == "5:1")
    }

    @Test func testScaleParsingAndEdgeCases() {
        #expect(DrawingViewScale.parse("1:1") == .full)
        #expect(DrawingViewScale.parse("1/2") == .half)
        #expect(DrawingViewScale.parse(" 2 : 1 ") == .double)
        #expect(DrawingViewScale.parse("1:5") == .fifth)
        #expect(DrawingViewScale.parse("1:10") == .tenth)
        #expect(DrawingViewScale.parse("5:1") == .quintuple)

        // Single number parsing
        let single = DrawingViewScale.parse("2.5")
        #expect(single != nil)
        #expect(single?.scaleFactor == 2.5)

        // Malformed and zero/negative scales
        #expect(DrawingViewScale.parse("") == nil)
        #expect(DrawingViewScale.parse("abc") == nil)
        #expect(DrawingViewScale.parse("1:0") == nil)
        #expect(DrawingViewScale.parse("-1:2") == nil)
        #expect(DrawingViewScale.parse("1:-2") == nil)

        // Initializer clamps denominator to >= 1e-4
        let clamped = DrawingViewScale(1, 0)
        #expect(clamped.denominator >= 1e-4)
        #expect(clamped.scaleFactor <= 10000.0)
    }

    @Test func testProjectionAngleDerivations() {
        let first = DrawingProjectionAngle.firstAngle
        let third = DrawingProjectionAngle.thirdAngle

        // DoD 4: Third-angle projection from front view:
        // right placement yields right view
        #expect(third.projectedView(from: .front, direction: .right) == .right)
        // left placement yields left view
        #expect(third.projectedView(from: .front, direction: .left) == .left)
        // above placement yields top view
        #expect(third.projectedView(from: .front, direction: .above) == .top)
        // below placement yields bottom view
        #expect(third.projectedView(from: .front, direction: .below) == .bottom)

        // DoD 3: First-angle projection from front view:
        // right placement yields left view
        #expect(first.projectedView(from: .front, direction: .right) == .left)
        // left placement yields right view
        #expect(first.projectedView(from: .front, direction: .left) == .right)
        // above placement yields bottom view
        #expect(first.projectedView(from: .front, direction: .above) == .bottom)
        // below placement yields top view
        #expect(first.projectedView(from: .front, direction: .below) == .top)

        // Isometric directions
        #expect(third.projectedView(from: .front, direction: .isometricTopRight) == .isometricNE)
        #expect(first.projectedView(from: .front, direction: .isometricTopRight) == .isometricSW)
    }

    @Test func testDisplayStyleMapping() {
        let visibleOnly = DrawingDisplayStyle.visibleLinesOnly
        #expect(!visibleOnly.hlrOptions.includeHidden)
        #expect(visibleOnly.hlrOptions.includeTangent)
        #expect(visibleOnly.hlrOptions.includeSilhouette)

        let hiddenVis = DrawingDisplayStyle.hiddenLinesVisible
        #expect(hiddenVis.hlrOptions.includeHidden)
        #expect(hiddenVis.hlrOptions.includeTangent)
        #expect(hiddenVis.hlrOptions.includeSilhouette)

        let shaded = DrawingDisplayStyle.shaded
        #expect(!shaded.hlrOptions.includeHidden)
    }

    @Test func testDocumentModelDrawingViewMutationsAndUndo() {
        let doc = DocumentModel(documentType: .drawing)
        #expect(doc.sheets.count == 1)
        guard let sheet = doc.activeSheet else {
            Issue.record("Expected active sheet")
            return
        }

        // Add base view
        let baseView = DrawingView(
            name: "Front View",
            kind: .base,
            standardView: .front,
            positionMM: SIMD2(120, 150),
            scale: .full,
            displayStyle: .visibleLinesOnly
        )
        let added = doc.addDrawingView(baseView, to: sheet.id)
        #expect(added != nil)
        #expect(doc.activeSheet?.views.count == 1)
        #expect(doc.selectedDrawingViewId == baseView.id)
        #expect(doc.selectedDrawingView?.name == "Front View")

        // Undo add
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.views.isEmpty == true)

        // Redo add
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.views.count == 1)
        #expect(doc.activeSheet?.views.first?.id == baseView.id)
    }

    @Test func testDocumentModelRemoveDrawingViewUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let view = DrawingView(name: "Detail View", kind: .base, standardView: .top)
        _ = doc.addDrawingView(view, to: sheet.id)
        #expect(doc.activeSheet?.views.count == 1)
        doc.undoManager?.removeAllActions()

        let removed = doc.removeDrawingView(id: view.id, from: sheet.id)
        #expect(removed)
        #expect(doc.activeSheet?.views.isEmpty == true)

        // Undo removal
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.views.count == 1)
        #expect(doc.activeSheet?.views.first?.id == view.id)

        // Redo removal
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.views.isEmpty == true)
    }

    @Test func testDocumentModelUpdateDrawingViewUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let view = DrawingView(name: "Front", kind: .base, standardView: .front, displayStyle: .visibleLinesOnly)
        _ = doc.addDrawingView(view, to: sheet.id)
        doc.undoManager?.removeAllActions()

        var updatedView = view
        updatedView.name = "Front Re-styled"
        updatedView.displayStyle = .hiddenLinesVisible
        let updated = doc.updateDrawingView(updatedView, on: sheet.id)
        #expect(updated)
        #expect(doc.activeSheet?.views.first?.name == "Front Re-styled")
        #expect(doc.activeSheet?.views.first?.displayStyle == .hiddenLinesVisible)

        // Undo update
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.views.first?.name == "Front")
        #expect(doc.activeSheet?.views.first?.displayStyle == .visibleLinesOnly)

        // Redo update
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.views.first?.name == "Front Re-styled")
        #expect(doc.activeSheet?.views.first?.displayStyle == .hiddenLinesVisible)
    }

    @Test func testDocumentModelRepositionDrawingViewUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let view = DrawingView(name: "Iso View", kind: .base, standardView: .isometric, positionMM: SIMD2(100, 100))
        _ = doc.addDrawingView(view, to: sheet.id)
        doc.undoManager?.removeAllActions()

        let moved = doc.repositionDrawingView(id: view.id, positionMM: SIMD2(220, 180), on: sheet.id)
        #expect(moved)
        #expect(doc.activeSheet?.views.first?.positionMM == SIMD2(220, 180))

        // Undo reposition
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.views.first?.positionMM == SIMD2(100, 100))

        // Redo reposition
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.views.first?.positionMM == SIMD2(220, 180))
    }

    @Test func testParentViewDeletionUnlinksChildren() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let baseView = DrawingView(name: "Base View", kind: .base, standardView: .front)
        _ = doc.addDrawingView(baseView, to: sheet.id)

        let childView = DrawingView(
            name: "Child View",
            kind: .projected,
            standardView: .right,
            parentViewId: baseView.id,
            projectionDirection: .right
        )
        _ = doc.addDrawingView(childView, to: sheet.id)

        #expect(doc.activeSheet?.views.count == 2)
        #expect(doc.activeSheet?.views.first(where: { $0.id == childView.id })?.parentViewId == baseView.id)
        #expect(doc.activeSheet?.views.first(where: { $0.id == childView.id })?.kind == .projected)

        // Remove base view
        let removed = doc.removeDrawingView(id: baseView.id, from: sheet.id)
        #expect(removed)
        #expect(doc.activeSheet?.views.count == 1)

        // Verify child was unlinked cleanly
        let remaining = doc.activeSheet?.views.first
        #expect(remaining?.id == childView.id)
        #expect(remaining?.parentViewId == nil)
        #expect(remaining?.kind == .base)
    }

    @Test func testLegacyDrawingSheetDecodingDefaults() throws {
        // Legacy DrawingSheet JSON without projectionAngle or views
        let legacySheetJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "Legacy Sheet",
            "size": "isoA3",
            "orientation": "landscape",
            "scale": "1:1",
            "titleBlockTemplate": "isoStandard",
            "customProperties": {}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let sheet = try decoder.decode(DrawingSheet.self, from: legacySheetJSON)

        #expect(sheet.name == "Legacy Sheet")
        #expect(sheet.size == .isoA3)
        // ISO defaults to first angle
        #expect(sheet.projectionAngle == .firstAngle)
        // Views defaults to empty array
        #expect(sheet.views.isEmpty)

        // ANSI sheet defaults to third angle
        let ansiSheetJSON = """
        {
            "id": "22222222-3333-4444-5555-666666666666",
            "name": "ANSI Sheet",
            "size": "ansiB",
            "orientation": "landscape",
            "scale": "1:1",
            "titleBlockTemplate": "ansiStandard",
            "customProperties": {}
        }
        """.data(using: .utf8)!

        let ansiSheet = try decoder.decode(DrawingSheet.self, from: ansiSheetJSON)
        #expect(ansiSheet.size == .ansiB)
        #expect(ansiSheet.projectionAngle == .thirdAngle)
        #expect(ansiSheet.views.isEmpty)
    }
}
