import Foundation

/// Dimensional powers for length and angle dimensions.
public struct ExpressionDimension: Sendable, Equatable, Hashable, CustomStringConvertible {
    public let length: Int
    public let angle: Int

    public init(length: Int = 0, angle: Int = 0) {
        self.length = length
        self.angle = angle
    }

    public static let scalar = ExpressionDimension(length: 0, angle: 0)
    public static let length = ExpressionDimension(length: 1, angle: 0)
    public static let angle = ExpressionDimension(length: 0, angle: 1)
    public static let area = ExpressionDimension(length: 2, angle: 0)
    public static let volume = ExpressionDimension(length: 3, angle: 0)

    public var description: String {
        if length == 0 && angle == 0 {
            return "scalar"
        }
        if length == 1 && angle == 0 {
            return "length"
        }
        if length == 0 && angle == 1 {
            return "angle"
        }
        if length == 2 && angle == 0 {
            return "area"
        }
        if length == 3 && angle == 0 {
            return "volume"
        }
        var parts: [String] = []
        if length != 0 {
            parts.append(length == 1 ? "length" : "length^\(length)")
        }
        if angle != 0 {
            parts.append(angle == 1 ? "angle" : "angle^\(angle)")
        }
        return parts.joined(separator: " * ")
    }

    public static func * (lhs: ExpressionDimension, rhs: ExpressionDimension) -> ExpressionDimension {
        ExpressionDimension(length: lhs.length + rhs.length, angle: lhs.angle + rhs.angle)
    }

    public static func / (lhs: ExpressionDimension, rhs: ExpressionDimension) -> ExpressionDimension {
        ExpressionDimension(length: lhs.length - rhs.length, angle: lhs.angle - rhs.angle)
    }

    public func power(_ exp: Int) -> ExpressionDimension {
        ExpressionDimension(length: length * exp, angle: angle * exp)
    }

    public static func from(unit: String?) -> ExpressionDimension {
        guard let raw = unit?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            return .scalar
        }
        switch raw {
        case "mm", "cm", "m", "in", "ft":
            return .length
        case "deg", "rad":
            return .angle
        case "mm2", "mm²", "cm2", "cm²", "m2", "m²", "in2", "in²", "ft2", "ft²":
            return .area
        case "mm3", "mm³", "cm3", "cm³", "m3", "m³", "in3", "in³", "ft3", "ft³":
            return .volume
        default:
            return .scalar
        }
    }
}

/// Diagnostic flags emitted during expression evaluation.
public enum EvaluationFlag: String, Sendable, Equatable, Hashable {
    case unitlessCoercedToDocumentUnit
}

/// The result of evaluating an expression.
public struct ExpressionEvaluationResult: Sendable, Equatable {
    public let value: Double
    public let dimension: ExpressionDimension
    public let unit: String?
    public let referencedParameters: Set<String>
    public let flags: Set<EvaluationFlag>

    public init(
        value: Double,
        dimension: ExpressionDimension,
        unit: String? = nil,
        referencedParameters: Set<String> = [],
        flags: Set<EvaluationFlag> = []
    ) {
        self.value = value
        self.dimension = dimension
        self.unit = unit
        self.referencedParameters = referencedParameters
        self.flags = flags
    }
}

/// Typed errors encountered during expression lexing, parsing, or evaluation.
public enum ExpressionError: Error, Sendable, Equatable, LocalizedError {
    case emptyExpression
    case syntaxError(String)
    case unexpectedToken(String, position: Int)
    case divisionByZero
    case unknownIdentifier(String)
    case unknownFunction(String)
    case invalidArgumentCount(function: String, expected: Int, actual: Int)
    case dimensionMismatch(left: String, right: String, operation: String)
    case invalidArgumentDimension(function: String, expected: String, actual: String)
    case domainError(String)
    case commaDecimalSeparatorRejected
    case circularReference([String])

    public var errorDescription: String? {
        switch self {
        case .emptyExpression:
            return "Expression cannot be empty."
        case .syntaxError(let details):
            return "Syntax error: \(details)"
        case .unexpectedToken(let token, let position):
            return "Unexpected token '\(token)' at position \(position)."
        case .divisionByZero:
            return "Division by zero."
        case .unknownIdentifier(let name):
            return "Unknown identifier '\(name)'."
        case .unknownFunction(let name):
            return "Unknown function '\(name)'."
        case .invalidArgumentCount(let function, let expected, let actual):
            return "Function '\(function)' expects \(expected) argument(s), got \(actual)."
        case .dimensionMismatch(let left, let right, let operation):
            return "Dimension mismatch in '\(operation)': left operand is \(left), right operand is \(right)."
        case .invalidArgumentDimension(let function, let expected, let actual):
            return "Function '\(function)' expects \(expected) dimension, got \(actual)."
        case .domainError(let details):
            return "Domain error: \(details)"
        case .commaDecimalSeparatorRejected:
            return "Comma cannot be used as a decimal separator; use '.' instead."
        case .circularReference(let cycle):
            return "Circular reference detected: \(cycle.joined(separator: " -> "))."
        }
    }
}

