import SwiftUI

/// A numeric field that edits a text draft and writes to the model only on Return or focus loss.
/// Binding a TextField straight to the model reformats the text after every keystroke.
struct CommitNumberField: View {
    let label: String
    let value: Double
    var width: CGFloat = 56
    var minimum: Double? = nil
    var parameterResolver: ((String) -> Double?)? = nil
    var evaluator: ((String) -> Double?)? = nil
    var commitExpression: ((Double, String?) -> Void)? = nil
    let commit: (Double) -> Void

    init(
        label: String,
        value: Double,
        width: CGFloat = 56,
        minimum: Double? = nil,
        parameterResolver: ((String) -> Double?)? = nil,
        evaluator: ((String) -> Double?)? = nil,
        commit: @escaping (Double) -> Void
    ) {
        self.label = label
        self.value = value
        self.width = width
        self.minimum = minimum
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
        parameterResolver: ((String) -> Double?)? = nil,
        evaluator: ((String) -> Double?)? = nil,
        commitExpression: @escaping (Double, String?) -> Void
    ) {
        self.label = label
        self.value = value
        self.width = width
        self.minimum = minimum
        self.parameterResolver = parameterResolver
        self.evaluator = evaluator
        self.commitExpression = commitExpression
        self.commit = { val in commitExpression(val, nil) }
    }

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private static let format = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(1))
        .grouping(.never)

    var body: some View {
        TextField(label, text: $text)
            .focused($isFocused)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(.numbersAndPunctuation)
            #endif
            .frame(width: width)
            .onSubmit(apply)
            .onChange(of: isFocused) { _, focused in
                if !focused { apply() }
            }
            .onChange(of: value, initial: true) { old, new in
                // Take model changes unless the user holds an unsubmitted edit.
                if !isFocused || text.isEmpty || text == Self.format.format(old) {
                    text = Self.format.format(new)
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
    static func cleanDraft(_ draft: String) -> String {
        draft.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(
                of: "[a-zA-Z°]+$",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
    }

    /// Parses a draft string after sanitizing unit symbols and suffixes.
    static func parseDraft(_ draft: String) -> Double? {
        let cleaned = cleanDraft(draft)
        guard let parsed = try? Double(cleaned, format: .number), parsed.isFinite else {
            return nil
        }
        return parsed
    }

    /// Parses a draft string, trying parameterResolver first, then evaluator, then sanitizing units and parsing as a numeric literal.
    static func parseDraft(
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

    /// Commits the draft, then shows the model value; a clamp that leaves the value unchanged still redraws.
    private func apply() {
        let draft = text.trimmingCharacters(in: .whitespaces)
        if let parsed = Self.parseDraft(draft, resolver: parameterResolver, evaluator: evaluator) {
            text = Self.format.format(parsed.value)
            if let minimum, parsed.value < minimum {
                text = Self.format.format(value)
                return
            }
            if parsed.value != value || parsed.expression != nil {
                if let commitExpression {
                    commitExpression(parsed.value, parsed.expression)
                } else {
                    commit(parsed.value)
                }
            }
        } else {
            text = Self.format.format(value)
        }
    }
}
