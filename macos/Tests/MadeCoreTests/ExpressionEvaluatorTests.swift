import Testing
import Foundation
@testable import MadeCore

@Suite struct ExpressionEvaluatorTests {

    // MARK: - Arithmetic and Operator Precedence

    @Test func testBasicArithmetic() throws {
        let r1 = try ExpressionEvaluator.evaluate("2 + 3")
        #expect(r1.value == 5.0)
        #expect(r1.dimension == .scalar)

        let r2 = try ExpressionEvaluator.evaluate("10 - 4")
        #expect(r2.value == 6.0)

        let r3 = try ExpressionEvaluator.evaluate("3 * 7")
        #expect(r3.value == 21.0)

        let r4 = try ExpressionEvaluator.evaluate("20 / 4")
        #expect(r4.value == 5.0)

        let r5 = try ExpressionEvaluator.evaluate("2 ^ 3")
        #expect(r5.value == 8.0)
    }

    @Test func testOperatorPrecedenceAndParentheses() throws {
        let r1 = try ExpressionEvaluator.evaluate("2 + 3 * 4")
        #expect(r1.value == 14.0)

        let r2 = try ExpressionEvaluator.evaluate("(2 + 3) * 4")
        #expect(r2.value == 20.0)

        // Exponentiation right-associativity: 2 ^ 3 ^ 2 = 2 ^ 9 = 512
        let r3 = try ExpressionEvaluator.evaluate("2 ^ 3 ^ 2")
        #expect(r3.value == 512.0)

        // Unary prefix
        let r4 = try ExpressionEvaluator.evaluate("-5 + 10")
        #expect(r4.value == 5.0)

        let r5 = try ExpressionEvaluator.evaluate("+7 - -3")
        #expect(r5.value == 10.0)
    }

    // MARK: - Units and Dimensional Analysis

    @Test func testUnitSuffixesAndCaseInsensitivity() throws {
        let mm = try ExpressionEvaluator.evaluate("10mm")
        #expect(mm.value == 10.0)
        #expect(mm.dimension == .length)
        #expect(mm.unit == "mm")

        let cm = try ExpressionEvaluator.evaluate("2.5 CM")
        #expect(cm.value == 25.0) // 2.5 cm = 25 mm
        #expect(cm.dimension == .length)

        let m = try ExpressionEvaluator.evaluate("1 m")
        #expect(m.value == 1000.0)
        #expect(m.dimension == .length)

        let inch = try ExpressionEvaluator.evaluate("2 in")
        #expect(inch.value == 50.8)
        #expect(inch.dimension == .length)

        let ft = try ExpressionEvaluator.evaluate("1 ft")
        #expect(ft.value == 304.8)
        #expect(ft.dimension == .length)

        let deg = try ExpressionEvaluator.evaluate("45 DEG")
        #expect(deg.value == 45.0)
        #expect(deg.dimension == .angle)

        let rad = try ExpressionEvaluator.evaluate("3.141592653589793 rad")
        #expect(abs(rad.value - 180.0) < 1e-6)
        #expect(rad.dimension == .angle)
    }

    @Test func testTargetExpressionWithParameter() throws {
        // Target: width / 2 + 3 mm when width is a length parameter
        let ctx = EvaluationContext(
            parameters: [
                "width": EvaluationContext.ParameterValue(value: 20.0, dimension: .length, unit: "mm")
            ],
            unitSettings: UnitSettings(lengthUnit: .millimeters)
        )
        let result = try ExpressionEvaluator.evaluate("width / 2 + 3 mm", context: ctx)
        #expect(result.value == 13.0)
        #expect(result.dimension == .length)
        #expect(result.referencedParameters == ["width"])
        #expect(result.flags.isEmpty)
    }