/// Evaluation context containing available parameter definitions and document units.
public struct EvaluationContext: Sendable {
    public var parameters: [String: ParameterValue]
    public var unitSettings: UnitSettings

    public struct ParameterValue: Sendable, Equatable {
        public var value: Double
        public var dimension: ExpressionDimension
        public var unit: String?

        public init(value: Double, dimension: ExpressionDimension = .scalar, unit: String? = nil) {
            self.value = value
            self.dimension = dimension
            self.unit = unit
        }
    }

    public init(
        parameters: [String: ParameterValue] = [:],
        unitSettings: UnitSettings = UnitSettings()
    ) {
        self.parameters = parameters
        self.unitSettings = unitSettings
    }

    public init(
        documentParameters: [DocumentParameter],
        unitSettings: UnitSettings = UnitSettings()
    ) {
        var params: [String: ParameterValue] = [:]
        for p in documentParameters {
            let dim = ExpressionDimension.from(unit: p.unit)
            params[p.name] = ParameterValue(value: p.value, dimension: dim, unit: p.unit.isEmpty ? nil : p.unit)
        }
        self.parameters = params
        self.unitSettings = unitSettings
    }
}

// MARK: - Tokens and Lexer

enum ExpressionToken: Equatable, Sendable {
    case number(Double)
    case identifier(String)
    case unit(String)
    case function(String)
    case plus
    case minus
    case multiply
    case divide
    case power
    case leftParen
    case rightParen
    case comma
}

struct ExpressionLexer {
    private let text: String
    private var index: String.Index

    static let unitSymbols: Set<String> = ["mm", "cm", "m", "in", "ft", "deg", "rad"]
    static let functionNames: Set<String> = ["sin", "cos", "tan", "sqrt", "abs", "min", "max"]

    init(_ text: String) {
        self.text = text
        self.index = text.startIndex
    }

    mutating func tokenize() throws -> [ExpressionToken] {
        var tokens: [ExpressionToken] = []

        while index < text.endIndex {
            let ch = text[index]

            if ch.isWhitespace {
                index = text.index(after: index)
                continue
            }

            // Comma detection
            if ch == "," {
                // If comma occurs directly between digits (e.g. 3,14), reject as decimal separator
                let prevIdx = index > text.startIndex ? text.index(before: index) : nil
                let nextIdx = text.index(after: index)
                let prevIsDigit = prevIdx.map { text[$0].isNumber } ?? false
                let nextIsDigit = nextIdx < text.endIndex && text[nextIdx].isNumber
                if prevIsDigit && nextIsDigit {
                    throw ExpressionError.commaDecimalSeparatorRejected
                }
                tokens.append(.comma)
                index = text.index(after: index)
                continue
            }

            if ch == "+" {
                tokens.append(.plus)
                index = text.index(after: index)
                continue
            }
            if ch == "-" {
                tokens.append(.minus)
                index = text.index(after: index)
                continue
            }
            if ch == "*" {
                tokens.append(.multiply)
                index = text.index(after: index)
                continue
            }
            if ch == "/" {
                tokens.append(.divide)
                index = text.index(after: index)
                continue
            }
            if ch == "^" {
                tokens.append(.power)
                index = text.index(after: index)
                continue
            }
            if ch == "(" {
                tokens.append(.leftParen)
                index = text.index(after: index)
                continue
            }
            if ch == ")" {
                tokens.append(.rightParen)
                index = text.index(after: index)
                continue
            }

            // Number: digit or decimal dot
            if ch.isNumber || (ch == "." && text.index(after: index) < text.endIndex && text[text.index(after: index)].isNumber) {
                let numToken = try scanNumber()
                tokens.append(numToken)
                continue
            }

            // Identifier, function name, or unit symbol
            if ch.isLetter || ch == "_" {
                let wordToken = scanWord()
                tokens.append(wordToken)
                continue
            }

            let pos = text.distance(from: text.startIndex, to: index)
            throw ExpressionError.unexpectedToken(String(ch), position: pos)
        }

        return tokens
    }

