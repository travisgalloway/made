import SwiftUI

/// A numeric field that edits a text draft and writes to the model only on Return or focus loss.
/// Binding a TextField straight to the model reformats the text after every keystroke.
struct CommitNumberField: View {
    let label: String
    let value: Double
    var width: CGFloat = 56
    var minimum: Double? = nil
    let commit: (Double) -> Void

    init(
        label: String,
        value: Double,
        width: CGFloat = 56,
        minimum: Double? = nil,
        commit: @escaping (Double) -> Void
    ) {
        self.label = label
        self.value = value
        self.width = width
        self.minimum = minimum
        self.commit = commit
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

    /// Commits the draft, then shows the model value; a clamp that leaves the value unchanged still redraws.
    private func apply() {
        let draft = text.trimmingCharacters(in: .whitespaces)
        text = Self.format.format(value)
        if let parsed = Self.parseDraft(draft), parsed != value {
            if let minimum, parsed < minimum {
                return
            }
            commit(parsed)
        }
    }
}
