import Testing
import Foundation
@testable import MadeCore

@Suite @MainActor struct ParameterRangeTests {

    // MARK: - Range Rejection (min > max)

    @Test func testInvalidRangeRejectedOnDefinition() throws {
        let doc = DocumentModel()
        let invalidParam = DocumentParameter(
            name: "bad_range",
            value: 10.0,
            min: 50.0,
            max: 20.0
        )
        #expect(throws: DocumentParameterError.invalidRange(min: 50.0, max: 20.0)) {
            try doc.addParameter(invalidParam)
        }
        #expect(doc.parameters.isEmpty)
    }

    @Test func testInvalidRangeRejectedOnMutation() throws {
        let doc = DocumentModel()
        let param = DocumentParameter(
            name: "test_param",
            value: 25.0,
            min: 10.0,
            max: 50.0
        )
        try doc.addParameter(param)

        // Mutating min > max should throw invalidRange
        #expect(throws: DocumentParameterError.invalidRange(min: 60.0, max: 50.0)) {
            try doc.updateParameter(id: param.id, min: 60.0)
        }

        // Parameter remains unchanged
        let current = doc.parameter(id: param.id)
        #expect(current?.min == 10.0)
        #expect(current?.max == 50.0)
        #expect(current?.value == 25.0)

        // Mutating max < min should throw invalidRange
        #expect(throws: DocumentParameterError.invalidRange(min: 10.0, max: 5.0)) {
            try doc.updateParameter(id: param.id, max: 5.0)
        }
        #expect(doc.parameter(id: param.id)?.max == 50.0)
    }

    // MARK: - Exact Boundary Acceptance

    @Test func testExactBoundaryValuesAccepted() throws {
        let doc = DocumentModel()
        let paramMin = DocumentParameter(name: "at_min", value: 10.0, min: 10.0, max: 50.0)
        let paramMax = DocumentParameter(name: "at_max", value: 50.0, min: 10.0, max: 50.0)

        try doc.addParameter(paramMin)
        try doc.addParameter(paramMax)

        #expect(doc.parameters.count == 2)
        #expect(doc.parameter(named: "at_min")?.value == 10.0)
        #expect(doc.parameter(named: "at_min")?.isOutOfRange == false)
        #expect(doc.parameter(named: "at_max")?.value == 50.0)
        #expect(doc.parameter(named: "at_max")?.isOutOfRange == false)

        // Update to exact boundaries
        try doc.updateParameter(id: paramMin.id, value: 50.0)
        #expect(doc.parameter(id: paramMin.id)?.value == 50.0)
        #expect(doc.parameter(id: paramMin.id)?.isOutOfRange == false)

        try doc.updateParameter(id: paramMax.id, value: 10.0)
        #expect(doc.parameter(id: paramMax.id)?.value == 10.0)
        #expect(doc.parameter(id: paramMax.id)?.isOutOfRange == false)
    }

    // MARK: - Out-of-Range Value Rejection and State Retention

    @Test func testOutOfRangeValueUpdateRejectedAndPreservesValue() throws {
        let doc = DocumentModel()
        let param = DocumentParameter(
            name: "length",
            value: 25.0,
            min: 10.0,
            max: 50.0
        )
        try doc.addParameter(param)

        // Value below minimum rejected
        #expect(throws: DocumentParameterError.valueOutOfRange(value: 5.0, min: 10.0, max: 50.0)) {
            try doc.updateParameter(id: param.id, value: 5.0)
        }
        #expect(doc.parameter(id: param.id)?.value == 25.0)

        // Value above maximum rejected
        #expect(throws: DocumentParameterError.valueOutOfRange(value: 55.0, min: 10.0, max: 50.0)) {
            try doc.updateParameter(id: param.id, value: 55.0)
        }
        #expect(doc.parameter(id: param.id)?.value == 25.0)
    }

    // MARK: - Narrowing Range Preserves Value

    @Test func testNarrowingRangePreservesValueAndFlagsOutOfRange() throws {
        let doc = DocumentModel()
        let param = DocumentParameter(
            name: "width",
            value: 50.0,
            min: 0.0,
            max: 100.0
        )
        try doc.addParameter(param)

        // Narrow maximum below current value (50.0 > 40.0)
        try doc.updateParameter(id: param.id, max: 40.0)

        let updated = doc.parameter(id: param.id)
        #expect(updated?.max == 40.0)
        #expect(updated?.value == 50.0)
        #expect(updated?.isOutOfRange == true)
        #expect(updated?.rangeErrorMessage == "Value must be between 0.0 and 40.0.")

        // Narrow minimum above current value (60.0 > 50.0)
        try doc.updateParameter(id: param.id, min: 60.0, max: 100.0)
        let updatedMin = doc.parameter(id: param.id)
        #expect(updatedMin?.min == 60.0)
        #expect(updatedMin?.value == 50.0)
        #expect(updatedMin?.isOutOfRange == true)
        #expect(updatedMin?.rangeErrorMessage == "Value must be between 60.0 and 100.0.")
    }

    // MARK: - Expression Evaluation Parity

    @Test func testExpressionEvaluationOutOfRangeParity() throws {
        let doc = DocumentModel()
        let base = DocumentParameter(name: "base", value: 30.0)
        try doc.addParameter(base)

        let bounded = DocumentParameter(name: "bounded", value: 20.0, min: 10.0, max: 50.0)
        try doc.addParameter(bounded)

        // Expression evaluating above maximum throws same valueOutOfRange error
        #expect(throws: DocumentParameterError.valueOutOfRange(value: 60.0, min: 10.0, max: 50.0)) {
            try doc.updateParameter(id: bounded.id, expression: "base * 2")
        }
        #expect(doc.parameter(id: bounded.id)?.value == 20.0)
        #expect(doc.parameter(id: bounded.id)?.expression == nil)

        // Expression evaluating below minimum throws same valueOutOfRange error
        #expect(throws: DocumentParameterError.valueOutOfRange(value: 5.0, min: 10.0, max: 50.0)) {
            try doc.updateParameter(id: bounded.id, expression: "base - 25")
        }
        #expect(doc.parameter(id: bounded.id)?.value == 20.0)
    }

    // MARK: - Range Diagnostics Formatting

    @Test func testRangeErrorMessageFormatting() {
        var param = DocumentParameter(name: "p", value: 100.0, min: 10.0, max: 50.0)
        #expect(param.isOutOfRange == true)
        #expect(param.rangeErrorMessage == "Value must be between 10.0 and 50.0.")

        param = DocumentParameter(name: "p", value: 5.0, min: 10.0)
        #expect(param.isOutOfRange == true)
        #expect(param.rangeErrorMessage == "Value must be at least 10.0.")

        param = DocumentParameter(name: "p", value: 55.0, max: 50.0)
        #expect(param.isOutOfRange == true)
        #expect(param.rangeErrorMessage == "Value must be at most 50.0.")

        param = DocumentParameter(name: "p", value: 25.0, min: 10.0, max: 50.0)
        #expect(param.isOutOfRange == false)
        #expect(param.rangeErrorMessage == nil)
    }

    // MARK: - Undo/Redo with Range Properties

    @Test func testUndoRedoPreservesRangeProperties() throws {
        let doc = DocumentModel()
        let undoManager = try #require(doc.undoManager)
        let param = DocumentParameter(
            name: "stepped",
            value: 20.0,
            min: 5.0,
            max: 50.0,
            step: 2.5
        )
        try doc.addParameter(param)
        undoManager.removeAllActions()

        // Update value
        try doc.updateParameter(id: param.id, value: 30.0)
        #expect(doc.parameter(id: param.id)?.value == 30.0)

        // Undo restores initial value and range
        undoManager.undo()
        let undone = try #require(doc.parameter(id: param.id))
        #expect(undone.value == 20.0)
        #expect(undone.min == 5.0)
        #expect(undone.max == 50.0)
        #expect(undone.step == 2.5)

        // Redo restores updated value and range
        undoManager.redo()
        let redone = try #require(doc.parameter(id: param.id))
        #expect(redone.value == 30.0)
        #expect(redone.min == 5.0)
        #expect(redone.max == 50.0)
        #expect(redone.step == 2.5)
    }
}