    private mutating func scanNumber() throws -> ExpressionToken {
        let start = index
        var hasDecimalPoint = false

        while index < text.endIndex {
            let ch = text[index]
            if ch.isNumber {
                index = text.index(after: index)
            } else if ch == "." && !hasDecimalPoint {
                hasDecimalPoint = true
                index = text.index(after: index)
            } else if ch == "," {
                // If comma occurs inside numeric literal
                let nextIdx = text.index(after: index)
                if nextIdx < text.endIndex && text[nextIdx].isNumber {
                    throw ExpressionError.commaDecimalSeparatorRejected
                }
                break
            } else {
                break
            }
        }

        let numStr = String(text[start..<index])
        guard let val = Double(numStr), val.isFinite else {
            let pos = text.distance(from: text.startIndex, to: start)
            throw ExpressionError.syntaxError("Invalid number format '\(numStr)' at position \(pos).")
        }
        return .number(val)
    }

    private mutating func scanWord() -> ExpressionToken {
        let start = index
        while index < text.endIndex {
            let ch = text[index]
            if ch.isLetter || ch.isNumber || ch == "_" {
                index = text.index(after: index)
            } else {
                break
            }
        }
        let word = String(text[start..<index])
        let lower = word.lowercased()

        if Self.unitSymbols.contains(lower) {
            return .unit(lower)
        }
        if Self.functionNames.contains(lower) {
            return .function(lower)
        }
        return .identifier(word)
    }
}

// MARK: - AST and Parser

indirect enum ExpressionNode: Sendable, Equatable {
    case number(Double)
    case identifier(String)
    case withUnit(ExpressionNode, String)
    case unary(UnaryOperator, ExpressionNode)
    case binary(BinaryOperator, ExpressionNode, ExpressionNode)
    case function(String, [ExpressionNode])
}

enum UnaryOperator: Sendable, Equatable {
    case plus
    case minus
}

enum BinaryOperator: Sendable, Equatable {
    case add
    case subtract
    case multiply
    case divide
    case power
}

struct ExpressionParser {
    private let tokens: [ExpressionToken]
    private var index: Int = 0

    init(_ tokens: [ExpressionToken]) {
        self.tokens = tokens
    }

    mutating func parse() throws -> ExpressionNode {
        guard !tokens.isEmpty else {
            throw ExpressionError.emptyExpression
        }
        let node = try parseAdditive()
        if index < tokens.count {
            let remaining = tokens[index]
            if remaining == .comma {
                throw ExpressionError.commaDecimalSeparatorRejected
            }
            throw ExpressionError.syntaxError("Unexpected token at end of expression: \(remaining)")
        }
        return node
    }

    private func peek() -> ExpressionToken? {
        guard index < tokens.count else { return nil }
        return tokens[index]
    }

    @discardableResult
    private mutating func consume() -> ExpressionToken {
        let token = tokens[index]
        index += 1
        return token
    }

    // Additive: + and - (left-associative)
    private mutating func parseAdditive() throws -> ExpressionNode {
        var node = try parseMultiplicative()

        while let token = peek(), token == .plus || token == .minus {
            consume()
            let rhs = try parseMultiplicative()
            node = .binary(token == .plus ? .add : .subtract, node, rhs)
        }
        return node
    }

    // Multiplicative: * and / (left-associative)
    private mutating func parseMultiplicative() throws -> ExpressionNode {
        var node = try parsePower()

        while let token = peek(), token == .multiply || token == .divide {
            consume()
            let rhs = try parsePower()
            node = .binary(token == .multiply ? .multiply : .divide, node, rhs)
        }
        return node
    }

    // Power: ^ (right-associative)
    private mutating func parsePower() throws -> ExpressionNode {
        let node = try parseUnary()

        if let token = peek(), token == .power {
            consume()
            let rhs = try parsePower()
            return .binary(.power, node, rhs)
        }
        return node
    }

    // Unary prefix: + and -
    private mutating func parseUnary() throws -> ExpressionNode {
        if let token = peek(), token == .plus {
            consume()
            let operand = try parseUnary()
            return .unary(.plus, operand)
        }
        if let token = peek(), token == .minus {
            consume()
            let operand = try parseUnary()
            return .unary(.minus, operand)
        }
        return try parsePostfix()
    }

    // Postfix: unit suffix
    private mutating func parsePostfix() throws -> ExpressionNode {
        var node = try parsePrimary()

        if case .unit(let symbol) = peek() {
            consume()
            node = .withUnit(node, symbol)
        }
        return node
    }

