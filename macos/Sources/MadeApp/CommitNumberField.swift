import SwiftUI

/// Localized diagnostic error for numeric draft field evaluation.
public enum CommitFieldError: LocalizedError, Equatable {
    case empty
    case invalidNumber(String)
    case thousandsSeparatorRejected
    case valueOutOfRange(min: Double?, max: Double?)
    case evaluationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Value cannot be empty."
        case .invalidNumber(let str):
            return "Invalid number '\(str)'."
        case .thousandsSeparatorRejected:
            return "Comma cannot be used as a decimal separator; use '.' instead."
        case .valueOutOfRange(let min, let max):
            if let min, let max {
                return "Value must be between \(min) and \(max)."
            } else if let min {
                return "Value must be at least \(min)."
            } else if let max {
                return "Value must be at most \(max)."
            }
            return "Value is out of range."
        case .evaluationFailed(let msg):
            return msg
        }
    }
}

/// A numeric field that edits a text draft and writes to the model only on Return or focus loss.
/// Binding a TextField straight to the model reformats the text after every keystroke.
struct CommitNumberField: View {
    typealias FieldError = CommitFieldError

    let label: String
    let value: Double
    var width: CGFloat = 56
    var minimum: Double? = nil
    var range: ClosedRange<Double>? = nil
    var step: Double = 1.0
    var expression: String? = nil
    var parameterResolver: ((String) -> Double?)? = nil
    var evaluator: ((String) throws -> Double)? = nil
    var commitExpression: ((Double, String?) -> Void)? = nil
    let commit: (Double) -> Void

    init(
        label: String,
        value: Double,
        width: CGFloat = 56,
        minimum: Double? = nil,
        range: ClosedRange<Double>? = nil,
        step: Double = 1.0,
        expression: String? = nil,
        parameterResolver: ((String) -> Double?)? = nil,
        evaluator: ((String) throws -> Double)? = nil,
        commit: @escaping (Double) -> Void
    ) {
        self.label = label
        self.value = value
        self.width = width
        self.minimum = minimum
        self.range = range
        self.step = step
        self.expression = expression
        self.parameterResolver = parameterResolver
        self.evaluator = evaluator
        self.commitExpression = nil
        self.commit = commit
    }

    init(
        label: String,
        value: Double,
        width: CGFloat = 56,
        minimum: Double? = nil,
        range: ClosedRange<Double>? = nil,
        step: Double = 1.0,
        expression: String? = nil,
        parameterResolver: ((String) -> Double?)? = nil,
        evaluator: ((String) throws -> Double)? = nil,
        commitExpression: @escaping (Double, String?) -> Void
    ) {
        self.label = label
        self.value = value
        self.width = width
        self.minimum = minimum
        self.range = range
        self.step = step
        self.expression = expression
        self.parameterResolver = parameterResolver
        self.evaluator = evaluator
        self.commitExpression = commitExpression
        self.commit = { val in commitExpression(val, nil) }
    }

    @State private var text = ""
    @State private var errorMessage: String? = nil
    @FocusState private var isFocused: Bool

