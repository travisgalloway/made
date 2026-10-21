import Testing
import Foundation
@testable import MadeCore

@Suite @MainActor struct DocumentParametersTests {

    // MARK: - Validation & Identifier Rules

    @Test func testDocumentParameterValidationRules() {
        // Valid identifiers
        #expect(DocumentParameter.isValidIdentifier("width"))
        #expect(DocumentParameter.isValidIdentifier("_param"))
        #expect(DocumentParameter.isValidIdentifier("length_2"))
        #expect(DocumentParameter.isValidIdentifier("H1"))
        #expect(DocumentParameter.isValidIdentifier("box_width_x"))

        // Invalid identifiers
        #expect(!DocumentParameter.isValidIdentifier(""))
        #expect(!DocumentParameter.isValidIdentifier("1width"))
        #expect(!DocumentParameter.isValidIdentifier("width-1"))
        #expect(!DocumentParameter.isValidIdentifier("width 1"))
        #expect(!DocumentParameter.isValidIdentifier("width.1"))
        #expect(!DocumentParameter.isValidIdentifier("@param"))

        #expect(throws: DocumentParameterError.invalidIdentifier("1width")) {
            try DocumentParameter.validateName("1width")
        }
        #expect(throws: DocumentParameterError.invalidIdentifier("width-1")) {
            try DocumentParameter.validateName("width-1")
        }
    }

    @Test func testReservedUnitSymbolRejection() throws {
        let reserved = ["mm", "cm", "m", "in", "ft", "deg", "rad", "MM", "In", "DEG"]
        for symbol in reserved {
            #expect(throws: DocumentParameterError.reservedUnitSymbol(symbol)) {
                try DocumentParameter.validateName(symbol)
            }
        }

        // Substrings that contain unit names but are valid identifiers are allowed
        try DocumentParameter.validateName("inner_radius")
        try DocumentParameter.validateName("deg_angle")
        try DocumentParameter.validateName("max_height")
    }

    @Test func testDuplicateNameRejection() throws {
        let existing = ["width", "height", "depth"]
        #expect(throws: DocumentParameterError.duplicateName("width")) {
            try DocumentParameter.validateName("width", existingNames: existing)
        }
        #expect(throws: DocumentParameterError.duplicateName("depth")) {
            try DocumentParameter.validateName("depth", existingNames: existing)
        }
        // Ignoring existing name for rename of itself
        try DocumentParameter.validateName("width", existingNames: existing, ignoringName: "width")
    }

    @Test func testEmptyAndInvalidValueRejection() throws {
        let doc = DocumentModel()
        let nanParam = DocumentParameter(name: "bad_val", value: .nan)
        #expect(throws: DocumentParameterError.emptyValue) {
            try doc.addParameter(nanParam)
        }

        let infParam = DocumentParameter(name: "bad_inf", value: .infinity)
        #expect(throws: DocumentParameterError.emptyValue) {
            try doc.addParameter(infParam)
        }

        let validParam = DocumentParameter(name: "good_param", value: 10.0)
        try doc.addParameter(validParam)

        #expect(throws: DocumentParameterError.emptyValue) {
            try doc.updateParameter(id: validParam.id, value: .nan)
        }
    }

    // MARK: - Mutators (Add, Rename, Delete, Update)

    @Test func testAddParameterMaintainsOrder() throws {
        let doc = DocumentModel()
        let p1 = DocumentParameter(name: "param_a", value: 10.0, unit: "mm", comment: "First")
        let p2 = DocumentParameter(name: "param_b", value: 20.0, unit: "mm", comment: "Second")
        let p3 = DocumentParameter(name: "param_c", value: 30.0, unit: "in", comment: "Third")

        try doc.addParameter(p1)
        try doc.addParameter(p2)
        try doc.addParameter(p3, at: 1) // Insert in between

        #expect(doc.parameters.count == 3)
        #expect(doc.parameters[0].name == "param_a")
        #expect(doc.parameters[1].name == "param_c")
        #expect(doc.parameters[2].name == "param_b")

        #expect(doc.parameter(named: "param_c")?.value == 30.0)
        #expect(doc.parameter(id: p2.id)?.comment == "Second")
    }

    @Test func testRenameParameterCascadesToFeatureExpressions() throws {
        let doc = DocumentModel()
        let p = DocumentParameter(name: "box_width", value: 45.0, unit: "mm")
        try doc.addParameter(p)

        // Set box width using the parameter formula
        doc.setParam(id: boxSolidId, key: "width", value: 45.0, expression: "box_width")

        let initialBox = try #require(doc.features.first(where: { $0.outputSolidId == boxSolidId }))
        #expect(initialBox.inputExpressions["width"]?.formula == "box_width")
        #expect(initialBox.inputExpressions["width"]?.value == 45.0)

        // Rename the parameter
        try doc.renameParameter(id: p.id, newName: "custom_width")
        #expect(doc.parameter(id: p.id)?.name == "custom_width")

        let updatedBox = try #require(doc.features.first(where: { $0.outputSolidId == boxSolidId }))
        #expect(updatedBox.inputExpressions["width"]?.formula == "custom_width")
        #expect(updatedBox.inputExpressions["width"]?.value == 45.0)
    }

    @Test func testDeleteParameterBlockedWhenInUse() throws {
        let doc = DocumentModel()
        let p = DocumentParameter(name: "box_width", value: 45.0, unit: "mm")
        try doc.addParameter(p)

        doc.setParam(id: boxSolidId, key: "width", value: 45.0, expression: "box_width")

        // Deleting when referenced should throw parameterInUse listing referencing feature
        let expectedError = DocumentParameterError.parameterInUse(name: "box_width", referencingFeatures: ["box-1"])
        #expect(throws: expectedError) {
            try doc.deleteParameter(id: p.id)
        }
        #expect(doc.parameters.count == 1)

        // Clear parameter reference on the feature
        doc.setParam(id: boxSolidId, key: "width", value: 40.0, expression: nil)

        // Now deletion succeeds
        try doc.deleteParameter(id: p.id)
        #expect(doc.parameters.isEmpty)
    }

    @Test func testUpdateParameterValueCascadesAndClamps() throws {
        let doc = DocumentModel()
        let p = DocumentParameter(name: "box_width", value: 45.0, unit: "mm")
        try doc.addParameter(p)

        doc.setParam(id: boxSolidId, key: "width", value: 45.0, expression: "box_width")

        // Updating parameter cascades new value to referencing feature
        let affected = try doc.updateParameter(id: p.id, value: 55.0)
        #expect(affected == [boxSolidId])

        let updatedBox = try #require(doc.features.first(where: { $0.outputSolidId == boxSolidId }))
        if case .primitive(.box(let params)) = updatedBox.operation {
            #expect(params.width == 55.0)
        } else {
            Issue.record("Expected box primitive")
        }
        #expect(updatedBox.inputExpressions["width"]?.formula == "box_width")
        #expect(updatedBox.inputExpressions["width"]?.value == 55.0)

        // Verify scene objects and bodies are also synced
        let syncedObj = try #require(doc.objects.first(where: { $0.id == boxSolidId }))
        if case .box(let objParams) = syncedObj.def {
            #expect(objParams.width == 55.0)
        } else {
            Issue.record("Expected box scene object")
        }
    }

    // MARK: - Undo / Redo

    @Test func testAddParameterUndoRedo() throws {
        let doc = DocumentModel()
        let undoManager = try #require(doc.undoManager)
        let p = DocumentParameter(name: "param_1", value: 12.0)

        try doc.addParameter(p)
        #expect(doc.parameters.count == 1)
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(doc.parameters.isEmpty)
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(doc.parameters.count == 1)
        #expect(doc.parameters.first?.name == "param_1")
    }

    @Test func testDeleteParameterUndoRedo() throws {
        let doc = DocumentModel()
        let undoManager = try #require(doc.undoManager)
        let p = DocumentParameter(name: "param_1", value: 12.0)
        try doc.addParameter(p)
        undoManager.removeAllActions()

        try doc.deleteParameter(id: p.id)
        #expect(doc.parameters.isEmpty)
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(doc.parameters.count == 1)
        #expect(doc.parameters.first?.id == p.id)
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(doc.parameters.isEmpty)
    }

    @Test func testRenameParameterUndoRedo() throws {
        let doc = DocumentModel()
        let undoManager = try #require(doc.undoManager)
        let p = DocumentParameter(name: "orig_name", value: 12.0)
        try doc.addParameter(p)
        doc.setParam(id: boxSolidId, key: "width", value: 12.0, expression: "orig_name")
        undoManager.removeAllActions()

        try doc.renameParameter(id: p.id, newName: "new_name")
        #expect(doc.parameters.first?.name == "new_name")
        #expect(doc.features.first(where: { $0.outputSolidId == boxSolidId })?.inputExpressions["width"]?.formula == "new_name")

        undoManager.undo()
        #expect(doc.parameters.first?.name == "orig_name")
        #expect(doc.features.first(where: { $0.outputSolidId == boxSolidId })?.inputExpressions["width"]?.formula == "orig_name")

        undoManager.redo()
        #expect(doc.parameters.first?.name == "new_name")
        #expect(doc.features.first(where: { $0.outputSolidId == boxSolidId })?.inputExpressions["width"]?.formula == "new_name")
    }

    @Test func testUpdateParameterValueUndoRedo() throws {
        let doc = DocumentModel()
        let undoManager = try #require(doc.undoManager)
        let p = DocumentParameter(name: "box_width", value: 40.0)
        try doc.addParameter(p)
        doc.setParam(id: boxSolidId, key: "width", value: 40.0, expression: "box_width")
        undoManager.removeAllActions()

        try doc.updateParameter(id: p.id, value: 70.0)
        #expect(doc.parameters.first?.value == 70.0)
        #expect(doc.features.first(where: { $0.outputSolidId == boxSolidId })?.inputExpressions["width"]?.value == 70.0)

        undoManager.undo()
        #expect(doc.parameters.first?.value == 40.0)
        #expect(doc.features.first(where: { $0.outputSolidId == boxSolidId })?.inputExpressions["width"]?.value == 40.0)

        undoManager.redo()
        #expect(doc.parameters.first?.value == 70.0)
        #expect(doc.features.first(where: { $0.outputSolidId == boxSolidId })?.inputExpressions["width"]?.value == 70.0)
    }

    @Test func testNonExistentParameterOperationsThrow() {
        let doc = DocumentModel()
        let randomId = UUID()
        #expect(throws: DocumentParameterError.parameterNotFound(randomId.uuidString)) {
            try doc.deleteParameter(id: randomId)
        }
        #expect(throws: DocumentParameterError.parameterNotFound(randomId.uuidString)) {
            try doc.renameParameter(id: randomId, newName: "something")
        }
        #expect(throws: DocumentParameterError.parameterNotFound(randomId.uuidString)) {
            try doc.updateParameter(id: randomId, value: 50.0)
        }
    }
}