    // Primary: numbers, identifiers, function calls, parenthesized expressions
    private mutating func parsePrimary() throws -> ExpressionNode {
        guard let token = peek() else {
            throw ExpressionError.syntaxError("Unexpected end of expression.")
        }

        switch token {
        case .number(let val):
            consume()
            return .number(val)

        case .identifier(let name):
            consume()
            if peek() == .leftParen {
                throw ExpressionError.unknownFunction(name)
            }
            return .identifier(name)

        case .function(let name):
            consume()
            guard peek() == .leftParen else {
                throw ExpressionError.syntaxError("Function '\(name)' must be followed by '('.")
            }
            consume() // consume '('
            var args: [ExpressionNode] = []
            if peek() != .rightParen {
                args.append(try parseAdditive())
                while peek() == .comma {
                    consume() // consume ','
                    args.append(try parseAdditive())
                }
            }
            guard peek() == .rightParen else {
                throw ExpressionError.syntaxError("Expected ')' closing function '\(name)'.")
            }
            consume() // consume ')'
            return .function(name, args)

        case .leftParen:
            consume()
            let node = try parseAdditive()
            guard peek() == .rightParen else {
                throw ExpressionError.syntaxError("Unmatched '('; missing ')'.")
            }
            consume()
            return node

        case .comma:
            throw ExpressionError.commaDecimalSeparatorRejected

        default:
            throw ExpressionError.syntaxError("Unexpected token: \(token)")
        }
    }
}

// MARK: - Evaluator

public enum ExpressionEvaluator {

    /// Evaluates an expression against an `EvaluationContext`.
    public static func evaluate(
        _ expression: String,
        context: EvaluationContext = EvaluationContext()
    ) throws -> ExpressionEvaluationResult {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExpressionError.emptyExpression
        }

        var lexer = ExpressionLexer(trimmed)
        let tokens = try lexer.tokenize()
        var parser = ExpressionParser(tokens)
        let ast = try parser.parse()

        var referenced: Set<String> = []
        var flags: Set<EvaluationFlag> = []

        let evaluated = try evaluateNode(
            ast,
            context: context,
            referenced: &referenced,
            flags: &flags
        )

