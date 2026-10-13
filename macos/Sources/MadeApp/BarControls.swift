import SwiftUI

extension View {
    /// One style for every button, menu, and field in an in-content bar, so icon size and hit area match.
    func barControl() -> some View {
        self
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .imageScale(.medium)
    }
}

/// A bottom-bar filter field with a leading filter symbol, as in Xcode's navigator and debug-area footers.
struct BarFilterField: View {
    @Binding var text: String
    var prompt = "Filter"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button("Clear Filter", systemImage: "xmark.circle.fill") { text = "" }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary, in: .capsule)
        .barControl()
    }
}
