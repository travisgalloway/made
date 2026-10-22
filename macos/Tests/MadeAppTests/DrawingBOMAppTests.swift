import Testing
import Foundation
import SwiftUI
import simd
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct DrawingBOMAppTests {

    @Test func testWorkspaceBOMTableActions() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()
        ws.document.undoManager?.groupsByEvent = false
        #expect(ws.document.activeSheet?.bomTables.isEmpty == true)

        // 1. Add BOM table
        ws.document.undoManager?.beginUndoGrouping()
        guard let table = ws.addBOMTable(positionMM: SIMD2(30.0, 30.0), structure: .flat) else {
            Issue.record("Failed to add BOM table")
            return
        }
        ws.document.undoManager?.endUndoGrouping()
        #expect(ws.document.activeSheet?.bomTables.count == 1)
        #expect(ws.selectedDrawingBOMTableId == table.id)
        #expect(ws.selectedDrawingBOMTable?.title == "BILL OF MATERIALS")
        #expect(ws.isDocumentModified)

        // 2. Update BOM table
        var updated = table
        updated.title = "PARTS BREAKDOWN"
        updated.columns = [.itemNumber, .name, .quantity]
        ws.document.undoManager?.beginUndoGrouping()
        let updateResult = ws.updateBOMTable(updated)
        ws.document.undoManager?.endUndoGrouping()
        #expect(updateResult)
        #expect(ws.selectedDrawingBOMTable?.title == "PARTS BREAKDOWN")
        #expect(ws.selectedDrawingBOMTable?.columns.count == 3)

        // 3. Undo update
        ws.document.undoManager?.undo()
        #expect(ws.selectedDrawingBOMTable?.title == "BILL OF MATERIALS")

        // 4. Redo update
        ws.document.undoManager?.redo()
        #expect(ws.selectedDrawingBOMTable?.title == "PARTS BREAKDOWN")

        // 5. Remove BOM table
        ws.document.undoManager?.beginUndoGrouping()
        let removeResult = ws.removeBOMTable(id: table.id)
        ws.document.undoManager?.endUndoGrouping()
        #expect(removeResult)
        #expect(ws.document.activeSheet?.bomTables.isEmpty == true)
        #expect(ws.selectedDrawingBOMTableId == nil)

        // 6. Undo removal
        ws.document.undoManager?.undo()
        #expect(ws.document.activeSheet?.bomTables.count == 1)
        #expect(ws.selectedDrawingBOMTableId == table.id)
    }

    @Test func testWorkspaceBalloonCreationAndLinking() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        let compId = UUID()
        let comp = ComponentInstance(
            id: compId,
            name: "Flange",
            reference: .internalPart(name: "Flange", bodyId: nil),
            metadata: [CustomPropertyKey.partNumber: "FLG-01"]
        )
        ws.document.addComponentInstance(comp)

        // Add base view
        guard let view = ws.addBaseView(standardView: .front) else {
            Issue.record("Failed to add front view")
            return
        }

        // Add balloon linked to component
        guard let balloon = ws.addBalloonAnnotation(
            viewId: view.id,
            anchorPoint: SIMD2(10.0, 10.0),
            balloonCenter: SIMD2(25.0, 25.0),
            shape: .circular,
            componentInstanceId: compId
        ) else {
            Issue.record("Failed to add balloon")
            return
        }

        #expect(balloon.kind == .balloon)
        if case .balloon(let d) = balloon.data {
            #expect(d.itemNumber == "1")
            #expect(d.componentName == "Flange")
            #expect(d.componentInstanceId == compId)
        } else {
            Issue.record("Expected balloon annotation data")
        }

        // Selection
        ws.selectDrawingAnnotation(balloon.id)
        #expect(ws.selectedDrawingAnnotationId == balloon.id)
        #expect(ws.selectedDrawingViewId == nil)
        #expect(ws.selectedDrawingBOMTableId == nil)
    }

    @Test func testWorkspaceAutoBalloonView() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        let c1 = ComponentInstance(
            name: "Body",
            reference: .internalPart(name: "Body", bodyId: nil),
            transform: Transform(position: SIMD3(0.0, 0.0, 0.0)),
            metadata: [CustomPropertyKey.partNumber: "BDY-01"]
        )
        let c2 = ComponentInstance(
            name: "Cover",
            reference: .internalPart(name: "Cover", bodyId: nil),
            transform: Transform(position: SIMD3(0.0, 20.0, 0.0)),
            metadata: [CustomPropertyKey.partNumber: "CVR-02"]
        )
        let c3 = ComponentInstance(
            name: "Handle",
            reference: .internalPart(name: "Handle", bodyId: nil),
            transform: Transform(position: SIMD3(0.0, 40.0, 0.0)),
            metadata: [CustomPropertyKey.partNumber: "HDL-03"]
        )
        ws.document.addComponentInstance(c1)
        ws.document.addComponentInstance(c2)
        ws.document.addComponentInstance(c3)

        guard let view = ws.addBaseView(standardView: .top) else {
            Issue.record("Failed to add top view")
            return
        }

        // Auto-balloon the view
        let balloons = ws.autoBalloon(viewId: view.id)
        #expect(balloons.count == 3)
        #expect(ws.document.activeSheet?.annotations.filter({ $0.kind == .balloon }).count == 3)

        let itemNumbers = balloons.compactMap { b -> String? in
            if case .balloon(let d) = b.data { return d.itemNumber }
            return nil
        }
        #expect(itemNumbers.contains("1"))
        #expect(itemNumbers.contains("2"))
        #expect(itemNumbers.contains("3"))
    }

    @Test func testWorkspaceBOMTableSelectionClearsOtherSelections() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        guard let view = ws.addBaseView(standardView: .front) else {
            Issue.record("Failed to add view")
            return
        }
        guard let table = ws.addBOMTable() else {
            Issue.record("Failed to add table")
            return
        }
        guard let balloon = ws.addBalloonAnnotation(anchorPoint: SIMD2(0, 0), balloonCenter: SIMD2(20, 20)) else {
            Issue.record("Failed to add balloon")
            return
        }

        // 1. Select View
        ws.selectDrawingView(view.id)
        #expect(ws.selectedDrawingViewId == view.id)
        #expect(ws.selectedDrawingBOMTableId == nil)
        #expect(ws.selectedDrawingAnnotationId == nil)

        // 2. Select BOM Table
        ws.selectDrawingBOMTable(table.id)
        #expect(ws.selectedDrawingBOMTableId == table.id)
        #expect(ws.selectedDrawingViewId == nil)
        #expect(ws.selectedDrawingAnnotationId == nil)

        // 3. Select Balloon
        ws.selectDrawingAnnotation(balloon.id)
        #expect(ws.selectedDrawingAnnotationId == balloon.id)
        #expect(ws.selectedDrawingViewId == nil)
        #expect(ws.selectedDrawingBOMTableId == nil)
    }

    @Test func testWorkspaceDanglingBalloonOnComponentRemoval() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()
        ws.document.undoManager?.groupsByEvent = false

        ws.document.undoManager?.beginUndoGrouping()
        let compId = UUID()
        let comp = ComponentInstance(
            id: compId,
            name: "Bearing",
            reference: .internalPart(name: "Bearing", bodyId: nil),
            metadata: [CustomPropertyKey.partNumber: "BRG-608"]
        )
        ws.document.addComponentInstance(comp)

        guard ws.addBalloonAnnotation(
            anchorPoint: SIMD2(50.0, 50.0),
            balloonCenter: SIMD2(80.0, 80.0),
            componentInstanceId: compId
        ) != nil else {
            Issue.record("Failed to add balloon")
            return
        }
        ws.document.undoManager?.endUndoGrouping()

        #expect(ws.document.activeSheet?.annotations.first?.isDangling == false)

        // Remove component
        ws.document.undoManager?.beginUndoGrouping()
        _ = ws.document.removeComponentInstance(id: compId)
        ws.document.undoManager?.endUndoGrouping()
        #expect(ws.document.activeSheet?.annotations.first?.isDangling == true)

        // Undo
        ws.document.undoManager?.undo()
        #expect(ws.document.activeSheet?.annotations.first?.isDangling == false)
    }
}