        return ExpressionEvaluationResult(
            value: evaluated.value,
            dimension: evaluated.dimension,
            unit: evaluated.unit,
            referencedParameters: referenced,
            flags: flags
        )
    }

    /// Convenience evaluator overload with simple parameter dictionary.
    public static func evaluate(
        _ expression: String,
        parameters: [String: Double] = [:],
        unitSettings: UnitSettings = UnitSettings()
    ) throws -> ExpressionEvaluationResult {
        var paramValues: [String: EvaluationContext.ParameterValue] = [:]
        for (name, val) in parameters {
            paramValues[name] = EvaluationContext.ParameterValue(value: val, dimension: .scalar)
        }
        let ctx = EvaluationContext(parameters: paramValues, unitSettings: unitSettings)
        return try evaluate(expression, context: ctx)
    }

    /// Convenience evaluator overload with document parameters.
    public static func evaluate(
        _ expression: String,
        documentParameters: [DocumentParameter],
        unitSettings: UnitSettings = UnitSettings()
    ) throws -> ExpressionEvaluationResult {
        let ctx = EvaluationContext(documentParameters: documentParameters, unitSettings: unitSettings)
        return try evaluate(expression, context: ctx)
    }

    /// Extracts referenced parameter names from an expression without evaluating it.
    public static func extractReferencedParameters(from expression: String) throws -> Set<String> {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        var lexer = ExpressionLexer(trimmed)
        let tokens = try lexer.tokenize()
        var parser = ExpressionParser(tokens)
        let ast = try parser.parse()

        var references = Set<String>()
        collectReferences(from: ast, into: &references)
        return references
    }

    /// Renames a parameter identifier within an expression.
    public static func renameIdentifier(
        in expression: String,
        from oldName: String,
        to newName: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: oldName))\\b") else {
            return expression
        }
        let range = NSRange(location: 0, length: expression.utf16.count)
        return regex.stringByReplacingMatches(in: expression, options: [], range: range, withTemplate: newName)
    }

    private static func collectReferences(from node: ExpressionNode, into refs: inout Set<String>) {
        switch node {
        case .number:
            break
        case .identifier(let name):
            refs.insert(name)
        case .withUnit(let child, _):
            collectReferences(from: child, into: &refs)
        case .unary(_, let child):
            collectReferences(from: child, into: &refs)
        case .binary(_, let lhs, let rhs):
            collectReferences(from: lhs, into: &refs)
            collectReferences(from: rhs, into: &refs)
        case .function(_, let args):
            for arg in args {
                collectReferences(from: arg, into: &refs)
            }
        }
    }

    private struct IntermediateValue {
        let value: Double
        let dimension: ExpressionDimension
        let unit: String?
    }

    private static func evaluateNode(
        _ node: ExpressionNode,
        context: EvaluationContext,
        referenced: inout Set<String>,
        flags: inout Set<EvaluationFlag>
    ) throws -> IntermediateValue {
        switch node {
        case .number(let val):
            return IntermediateValue(value: val, dimension: .scalar, unit: nil)

        case .identifier(let name):
            guard let param = context.parameters[name] else {
                throw ExpressionError.unknownIdentifier(name)
            }
            referenced.insert(name)
            return IntermediateValue(value: param.value, dimension: param.dimension, unit: param.unit)

        case .withUnit(let child, let symbol):
            let evaluatedChild = try evaluateNode(child, context: context, referenced: &referenced, flags: &flags)
            guard evaluatedChild.dimension == .scalar else {
                throw ExpressionError.invalidArgumentDimension(
                    function: "unit",
                    expected: "scalar",
                    actual: evaluatedChild.dimension.description
                )
            }
            return convertUnit(value: evaluatedChild.value, unit: symbol)

        case .unary(let op, let child):
            let evaluated = try evaluateNode(child, context: context, referenced: &referenced, flags: &flags)
            let val = (op == .plus) ? evaluated.value : -evaluated.value
            return IntermediateValue(value: val, dimension: evaluated.dimension, unit: evaluated.unit)

        case .binary(let op, let lhs, let rhs):
            let left = try evaluateNode(lhs, context: context, referenced: &referenced, flags: &flags)
            let right = try evaluateNode(rhs, context: context, referenced: &referenced, flags: &flags)
            return try evaluateBinary(op: op, left: left, right: right, context: context, flags: &flags)

        case .function(let name, let args):
            return try evaluateFunction(name: name, args: args, context: context, referenced: &referenced, flags: &flags)
        }
    }

    private static func convertUnit(value: Double, unit: String) -> IntermediateValue {
        let lower = unit.lowercased()
        switch lower {
        case "mm":
            return IntermediateValue(value: value, dimension: .length, unit: "mm")
        case "cm":
            return IntermediateValue(value: value * 10.0, dimension: .length, unit: "mm")
        case "m":
            return IntermediateValue(value: value * 1000.0, dimension: .length, unit: "mm")
        case "in":
            return IntermediateValue(value: value * 25.4, dimension: .length, unit: "mm")
        case "ft":
            return IntermediateValue(value: value * 304.8, dimension: .length, unit: "mm")
        case "deg":
            return IntermediateValue(value: value, dimension: .angle, unit: "deg")
        case "rad":
            return IntermediateValue(value: value * (180.0 / .pi), dimension: .angle, unit: "deg")
        default:
            return IntermediateValue(value: value, dimension: .scalar, unit: unit)
        }
    }

    private static func evaluateBinary(
        op: BinaryOperator,
        left: IntermediateValue,
        right: IntermediateValue,
        context: EvaluationContext,
        flags: inout Set<EvaluationFlag>
    ) throws -> IntermediateValue {
        switch op {
        case .add, .subtract:
            let isAdd = (op == .add)
            if left.dimension == right.dimension {
                let resVal = isAdd ? (left.value + right.value) : (left.value - right.value)
                return IntermediateValue(value: resVal, dimension: left.dimension, unit: left.unit ?? right.unit)
            }
            // Coerce unitless scalar operand if added to/subtracted with a length
            if left.dimension == .scalar && right.dimension == .length {
                flags.insert(.unitlessCoercedToDocumentUnit)
                let coercedLeft = context.unitSettings.lengthUnit.toMillimeters(left.value)
                let resVal = isAdd ? (coercedLeft + right.value) : (coercedLeft - right.value)
                return IntermediateValue(value: resVal, dimension: .length, unit: right.unit ?? context.unitSettings.lengthUnit.symbol)
            }
            if left.dimension == .length && right.dimension == .scalar {
                flags.insert(.unitlessCoercedToDocumentUnit)
                let coercedRight = context.unitSettings.lengthUnit.toMillimeters(right.value)
                let resVal = isAdd ? (left.value + coercedRight) : (left.value - coercedRight)
                return IntermediateValue(value: resVal, dimension: .length, unit: left.unit ?? context.unitSettings.lengthUnit.symbol)
            }

            throw ExpressionError.dimensionMismatch(
                left: left.dimension.description,
                right: right.dimension.description,
                operation: isAdd ? "+" : "-"
            )

        case .multiply:
            let resDim = left.dimension * right.dimension
            let resVal = left.value * right.value
            let unit: String? = (left.unit != nil && right.unit == nil) ? left.unit : (right.unit != nil && left.unit == nil ? right.unit : nil)
            return IntermediateValue(value: resVal, dimension: resDim, unit: unit)

        case .divide:
            if abs(right.value) < 1e-15 || right.value == 0.0 {
                throw ExpressionError.divisionByZero
            }
            let resDim = left.dimension / right.dimension
            let resVal = left.value / right.value
            let unit: String? = (resDim == left.dimension && right.dimension == .scalar) ? left.unit : nil
            return IntermediateValue(value: resVal, dimension: resDim, unit: unit)

        case .power:
            guard right.dimension == .scalar else {
                throw ExpressionError.invalidArgumentDimension(
                    function: "^",
                    expected: "scalar",
                    actual: right.dimension.description
                )
            }
            if left.dimension == .scalar {
                let resVal = pow(left.value, right.value)
                return IntermediateValue(value: resVal, dimension: .scalar, unit: nil)
            }
            guard right.value.rounded() == right.value else {
                throw ExpressionError.domainError("Dimension exponent must be an integer: \(right.value)")
            }
            let intExp = Int(right.value)
            let resDim = left.dimension.power(intExp)
            let resVal = pow(left.value, right.value)
            return IntermediateValue(value: resVal, dimension: resDim, unit: nil)
        }
    }

    private static func evaluateFunction(
        name: String,
        args: [ExpressionNode],
        context: EvaluationContext,
        referenced: inout Set<String>,
        flags: inout Set<EvaluationFlag>
    ) throws -> IntermediateValue {
        switch name.lowercased() {
        case "sin":
            guard args.count == 1 else {
                throw ExpressionError.invalidArgumentCount(function: "sin", expected: 1, actual: args.count)
            }
            let arg = try evaluateNode(args[0], context: context, referenced: &referenced, flags: &flags)
            let radians = try angleToRadians(arg, functionName: "sin")
            let resVal = cleanTrigResult(sin(radians))
            return IntermediateValue(value: resVal, dimension: .scalar, unit: nil)

        case "cos":
            guard args.count == 1 else {
                throw ExpressionError.invalidArgumentCount(function: "cos", expected: 1, actual: args.count)
            }
            let arg = try evaluateNode(args[0], context: context, referenced: &referenced, flags: &flags)
            let radians = try angleToRadians(arg, functionName: "cos")
            let resVal = cleanTrigResult(cos(radians))
            return IntermediateValue(value: resVal, dimension: .scalar, unit: nil)

        case "tan":
            guard args.count == 1 else {
                throw ExpressionError.invalidArgumentCount(function: "tan", expected: 1, actual: args.count)
            }
            let arg = try evaluateNode(args[0], context: context, referenced: &referenced, flags: &flags)
            let radians = try angleToRadians(arg, functionName: "tan")
            let cosVal = cos(radians)
            if abs(cosVal) < 1e-15 {
                throw ExpressionError.domainError("Tangent is undefined for the given angle.")
            }
            let resVal = cleanTrigResult(tan(radians))
            return IntermediateValue(value: resVal, dimension: .scalar, unit: nil)

        case "sqrt":
            guard args.count == 1 else {
                throw ExpressionError.invalidArgumentCount(function: "sqrt", expected: 1, actual: args.count)
            }
            let arg = try evaluateNode(args[0], context: context, referenced: &referenced, flags: &flags)
            if arg.value < 0 {
                throw ExpressionError.domainError("Square root of negative number: \(arg.value)")
            }
            if arg.dimension == .scalar {
                return IntermediateValue(value: sqrt(arg.value), dimension: .scalar, unit: nil)
            }
            if arg.dimension.length % 2 == 0 && arg.dimension.angle % 2 == 0 {
                let resDim = ExpressionDimension(length: arg.dimension.length / 2, angle: arg.dimension.angle / 2)
                let resUnit = (resDim == .length) ? "mm" : nil
                return IntermediateValue(value: sqrt(arg.value), dimension: resDim, unit: resUnit)
            }
            throw ExpressionError.invalidArgumentDimension(
                function: "sqrt",
                expected: "scalar or even powers",
                actual: arg.dimension.description
            )

        case "abs":
            guard args.count == 1 else {
                throw ExpressionError.invalidArgumentCount(function: "abs", expected: 1, actual: args.count)
            }
            let arg = try evaluateNode(args[0], context: context, referenced: &referenced, flags: &flags)
            return IntermediateValue(value: abs(arg.value), dimension: arg.dimension, unit: arg.unit)

        case "min":
            guard args.count >= 2 else {
                throw ExpressionError.invalidArgumentCount(function: "min", expected: 2, actual: args.count)
            }
            var evaluatedArgs: [IntermediateValue] = []
            for a in args {
                evaluatedArgs.append(try evaluateNode(a, context: context, referenced: &referenced, flags: &flags))
            }
            let (compatDim, unit) = try checkCompatibleDimensions(for: evaluatedArgs, functionName: "min", context: context, flags: &flags)
            let minVal = evaluatedArgs.map { toEffectiveValue($0, targetDim: compatDim, context: context) }.min() ?? 0.0
            return IntermediateValue(value: minVal, dimension: compatDim, unit: unit)

        case "max":
            guard args.count >= 2 else {
                throw ExpressionError.invalidArgumentCount(function: "max", expected: 2, actual: args.count)
            }
            var evaluatedArgs: [IntermediateValue] = []
            for a in args {
                evaluatedArgs.append(try evaluateNode(a, context: context, referenced: &referenced, flags: &flags))
            }
            let (compatDim, unit) = try checkCompatibleDimensions(for: evaluatedArgs, functionName: "max", context: context, flags: &flags)
            let maxVal = evaluatedArgs.map { toEffectiveValue($0, targetDim: compatDim, context: context) }.max() ?? 0.0
            return IntermediateValue(value: maxVal, dimension: compatDim, unit: unit)

        default:
            throw ExpressionError.unknownFunction(name)
        }
    }

    private static func angleToRadians(_ arg: IntermediateValue, functionName: String) throws -> Double {
        if arg.dimension == .angle {
            // Angle internal value is stored in degrees
            return arg.value * .pi / 180.0
        }
        if arg.dimension == .scalar {
            return arg.value
        }
        throw ExpressionError.invalidArgumentDimension(
            function: functionName,
            expected: "angle",
            actual: arg.dimension.description
        )
    }

    private static func cleanTrigResult(_ val: Double) -> Double {
        if abs(val) < 1e-15 { return 0.0 }
        if abs(val - 1.0) < 1e-15 { return 1.0 }
        if abs(val - (-1.0)) < 1e-15 { return -1.0 }
        if abs(val - 0.5) < 1e-15 { return 0.5 }
        if abs(val - (-0.5)) < 1e-15 { return -0.5 }
        return val
    }

    private static func checkCompatibleDimensions(
        for items: [IntermediateValue],
        functionName: String,
        context: EvaluationContext,
        flags: inout Set<EvaluationFlag>
    ) throws -> (ExpressionDimension, String?) {
        guard let first = items.first else {
            return (.scalar, nil)
        }
        var commonDim = first.dimension
        var commonUnit = first.unit
        var hasScalar = (first.dimension == .scalar)
        var hasLength = (first.dimension == .length)

        for item in items.dropFirst() {
            if item.dimension != commonDim {
                if (commonDim == .scalar && item.dimension == .length) || (commonDim == .length && item.dimension == .scalar) {
                    hasScalar = true
                    hasLength = true
                    commonDim = .length
                    commonUnit = commonUnit ?? item.unit ?? context.unitSettings.lengthUnit.symbol
                } else {
                    throw ExpressionError.dimensionMismatch(
                        left: commonDim.description,
                        right: item.dimension.description,
                        operation: functionName
                    )
                }
            }
        }
        if hasScalar && hasLength {
            flags.insert(.unitlessCoercedToDocumentUnit)
        }
        return (commonDim, commonUnit)
    }

    private static func toEffectiveValue(
        _ item: IntermediateValue,
        targetDim: ExpressionDimension,
        context: EvaluationContext
    ) -> Double {
        if item.dimension == .scalar && targetDim == .length {
            return context.unitSettings.lengthUnit.toMillimeters(item.value)
        }
        return item.value
    }
}