    nonisolated private static let format = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(1))
        .grouping(.never)

    /// Determines the text to display based on value, bound expression, and focus state.
    nonisolated static func textForState(value: Double, expression: String?, isFocused: Bool) -> String {
        if isFocused, let expression, !expression.isEmpty, Double(expression) == nil {
            return expression
        }
        return format.format(value)
    }

    /// Computes stepped value with optional Shift (10x) multiplier and boundary clamping.
    nonisolated static func stepValue(
        value: Double,
        step: Double,
        isUp: Bool,
        isShift: Bool,
        min: Double? = nil,
        max: Double? = nil
    ) -> Double {
        let multiplier: Double = isShift ? 10.0 : 1.0
        let delta = (isUp ? step : -step) * multiplier
        var newValue = value + delta
        if let min, newValue < min {
            newValue = min
        }
        if let max, newValue > max {
            newValue = max
        }
        return newValue
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            TextField(label, text: $text)
                .focused($isFocused)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .frame(width: width)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(errorMessage != nil ? Color.red : Color.clear, lineWidth: 1)
                )
                .accessibilityHint(errorMessage ?? "")
                .onSubmit {
                    apply(isSubmitting: true)
                }
                .onKeyPress(.escape) {
                    errorMessage = nil
                    text = Self.textForState(value: value, expression: expression, isFocused: true)
                    return .handled
                }
                .onKeyPress(phases: .down) { press in
                    if press.key == .upArrow || press.key == .downArrow {
                        let isUp = press.key == .upArrow
                        let isShift = press.modifiers.contains(.shift)
                        let effectiveMin = [minimum, range?.lowerBound].compactMap { $0 }.max()
                        let effectiveMax = range?.upperBound
                        let newValue = Self.stepValue(
                            value: value,
                            step: step,
                            isUp: isUp,
                            isShift: isShift,
                            min: effectiveMin,
                            max: effectiveMax
                        )
                        errorMessage = nil
                        text = Self.format.format(newValue)
                        if let commitExpression {
                            commitExpression(newValue, nil)
                        } else {
                            commit(newValue)
                        }
                        return .handled
                    }
                    return .ignored
                }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        errorMessage = nil
                        text = Self.textForState(value: value, expression: expression, isFocused: true)
                    } else {
                        if errorMessage != nil {
                            errorMessage = nil
                            text = Self.format.format(value)
                        } else {
                            apply(isSubmitting: false)
                        }
                    }
                }
                .onChange(of: value, initial: true) { old, new in
                    if !isFocused || text.isEmpty || text == Self.format.format(old) {
                        text = Self.format.format(new)
                        errorMessage = nil
                    }
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Result of parsing draft input with optional parameter expression identification.
    public struct ParsedDraft: Equatable {
        public let value: Double
        public let expression: String?

        public init(value: Double, expression: String? = nil) {
            self.value = value
            self.expression = expression
        }
    }

    /// Strips trailing unit symbols, letters, and degree signs from draft input.
    nonisolated static func cleanDraft(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(
                of: "[a-zA-Z°]+$",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
    }

    /// Parses a draft string after sanitizing unit symbols and suffixes.
    nonisolated static func parseDraft(_ draft: String) -> Double? {
        let cleaned = cleanDraft(draft)
        guard let parsed = try? Double(cleaned, format: .number), parsed.isFinite else {
            return nil
        }
        return parsed
    }

    /// Parses a draft string, trying parameterResolver first, then evaluator, then sanitizing units and parsing as a numeric literal.
    nonisolated static func parseDraft(
        _ draft: String,
        resolver: ((String) -> Double?)?,
        evaluator: ((String) -> Double?)? = nil
    ) -> ParsedDraft? {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let resolver, let resolved = resolver(trimmed) {
            return ParsedDraft(value: resolved, expression: trimmed)
        }
        if let evaluator, let evaluated = evaluator(trimmed) {
            return ParsedDraft(value: evaluated, expression: trimmed)
        }
        guard let parsed = parseDraft(draft) else { return nil }
        return ParsedDraft(value: parsed, expression: nil)
    }

    /// Parses a draft with validation, returning `ParsedDraft` or throwing `CommitFieldError`.
    nonisolated public static func parseDraftWithValidation(
        _ draft: String,
        resolver: ((String) -> Double?)? = nil,
        evaluator: ((String) throws -> Double)? = nil,
        min: Double? = nil,
        max: Double? = nil
    ) throws -> ParsedDraft {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CommitFieldError.empty
        }

        if draft.contains(",") {
            throw CommitFieldError.thousandsSeparatorRejected
        }

        // 2. Parameter resolver
        if let resolver, let resolved = resolver(trimmed) {
            try validateRange(resolved, min: min, max: max)
            return ParsedDraft(value: resolved, expression: trimmed)
        }

        // 3. Pure numeric literal check
        if let literal = Double(trimmed), literal.isFinite {
            try validateRange(literal, min: min, max: max)
            return ParsedDraft(value: literal, expression: nil)
        }

        // 4. Expression evaluator
        if let evaluator {
            do {
                let evaluated = try evaluator(trimmed)
                guard evaluated.isFinite else {
                    throw CommitFieldError.invalidNumber(trimmed)
                }
                try validateRange(evaluated, min: min, max: max)
                return ParsedDraft(value: evaluated, expression: trimmed)
            } catch let error as CommitFieldError {
                throw error
            } catch {
                throw CommitFieldError.evaluationFailed(error.localizedDescription)
            }
        }

        // 5. Fallback numeric parse
        if let parsed = parseDraft(draft) {
            try validateRange(parsed, min: min, max: max)
            return ParsedDraft(value: parsed, expression: nil)
        } else {
            throw CommitFieldError.invalidNumber(draft)
        }
    }

    nonisolated private static func validateRange(_ value: Double, min: Double?, max: Double?) throws {
        if let min, value < min {
            throw CommitFieldError.valueOutOfRange(min: min, max: max)
        }
        if let max, value > max {
            throw CommitFieldError.valueOutOfRange(min: min, max: max)
        }
    }

    /// Commits the draft or presents an inline error when invalid.
    private func apply(isSubmitting: Bool = false) {
        let draft = text.trimmingCharacters(in: .whitespaces)
        let effectiveMin = [minimum, range?.lowerBound].compactMap { $0 }.max()
        let effectiveMax = range?.upperBound

        do {
            let parsed = try Self.parseDraftWithValidation(
                draft,
                resolver: parameterResolver,
                evaluator: evaluator,
                min: effectiveMin,
                max: effectiveMax
            )
            errorMessage = nil
            text = Self.format.format(parsed.value)
            if isSubmitting {
                isFocused = false
            }
            if parsed.value != value || parsed.expression != nil || parsed.expression != expression {
                if let commitExpression {
                    commitExpression(parsed.value, parsed.expression)
                } else {
                    commit(parsed.value)
                }
            }
        } catch {
            if isSubmitting {
                errorMessage = error.localizedDescription
                isFocused = true
                AccessibilityNotification.Announcement(error.localizedDescription).post()
            } else {
                errorMessage = nil
                text = Self.format.format(value)
            }
        }
    }
}
