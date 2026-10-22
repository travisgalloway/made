import Testing
import Foundation
import SwiftUI
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct DraftingStandardsAppTests {

    @Test func testWorkspaceSheetDraftingStandardSwitchingAndUndoRedo() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        guard var sheet = ws.document.activeSheet else {
            Issue.record("No active sheet in new drawing document")
            return
        }

        #expect(sheet.draftingStandards.standard == .iso)
        #expect(sheet.draftingStandards.arrows.style == .closedFilled)
        #expect(sheet.draftingStandards.text.placement == .aligned)

        // Switch to ANSI with customized arrow size and unidirectional placement
        var ansiStandards = DraftingStandardSettings.ansi
        ansiStandards.arrows.lengthMM = 4.0
        ansiStandards.arrows.style = .open
        sheet.draftingStandards = ansiStandards

        let updated = ws.updateSheet(sheet)
        #expect(updated)
        #expect(ws.document.activeSheet?.draftingStandards.standard == .ansi)
        #expect(ws.document.activeSheet?.draftingStandards.arrows.lengthMM == 4.0)
        #expect(ws.document.activeSheet?.draftingStandards.arrows.style == .open)
        #expect(ws.document.activeSheet?.draftingStandards.text.placement == .unidirectional)

        // Undo
        ws.undo()
        #expect(ws.document.activeSheet?.draftingStandards.standard == .iso)
        #expect(ws.document.activeSheet?.draftingStandards.arrows.style == .closedFilled)
        #expect(ws.document.activeSheet?.draftingStandards.text.placement == .aligned)

        // Redo
        ws.redo()
        #expect(ws.document.activeSheet?.draftingStandards.standard == .ansi)
        #expect(ws.document.activeSheet?.draftingStandards.arrows.lengthMM == 4.0)
        #expect(ws.document.activeSheet?.draftingStandards.arrows.style == .open)
    }

    @Test func testWorkspaceDimensionAnnotationToleranceAndUndoRedo() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        guard let sheet = ws.document.activeSheet else {
            Issue.record("No active sheet")
            return
        }

        let dim = ws.addLinearDimension(
            start: SIMD2(0, 0),
            end: SIMD2(50, 0),
            offset: 10
        )
        guard let dim = dim, case .linear(let initialData) = dim.data else {
            Issue.record("Failed to add linear dimension")
            return
        }

        #expect(initialData.tolerance == nil)
        #expect(initialData.formattedText(using: sheet.draftingStandards) == "50")

        // Add tolerance to dimension
        var updatedDim = dim
        var modifiedData = initialData
        modifiedData.precision = 2
        modifiedData.tolerance = DimensionTolerance(symmetrical: 0.05, precision: 2)
        updatedDim.data = .linear(modifiedData)

        ws.document.undoManager?.removeAllActions()
        let updated = ws.updateDrawingAnnotation(updatedDim)
        #expect(updated)

        let fetchedDim = ws.document.activeSheet?.annotations.first(where: { $0.id == dim.id })
        guard case .linear(let fetchedData) = fetchedDim?.data else {
            Issue.record("Fetched annotation is not linear")
            return
        }
        #expect(fetchedData.tolerance?.type == .symmetrical)
        #expect(fetchedData.tolerance?.upperValue == 0.05)
        #expect(fetchedData.formattedText(using: sheet.draftingStandards) == "50 ±0,05")

        // Undo
        ws.undo()
        let undoneDim = ws.document.activeSheet?.annotations.first(where: { $0.id == dim.id })
        guard case .linear(let undoneData) = undoneDim?.data else {
            Issue.record("Undone annotation is not linear")
            return
        }
        #expect(undoneData.tolerance == nil)
        #expect(undoneData.formattedText(using: sheet.draftingStandards) == "50")

        // Redo
        ws.redo()
        let redoneDim = ws.document.activeSheet?.annotations.first(where: { $0.id == dim.id })
        guard case .linear(let redoneData) = redoneDim?.data else {
            Issue.record("Redone annotation is not linear")
            return
        }
        #expect(redoneData.tolerance?.type == .symmetrical)
        #expect(redoneData.tolerance?.upperValue == 0.05)
        #expect(redoneData.formattedText(using: sheet.draftingStandards) == "50 ±0,05")
    }

    @Test func testWorkspacePresetSwitchingAffectsAnnotationFormatting() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        guard var sheet = ws.document.activeSheet else {
            Issue.record("No active sheet")
            return
        }

        let dim = ws.addLinearDimension(
            start: SIMD2(0, 0),
            end: SIMD2(25.5, 0),
            offset: 8
        )
        guard let dim = dim, case .linear(var data) = dim.data else {
            Issue.record("Failed to create dimension")
            return
        }

        data.precision = 2
        data.tolerance = DimensionTolerance(type: .deviation, upperValue: 0.1, lowerValue: -0.05, precision: 2)
        var updatedDim = dim
        updatedDim.data = .linear(data)
        _ = ws.updateDrawingAnnotation(updatedDim)

        let standardISO = ws.document.activeSheet?.draftingStandards
        let currentDim = ws.document.activeSheet?.annotations.first(where: { $0.id == dim.id })
        guard case .linear(let currentData) = currentDim?.data else {
            Issue.record("Current annotation is not linear")
            return
        }
        #expect(currentData.formattedText(using: standardISO) == "25,5 +0,1/-0,05")

        // Switch active sheet to ANSI
        sheet.draftingStandards = .ansi
        _ = ws.updateSheet(sheet)

        let standardANSI = ws.document.activeSheet?.draftingStandards
        #expect(currentData.formattedText(using: standardANSI) == "25.50 +0.10/-0.05")
    }
}