// MARK: - Parameter Dependency Graph

public struct ParameterDependencyGraph: Sendable, Equatable {
    /// Mapping of parameter name -> set of parameters it references (dependencies)
    public private(set) var dependencies: [String: Set<String>] = [:]
    /// Mapping of parameter name -> set of parameters that reference it (dependents)
    public private(set) var dependents: [String: Set<String>] = [:]

    public init() {}

    /// Registers or updates dependencies for a parameter name from an expression.
    /// Throws `ExpressionError.circularReference` if updating dependencies would create a cycle.
    public mutating func updateDependencies(
        for parameterName: String,
        expression: String?
    ) throws {
        let refs: Set<String>
        if let expression, !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            refs = try ExpressionEvaluator.extractReferencedParameters(from: expression)
        } else {
            refs = []
        }

        if let cycle = detectCycle(for: parameterName, referencing: refs) {
            throw ExpressionError.circularReference(cycle)
        }

        // Remove old dependencies
        if let oldDeps = dependencies[parameterName] {
            for dep in oldDeps {
                dependents[dep]?.remove(parameterName)
                if dependents[dep]?.isEmpty == true {
                    dependents.removeValue(forKey: dep)
                }
            }
        }

        if refs.isEmpty {
            dependencies.removeValue(forKey: parameterName)
        } else {
            dependencies[parameterName] = refs
            for ref in refs {
                dependents[ref, default: []].insert(parameterName)
            }
        }
    }

    /// Checks if setting dependencies `references` for `parameterName` would create a reference cycle.
    /// If a cycle is detected, returns the cycle path as an array of parameter names (e.g. `["b", "a", "b"]`).
    public func detectCycle(
        for parameterName: String,
        referencing references: Set<String>
    ) -> [String]? {
        if references.contains(parameterName) {
            return [parameterName, parameterName]
        }

        var tempDeps = dependencies
        tempDeps[parameterName] = references

        var visited = Set<String>()
        var path: [String] = [parameterName]

        func dfs(current: String) -> [String]? {
            guard let nextNodes = tempDeps[current] else { return nil }
            for next in nextNodes.sorted() {
                if next == parameterName {
                    return path + [parameterName]
                }
                if !visited.contains(next) {
                    visited.insert(next)
                    path.append(next)
                    if let found = dfs(current: next) {
                        return found
                    }
                    path.removeLast()
                }
            }
            return nil
        }

        return dfs(current: parameterName)
    }

    /// Returns all downstream dependents of `parameterName` in topological evaluation order.
    public func topologicalDependents(of parameterName: String) -> [String] {
        // Collect all downstream reachable dependents via BFS
        var allDescendants = Set<String>()
        var queue = [parameterName]

        while !queue.isEmpty {
            let curr = queue.removeFirst()
            for dep in dependents[curr] ?? [] {
                if !allDescendants.contains(dep) {
                    allDescendants.insert(dep)
                    queue.append(dep)
                }
            }
        }

        guard !allDescendants.isEmpty else { return [] }

        // Compute in-degrees within the subgraph of descendants
        var inDegree: [String: Int] = [:]
        for node in allDescendants {
            let directDeps = dependencies[node] ?? []
            inDegree[node] = directDeps.intersection(allDescendants).count
        }

        // Ready queue with in-degree 0 (depend only on parameterName or external parameters)
        var ready = allDescendants.filter { inDegree[$0] == 0 }.sorted()
        var ordered: [String] = []

        while !ready.isEmpty {
            let curr = ready.removeFirst()
            ordered.append(curr)

            for next in (dependents[curr] ?? []).sorted() {
                if allDescendants.contains(next) {
                    inDegree[next, default: 0] -= 1
                    if inDegree[next] == 0 {
                        ready.append(next)
                    }
                }
            }
        }

        return ordered
    }

    /// Removes a parameter from the dependency graph.
    public mutating func removeParameter(_ parameterName: String) {
        if let deps = dependencies.removeValue(forKey: parameterName) {
            for dep in deps {
                dependents[dep]?.remove(parameterName)
                if dependents[dep]?.isEmpty == true {
                    dependents.removeValue(forKey: dep)
                }
            }
        }
        if let directDependents = dependents.removeValue(forKey: parameterName) {
            for dep in directDependents {
                dependencies[dep]?.remove(parameterName)
                if dependencies[dep]?.isEmpty == true {
                    dependencies.removeValue(forKey: dep)
                }
            }
        }
    }

    /// Renames a parameter in the dependency graph.
    public mutating func renameParameter(from oldName: String, to newName: String) {
        guard oldName != newName else { return }

        let deps = dependencies.removeValue(forKey: oldName) ?? []
        dependencies[newName] = deps

        for dep in deps {
            dependents[dep]?.remove(oldName)
            dependents[dep, default: []].insert(newName)
        }

        let directDependents = dependents.removeValue(forKey: oldName) ?? []
        dependents[newName] = directDependents

        for dep in directDependents {
            dependencies[dep]?.remove(oldName)
            dependencies[dep, default: []].insert(newName)
        }
    }
}
