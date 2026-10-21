import Testing
import SwiftUI
@testable import MadeApp
import MadeCore

@Suite @MainActor struct CommitNumberFieldTests {

    @Test func testCommitFieldErrorDescriptions() {
        #expect(CommitFieldError.empty.errorDescription == "Value cannot be empty.")
        #expect(CommitFieldError.invalidNumber("abc").errorDescription == "Invalid number 'abc'.")
        #expect(CommitFieldError.thousandsSeparatorRejected.errorDescription == "Comma cannot be used as a decimal separator; use '.' instead.")
        #expect(CommitFieldError.valueOutOfRange(min: 5.0, max: 90.0).errorDescription == "Value must be between 5.0 and 90.0.")
        #expect(CommitFieldError.valueOutOfRange(min: 5.0, max: nil).errorDescription == "Value must be at least 5.0.")
        #expect(CommitFieldError.valueOutOfRange(min: nil, max: 90.0).errorDescription == "Value must be at most 90.0.")
        #expect(CommitFieldError.valueOutOfRange(min: nil, max: nil).errorDescription == "Value is out of range.")
        #expect(CommitFieldError.evaluationFailed("Division by zero is not allowed.").errorDescription == "Division by zero is not allowed.")
    }

    @Test func testParseDraftWithValidationEmptyAndWhitespace() {
        #expect(throws: CommitFieldError.empty) {
            try CommitNumberField.parseDraftWithValidation("")
        }
        #expect(throws: CommitFieldError.empty) {
            try CommitNumberField.parseDraftWithValidation("   ")
        }
        #expect(throws: CommitFieldError.empty) {
            try CommitNumberField.parseDraftWithValidation("\t\n")
        }
    }

    @Test func testParseDraftWithValidationCommaRejection() {
        // Pasted values with thousands separators are rejected with a clear message, never misread
        #expect(throws: CommitFieldError.thousandsSeparatorRejected) {
            try CommitNumberField.parseDraftWithValidation("1,000")
        }
        #expect(throws: CommitFieldError.thousandsSeparatorRejected) {
            try CommitNumberField.parseDraftWithValidation("1,000.5")
        }
        #expect(throws: CommitFieldError.thousandsSeparatorRejected) {
            try CommitNumberField.parseDraftWithValidation("12,5")
        }
        #expect(throws: CommitFieldError.thousandsSeparatorRejected) {
            try CommitNumberField.parseDraftWithValidation("1,000 mm")
        }
        #expect(throws: CommitFieldError.thousandsSeparatorRejected) {
            try CommitNumberField.parseDraftWithValidation("width + 1,000")
        }
    }

    @Test func testParseDraftWithValidationPureNumericLiterals() throws {
        // Pure numbers without units do not store an expression, preserving document display units
        let p1 = try CommitNumberField.parseDraftWithValidation("42")
        #expect(p1.value == 42.0)
        #expect(p1.expression == nil)

        let p2 = try CommitNumberField.parseDraftWithValidation("12.5")
        #expect(p2.value == 12.5)
        #expect(p2.expression == nil)

        let p3 = try CommitNumberField.parseDraftWithValidation("-5.2")
        #expect(p3.value == -5.2)
        #expect(p3.expression == nil)

        let p4 = try CommitNumberField.parseDraftWithValidation("  100.0  ")
        #expect(p4.value == 100.0)
        #expect(p4.expression == nil)
    }

    @Test func testParseDraftWithValidationParameterResolver() throws {
        let resolver: (String) -> Double? = { name in
            switch name {
            case "width": return 40.0
            case "depth": return 20.0
            default: return nil
            }
        }

        let p1 = try CommitNumberField.parseDraftWithValidation("width", resolver: resolver)
        #expect(p1.value == 40.0)
        #expect(p1.expression == "width")

        let p2 = try CommitNumberField.parseDraftWithValidation("  depth  ", resolver: resolver)
        #expect(p2.value == 20.0)
        #expect(p2.expression == "depth")

        // Unresolved identifier falls through
        #expect(throws: CommitFieldError.invalidNumber("unknown_var")) {
            try CommitNumberField.parseDraftWithValidation("unknown_var", resolver: resolver)
        }
    }

    @Test func testParseDraftWithValidationEvaluatorExpressions() throws {
        let resolver: (String) -> Double? = { name in
            (name == "width") ? 40.0 : nil
        }
        let evaluator: (String) throws -> Double = { expr in
            try ExpressionEvaluator.evaluate(
                expr,
                context: EvaluationContext(
                    parameters: [
                        "width": EvaluationContext.ParameterValue(value: 40.0, dimension: .length, unit: "mm")
                    ]
                )
            ).value
        }

        // Unit-bearing expression
        let p1 = try CommitNumberField.parseDraftWithValidation("12 mm + 1 in", resolver: resolver, evaluator: evaluator)
        #expect(abs(p1.value - 37.4) < 1e-4)
        #expect(p1.expression == "12 mm + 1 in")

        // Arithmetic with parameter reference
        let p2 = try CommitNumberField.parseDraftWithValidation("width / 2 + 5 mm", resolver: resolver, evaluator: evaluator)
        #expect(p2.value == 25.0)
        #expect(p2.expression == "width / 2 + 5 mm")

        // Trigonometric function expression
        let p3 = try CommitNumberField.parseDraftWithValidation("sin(30 deg) * 20 mm", resolver: resolver, evaluator: evaluator)
        #expect(abs(p3.value - 10.0) < 1e-4)
        #expect(p3.expression == "sin(30 deg) * 20 mm")

        // Division by zero throws evaluation error
        #expect(throws: CommitFieldError.self) {
            try CommitNumberField.parseDraftWithValidation("50 / 0", resolver: resolver, evaluator: evaluator)
        }

        // Unknown identifier in expression throws evaluation error
        #expect(throws: CommitFieldError.self) {
            try CommitNumberField.parseDraftWithValidation("foo + 10", resolver: resolver, evaluator: evaluator)
        }
    }

    @Test func testParseDraftWithValidationRangeValidation() throws {
        // Within range
        let valid = try CommitNumberField.parseDraftWithValidation("50", min: 5.0, max: 90.0)
        #expect(valid.value == 50.0)

        // Exact boundaries
        let atMin = try CommitNumberField.parseDraftWithValidation("5.0", min: 5.0, max: 90.0)
        #expect(atMin.value == 5.0)
        let atMax = try CommitNumberField.parseDraftWithValidation("90.0", min: 5.0, max: 90.0)
        #expect(atMax.value == 90.0)

        // Below min
        #expect(throws: CommitFieldError.valueOutOfRange(min: 5.0, max: 90.0)) {
            try CommitNumberField.parseDraftWithValidation("4.9", min: 5.0, max: 90.0)
        }

        // Above max
        #expect(throws: CommitFieldError.valueOutOfRange(min: 5.0, max: 90.0)) {
            try CommitNumberField.parseDraftWithValidation("90.1", min: 5.0, max: 90.0)
        }

        // Range with only min
        #expect(throws: CommitFieldError.valueOutOfRange(min: 0.0001, max: nil)) {
            try CommitNumberField.parseDraftWithValidation("0", min: 0.0001, max: nil)
        }

        // Range with only max
        #expect(throws: CommitFieldError.valueOutOfRange(min: nil, max: 100.0)) {
            try CommitNumberField.parseDraftWithValidation("150", min: nil, max: 100.0)
        }

        // Evaluator output checked against range
        let evaluator: (String) throws -> Double = { expr in
            if expr == "big" { return 120.0 }
            return 50.0
        }
        #expect(throws: CommitFieldError.valueOutOfRange(min: 5.0, max: 90.0)) {
            try CommitNumberField.parseDraftWithValidation("big", evaluator: evaluator, min: 5.0, max: 90.0)
        }
    }

    @Test func testParseDraftFallbackSanitization() throws {
        // Fallback without evaluator sanitizes trailing units
        let p1 = try CommitNumberField.parseDraftWithValidation("50 mm")
        #expect(p1.value == 50.0)
        #expect(p1.expression == nil)

        let p2 = try CommitNumberField.parseDraftWithValidation("45°")
        #expect(p2.value == 45.0)
        #expect(p2.expression == nil)

        // Invalid fallback string throws invalidNumber
        #expect(throws: CommitFieldError.invalidNumber("not_a_number")) {
            try CommitNumberField.parseDraftWithValidation("not_a_number")
        }
    }

    @Test func testStepValueCalculations() {
        // Default step (1.0)
        #expect(CommitNumberField.stepValue(value: 10.0, step: 1.0, isUp: true, isShift: false) == 11.0)
        #expect(CommitNumberField.stepValue(value: 10.0, step: 1.0, isUp: false, isShift: false) == 9.0)

        // Shift multiplier (10x step)
        #expect(CommitNumberField.stepValue(value: 10.0, step: 1.0, isUp: true, isShift: true) == 20.0)
        #expect(CommitNumberField.stepValue(value: 25.0, step: 1.0, isUp: false, isShift: true) == 15.0)

        // Custom step (0.1 for inches)
        let steppedUp = CommitNumberField.stepValue(value: 1.0, step: 0.1, isUp: true, isShift: false)
        #expect(abs(steppedUp - 1.1) < 1e-6)
        let steppedDown = CommitNumberField.stepValue(value: 1.0, step: 0.1, isUp: false, isShift: false)
        #expect(abs(steppedDown - 0.9) < 1e-6)

        // Custom step with Shift (0.1 * 10 = 1.0)
        let shiftedUp = CommitNumberField.stepValue(value: 1.0, step: 0.1, isUp: true, isShift: true)
        #expect(abs(shiftedUp - 2.0) < 1e-6)

        // Clamping to minimum
        let clampedMin = CommitNumberField.stepValue(value: 8.0, step: 1.0, isUp: false, isShift: true, min: 5.0)
        #expect(clampedMin == 5.0)

        // Clamping to maximum
        let clampedMax = CommitNumberField.stepValue(value: 85.0, step: 1.0, isUp: true, isShift: true, max: 90.0)
        #expect(clampedMax == 90.0)
    }

    @Test func testTextForStateDisplayLogic() {
        // When unfocused, always displays formatted numeric value
        #expect(CommitNumberField.textForState(value: 37.4, expression: nil, isFocused: false) == "37.4")
        #expect(CommitNumberField.textForState(value: 37.4, expression: "12 mm + 1 in", isFocused: false) == "37.4")
        #expect(CommitNumberField.textForState(value: 40.0, expression: "width", isFocused: false) == "40.0")

        // When focused without expression, displays formatted numeric value
        #expect(CommitNumberField.textForState(value: 37.4, expression: nil, isFocused: true) == "37.4")
        #expect(CommitNumberField.textForState(value: 40.0, expression: "40.0", isFocused: true) == "40.0")

        // When focused with formula or parameter expression, reveals expression
        #expect(CommitNumberField.textForState(value: 37.4, expression: "12 mm + 1 in", isFocused: true) == "12 mm + 1 in")
        #expect(CommitNumberField.textForState(value: 40.0, expression: "width", isFocused: true) == "width")
        #expect(CommitNumberField.textForState(value: 25.0, expression: "width / 2 + 5 mm", isFocused: true) == "width / 2 + 5 mm")
    }

    @Test @MainActor func testViewInstantiationWithAllParameters() {
        var committedValue: Double? = nil
        var committedExpr: String? = nil

        let view = CommitNumberField(
            label: "Width",
            value: 37.4,
            width: 52,
            minimum: 5.0,
            maximum: 90.0,
            range: 5.0...90.0,
            step: 1.0,
            expression: "12 mm + 1 in",
            parameterResolver: { _ in 40.0 },
            evaluator: { _ in 37.4 },
            commitExpression: { val, expr in
                committedValue = val
                committedExpr = expr
            }
        )
        #expect(view.label == "Width")
        #expect(view.value == 37.4)
        #expect(view.width == 52)
        #expect(view.minimum == 5.0)
        #expect(view.maximum == 90.0)
        #expect(view.range == 5.0...90.0)
        #expect(view.step == 1.0)
        #expect(view.expression == "12 mm + 1 in")
        _ = committedValue
        _ = committedExpr
    }

    @Test func testCommitNumberFieldIndependentMaximum() throws {
        // 1. Independent maximum stepping clamp
        let clampedUp = CommitNumberField.stepValue(
            value: 48.0,
            step: 5.0,
            isUp: true,
            isShift: false,
            min: nil,
            max: 50.0
        )
        #expect(clampedUp == 50.0)

        let steppedDown = CommitNumberField.stepValue(
            value: 50.0,
            step: 5.0,
            isUp: false,
            isShift: false,
            min: nil,
            max: 50.0
        )
        #expect(steppedDown == 45.0)

        // 2. Independent maximum validation
        let valid = try CommitNumberField.parseDraftWithValidation("49.5", min: nil, max: 50.0)
        #expect(valid.value == 49.5)

        let atBoundary = try CommitNumberField.parseDraftWithValidation("50.0", min: nil, max: 50.0)
        #expect(atBoundary.value == 50.0)

        #expect(throws: CommitFieldError.valueOutOfRange(min: nil, max: 50.0)) {
            try CommitNumberField.parseDraftWithValidation("50.1", min: nil, max: 50.0)
        }

        // 3. Combined independent minimum and maximum
        let inRange = try CommitNumberField.parseDraftWithValidation("25.0", min: 10.0, max: 50.0)
        #expect(inRange.value == 25.0)

        #expect(throws: CommitFieldError.valueOutOfRange(min: 10.0, max: 50.0)) {
            try CommitNumberField.parseDraftWithValidation("9.9", min: 10.0, max: 50.0)
        }

        #expect(throws: CommitFieldError.valueOutOfRange(min: 10.0, max: 50.0)) {
            try CommitNumberField.parseDraftWithValidation("50.1", min: 10.0, max: 50.0)
        }
    }

    @Test @MainActor func testFeatureExpressionWorkflowIntegration() throws {
        let workspace = WorkspaceModel()
        workspace.setUp()

        let boxDef = ObjectDef.box(BoxParams(width: 20.0, depth: 20.0, height: 10.0))
        workspace.addObject(boxDef)

        guard let selectedId = workspace.selectedId else {
            Issue.record("Failed to create box")
            return
        }

        // 1. Evaluate expression '12 mm + 1 in'
        let parsed = try CommitNumberField.parseDraftWithValidation(
            "12 mm + 1 in",
            evaluator: { expr in
                try workspace.document.evaluateExpression(expr).value
            },
            min: 5.0,
            max: 90.0
        )
        #expect(abs(parsed.value - 37.4) < 1e-4)
        #expect(parsed.expression == "12 mm + 1 in")

        // 2. Commit expression to workspace
        workspace.setParam(selectedId, "width", Float(parsed.value), expression: parsed.expression)

        // Verify document updated
        let feature = workspace.document.features.first(where: { $0.outputSolidId == selectedId })
        #expect(feature?.inputExpressions["width"]?.formula == "12 mm + 1 in")
        #expect(abs((feature?.inputExpressions["width"]?.value ?? 0) - 37.4) < 1e-4)

        // 3. Verify text display: formula when focused, formatted result when unfocused
        let formula = feature?.inputExpressions["width"]?.formula
        let unfocusedText = CommitNumberField.textForState(value: 37.4, expression: formula, isFocused: false)
        #expect(unfocusedText == "37.4")
        let focusedText = CommitNumberField.textForState(value: 37.4, expression: formula, isFocused: true)
        #expect(focusedText == "12 mm + 1 in")

        // 4. Verify stepping
        let steppedUp = CommitNumberField.stepValue(value: 37.4, step: 1.0, isUp: true, isShift: false)
        #expect(abs(steppedUp - 38.4) < 1e-4)
        let shiftedUp = CommitNumberField.stepValue(value: 37.4, step: 1.0, isUp: true, isShift: true)
        #expect(abs(shiftedUp - 47.4) < 1e-4)

        // 5. Verify thousands separator and division by zero rejection leaves document unchanged
        #expect(throws: CommitFieldError.thousandsSeparatorRejected) {
            try CommitNumberField.parseDraftWithValidation("1,000")
        }
        #expect(throws: CommitFieldError.self) {
            try CommitNumberField.parseDraftWithValidation("50 / 0", evaluator: { expr in
                try workspace.document.evaluateExpression(expr).value
            })
        }
        // Verify unchanged
        let featureAfter = workspace.document.features.first(where: { $0.outputSolidId == selectedId })
        #expect(featureAfter?.inputExpressions["width"]?.formula == "12 mm + 1 in")
    }
}