    @Test func testDimensionMismatchFailsWithExplicitNames() {
        // Adding length to angle: 10 mm + 30 deg
        #expect {
            try ExpressionEvaluator.evaluate("10 mm + 30 deg")
        } throws: { error in
            guard let exprError = error as? ExpressionError,
                  case .dimensionMismatch(let left, let right, let op) = exprError else {
                return false
            }
            #expect(op == "+")
            let desc = exprError.localizedDescription
            return desc.contains("length") && desc.contains("angle") && left == "length" && right == "angle"
        }

        // Subtraction dimension mismatch
        #expect {
            try ExpressionEvaluator.evaluate("90 deg - 5 mm")
        } throws: { error in
            guard let exprError = error as? ExpressionError,
                  case .dimensionMismatch(let left, let right, _) = exprError else {
                return false
            }
            return left == "angle" && right == "length"
        }
    }

    @Test func testUnitlessCoercedToDocumentUnit() throws {
        // Adding unitless number to length: 5 + 10 mm
        let mmSettings = UnitSettings(lengthUnit: .millimeters)
        let ctx1 = EvaluationContext(unitSettings: mmSettings)
        let r1 = try ExpressionEvaluator.evaluate("5 + 10 mm", context: ctx1)
        #expect(r1.value == 15.0)
        #expect(r1.dimension == .length)
        #expect(r1.flags.contains(.unitlessCoercedToDocumentUnit))

        // Length + unitless
        let r2 = try ExpressionEvaluator.evaluate("10 mm + 5", context: ctx1)
        #expect(r2.value == 15.0)
        #expect(r2.dimension == .length)
        #expect(r2.flags.contains(.unitlessCoercedToDocumentUnit))

        // Document length unit in inches (1 in = 25.4 mm)
        let inSettings = UnitSettings(lengthUnit: .inches)
        let ctx2 = EvaluationContext(unitSettings: inSettings)
        let r3 = try ExpressionEvaluator.evaluate("1 + 10 mm", context: ctx2)
        // 1 in coerced = 25.4 mm + 10 mm = 35.4 mm
        #expect(abs(r3.value - 35.4) < 1e-6)
        #expect(r3.dimension == .length)
        #expect(r3.flags.contains(.unitlessCoercedToDocumentUnit))
    }

    // MARK: - Mathematical Functions

    @Test func testTrigonometricFunctions() throws {
        // sin(30 deg) -> 0.5
        let sinRes = try ExpressionEvaluator.evaluate("sin(30 deg)")
        #expect(sinRes.value == 0.5)
        #expect(sinRes.dimension == .scalar)

        // cos(60 deg) -> 0.5
        let cosRes = try ExpressionEvaluator.evaluate("cos(60 deg)")
        #expect(cosRes.value == 0.5)
        #expect(cosRes.dimension == .scalar)

        // tan(45 deg) -> 1.0
        let tanRes = try ExpressionEvaluator.evaluate("tan(45 deg)")
        #expect(tanRes.value == 1.0)
        #expect(tanRes.dimension == .scalar)

        // Invalid argument dimension for sin
        #expect(throws: ExpressionError.invalidArgumentDimension(function: "sin", expected: "angle", actual: "length")) {
            try ExpressionEvaluator.evaluate("sin(30 mm)")
        }
    }

    @Test func testSqrtFunction() throws {
        let r1 = try ExpressionEvaluator.evaluate("sqrt(16)")
        #expect(r1.value == 4.0)
        #expect(r1.dimension == .scalar)

        // Negative argument throws domain error
        #expect {
            try ExpressionEvaluator.evaluate("sqrt(-4)")
        } throws: { error in
            guard let exprError = error as? ExpressionError,
                  case .domainError(let details) = exprError else {
                return false
            }
            return details.contains("-4")
        }
    }

    @Test func testAbsFunction() throws {
        let r1 = try ExpressionEvaluator.evaluate("abs(-5 mm)")
        #expect(r1.value == 5.0)
        #expect(r1.dimension == .length)
        #expect(r1.unit == "mm")

        let r2 = try ExpressionEvaluator.evaluate("abs(-42)")
        #expect(r2.value == 42.0)
        #expect(r2.dimension == .scalar)
    }

    @Test func testMinAndMaxFunctions() throws {
        // min(10 mm, 2 cm) -> 10 mm
        let minRes = try ExpressionEvaluator.evaluate("min(10 mm, 2 cm)")
        #expect(minRes.value == 10.0)
        #expect(minRes.dimension == .length)

        // max(10 mm, 2 cm) -> 20 mm
        let maxRes = try ExpressionEvaluator.evaluate("max(10 mm, 2 cm)")
        #expect(maxRes.value == 20.0)
        #expect(maxRes.dimension == .length)

        // min with incompatible dimensions
        #expect {
            try ExpressionEvaluator.evaluate("min(10 mm, 45 deg)")
        } throws: { error in
            guard let exprError = error as? ExpressionError,
                  case .dimensionMismatch = exprError else {
                return false
            }
            return true
        }
    }

    // MARK: - Error States

    @Test func testDivisionByZeroReportsError() {
        #expect(throws: ExpressionError.divisionByZero) {
            try ExpressionEvaluator.evaluate("10 / 0")
        }
        #expect(throws: ExpressionError.divisionByZero) {
            try ExpressionEvaluator.evaluate("25 mm / 0")
        }
    }

    @Test func testUnknownIdentifierReportsName() {
        #expect(throws: ExpressionError.unknownIdentifier("foo")) {
            try ExpressionEvaluator.evaluate("foo + 1")
        }
        #expect(throws: ExpressionError.unknownIdentifier("missing_param")) {
            try ExpressionEvaluator.evaluate("missing_param * 2")
        }
    }

    @Test func testCommaDecimalSeparatorRejected() {
        #expect(throws: ExpressionError.commaDecimalSeparatorRejected) {
            try ExpressionEvaluator.evaluate("3,14 mm")
        }
        #expect(throws: ExpressionError.commaDecimalSeparatorRejected) {
            try ExpressionEvaluator.evaluate("10,5 + 2")
        }
    }

    @Test func testEmptyExpressionRejected() {
        #expect(throws: ExpressionError.emptyExpression) {
            try ExpressionEvaluator.evaluate("")
        }
        #expect(throws: ExpressionError.emptyExpression) {
            try ExpressionEvaluator.evaluate("   ")
        }
    }

    // MARK: - Dependency Graph and Cycle Detection

    @Test func testCycleDetectionPath() throws {
        var graph = ParameterDependencyGraph()
        try graph.updateDependencies(for: "a", expression: "b + 1")

        // Candidate b referencing a creates cycle ["b", "a", "b"]
        let cycle = graph.detectCycle(for: "b", referencing: ["a"])
        #expect(cycle == ["b", "a", "b"])

        #expect(throws: ExpressionError.circularReference(["b", "a", "b"])) {
            try graph.updateDependencies(for: "b", expression: "a")
        }
    }

    @Test func testSelfReferenceCycleDetection() throws {
        var graph = ParameterDependencyGraph()
        let cycle = graph.detectCycle(for: "x", referencing: ["x"])
        #expect(cycle == ["x", "x"])

        #expect(throws: ExpressionError.circularReference(["x", "x"])) {
            try graph.updateDependencies(for: "x", expression: "x + 1")
        }
    }

    @Test func testTopologicalEvaluationOrder() throws {
        var graph = ParameterDependencyGraph()
        try graph.updateDependencies(for: "a", expression: nil) // root
        try graph.updateDependencies(for: "b", expression: "a * 2")
        try graph.updateDependencies(for: "c", expression: "b + 5")
        try graph.updateDependencies(for: "d", expression: "10") // independent

        let dependents = graph.topologicalDependents(of: "a")
        #expect(dependents == ["b", "c"])
        #expect(!dependents.contains("d"))
    }
}
